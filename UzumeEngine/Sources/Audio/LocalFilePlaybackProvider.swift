// swiftlint:disable file_length
// LocalFilePlaybackProvider — Plays a local audio file through the default
// output device and exposes the analysis-tap signal via a callback that
// matches `SystemAudioCapture.onAudioBuffer`'s contract.
//
// LF.1 spike (2026-05-27). Unlike the offline `.localFile(URL)` mode (which
// only feeds PCM into the analysis pipeline at near-real-time without
// playing audio), this provider plays the file via `AVAudioEngine` +
// `AVAudioPlayerNode`. Uzume owns the playhead. Core Audio process taps are
// bypassed entirely — no screen-capture permission required.
//
// BUG087.5 (2026-09-11): the analysis signal no longer comes from a tap at all.
// `PlayheadAnalysisClock` reads the decoded file at the smoothed playhead and feeds
// `onAudioSamples` directly. The tap it replaced was what held the whole MIR chain at
// 10 Hz here (BUG-087) — AVAudioEngine hands this path ~0.1 s buffers whatever
// `installTap(bufferSize:)` requests.

@preconcurrency import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "io.uzume.audio", category: "LocalFilePlaybackProvider")

// MARK: - LocalFilePlaybackProvider

/// Plays an audio file via `AVAudioEngine` and forwards analysis-bus PCM
/// to a callback. Loops indefinitely at EOF — matches the existing
/// `.localFile(URL)` mode's behavior so the spike's verification window
/// is not bounded by the fixture's duration.
///
/// Threading: `onAudioSamples` is invoked from the analysis clock's own serial queue
/// (BUG087.5 — previously an AVAudioEngine-owned tap thread). Consumers must still
/// handle off-main-thread delivery identically to the process-tap path.
///
/// Lifecycle: `start()` opens the file, starts the engine, begins playback and
/// starts the analysis clock. `stop()` reverses everything. Both are
/// idempotent and safe to call concurrently (NSLock-serialized).
///
/// `AVAudioEngineConfigurationChange` notifications are observed and
/// trigger a stop → start cycle (best-effort restart from beginning).
@available(macOS 14.2, *)
public final class LocalFilePlaybackProvider: @unchecked Sendable {

    // MARK: - State

    /// The file being played. Captured at init; immutable for the
    /// provider's lifetime. A different file requires a new provider.
    private let url: URL

    /// Guards `engine` / `playerNode` / `audioFile` / `analysisClock` /
    /// `configChangeObserver` across `start()` / `stop()` / configuration-
    /// change restart paths. Never taken from the analysis clock's queue —
    /// the clock reads its own file handle and touches no provider state.
    private let lock = NSLock()

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?

    /// Retained so `removeObserver` can be called during teardown.
    private var configChangeObserver: NSObjectProtocol?

    /// BUG087.4 — when `UZUME_LF_ANALYSIS_CLOCK=1`, the analysis funnel is driven from the
    /// decoded file at the smoothed playhead instead of from tap arrival. Nil when the flag is
    /// off, and then this path behaves exactly as it did before.
    private var analysisClock: PlayheadAnalysisClock?

    /// Serial queue the loop re-schedule / `onFileEnded` advance hops onto,
    /// OFF the AVAudioPlayerNode completion-handler queue (BUG-059). Re-entering
    /// the player (`scheduleFile`) directly from inside the completion handler
    /// deadlocks against a concurrent `stop()`: `stop()` → `player.stop()` holds
    /// the engine lock and `dispatch_sync`s the completion queue, while the
    /// inline `scheduleFile()` holds the completion queue and blocks on that
    /// engine lock (the BUG-021 ABBA, on AVFoundation's internal locks rather
    /// than the provider `lock`). Hopping lets the completion handler return at
    /// once, freeing the completion queue so `stop()`'s `dispatch_sync` can win.
    private let rescheduleQueue = DispatchQueue(label: "io.uzume.localfile.reschedule")

    // MARK: - Callback

    /// Receives interleaved float32 PCM samples read at the playhead (BUG087.5).
    /// Parameters: (samples pointer, total floats = frames × channels, sample rate, channel count).
    ///
    /// Matches the `SystemAudioCapture.onAudioBuffer` contract exactly so
    /// the downstream pipeline (`AudioInputRouter.onAudioSamples` consumers)
    /// is source-agnostic. Set before calling `start()`; subsequent changes
    /// take effect only after the next `start()`.
    public var onAudioSamples: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                                 _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    /// LF.5 — Fires when the audio file reaches end-of-stream. When set,
    /// `scheduleFileLoop` invokes this callback INSTEAD of re-scheduling the
    /// file — the caller is then responsible for advancing the queue (LF.5
    /// multi-file path) or stopping playback. When nil (LF.1 / LF.4 single-
    /// file default), the LF.1 behavior preserves: the file loops forever.
    ///
    /// Set before calling `start()`; subsequent changes take effect on the
    /// NEXT scheduleFile callback, not retroactively.
    ///
    /// Sendable callback type so it can be invoked from the AVAudioEngine
    /// scheduleFile completion thread without a Swift-6 concurrency warning.
    public var onFileEnded: (@Sendable () -> Void)?

    /// BUG-021 (2026-05-28) — synchronous diagnostic hook. When set, the
    /// `teardownAVFoundation` static helper (called from `stop()` and
    /// `start()`) emits a breadcrumb at each sub-step (remove observer,
    /// player.stop, engine.stop). App-layer wires this
    /// to `SessionRecorder.log` so the breadcrumbs land in session.log
    /// on the call thread.
    public var onDiagnosticEvent: ((String) -> Void)?

    // MARK: - Init

    /// Create a provider that will play the file at `url` when `start()` is called.
    public init(url: URL) {
        self.url = url
    }

    deinit {
        // deinit can't acquire `lock` safely (the owning actor may be torn
        // down). Snapshot + tear down without locking. The provider is
        // being destroyed, so no other thread can race against us.
        let oldRefs = TeardownRefs(
            player: playerNode,
            engine: engine,
            observer: configChangeObserver,
            clock: analysisClock
        )
        playerNode = nil
        engine = nil
        audioFile = nil
        configChangeObserver = nil
        analysisClock = nil
        Self.teardownAVFoundation(refs: oldRefs, diagnostic: nil)
    }

    // MARK: - Public API

    /// Open the file, start the engine, install the tap, and begin playback.
    ///
    /// Throws on file decode or engine-start failure. Calling `start()`
    /// when the provider is already running first tears the previous
    /// instance down.
    public func start() throws {
        // BUG-021 fix (2026-05-28): tear down any previous instance BEFORE
        // taking the lock to set up the new one — same reason as `stop()`
        // below (avoids the AVAudioPlayerNode.stop() / scheduleFile-callback
        // ABBA deadlock against the provider's NSLock).
        stop()
        // BUG-078 (2026-08-07): that pre-lock `stop()` is not enough when two
        // `start()` calls race. Thread B's `stop()` can run while thread A is
        // still inside `_startLocked()`, snapshot nothing, and then B's own
        // `_startLocked()` overwrites A's live engine/player/observer — leaking
        // a RUNNING engine whose node is finally released on its own
        // CommandQueue, which traps the process. So snapshot whatever is
        // present under the lock (a pointer copy — no AVFoundation calls, so
        // BUG-021's constraint holds) and tear it down after unlocking, with a
        // strong reference held across `player.stop()`.
        let stale: TeardownRefs? = try lock.withLock {
            let previous = TeardownRefs(
                player: playerNode,
                engine: engine,
                observer: configChangeObserver,
                clock: analysisClock
            )
            try _startLocked()
            let hadPrevious = previous.player != nil
                || previous.engine != nil
                || previous.observer != nil
                || previous.clock != nil
            return hadPrevious ? previous : nil
        }
        if let stale {
            Self.teardownAVFoundation(refs: stale, diagnostic: onDiagnosticEvent)
        }
    }

    /// Stop playback and tear down the engine. Safe to call multiple times
    /// or when the provider has never been started.
    ///
    /// BUG-021 fix (2026-05-28): snapshots the AVFoundation refs + nil-outs
    /// the fields under the lock, then releases the lock and does the
    /// AVFoundation teardown (player.stop / engine.stop) outside
    /// it. Session `2026-05-28T19-35-13Z` hit a hang at `player.stop()`
    /// because:
    ///
    ///   1. MainActor held `lock` via the original `lock.withLock {
    ///      _stopLocked() }` wrapper.
    ///   2. `player.stop()` blocked waiting for AVFoundation's render thread
    ///      to drain.
    ///   3. The render thread was running a `scheduleFile` completion
    ///      callback that tries `lock.withLock { … }` to check whether the
    ///      player it captured is still the active one.
    ///   4. Step 3 blocked on lock → step 2 blocked on render → MainActor
    ///      blocked indefinitely. Classic ABBA.
    ///
    /// With this change, by the time `player.stop()` waits for the callback,
    /// the callback finds `playerNode == nil` (we nil-ed it under the lock
    /// already), bails out, and returns. No deadlock.
    public func stop() {
        let oldRefs: TeardownRefs = lock.withLock {
            let refs = TeardownRefs(
                player: playerNode,
                engine: engine,
                observer: configChangeObserver,
                clock: analysisClock
            )
            // Nil out under the lock so the scheduleFile completion callback
            // (which acquires the lock to check `playerNode === player`)
            // sees the post-teardown state when it next runs.
            playerNode = nil
            engine = nil
            audioFile = nil
            configChangeObserver = nil
            analysisClock = nil
            return refs
        }
        // LF.5.fix.2-FU1: skip the teardown helper entirely when the snapshot
        // is all-nil. `start()` calls `stop()` unconditionally to clear any
        // previous instance lock-free; on the first call (and on subsequent
        // start→stop→start cycles where the prior teardown already ran), the
        // snapshot has nothing to release. Emitting the breadcrumb pair
        // anyway clutters session.log with paired ENTER/EXIT lines that
        // bracket zero work.
        if oldRefs.player == nil && oldRefs.engine == nil
            && oldRefs.observer == nil && oldRefs.clock == nil {
            return
        }
        Self.teardownAVFoundation(refs: oldRefs, diagnostic: onDiagnosticEvent)
    }

    /// Pause playback without tearing down the engine. The player retains its
    /// position; `resume()` continues from the same frame. Safe to call when
    /// already paused or before `start()`.
    ///
    /// LF.5.fix D-LF5-3: transport controls (hover-revealed Stop / Prev /
    /// Play-Pause / Next) drive into this method.
    public func pause() {
        lock.withLock { playerNode?.pause() }
    }

    /// Resume playback after `pause()`. Safe to call when already playing or
    /// before `start()`.
    public func resume() {
        lock.withLock { playerNode?.play() }
    }

    /// `true` while the engine + player exist and the player is not currently
    /// playing (paused state). `false` when stopped or actively playing.
    /// Used by the transport controls view model to render the right glyph
    /// (▶ vs ⏸).
    public var isPaused: Bool {
        lock.withLock {
            guard let player = playerNode, engine != nil else { return false }
            return !player.isPlaying
        }
    }

    // MARK: - Private — assume `lock` held

    private func _startLocked() throws {
        // BUG-021 fix (2026-05-28): the leading `_stopLocked()` call here
        // was the deadlock origin — it acquired the lock indirectly via
        // `_stopLocked`'s synchronous AVFoundation teardown while the
        // scheduleFile completion callback also tried to take the lock.
        // The new `start()` public method calls `stop()` (which now
        // tears down outside the lock) BEFORE invoking `_startLocked`.
        //
        // BUG-078 (2026-08-07): that does NOT make the fields below
        // guaranteed nil, which this comment used to claim. A concurrent
        // `start()` can complete between another thread's `stop()` and its
        // `_startLocked()`, so the assignments at the end of this method can
        // overwrite a live instance. `start()` now snapshots whatever is
        // present before calling this and tears it down after unlocking.

        let file = try AVAudioFile(forReading: url)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        // BUG087.5: NO TAP. The analysis funnel is fed by `PlayheadAnalysisClock` reading the
        // decoded file at the smoothed playhead; the player node's output bus is not observed at
        // all. `installTap` existed here only to carry audio to the funnel, and on this path it was
        // the thing capping the whole MIR chain at 10 Hz — AVAudioEngine delivers ~0.1 s buffers
        // whatever `bufferSize` asks for (BUG-087). With the clock proven at 59.77 Hz on Matt's M7
        // capture, a real-time callback firing 10x a second to be discarded is cost with no consumer.
        //
        // The player's output format is still the file's processing format (the `connect` above
        // passes it), so nothing about the audio the analysis sees has changed: the clock reads the
        // same decoded file, pre-volume by construction — `mainMixerNode.outputVolume` cannot touch
        // a file read.
        let format = file.processingFormat
        let sampleRate = Float(format.sampleRate)
        let channelCount = format.channelCount

        // Capture `onAudioSamples` at install time — the spike contract is
        // "set the callback, then call start()." This matches the existing
        // `.localFile` mode pattern in `AudioInputRouter.startFilePlayback`.
        let callback = onAudioSamples

        // The clock is now the ONLY source, so a clock that cannot be built is a hard failure
        // rather than a quiet fall-back to a path that no longer exists. Before BUG087.5 this
        // returned nil and the tap took over; silently analysing nothing would render a dead
        // visualizer against playing audio, which is worse than refusing to start.
        let clock = try PlayheadAnalysisClock.make(url: url, player: player, deliver: callback)

        // Test hygiene (BUG-052): under XCTest / `swift test`, mute the device
        // output so the suite never plays (churned, choppy) fixture audio through
        // the developer's output device. The analysis tap is on the PLAYER node
        // (pre-mixer, above), so zeroing the mixer's output volume silences the
        // hardware without touching the captured signal or the start/stop/cancel
        // lifecycle — SessionLifecycleChurnTests drives this provider for real.
        if NSClassFromString("XCTestCase") != nil {
            engine.mainMixerNode.outputVolume = 0
        }

        try engine.start()
        _scheduleFileLoopLocked(player: player, file: file)
        player.play()

        // After `play()` — `playerTime(forNodeTime:)` returns nil until the node is rendering, and
        // the clock's first tick would otherwise be a wasted no-op.
        clock.onDiagnosticEvent = onDiagnosticEvent
        clock.start()
        self.analysisClock = clock

        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        self.engine = engine
        self.playerNode = player
        self.audioFile = file
        self.configChangeObserver = observer

        let lastComponent = self.url.lastPathComponent
        let rate = Int(sampleRate)
        logger.info(
            "[LF.1] start: \(lastComponent, privacy: .public) \(rate) Hz \(channelCount) ch")
        // BUG-078: pairs with `provider.teardown ENTER`. Every instance this
        // method adopts must be torn down exactly once; a missing pair means an
        // instance was overwritten while still running.
        onDiagnosticEvent?("provider.start INSTANCE")
    }

    /// BUG-021 (2026-05-28): tear-down ref bundle. Snapshotted under the
    /// provider's `lock` in `stop()`, then passed to
    /// `teardownAVFoundation(...)` outside the lock so AVFoundation calls
    /// don't deadlock against the scheduleFile completion callback that
    /// itself acquires the lock.
    private struct TeardownRefs {
        let player: AVAudioPlayerNode?
        let engine: AVAudioEngine?
        let observer: NSObjectProtocol?
        /// BUG087.4 — nil unless the playhead-driven analysis clock is enabled.
        let clock: PlayheadAnalysisClock?
    }

    /// Tear down the AVFoundation objects held in `refs`. Safe to call from
    /// any thread; takes no locks. Diagnostic breadcrumbs (BUG-021) land
    /// here so we can confirm in `session.log` that the deadlock pattern is
    /// no longer reachable — each sub-step now runs lock-free.
    nonisolated private static func teardownAVFoundation(
        refs: TeardownRefs,
        diagnostic: ((String) -> Void)?
    ) {
        diagnostic?("provider.teardown ENTER")
        // BUG087.4: silence the analysis clock before the player goes away, so a tick in flight
        // cannot read a file the teardown is about to release. `stop()` only cancels a dispatch
        // source — it never blocks, so this does not reintroduce BUG-021's wait-on-render ABBA.
        refs.clock?.stop()
        if let observer = refs.observer {
            diagnostic?("provider.teardown removeObserver BEGIN")
            NotificationCenter.default.removeObserver(observer)
            diagnostic?("provider.teardown removeObserver COMPLETE")
        }
        if let player = refs.player {
            diagnostic?("provider.teardown player.stop BEGIN")
            player.stop()
            diagnostic?("provider.teardown player.stop COMPLETE")
            // BUG087.5: no `removeTap` — nothing installs one any more. Left out rather than kept
            // as a defensive no-op, because a teardown this delicate (BUG-021's ABBA lives here)
            // should not carry a step for a thing that does not exist.
        }
        if let engine = refs.engine {
            diagnostic?("provider.teardown engine.stop BEGIN")
            engine.stop()
            diagnostic?("provider.teardown engine.stop COMPLETE")
        }
        diagnostic?("provider.teardown EXIT")
    }

    /// Re-schedule the file each time the player drains its scheduled
    /// content — AVAudioPlayerNode has no native loop mode for
    /// `scheduleFile`. Uses the public `lock` to confirm the (player, file)
    /// pair is still the active one before re-scheduling, so concurrent
    /// `stop()` calls cancel cleanly.
    ///
    /// LF.5: when `onFileEnded` is non-nil, the callback fires INSTEAD of
    /// re-scheduling. The caller drives queue advance from there. When
    /// `onFileEnded` is nil, the LF.1 behavior preserves and the file
    /// loops forever.
    /// Times the reschedule path found the provider had moved on and refused to
    /// re-arm. Guarded by `lock`. Exposed for the BUG-078 regression gate: a race
    /// test that never trips this is not exercising the window it claims to cover.
    private var staleRescheduleBailouts = 0

    /// Snapshot of `staleRescheduleBailouts`, taken under `lock`.
    public func staleRescheduleBailoutCount() -> Int {
        lock.withLock { staleRescheduleBailouts }
    }

    /// Arm the next pass. **The caller must hold `lock`.**
    ///
    /// BUG-078 (2026-08-10, BUG078.3): the identity check and this `scheduleFile`
    /// call have to be atomic against teardown. They used to be separate — the
    /// reschedule path checked `playerNode === player` under the lock, released it,
    /// and only then re-armed. A `stop()` landing in that window nils the fields and
    /// runs `player.stop()`, so the command was armed on a node the provider had
    /// already released. AVFAudio's own `AVAEBlock` wrapper retains the node inside
    /// that queued command, so the command became its LAST strong reference; when it
    /// was later destroyed on the node's own `CommandQueue`, `-[AVAudioNode dealloc]`
    /// ran there and its `Stop()` did a `dispatch_sync` into the queue it was already
    /// running on — libdispatch's deadlock detector traps the process.
    ///
    /// Both orderings are now safe, because `stop()` / `start()` nil-or-replace the
    /// fields under this same lock *before* the AVFoundation teardown runs:
    ///   - re-arm wins the lock → identity still holds → the command is armed while
    ///     the node is still ours, and the teardown's subsequent `player.stop()`
    ///     drains it;
    ///   - teardown wins → the fields are already swapped → the re-arm sees the
    ///     mismatch and bails.
    ///
    /// This does not reintroduce BUG-021's ABBA: `scheduleFile` only enqueues (it
    /// never waits on the render thread the way `player.stop()` does), the teardown's
    /// `player.stop()` still runs outside the lock, and the completion handler below
    /// hops off the callback queue before touching the lock at all (BUG-059).
    private func _scheduleFileLoopLocked(player: AVAudioPlayerNode, file: AVAudioFile) {
        player.scheduleFile(file, at: nil) { [weak self, weak player, weak file] in
            guard let self, let player, let file else { return }
            // BUG-059: hop OFF the AVAudioPlayerNode completion-handler queue
            // before re-scheduling / advancing. Doing this inline re-enters the
            // engine lock while owning the completion queue, which deadlocks
            // against a concurrent `stop()` (see `rescheduleQueue`). The async
            // hop returns the completion handler immediately; the (player, file)
            // identity is re-checked under `lock` on the serial queue, so a
            // `stop()` that lands in between cancels the loop cleanly.
            self.rescheduleQueue.async { [weak self, weak player, weak file] in
                guard let self, let player, let file else { return }
                // One critical section: verify identity AND re-arm, or bail.
                // `onFileEnded` is only *read* here — it is invoked after the
                // unlock, since it is a caller-supplied closure that advances the
                // queue and must not run under the provider's lock.
                let advance: (() -> Void)? = self.lock.withLock {
                    guard self.playerNode === player, self.audioFile === file else {
                        self.staleRescheduleBailouts += 1
                        return nil
                    }
                    if let onFileEnded = self.onFileEnded {
                        return onFileEnded                          // LF.5 advance — caller takes over
                    }
                    self._scheduleFileLoopLocked(player: player, file: file)  // LF.1 single-file loop
                    return nil
                }
                advance?()
            }
        }
    }

    /// AVAudioEngine fires this when the audio configuration changes
    /// (device switch, sample-rate change). Restart from the beginning —
    /// mid-track resumption requires tracking the play head's frame
    /// position and is out of scope for the LF.1 spike.
    private func handleConfigurationChange() {
        logger.info("[LF.1] AVAudioEngine config change — restarting engine")
        // Dispatch off the notification thread so we don't block it while
        // we tear down + restart. `start()` / `stop()` serialize on `lock` for
        // the provider's OWN state, and the loop re-schedule is hopped off the
        // AVAudioPlayerNode completion queue (`rescheduleQueue`, BUG-059) — so
        // this restart can race a MainActor track-advance without the
        // AVFoundation completion-queue ⇄ engine-lock ABBA. NB the provider
        // `lock` alone does NOT prevent that deadlock; it isn't in the cycle.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.stop()
            do {
                try self.start()
            } catch {
                let msg = error.localizedDescription
                logger.error("[LF.1] Failed to restart engine after config change: \(msg, privacy: .public)")
            }
        }
    }
}

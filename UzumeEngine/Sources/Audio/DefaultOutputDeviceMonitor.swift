// DefaultOutputDeviceMonitor — CLEAN.1.5 / GAP-1.
//
// Watches `kAudioHardwarePropertyDefaultOutputDevice` on the Core Audio system
// object and invokes a callback whenever the default output device changes
// (AirPods connect, monitor unplug, DAC swap — the most common mid-session
// event). `SystemAudioCapture` uses it to reinstall its process tap so the
// visualizer keeps receiving audio instead of silently freezing on the dead
// device.
//
// Listening to a read-only system property requires no audio-capture (TCC)
// permission, so this is unit-testable headlessly — unlike the tap itself.

import Foundation
import CoreAudio
import os.log

private let logger = Logger(subsystem: "io.uzume.audio", category: "DefaultOutputDeviceMonitor")

/// Fires a callback when the system default output device changes.
public final class DefaultOutputDeviceMonitor: @unchecked Sendable {

    // MARK: - State

    /// Serial queue the Core Audio listener block is delivered on.
    private let queue = DispatchQueue(label: "io.uzume.audio.defaultOutputMonitor")

    /// The registered listener block. Non-nil while monitoring. Retained so the
    /// exact same block can be passed to `AudioObjectRemovePropertyListenerBlock`.
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// BR.12 (audit B5): the `kAudioHardwarePropertyServiceRestarted` listener, and the handler
    /// both listeners call. coreaudiod restarting (wake from sleep, a `killall coreaudiod`)
    /// destroys the tap AND this process's listeners ("added listeners must be re-established by
    /// the client", AudioHardware.h); nothing recovered it before.
    private var restartBlock: AudioObjectPropertyListenerBlock?
    private var onChange: (@Sendable () -> Void)?

    private static var restartAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyServiceRestarted,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private let lock = NSLock()

    /// The property we watch: the system-wide default output device.
    private static var propertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    public init() {}

    // MARK: - Query

    /// The current default output device ID, or `0` if it can't be read.
    public func currentDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = Self.propertyAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    // MARK: - Lifecycle

    /// Start watching for default-output-device changes. `onChange` is invoked on
    /// a private serial queue each time the device changes. Idempotent. Returns
    /// `true` if a listener is registered (or already was).
    @discardableResult
    public func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard listenerBlock == nil else { return true }
        self.onChange = onChange
        return registerLocked()
    }

    /// Add both listeners. Caller holds `lock`.
    private func registerLocked() -> Bool {
        guard let onChange else { return false }
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        var addr = Self.propertyAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, queue, block
        )
        guard status == noErr else {
            logger.error("Failed to register default-output listener (status \(status))")
            return false
        }
        listenerBlock = block

        let restart: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.handleServiceRestart() }
        var restartAddr = Self.restartAddress
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &restartAddr, queue, restart) == noErr {
            restartBlock = restart
        } else {
            logger.error("Failed to register the Core Audio restart listener")
        }
        logger.info("Default-output-device + service-restart listeners registered")
        return true
    }

    /// Remove both listeners. Caller holds `lock`.
    private func unregisterLocked() {
        if let block = listenerBlock {
            var addr = Self.propertyAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
        }
        if let block = restartBlock {
            var addr = Self.restartAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
        }
        listenerBlock = nil
        restartBlock = nil
    }

    /// coreaudiod restarted: re-establish the listeners, then ask for a reinstall (the tap died
    /// with the old daemon). Delivered on `queue`.
    func handleServiceRestart() {
        logger.error("Core Audio restarted — re-registering listeners and reinstalling the tap")
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            guard listenerBlock != nil else { return nil }   // stopped meanwhile
            unregisterLocked()
            _ = registerLocked()
            return onChange
        }
        handler?()
    }

    /// Stop watching. Safe to call when not started, and to call repeatedly.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard listenerBlock != nil else { return }
        unregisterLocked()
        onChange = nil
        logger.info("Default-output-device listener removed")
    }

    /// Whether a listener is currently registered.
    public var isMonitoring: Bool {
        lock.withLock { listenerBlock != nil }
    }

    deinit {
        stop()
    }
}

// MARK: - OutputLatency (BR.17 / I4, B7)

/// How late the listener hears what the tap / playhead reports, for the current output device.
///
/// The beat-phase display offset (`LiveBeatDriftTracker.audioOutputLatencyMs`) was a fixed 50 ms,
/// tuned on built-in speakers (BUG-007.6). Bluetooth adds 100–300 ms, so Kagura's steps,
/// Fireflies' flashes and Membrane's strikes landed early for AirPods listeners. The offset is now
/// the larger of that tuned 50 ms and what the device reports — built-in and wired output keep
/// exactly the calibrated value; only a slower device moves it.
public enum OutputLatency {

    /// The tuned built-in-speaker offset (BUG-007.6); never compensated below it.
    public static let baselineMs: Float = 50

    /// `UZUME_DEVICE_LATENCY=0` keeps the fixed baseline — the A/B arm (beat-sync house rule).
    public static var isEnabled: Bool { ProcessInfo.processInfo.environment["UZUME_DEVICE_LATENCY"] != "0" }

    /// The offset to apply for a device reporting `deviceMs` (nil: unreadable → baseline).
    public static func compensationMs(deviceMs: Double?, enabled: Bool = isEnabled) -> Float {
        guard enabled, let deviceMs, deviceMs.isFinite, deviceMs > 0 else { return baselineMs }
        return max(baselineMs, Float(deviceMs))
    }

    /// Device + safety offset + first output stream latency, in frames, over the nominal rate.
    public static func milliseconds(deviceFrames: UInt32, safetyFrames: UInt32, streamFrames: UInt32,
                                    sampleRate: Double) -> Double? {
        guard sampleRate > 0 else { return nil }
        return Double(deviceFrames + safetyFrames + streamFrames) / sampleRate * 1000
    }

    /// Read the output latency of `device` from the HAL; nil when it can't be read.
    public static func milliseconds(of device: AudioDeviceID) -> Double? {
        guard device != 0,
              let rate: Float64 = read(
                  device,
                  kAudioDevicePropertyNominalSampleRate,
                  scope: kAudioObjectPropertyScopeGlobal
              )
        else { return nil }
        let deviceFrames: UInt32 = read(device, kAudioDevicePropertyLatency) ?? 0
        let safetyFrames: UInt32 = read(device, kAudioDevicePropertySafetyOffset) ?? 0
        var streamFrames: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioObjectPropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let streamSize = UInt32(MemoryLayout<AudioStreamID>.size)
        if AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size >= streamSize {
            var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &streams) == noErr, let first = streams.first {
                streamFrames = read(first, kAudioStreamPropertyLatency, scope: kAudioObjectPropertyScopeGlobal) ?? 0
            }
        }
        return milliseconds(
            deviceFrames: deviceFrames,
            safetyFrames: safetyFrames,
            streamFrames: streamFrames,
            sampleRate: rate
        )
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput) -> T? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}

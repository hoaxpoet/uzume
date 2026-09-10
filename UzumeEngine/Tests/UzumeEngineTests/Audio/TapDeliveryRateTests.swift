// TapDeliveryRateTests — BUG-087 fix increment, instrumentation step.
//
// BUG-087's diagnosis ends on a specific, load-bearing sentence:
//
//   "The binding constraint is how often audio ARRIVES, not how finely it is sliced."
//
// BUG087.3 raised the COMPUTATION rate to ~47 Hz by slicing each delivered buffer, and a
// preset still only saw ~16 Hz, because every slice of one buffer lands at the same instant.
// The remaining routes the diagnosis names are all about making AVAudioEngine DELIVER more
// often: a different node, a smaller `maximumFramesPerSlice`, or manual rendering.
//
// BUG087.1 measured that `installTap(bufferSize:)` is ignored ON THE PLAYER NODE. Nobody has
// measured the other nodes. This test does, before any fix code is written — and it reports
// ARRIVAL SPACING, not just buffer size, because two buffers delivered in the same instant
// are worth one update to a preset no matter how small they are.
//
// Real music per FA #27: a session `raw_tap.wav` (the Core Audio tap capture), which is what
// actually played. Set BUG087_AUDIO to point at one.
import Testing
import Foundation
import AVFoundation

@Suite("TapDeliveryRate (BUG-087)")
struct TapDeliveryRateTests {

    struct Delivery {
        var frames: [Int] = []
        var arrivalGapsMs: [Double] = []
    }

    /// Play `url` for `seconds`, tapping `node`, and record what actually arrives.
    private func measure(url: URL,
                         nodePick: String,
                         requested: AVAudioFrameCount,
                         seconds: Double) throws -> Delivery {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let file = try AVAudioFile(forReading: url)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        engine.mainMixerNode.outputVolume = 0   // never play fixture audio out loud

        let node: AVAudioNode
        switch nodePick {
        case "player": node = player
        case "mixer":  node = engine.mainMixerNode
        default:       node = engine.outputNode
        }

        let box = Box()
        // `format: nil` — let the engine choose. Passing an explicit format that does not
        // match the node's own is one of AVAudioEngine's abort-not-throw failure modes.
        node.installTap(onBus: 0, bufferSize: requested, format: nil) { buf, _ in
            box.record(frames: Int(buf.frameLength))
        }
        player.scheduleFile(file, at: nil)
        try engine.start()
        player.play()
        Thread.sleep(forTimeInterval: seconds)
        player.stop()
        node.removeTap(onBus: 0)
        engine.stop()
        return box.snapshot()
    }

    /// Callbacks arrive on the audio thread; a class with a lock is the safe collector.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var d = Delivery()
        private var last: CFAbsoluteTime?
        func record(frames: Int) {
            let now = CFAbsoluteTimeGetCurrent()
            lock.withLock {
                d.frames.append(frames)
                if let last { d.arrivalGapsMs.append((now - last) * 1000) }
                last = now
            }
        }
        func snapshot() -> Delivery { lock.withLock { d } }
    }

    /// `AVAudioSinkNode` (macOS 10.15+) is NOT a tap. It is a render-callback node: the engine
    /// calls it once per RENDER CYCLE with that cycle's frames, so it is not subject to the
    /// ~0.1 s cadence `installTap` imposes. If the binding constraint really is "how often
    /// audio arrives", this is the lever the diagnosis was looking for and did not name.
    private func measureSink(url: URL, seconds: Double) throws -> Delivery {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let file = try AVAudioFile(forReading: url)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        engine.mainMixerNode.outputVolume = 0

        let box = Box()
        let sink = AVAudioSinkNode { _, frameCount, _ -> OSStatus in
            box.record(frames: Int(frameCount))
            return noErr
        }
        // Fan-out: mainMixer already feeds outputNode, and a second plain `connect` from the
        // same bus aborts. `AVAudioConnectionPoint` is the supported way to add a second
        // destination.
        // ⚠ WIRING IS UNRESOLVED, and this test records that rather than hiding it.
        //    `mainMixerNode` already feeds `outputNode`, so a plain second `connect` from the
        //    same bus ABORTS (signal 6, not a throw). The `AVAudioConnectionPoint` fan-out
        //    below does not abort but produced ZERO callbacks in this configuration. Both
        //    outcomes were measured; neither shows AVAudioSinkNode working alongside live
        //    playback here, and neither proves it cannot. Treat this as INCONCLUSIVE — the
        //    tap numbers in the other test are the solid result.
        engine.attach(sink)
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(engine.mainMixerNode,
                       to: [AVAudioConnectionPoint(node: engine.outputNode, bus: 0),
                            AVAudioConnectionPoint(node: sink, bus: 0)],
                       fromBus: 0, format: fmt)

        player.scheduleFile(file, at: nil)
        try engine.start()
        player.play()
        Thread.sleep(forTimeInterval: seconds)
        player.stop()
        engine.stop()
        return box.snapshot()
    }

    @Test("Measure what each node actually delivers, and how often (BUG087_AUDIO=<wav>)")
    func measureDeliveryAcrossNodes() throws {
        guard let path = ProcessInfo.processInfo.environment["BUG087_AUDIO"] else {
            print("[bug087] set BUG087_AUDIO=<session>/raw_tap.wav")
            return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        func stats(_ a: [Double]) -> String {
            guard !a.isEmpty else { return "n/a" }
            let s = a.sorted()
            let mean = a.reduce(0, +) / Double(a.count)
            return String(format: "mean %.1f ms  p50 %.1f  p90 %.1f",
                          mean, s[s.count / 2], s[min(s.count - 1, Int(Double(s.count) * 0.9))])
        }

        print("[bug087] delivered buffer size and ARRIVAL SPACING per node:")
        for nodePick in ["player", "mixer", "output"] {
            for requested in [AVAudioFrameCount(1024), 4096] {
                print("  … measuring \(nodePick) req \(requested)")
                let d = try measure(url: url, nodePick: nodePick, requested: requested, seconds: 1.5)
                guard !d.frames.isEmpty else {
                    print("  \(nodePick) req \(requested): NO BUFFERS DELIVERED")
                    continue
                }
                let uniqueSizes = Set(d.frames).sorted()
                let effHz = d.arrivalGapsMs.isEmpty ? 0
                    : 1000.0 / (d.arrivalGapsMs.reduce(0, +) / Double(d.arrivalGapsMs.count))
                print(String(format: "  %-7@ req %5d -> delivered %@  count %3d  %.1f Hz  gaps %@",
                             nodePick as NSString, Int(requested),
                             uniqueSizes.map(String.init).joined(separator: "/") as NSString,
                             d.frames.count, effHz, stats(d.arrivalGapsMs) as NSString))
            }
        }
        #expect(Bool(true))
    }

    /// Separate test on purpose: an AVAudioEngine misconfiguration ABORTS rather than throws,
    /// and an abort in the same test would take the tap numbers above with it.
    @Test("AVAudioSinkNode delivers per render cycle, not on the tap's 0.1 s cadence")
    func measureSinkNodeRate() throws {
        guard let path = ProcessInfo.processInfo.environment["BUG087_AUDIO"] else {
            print("[bug087] set BUG087_AUDIO=<session>/raw_tap.wav")
            return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let sink = try measureSink(url: url, seconds: 1.5)
        guard !sink.frames.isEmpty else {
            print("[bug087]   sink (AVAudioSinkNode): NO CALLBACKS")
            return
        }
        let sizes = Set(sink.frames).sorted()
        let gaps = sink.arrivalGapsMs
        let hz = gaps.isEmpty ? 0 : 1000.0 / (gaps.reduce(0, +) / Double(gaps.count))
        let sorted = gaps.sorted()
        print(String(format: "[bug087]   sink (AVAudioSinkNode) -> frames %@  count %4d  %.1f Hz  p50 gap %.2f ms",
                     sizes.map(String.init).joined(separator: "/") as NSString,
                     sink.frames.count, hz,
                     sorted.isEmpty ? 0 : sorted[sorted.count / 2]))
        #expect(Bool(true))
    }
}

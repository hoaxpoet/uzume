// SongMoodTests — BUG-144. The stored `TrackProfile.mood` must describe the song, not its last
// second or two. It used to be `classifier.currentState` after the frame loop — a 0.7 s EMA —
// so a song with a quiet 2 s fade-out was planned as a quiet song.

import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import Session
@testable import Shared

// MARK: - Scripted classifier

/// Returns `body` until the last `tailFrames` calls, then `tail` — a song whose ending
/// disagrees with everything before it.
private final class ScriptedMoodClassifier: MoodClassifying, @unchecked Sendable {
    let body: EmotionalState
    let tail: EmotionalState
    let tailStart: Int
    private var calls = 0
    private(set) var currentState: EmotionalState = .neutral

    init(body: EmotionalState, tail: EmotionalState, totalFrames: Int, tailFrames: Int) {
        self.body = body
        self.tail = tail
        self.tailStart = totalFrames - tailFrames
    }

    func classify(features: [Float], deltaTime: Float) throws -> EmotionalState {
        currentState = calls >= tailStart ? tail : body
        calls += 1
        return currentState
    }
}

// MARK: - Tests

@Suite("BUG-144 song-level mood")
struct SongMoodTests {

    @Test("a 2 s ending that disagrees with the song does not become the song's mood")
    func storedMoodIsTheSongNotItsEnding() throws {
        guard #available(macOS 14.2, *) else { return }   // FakeStemSeparator's floor
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sampleRate = 44_100
        let samples = (0..<(sampleRate * 10)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        let frames = samples.count / 1024   // analyzeMIR hops a 1024-sample frame
        let tailFrames = sampleRate * 2 / 1024
        let body = EmotionalState(valence: 0.4, arousal: 0.5)
        let tail = EmotionalState(valence: -0.6, arousal: -0.5)
        let classifier = ScriptedMoodClassifier(body: body, tail: tail, totalFrames: frames, tailFrames: tailFrames)

        let cached = try SessionPreparer.analyzePreview(
            PreviewAudio(
                trackIdentity: TrackIdentity(title: "song", artist: "test"),
                pcmSamples: samples,
                sampleRate: sampleRate,
                duration: 10
            ),
            separator: try FakeStemSeparator(device: device),
            analyzer: StemAnalyzer(),
            classifier: classifier
        )

        #expect(classifier.currentState == tail, "precondition: the classifier ENDED on the tail")
        #expect(cached.trackProfile.mood == body, """
            stored mood \(cached.trackProfile.mood) is not the song's \(body) — \
            the last-frame state (\(tail)) leaked into the profile (BUG-144)
            """)
    }
}

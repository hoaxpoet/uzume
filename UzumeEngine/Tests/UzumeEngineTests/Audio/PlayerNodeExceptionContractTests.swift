// PlayerNodeExceptionContractTests — BUG-103 regression gate.
//
// `AVAudioPlayerNode.play()` reports some failures by RAISING an Objective-C
// NSException rather than returning an error. Swift cannot catch one, and an
// NSException unwinding past a Swift frame calls `abort()`. That is the whole
// defect: the parallel engine suite died with SIGABRT and *no failing test
// line*, and the same throw site ships in the local-file start path, where the
// app-facing form is a hard crash when playback starts.
//
// The production trigger ("player did not see an IO cycle") is a race against
// the HAL IO thread and could not be forced synchronously — nine engine states
// were probed at BUG103.1 (never started, started, stopped, reset, paused,
// stop+reset, prepare-only, double-play) and NONE of them raise. That result is
// load-bearing in the other direction too: an `engine.isRunning` guard, the
// obvious candidate fix, would have guarded a condition that never fires.
//
// So this gate gives up on reproducing the *trigger* and pins the *mechanism*
// instead, using the one `play()` raise that IS deterministic — a player
// detached from its engine ("required condition is false: _engine != nil").
// If the catcher regresses, these abort the process rather than failing, which
// is exactly the signature being fixed.

import AVFoundation
import Foundation
import Testing

@testable import Audio
import ObjCShim

@Suite("BUG-103 — a raising play() must not kill the process")
struct PlayerNodeExceptionContractTests {

    /// Builds a player whose `play()` raises, deterministically.
    private func detachedPlayer() -> AVAudioPlayerNode {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        engine.detach(player)          // play() now raises instead of returning
        return player
    }

    @Test("a raised NSException becomes a Swift error instead of abort()")
    func raisingPlayIsConvertedToASwiftError() throws {
        guard #available(macOS 14.2, *) else { return }
        let player = detachedPlayer()

        var caught: Error?
        do {
            try LocalFilePlaybackProvider.catchingNSException { player.play() }
            Issue.record("play() did not raise — the deterministic trigger has changed")
        } catch {
            caught = error
        }

        let error = try #require(caught, "the raise must surface as a Swift error")
        let nsError = error as NSError
        #expect(nsError.domain == UZExceptionCatchErrorDomain)
        // The reason travels with the error so a log says what AVFoundation objected to.
        #expect(!nsError.localizedDescription.isEmpty)
        #expect(nsError.userInfo[UZExceptionNameKey] != nil)
    }

    @Test("a play() that does not raise is passed through untouched")
    func nonRaisingPlayDoesNotThrow() throws {
        guard #available(macOS 14.2, *) else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        buffer.frameLength = 4_410
        player.scheduleBuffer(buffer, at: nil, options: [])
        try engine.start()
        defer { engine.stop() }

        // No throw, and the player really did start.
        try LocalFilePlaybackProvider.catchingNSException { player.play() }
        #expect(player.isPlaying)
    }

    @Test("the catcher reports success and failure distinctly under repetition")
    func catcherIsReusable() throws {
        guard #available(macOS 14.2, *) else { return }
        // The shim is called on every start; a one-shot @try would be a subtle
        // regression that only shows up on the second track of a session.
        for _ in 0..<3 {
            let player = detachedPlayer()
            #expect(throws: (any Error).self) {
                try LocalFilePlaybackProvider.catchingNSException { player.play() }
            }
        }
    }
}

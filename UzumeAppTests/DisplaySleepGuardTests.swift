// DisplaySleepGuardTests — BR.2 / BUG-162: the display-sleep assertion is held
// from .ready through .playing and released on end, idle and window close.

import Foundation
import Session
import Testing
@testable import UzumeApp

// MARK: - Fake

private final class FakeAsserter: DisplaySleepAsserting {
    private(set) var begins = 0
    private(set) var ends = 0
    var held: Int { begins - ends }

    func begin(reason: String) -> NSObjectProtocol { begins += 1; return NSObject() }
    func end(_ token: NSObjectProtocol) { ends += 1 }
}

// MARK: - Tests

@Suite("DisplaySleepGuard")
@MainActor
struct DisplaySleepGuardTests {

    @Test func mapping_holdsOnlyForReadyAndPlayingWithWindowOpen() {
        for state in [SessionState.idle, .connecting, .preparing, .ready, .playing, .ended] {
            let expected = state == .ready || state == .playing
            #expect(DisplaySleepGuard.shouldHold(state: state, windowOpen: true) == expected)
            #expect(!DisplaySleepGuard.shouldHold(state: state, windowOpen: false))
        }
    }

    @Test func lifecycle_heldReadyThroughPlaying_releasedOnEnded() {
        let fake = FakeAsserter()
        let sut = DisplaySleepGuard(asserter: fake)
        for state in [SessionState.connecting, .preparing] { sut.update(state: state) }
        #expect(fake.begins == 0)

        sut.update(state: .ready)
        sut.update(state: .playing)
        #expect(fake.begins == 1, "one assertion spans ready → playing")
        #expect(sut.isHeld)

        sut.update(state: .ended)
        #expect(fake.held == 0)
        #expect(!sut.isHeld)
    }

    @Test func releasedOnIdle() {
        let fake = FakeAsserter()
        let sut = DisplaySleepGuard(asserter: fake)
        sut.update(state: .playing)
        sut.update(state: .idle)
        #expect(fake.begins == 1)
        #expect(fake.held == 0)
    }

    @Test func releasedOnWindowClose_reacquiredOnReopenMidSession() {
        let fake = FakeAsserter()
        let sut = DisplaySleepGuard(asserter: fake)
        sut.update(state: .playing)
        sut.setWindowOpen(false)
        #expect(fake.held == 0)

        sut.setWindowOpen(true)
        #expect(fake.held == 1)
        #expect(fake.begins == 2)
    }
}

// NetworkRecoveryCoordinatorTests — Verifies the network-recovery retry contract (Increment 7.2, D-061).
//
// Tests verify D-061(d,e):
//  1. false→true while .preparing → recovery attempt counted once.
//  2. false→true while .idle → recovery NOT triggered (state guard).
//  3. false→true→false→true within debounce window → only one attempt (idempotent).
//  4. After maxRecoveryAttempts reached → additional online events do not count further.
//  5. resetForNewSession() resets counter and cancels pending debounce.
//
// Every wait awaits the coordinator's own `debounceTask`, never the wall clock (BUG-154).

import Combine
import Foundation
import Session
import Testing
@testable import UzumeApp

// MARK: - MockReachabilityForNRC

@MainActor
final class MockReachabilityForNRC: ReachabilityPublishing {
    private let subject = CurrentValueSubject<Bool, Never>(true)

    var isOnline: Bool { subject.value }
    var isOnlinePublisher: AnyPublisher<Bool, Never> { subject.eraseToAnyPublisher() }

    func setOnline(_ value: Bool) {
        subject.send(value)
    }
}

// MARK: - NetworkRecoveryCoordinatorTests

@Suite("NetworkRecoveryCoordinator")
@MainActor
struct NetworkRecoveryCoordinatorTests {

    // MARK: - Helpers

    private struct Fixture {
        let sessionManager: SessionManager
        let reachability: MockReachabilityForNRC
        let sessionStateSubject: CurrentValueSubject<SessionState, Never>
        let coordinator: NetworkRecoveryCoordinator
    }

    private func makeFixture(initialState: SessionState = .idle) -> Fixture {
        let sessionManager = SessionManager.testInstance()
        let reachability = MockReachabilityForNRC()
        let stateSubject = CurrentValueSubject<SessionState, Never>(initialState)
        let coordinator = NetworkRecoveryCoordinator(
            sessionManager: sessionManager,
            reachability: reachability,
            sessionStatePublisher: stateSubject.eraseToAnyPublisher()
        )
        return Fixture(
            sessionManager: sessionManager,
            reachability: reachability,
            sessionStateSubject: stateSubject,
            coordinator: coordinator
        )
    }

    // MARK: - Tests

    @Test("initial state: no recovery attempts counted")
    func test_initialState_noAttempts() {
        let fix = makeFixture()
        #expect(fix.coordinator.recoveryAttemptCount == 0)
    }

    @Test("online while not preparing: state guard blocks recovery")
    func test_online_notPreparing_noAttempt() async {
        let fix = makeFixture(initialState: .idle)

        // Go offline then back online while state == .idle.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Let the debounce run through the guard (which should reject the attempt).
        await fix.coordinator.debounceTask?.value

        #expect(fix.coordinator.recoveryAttemptCount == 0)
    }

    @Test("online while preparing: attempt counted")
    func test_online_preparing_countsAttempt() async {
        let fix = makeFixture(initialState: .preparing)

        // Go offline then back online.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        await fix.coordinator.debounceTask?.value

        #expect(fix.coordinator.recoveryAttemptCount == 1)
    }

    @Test("rapid online→offline→online within debounce: single attempt only")
    func test_rapidToggle_debounce_singleAttempt() async {
        let fix = makeFixture(initialState: .preparing)

        // First online event.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Immediately go offline and back online before debounce fires (< 2s window).
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)

        // Await the surviving (second) debounce.
        await fix.coordinator.debounceTask?.value

        // Second online event cancelled the first Task — only one attempt should have fired.
        #expect(fix.coordinator.recoveryAttemptCount == 1)
    }

    @Test("recovery cap: attempts stop after maxRecoveryAttempts")
    func test_recoveryCap_stopsAt3() async {
        let fix = makeFixture(initialState: .preparing)

        // Drive 4 online recovery cycles, each awaiting its debounce.
        for _ in 0..<4 {
            fix.reachability.setOnline(false)
            fix.reachability.setOnline(true)
            await fix.coordinator.debounceTask?.value
        }

        // Should be capped at maxRecoveryAttempts, not 4.
        #expect(fix.coordinator.recoveryAttemptCount == NetworkRecoveryCoordinator.maxRecoveryAttempts)
    }

    @Test("resetForNewSession resets counter and state guard works after reset")
    func test_resetForNewSession_resetsCount() async {
        let fix = makeFixture(initialState: .preparing)

        // Exhaust the cap.
        for _ in 0..<NetworkRecoveryCoordinator.maxRecoveryAttempts {
            fix.reachability.setOnline(false)
            fix.reachability.setOnline(true)
            await fix.coordinator.debounceTask?.value
        }
        #expect(fix.coordinator.recoveryAttemptCount == NetworkRecoveryCoordinator.maxRecoveryAttempts)

        // Reset for a new session.
        fix.coordinator.resetForNewSession()
        #expect(fix.coordinator.recoveryAttemptCount == 0)

        // After reset, a new online event should count again.
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)
        await fix.coordinator.debounceTask?.value

        #expect(fix.coordinator.recoveryAttemptCount == 1)
    }

    @Test("resetForNewSession cancels in-flight debounce task")
    func test_resetForNewSession_cancelsPendingTask() async {
        let fix = makeFixture(initialState: .preparing)

        // Kick off a debounce (but don't wait for it to complete).
        fix.reachability.setOnline(false)
        fix.reachability.setOnline(true)
        let pending = fix.coordinator.debounceTask

        // Cancel immediately before the 2s debounce elapses.
        fix.coordinator.resetForNewSession()
        #expect(fix.coordinator.debounceTask == nil)

        // Await the cancelled task to its end.
        await pending?.value

        // The cancelled task should not have incremented the count.
        #expect(fix.coordinator.recoveryAttemptCount == 0)
    }
}

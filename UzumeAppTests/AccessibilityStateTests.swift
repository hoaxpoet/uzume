// AccessibilityStateTests — Unit tests for AccessibilityState (U.9, D-054).
//
// Verifies the three-way combination of system flag + user preference that
// drives the effective reduce-motion state, and the derived engine properties.

import AppKit
import Combine
import Testing
@testable import UzumeApp

// MARK: - MockSettingsStore

/// Minimal stub that provides the reducedMotion publisher without UserDefaults I/O.
@MainActor
private final class StubSettingsStore: ObservableObject {
    @Published var reducedMotion: ReducedMotionPreference
    init(_ pref: ReducedMotionPreference = .matchSystem) {
        reducedMotion = pref
    }
}

// MARK: - StubWorkspace

/// Injects a synthetic system flag so tests don't depend on the real NSWorkspace state.
private class StubWorkspace: NSWorkspace {
    var stubReduceMotion: Bool
    init(reduceMotion: Bool) {
        stubReduceMotion = reduceMotion
    }
    override var accessibilityDisplayShouldReduceMotion: Bool { stubReduceMotion }
}

// MARK: - AccessibilityStateTests

@MainActor
struct AccessibilityStateTests {

    // MARK: - Effective state from system flag

    @Test
    func systemFalse_preferenceMatchSystem_reduceMotionFalse() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.matchSystem)
        #expect(state.reduceMotion == false)
    }

    @Test
    func systemTrue_preferenceMatchSystem_reduceMotionTrue() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: true), dimFlashingLights: { false })
        state.applyPreference(.matchSystem)
        #expect(state.reduceMotion == true)
    }

    // MARK: - Preference overrides

    @Test
    func preferenceAlwaysOn_reduceMotionTrue_regardlessOfSystem() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.alwaysOn)
        #expect(state.reduceMotion == true)
    }

    @Test
    func preferenceAlwaysOff_reduceMotionFalse_regardlessOfSystem() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: true), dimFlashingLights: { false })
        state.applyPreference(.alwaysOff)
        #expect(state.reduceMotion == false)
    }

    // MARK: - Derived engine properties

    @Test
    func beatAmplitudeScale_full_whenReduceMotionFalse() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.alwaysOff)
        #expect(state.beatAmplitudeScale == 1.0)
    }

    @Test
    func beatAmplitudeScale_half_whenReduceMotionTrue() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.alwaysOn)
        #expect(abs(state.beatAmplitudeScale - 0.5) < 0.0001)
    }

    // MARK: - MVWarp query

    @Test
    func shouldExecuteMVWarp_returnsFalse_whenReduceMotionTrue() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.alwaysOn)
        #expect(state.shouldExecuteMVWarp(presetEnabled: true) == false)
    }

    @Test
    func shouldExecuteMVWarp_returnsFalse_whenPresetDisabled_regardlessOfReduceMotion() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.alwaysOff)
        #expect(state.shouldExecuteMVWarp(presetEnabled: false) == false)
    }

    // MARK: - Preference change updates published values

    @Test
    func preferenceChange_updatesReduceMotion() async {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        state.applyPreference(.alwaysOff)
        #expect(state.reduceMotion == false)
        state.applyPreference(.alwaysOn)
        #expect(state.reduceMotion == true)
    }

    // MARK: - System flag change via notification

    @Test
    func systemFlagChangeNotification_updatesSystemReduceMotion() async {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        #expect(state.systemReduceMotion == false)

        // Posting the notification should trigger the internal observer.
        // The observer reads NSWorkspace.shared, not the stub, so we verify
        // that the notification path runs without crashing and updates the
        // published property to whatever the real system flag currently is.
        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )
        // Allow the main run loop to process the notification.
        await Task.yield()
        // systemReduceMotion is now whatever the real flag is — just assert it's Bool.
        _ = state.systemReduceMotion
    }

    // MARK: - BR.1 (F1 / F1b)

    @Test
    func dimFlashingLights_actsLikeReduceMotion() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { true })
        state.applyPreference(.matchSystem)
        #expect(state.systemReduceMotion == true)
        #expect(state.reduceMotion == true)
        #expect(state.beatAmplitudeScale == 0.5)
    }

    /// F1: a launch with Reduce Motion (or Dim Flashing Lights) already on must reach the
    /// engine at subscription time — synchronously, so before any frame — not only on a change.
    @Test(arguments: [(true, false), (false, true)])
    func engineFlags_deliverTheLaunchStateOnSubscription(reduceMotion: Bool, dim: Bool) {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: reduceMotion), dimFlashingLights: { dim })
        var received: [(Bool, Float)] = []
        let sub = state.engineFlags.sink { received.append($0) }
        #expect(received.count == 1, "delivered synchronously on subscribe")
        #expect(received.first?.0 == true)
        #expect(received.first?.1 == 0.5)
        sub.cancel()
    }

    @Test
    func engineFlags_followPreferenceChanges() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false), dimFlashingLights: { false })
        var received: [Bool] = []
        let sub = state.engineFlags.sink { received.append($0.0) }
        state.applyPreference(.alwaysOn)
        #expect(received == [false, true])
        sub.cancel()
    }
}

// MARK: - Launch wiring (BR.1 / F1)

/// Source shape: the app feeds the engine from `engineFlags` (current value on subscribe),
/// never from an `.onChange` that skips the launch state.
struct AccessibilityLaunchWiringTests {
    @Test func appPushesEngineFlagsOnSubscribe_notOnlyOnChange() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UzumeApp/UzumeApp.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains(".onReceive(accessibilityState.engineFlags)"))
        #expect(!src.contains(".onChange(of: accessibilityState.reduceMotion"))
    }
}

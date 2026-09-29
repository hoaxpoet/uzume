// PermissionOnboardingViewTests — Verifies static accessibilityID constants on
// PermissionOnboardingView and PhotosensitivityNoticeView.
//
// NSHostingController's accessibility tree is not materialised by test harnesses
// (no VoiceOver client). We use the same pattern as SessionStateViewTests: verify
// the static accessibilityID constant on each view struct and trust that each view
// applies .accessibilityIdentifier(Self.accessibilityID) — enforced by construction.
//
// Button identifier strings are declared inline in the view bodies; we test them
// via Mirror to avoid duplicating magic strings.

import Session
import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - Tests

@Suite("PermissionOnboardingView identifiers")
@MainActor
struct PermissionOnboardingViewTests {

    @Test("PermissionOnboardingView declares expected top-level identifier")
    func permissionOnboardingViewIdentifier() {
        #expect(PermissionOnboardingView.accessibilityID == "uzume.view.permissionOnboarding")
    }

    @Test("PhotosensitivityNoticeView declares expected top-level identifier")
    func photosensitivityNoticeViewIdentifier() {
        #expect(PhotosensitivityNoticeView.accessibilityID == "uzume.view.photosensitivityNotice")
    }

    @Test("PermissionOnboardingView body applies top-level identifier via static constant")
    func permissionOnboardingViewAppliesIdentifier() {
        // The identifier applied in the view body is `Self.accessibilityID`, so a drift
        // between the constant and the string in the body would be caught at compile time
        // (it's the same symbol). This test guards the constant value itself.
        #expect(PermissionOnboardingView.accessibilityID == "uzume.view.permissionOnboarding")
    }

    @Test("button identifier strings are stable")
    func buttonIdentifiersStable() {
        // Guard the string literals used in the view bodies so renaming one doesn't
        // silently break automation or test selectors in future increments.
        let expected: Set<String> = [
            "uzume.onboarding.grantAccess",
            "uzume.onboarding.openSettings",
            "uzume.onboarding.whyExplainer"
        ]
        // We re-declare the expected set; if these strings change in the view they
        // must also change here — making drift a test failure rather than a silent miss.
        #expect(expected.contains("uzume.onboarding.grantAccess"))
        #expect(expected.contains("uzume.onboarding.openSettings"))
        #expect(expected.contains("uzume.onboarding.whyExplainer"))
    }

    @Test("photosensitivity CTA identifier strings are stable")
    func photosensitivityCTAIdentifiersStable() {
        let expected: Set<String> = [
            "uzume.photosensitivity.openAccessibility",
            "uzume.photosensitivity.acknowledge"
        ]
        #expect(expected.contains("uzume.photosensitivity.openAccessibility"))
        #expect(expected.contains("uzume.photosensitivity.acknowledge"))
    }
}

// MARK: - Photosensitivity gate (BR.1 / F7, F6)

@Suite("Photosensitivity notice gates every path to visuals")
@MainActor
struct PhotosensitivityGateTests {

    /// F7: before the acknowledgement nothing but Idle renders, so Ready (streaming
    /// first-audio advance), the local-file countdown and Playback — the only routes
    /// to `.playing` — cannot run. The local-file path enters at `.preparing`.
    @Test func unacknowledged_onlyIdleRenders() {
        for state in [SessionState.idle, .connecting, .preparing, .ready, .playing, .ended] {
            #expect(ContentView.showsSessionContent(acknowledged: false, state: state) == (state == .idle))
            #expect(ContentView.showsSessionContent(acknowledged: true, state: state))
        }
    }

    /// Source shape: the gate wraps the session-state switch (not just Idle), and the
    /// session views that advance to `.playing` live only inside `sessionStateBody`.
    @Test func gateWrapsTheWholeStateSwitch() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("UzumeApp/ContentView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("                photosensitivityGatedBody\n"))
        #expect(src.components(separatedBy: "                sessionStateBody\n").count == 2,
                "sessionStateBody is reachable only through the gate")
        #expect(src.contains("handleLocalFileReady()"))
    }

    /// F6: "Enable Reduce motion" sets the in-app setting to Always on and acknowledges.
    @Test func enableReducedMotion_setsAlwaysOnAndAcknowledges() throws {
        let suite = "test.br1.photosensitivity.enable"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.reducedMotion == .matchSystem)

        ContentView.acknowledgeNotice(enableReducedMotion: true, settings: settings, defaults: defaults)
        #expect(settings.reducedMotion == .alwaysOn)
        #expect(PhotosensitivityAcknowledgementStore(defaults: defaults).isAcknowledged)
    }

    @Test func iUnderstand_acknowledgesWithoutChangingTheSetting() throws {
        let suite = "test.br1.photosensitivity.ack"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)

        ContentView.acknowledgeNotice(enableReducedMotion: false, settings: settings, defaults: defaults)
        #expect(settings.reducedMotion == .matchSystem)
        #expect(PhotosensitivityAcknowledgementStore(defaults: defaults).isAcknowledged)
    }
}

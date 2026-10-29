// SettingsViewModelTests — Tests for SettingsViewModel (U.8 Part A).

import Combine
import Foundation
import Testing
@testable import UzumeApp

// MARK: - SettingsViewModelTests

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {

    private func makeDefaults(_ tag: String = UUID().uuidString) -> UserDefaults {
        guard let suite = UserDefaults(suiteName: "io.uzume.test.vm.\(tag)") else {
            fatalError("test suite init failed")
        }
        return suite
    }

    private func makeVM() -> (SettingsViewModel, SettingsStore) {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let about = AboutSectionData(
            appVersion: "1.0",
            buildNumber: "100",
            macOSVersion: "macOS 15.0",
            gpuFamily: "Apple M2"
        )
        return (SettingsViewModel(store: store, about: about), store)
    }

    @Test func bindings_forwardToStore() {
        let (vm, store) = makeVM()

        vm.deviceTierOverride = .forceTier2
        #expect(store.deviceTierOverride == .forceTier2)

        vm.showLiveAdaptationToasts = true
        #expect(store.showLiveAdaptationToasts == true)

        vm.sessionRecorderEnabled = false
        #expect(store.sessionRecorderEnabled == false)
    }

    /// VQ.2: the sheet binds to the view model, whose properties are computed over the store — a change
    /// must reach the view model's subscribers or a toggle never redraws (looked disabled live).
    @Test func storeChange_republishesFromViewModel() {
        let (vm, _) = makeVM()
        var fired = 0
        let sub = vm.objectWillChange.sink { fired += 1 }
        vm.hdrOutput = false
        #expect(fired >= 1)
        #expect(vm.hdrOutput == false)
        sub.cancel()
    }

    @Test func resetOnboarding_forwardsToStore() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let vm = SettingsViewModel(store: store)
        defaults.set(true, forKey: "uzume.onboarding.photosensitivityAcknowledged")

        vm.resetOnboarding()

        #expect(defaults.object(forKey: "uzume.onboarding.photosensitivityAcknowledged") == nil)
    }

    @Test func aboutSection_populatedFromInjectedData() {
        let (vm, _) = makeVM()
        #expect(vm.about.appVersion == "1.0")
        #expect(vm.about.buildNumber == "100")
        #expect(vm.about.macOSVersion == "macOS 15.0")
        #expect(vm.about.gpuFamily == "Apple M2")
    }

    @Test func debugInfo_containsSystemInfo_noAudioData() {
        let (vm, _) = makeVM()
        let info = vm.about.debugInfo
        #expect(info.contains("Uzume"))
        #expect(info.contains("1.0"))
        #expect(info.contains("Apple M2"))
        // Must not contain audio or session data keywords.
        #expect(!info.contains("bass"))
        #expect(!info.contains("FFT"))
        #expect(!info.contains("stem"))
    }
}

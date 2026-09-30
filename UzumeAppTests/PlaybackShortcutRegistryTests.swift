// PlaybackShortcutRegistryTests — Unit tests for PlaybackShortcutRegistry (U.6 Part B).

import Foundation
import Orchestrator
import Testing
@testable import UzumeApp

// MARK: - Stub router

@MainActor
private final class StubActionRouter: PlaybackActionRouter, @unchecked Sendable {
    var moreLikeThisCount = 0
    var lessLikeThisCount = 0
    var reshuffleCount = 0
    var nudgeCalls: [(NudgeDirection, Bool)] = []
    var rePlanCount = 0
    var undoCount = 0

    func moreLikeThis() { moreLikeThisCount += 1 }
    func lessLikeThis() { lessLikeThisCount += 1 }
    func reshuffleUpcoming() { reshuffleCount += 1 }
    func presetNudge(_ direction: NudgeDirection, immediate: Bool) { nudgeCalls.append((direction, immediate)) }
    func rePlanSession() { rePlanCount += 1 }
    func undoLastAdaptation() { undoCount += 1 }
}

@MainActor
private func makeRegistry() -> (PlaybackShortcutRegistry, StubActionRouter) {
    let router = StubActionRouter()
    let registry = PlaybackShortcutRegistry(
        actionRouter: router,
        onToggleFullscreen: {},
        onMoveToSecondaryDisplay: {},
        onToggleOverlay: {},
        onToggleDebug: {},
        onHandleEsc: {},
        onShowHelp: {}
    )
    return (registry, router)
}

// MARK: - Suite

@Suite("PlaybackShortcutRegistry")
@MainActor
struct PlaybackShortcutRegistryTests {

    @Test func allShortcutsUnique_byID() {
        let (registry, _) = makeRegistry()
        let ids = registry.shortcuts.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count, "Duplicate shortcut IDs: \(ids)")
    }

    @Test func registryCoversAllExpectedIDs() {
        let (registry, _) = makeRegistry()
        let expectedIDs: Set<String> = [
            "fullscreenToggle", "fullscreenSecondary", "overlayToggle",
            "endSession", "helpOverlay",
            "moreLikeThis", "lessLikeThis", "reshuffleUpcoming",
            "presetNudgeNext", "presetNudgePrev", "presetCutNext", "presetCutPrev",
            "rePlan", "undoAdaptation", "debugToggle"
        ]
        let registeredIDs = Set(registry.shortcuts.map(\.id))
        let missing = expectedIDs.subtracting(registeredIDs)
        #expect(missing.isEmpty, "Missing shortcut IDs: \(missing)")
    }

    @Test func actionRouterStubs_areInvokable_withoutCrash() {
        let (_, router) = makeRegistry()
        router.moreLikeThis()
        router.lessLikeThis()
        router.reshuffleUpcoming()
        router.presetNudge(.next, immediate: false)
        router.presetNudge(.previous, immediate: true)
        router.rePlanSession()
        router.undoLastAdaptation()
        #expect(router.moreLikeThisCount == 1)
        #expect(router.nudgeCalls.count == 2)
    }
}

// MARK: - BR.4 (F8): the public build's keys

@Suite("Public build keys (BR.4)")
@MainActor
struct PublicBuildShortcutTests {

    private func registry(_ flavor: BuildFlavor) -> PlaybackShortcutRegistry {
        PlaybackShortcutRegistry(
            actionRouter: StubActionRouter(),
            onToggleFullscreen: {},
            onMoveToSecondaryDisplay: {},
            onToggleOverlay: {},
            onToggleDebug: {},
            onHandleEsc: {},
            onShowHelp: {},
            onToggleDiagnosticHold: {},
            onToggleAudioStallCard: {},
            onDecreaseBeatPhaseOffset: {},
            onIncreaseBeatPhaseOffset: {},
            onCycleBarPhaseOffset: {},
            onDecreaseAudioOutputLatency: {},
            onIncreaseAudioOutputLatency: {},
            flavor: flavor
        )
    }

    @Test func public_hasNoDeveloperKeysOrBugIDs() {
        let shortcuts = registry(.public).shortcuts
        #expect(!shortcuts.contains { $0.category == .developer })
        #expect(!shortcuts.contains { $0.label.contains("BUG-") })
        #expect(shortcuts.filter { $0.key == "." }.count <= 1, "'.' is never bound twice (BR.15 hides reshuffle)")
        #expect(registry(.developer).shortcuts.contains { $0.category == .developer }, "developer build unchanged")
    }

    @Test func plus_firesWithShift_asOnUSAndUKLayouts() throws {
        let plus = try #require(registry(.developer).shortcut(withID: "moreLikeThis"))
        #expect(plus.matches(characters: "+", modifiers: [.shift]), "US/UK: + is Shift+=")
        #expect(plus.matches(characters: "+", modifiers: []), "layouts / numpad with an unshifted +")
        #expect(!plus.matches(characters: "+", modifiers: [.command]))
    }

    @Test func lettersAndArrows_keepExactShift() throws {
        let reg = registry(.developer)
        let nudge = try #require(reg.shortcuts.first { $0.key == "\u{F703}" && $0.modifiers.isEmpty })
        #expect(!nudge.matches(characters: "\u{F703}", modifiers: [.shift]), "→ and ⇧→ stay distinct")
        let help = try #require(reg.shortcut(withID: "helpOverlay"))
        #expect(help.matches(characters: "?", modifiers: [.shift]))
    }
}

// MARK: - BR.15 (E4): adaptation keys that don't do what they say are hidden for the beta

extension PublicBuildShortcutTests {

    @Test func public_hidesTheUnwiredAdaptationKeys_developerKeepsThem() {
        let publicIDs = Set(registry(.public).shortcuts.map(\.id))
        let developerIDs = Set(registry(.developer).shortcuts.map(\.id))
        #expect(publicIDs.isDisjoint(with: PlaybackShortcutRegistry.unwiredIDs), "hidden: - + . ← → ⌘R")
        #expect(PlaybackShortcutRegistry.unwiredIDs.isSubset(of: developerIDs), "developer build keeps them")
        // What the tester keeps: the immediate cuts and undo.
        #expect(publicIDs.isSuperset(of: ["presetCutNext", "presetCutPrev", "undoAdaptation", "helpOverlay"]))
        #expect(!BuildFlavor.public.exposesUnwiredControls && BuildFlavor.developer.exposesUnwiredControls)
    }

    /// E5 / E14 source shape: tier + quality ceiling, and blocklist + toast toggle, sit behind the flag.
    @Test func settings_hideTheUnwiredControls() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UzumeApp/Views/Settings/VisualsSettingsSection.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        let gates = src.components(separatedBy: "if BuildFlavor.current.exposesUnwiredControls {")
        #expect(gates.count == 3, "two gated blocks")
        #expect(gates[1].prefix(900).contains("viewModel.deviceTierOverride"))
        #expect(gates[1].prefix(1_800).contains("viewModel.qualityCeiling"))
        #expect(gates[2].prefix(900).contains("viewModel.excludedPresetCategories"))
        #expect(gates[2].prefix(1_200).contains("viewModel.showLiveAdaptationToasts"))
    }
}

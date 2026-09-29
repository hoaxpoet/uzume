// MeshCapabilityCatalogTests — BR.1 scene reach.
//   K1 (decision 3): mesh-shader scenes (Fractal Tree) are excluded from planning, reactive
//   mode and the Shift+→ walk on pre-Apple8 GPUs.
//   K3 / E13 / F15 / A13: the public build reaches only certified, non-diagnostic scenes.

import Foundation
import Presets
import Shared
import Testing
@testable import UzumeApp

// MARK: - GPU capability gate (BR.1 / K1)

@Suite("Mesh-shader scenes are excluded on pre-Apple8 GPUs (BR.1 / K1)")
struct MeshCapabilityCatalogTests {

    private static func descriptor(_ name: String, passes: String) throws -> PresetDescriptor {
        let json = """
        {"name":"\(name)","family":"particles","passes":[\(passes)],
         "visual_density":0.5,"motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},
         "transition_affordances":["crossfade"],"certified":true}
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    @Test func apple7_dropsMeshScenes_apple8_keepsEverything() throws {
        let tree = try Self.descriptor("Fractal Tree", passes: "\"mesh_shader\"")
        let other = try Self.descriptor("Nacre", passes: "\"mv_warp\"")
        let catalog = [tree, other]
        #expect(tree.passes.contains(.meshShader))

        let apple7 = VisualizerEngine.capableCatalog(catalog, supportsNativeMeshShaders: false)
        #expect(apple7.map(\.name) == ["Nacre"])
        let apple8 = VisualizerEngine.capableCatalog(catalog, supportsNativeMeshShaders: true)
        #expect(apple8.map(\.name) == ["Fractal Tree", "Nacre"])
    }

    /// Source shape: planner, reactive mode and the Shift+→ walk all read the gated catalog.
    @Test func everyCatalogSiteUsesTheGate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let orchestrator = try String(
            contentsOf: root.appendingPathComponent("UzumeApp/VisualizerEngine+Orchestrator.swift"), encoding: .utf8
        )
        #expect(!orchestrator.contains("presetLoader.presets.map"))
        #expect(orchestrator.components(separatedBy: "let catalog = plannableCatalog").count == 4)
        let router = try String(
            contentsOf: root.appendingPathComponent("UzumeApp/Services/DefaultPlaybackActionRouter.swift"),
            encoding: .utf8
        )
        #expect(router.contains("getCatalog: { [weak engine] in engine?.plannableCatalog ?? [] }"))
    }
}

// MARK: - Public build reaches only checked scenes (BR.1 / K3, E13, F15, A13)

@Suite("The public build reaches only certified, non-diagnostic scenes")
@MainActor
struct PublicFlavorSceneReachTests {

    private static func descriptor(
        _ name: String, certified: Bool, diagnostic: Bool = false
    ) throws -> PresetDescriptor {
        let family = diagnostic ? "" : "\"family\":\"particles\","
        let json = """
        {"name":"\(name)",\(family)"is_diagnostic":\(diagnostic),
         "visual_density":0.5,"motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},
         "transition_affordances":["crossfade"],"certified":\(certified)}
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    private static func catalog() throws -> [PresetDescriptor] {
        [
            try descriptor("Nacre", certified: true),
            try descriptor("FFT Sandbox", certified: false),
            try descriptor("Spectral Cartograph", certified: true, diagnostic: true),
            try descriptor("Waveform", certified: false),
            try descriptor("Aurora Veil", certified: true)
        ]
    }

    @Test func walkCatalog_publicIsCertifiedNonDiagnostic_developerIsEverything() throws {
        let catalog = try Self.catalog()
        #expect(catalog[2].isDiagnostic)
        #expect(DefaultPlaybackActionRouter.walkCatalog(catalog, flavor: .public).map(\.name)
                == ["Aurora Veil", "Nacre"])
        #expect(DefaultPlaybackActionRouter.walkCatalog(catalog, flavor: .developer).count == 5)
    }

    /// Shift+→ through the router itself: a full lap in the public build lands only on checked scenes.
    @Test func shiftRight_inThePublicBuild_neverLandsOnAnUncheckedScene() throws {
        let catalog = try Self.catalog()
        var current: String?
        var visited: [String] = []
        let router = DefaultPlaybackActionRouter(
            getCurrentPresetID: { current },
            getCatalog: { catalog },
            onApplyPresetOverride: { id, _ in current = id; visited.append(id) },
            flavor: .public
        )
        for _ in 0..<4 { router.presetNudge(.next, immediate: true) }
        let names = Set(catalog.filter { visited.contains($0.id) }.map(\.name))
        #expect(names == ["Aurora Veil", "Nacre"])
    }

    @Test func flavorCapability() {
        #expect(BuildFlavor.developer.exposesUncheckedScenes)
        #expect(!BuildFlavor.public.exposesUncheckedScenes)
    }

    /// Source shape: the Settings toggle, the engine push and the user-preset folder are gated.
    @Test func settingsToggle_enginePush_andUserFolder_areGatedOnTheFlavor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func src(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let settings = try src("UzumeApp/Views/Settings/VisualsSettingsSection.swift")
        let gate = try #require(settings.range(of: "if BuildFlavor.current.exposesUncheckedScenes {"))
        let toggle = try #require(settings.range(of: "settings.visuals.show_uncertified_presets.label"))
        #expect(gate.upperBound < toggle.lowerBound)
        #expect(try src("UzumeApp/UzumeApp.swift").contains("engine.applyShowUncertifiedPresets(allowed && value)"))
        #expect(try src("UzumeApp/VisualizerEngine.swift")
            .contains("let userPresetsDir = BuildFlavor.current.exposesUncheckedScenes"))
    }
}

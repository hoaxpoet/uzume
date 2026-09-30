// MeshCapabilityCatalogTests — BR.1 scene reach.
//   K1 (decision 3): mesh-shader scenes (Fractal Tree) are excluded from planning, reactive
//   mode and the Shift+→ walk on pre-Apple8 GPUs.
//   K3 / E13 / F15 / A13: the public build reaches only certified, non-diagnostic scenes.

import Foundation
import MetalKit
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

// MARK: - BR.9 (audit C3 / G3): background preparation has its own analyzers

@Suite("Background preparation never shares the live analyzers (BR.9)")
struct PreparerAnalysisIsolationTests {

    @Test func preparerAnalysis_isFreshEveryTime() {
        let first = VisualizerEngine.makePreparerAnalysis()
        let second = VisualizerEngine.makePreparerAnalysis()
        #expect(first.stemAnalyzer !== second.stemAnalyzer)
        #expect(first.moodClassifier !== second.moodClassifier)
    }

    /// Source shape: the session-manager factory takes no analyzer or classifier (so the live
    /// ones can't be handed to it) and builds its own through `makePreparerAnalysis`.
    @Test func sessionManagerFactory_buildsItsOwn() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helpers = try String(
            contentsOf: root.appendingPathComponent("UzumeApp/VisualizerEngine+InitHelpers.swift"), encoding: .utf8)
        let factory = try #require(helpers.range(of: "static func makeSessionManager("))
        let body = helpers[factory.lowerBound...].prefix(1_500)
        #expect(!body.contains("analyzer: StemAnalyzer"), "no live analyzer parameter")
        #expect(!body.contains("classifier: MoodClassifier"), "no live classifier parameter")
        #expect(body.contains("let analysis = makePreparerAnalysis()"))
        #expect(body.contains("stemAnalyzer: analysis.stemAnalyzer"))
    }
}

// MARK: - Tier-1 render cap + Alfvén exclusion (BR.6b / decision 4)

@Suite("Tier-1 Macs: capped drawable, no Alfvén (BR.6b)")
@MainActor
struct Tier1RenderBudgetTests {

    @Test func cappedSize_keepsAspect_neverUpscales_staysWithinBudget() {
        let cap = CappedMTKView.tier1MaxPixels
        // MacBook Air 13" fullscreen (2560×1664 backing) and a 5K display.
        for backing in [CGSize(width: 2560, height: 1664), CGSize(width: 5120, height: 2880),
                        CGSize(width: 3840, height: 2160)] {
            let out = CappedMTKView.cappedSize(backing, maxPixels: cap)
            #expect(Double(out.width * out.height) <= cap)
            #expect(abs(out.width / out.height - backing.width / backing.height) < 0.01)
        }
        #expect(CappedMTKView.cappedSize(CGSize(width: 3840, height: 2160), maxPixels: cap)
                == CGSize(width: 2560, height: 1440))
        // At or under the budget: untouched.
        #expect(CappedMTKView.cappedSize(CGSize(width: 1920, height: 1080), maxPixels: cap)
                == CGSize(width: 1920, height: 1080))
    }

    @Test func capOnlyApplies_whenSet() {
        let view = CappedMTKView(frame: CGRect(x: 0, y: 0, width: 640, height: 360),
                                 device: MTLCreateSystemDefaultDevice())
        #expect(view.autoResizeDrawable, "native resolution by default (tier 2)")
        view.maxDrawablePixels = CappedMTKView.tier1MaxPixels
        #expect(!view.autoResizeDrawable)
    }

    private final class SizeSpy: NSObject, MTKViewDelegate {
        var sizes: [CGSize] = []
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { sizes.append(size) }
        func draw(in view: MTKView) {}
    }

    /// In a real window larger than the budget, the drawable is capped AND the render pipeline
    /// (the delegate) is told — so its textures follow the capped size, not the backing size.
    @Test func inALargeWindow_theDrawableIsCapped_andTheDelegateHearsIt() throws {
        let window = NSWindow.offscreen(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        defer { window.close() }
        let view = CappedMTKView(frame: window.contentLayoutRect, device: MTLCreateSystemDefaultDevice())
        let spy = SizeSpy()
        view.delegate = spy
        view.isPaused = true
        view.maxDrawablePixels = CappedMTKView.tier1MaxPixels
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.layout()

        let backing = view.convertToBacking(view.bounds).size
        #expect(Double(backing.width * backing.height) > CappedMTKView.tier1MaxPixels, "window exceeds the budget")
        #expect(Double(view.drawableSize.width * view.drawableSize.height) <= CappedMTKView.tier1MaxPixels)
        let told = try #require(spy.sizes.last, "the delegate was never told the drawable size")
        #expect(told == view.drawableSize)
    }

    @Test func alfven_excludedOnTier1_keptOnTier2() throws {
        let json = """
        {"name":"Alfv\\u00e9n","family":"particles",
         "visual_density":0.5,"motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},
         "transition_affordances":["crossfade"],"certified":true}
        """
        let alfven = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        #expect(VisualizerEngine.capableCatalog([alfven], supportsNativeMeshShaders: true, tier: .tier1).isEmpty)
        #expect(VisualizerEngine.capableCatalog([alfven], supportsNativeMeshShaders: true, tier: .tier2).count == 1)
    }
}

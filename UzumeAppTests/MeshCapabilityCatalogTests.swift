// MeshCapabilityCatalogTests — BR.1 / K1 (decision 3): mesh-shader scenes (Fractal Tree)
// are excluded from planning, reactive mode and the Shift+→ walk on pre-Apple8 GPUs.

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

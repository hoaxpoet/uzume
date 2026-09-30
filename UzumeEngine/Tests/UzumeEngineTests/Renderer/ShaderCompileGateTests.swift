// ShaderCompileGateTests — BR.6a / audit H1, H8: CI compiles every shader the app compiles,
// through the app's own source assembly and the runtime Metal compiler.
//
// The app compiles Metal from source at launch: `ShaderLibrary` concatenates the renderer's
// `.metal` files (a failure is `fatalError` in `VisualizerEngine` — every launch crashes), and
// `PresetLoader` builds each scene's translation unit(s) with its preamble (a failure silently
// drops the scene). These tests call exactly those two paths, so what they compile is what a
// tester's Mac compiles.
//
// Unlike `PresetLoaderCompileFailureTest` (which skips without a device and checks only a
// count), this gate FAILS when there is no Metal device — CI must never pass vacuously — and
// names every scene file that did not load. GitHub's macOS 15+ runners expose Apple's
// paravirtual Metal device, which compiles MSL.

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer

@Suite("Shader compile gate (BR.6a — CI)")
struct ShaderCompileGateTests {

    @Test func theRendererLibraryCompiles() throws {
        _ = try #require(MTLCreateSystemDefaultDevice(), "no Metal device — this gate must not pass vacuously")
        let library = try ShaderLibrary(context: try MetalContext())
        #expect(library.function(named: "fullscreen_vertex") != nil)
    }

    @Test func everySceneShaderCompiles() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device — this gate must not pass vacuously")
        let shaders = try #require(PresetLoader.bundledShadersURL)
        let sceneFiles = try FileManager.default
            .contentsOfDirectory(at: shaders, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { $0.pathExtension == "metal" && $0.lastPathComponent != "ShaderUtilities.metal" }
            .map(\.lastPathComponent)
        #expect(!sceneFiles.isEmpty)

        let loaded = Set(PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
            .presets.map(\.descriptor.shaderFileName))
        let dropped = sceneFiles.filter { !loaded.contains($0) }.sorted()
        #expect(dropped.isEmpty, """
            scene shader(s) failed to compile and would be silently missing from the app: \(dropped). \
            The failing source + compiler diagnostic are in $TMPDIR/uzume_shader_failure_<file>.
            """)
    }
}

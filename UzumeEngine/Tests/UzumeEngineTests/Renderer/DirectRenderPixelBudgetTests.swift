// DirectRenderPixelBudgetTests — EFB.1: the direct path's pixel budget keeps the rendered area fixed
// across displays (a fixed scale costs in proportion to the drawable).

import Testing
@testable import Renderer

@Suite("Direct render pixel budget (EFB.1)")
struct DirectRenderPixelBudgetTests {

    private let budget = 1152.0 * 648.0

    @Test("The budget renders the same area on a 1080p window, the Tier-1 1440p cap and a 4K drawable")
    func budgetHoldsTheRenderedArea() {
        for (width, height) in [(1920.0, 1080.0), (2560.0, 1440.0), (3840.0, 2160.0)] {
            let scale = Double(RenderPipeline.directRenderScale(1, budget: budget, drawablePixels: width * height))
            #expect(abs(width * scale * height * scale - budget) / budget < 1e-4, "\(width)x\(height) at \(scale)")
        }
        #expect(abs(RenderPipeline.directRenderScale(1, budget: budget, drawablePixels: 1920 * 1080) - 0.6) < 1e-4)
    }

    @Test("A small drawable is never upscaled past the preset's own scale; no budget means the scale")
    func budgetOnlyLowers() {
        #expect(RenderPipeline.directRenderScale(1, budget: budget, drawablePixels: 800 * 450) == 1)
        #expect(RenderPipeline.directRenderScale(0.5, budget: budget, drawablePixels: 800 * 450) == 0.5)
        #expect(RenderPipeline.directRenderScale(0.5, budget: nil, drawablePixels: 3840 * 2160) == 0.5)
    }
}

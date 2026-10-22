// RenderBudgetRefusalTests — VQ.0: a scene the render-target budget refuses is skipped and the next one
// plays (D-264, Matt's DECISION-NEEDED option A).

import Testing
@testable import UzumeApp

@Suite("RenderBudgetRefusal")
struct RenderBudgetRefusalTests {

    private func next(_ current: String, plan: [String], catalog: [String] = [], excluded: Set<String>) -> String? {
        VisualizerEngine.sceneAfterRefusal(current: current, planOrder: plan, catalog: catalog, excluded: excluded)
    }

    @Test("the next plan entry that is not refused plays, wrapping; else the catalog")
    func nextScene() {
        let plan = ["A", "B", "C", "B", "D"]
        #expect(next("B", plan: plan, excluded: ["B"]) == "C")
        #expect(next("D", plan: plan, excluded: ["D"]) == "A", "wraps to the start of the plan")
        #expect(next("C", plan: plan, excluded: ["C", "B", "D"]) == "A")
        #expect(next("X", plan: [], catalog: ["X", "Y"], excluded: ["X"]) == "Y", "no plan: the catalog")
        #expect(next("X", plan: ["X"], catalog: ["X"], excluded: ["X"]) == nil, "nothing left: stay")
    }
}

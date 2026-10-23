// RenderInventoryReport — the VQ.0 render-memory inventory as Markdown (pure; `RenderSoakDriver` feeds it).

import Foundation
import Metal
import Renderer

// MARK: - RenderInventoryReport

enum RenderInventoryReport {

    /// One scene at one size: what the budget charged and what Metal holds.
    struct Row {
        let scene: String
        let config: String
        /// Sum of the budget's live labelled targets.
        let labelledBytes: Int
        /// Drawable pool + MetalFX reservations.
        let reservedBytes: Int
        /// `device.currentAllocatedSize` (process-wide: includes every fixed-size allocation).
        let metalBytes: Int
        let gpuP50: Float?
        let targets: [RenderTargetBudget.Allocation]
    }

    static func megabytes(_ bytes: Int) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }

    /// The report. `configs` orders the columns; the first is the size-delta baseline and the last is
    /// the one whose targets are listed and whose largest set derives the ceiling.
    static func markdown(rows: [Row], configs: [String], machine: String) -> String {
        guard let base = configs.first, let top = configs.last else { return "" }
        let scenes = Array(Set(rows.map(\.scene))).sorted()
        func row(_ scene: String, _ config: String) -> Row? { rows.first { $0.scene == scene && $0.config == config } }

        let legend = "Charged = budget's live labelled targets + reservations (drawable pool, MetalFX), at Metal's "
            + "own `allocatedSize`. Metal = `device.currentAllocatedSize` (process-wide). The size check compares "
            + "how each grows from \(base) to \(top): fixed-size allocations cancel in that difference, so the "
            + "labelled growth must match Metal's within 10 %."
        var out = ["# VQ.0 render-memory inventory", "", "Machine: `\(machine)`", "", legend, ""]
        out.append("| Scene | " + configs.map { "Charged MB @ \($0)" }.joined(separator: " | ")
                   + " | Metal Δ MB | Labelled Δ MB | Gap | GPU p50 ms @ \(top) |")
        out.append("|---|" + String(repeating: "---|", count: configs.count + 4))
        for scene in scenes {
            let charged = configs.map { config in
                row(scene, config).map { megabytes($0.labelledBytes + $0.reservedBytes) } ?? "—"
            }
            var check = ["—", "—", "—"]
            if let low = row(scene, base), let high = row(scene, top) {
                let metal = high.metalBytes - low.metalBytes
                let labelled = (high.labelledBytes + high.reservedBytes) - (low.labelledBytes + low.reservedBytes)
                let gap = labelled == 0 ? 0 : Double(metal - labelled) / Double(abs(labelled)) * 100
                check = [megabytes(metal), megabytes(labelled), String(format: "%+.0f %%", gap)]
            }
            let gpu = row(scene, top)?.gpuP50.map { String(format: "%.2f", $0) } ?? "—"
            out.append("| \(scene) | " + (charged + check + [gpu]).joined(separator: " | ") + " |")
        }

        func charged(_ row: Row) -> Int { row.labelledBytes + row.reservedBytes }
        if let largest = scenes.compactMap({ row($0, top) }).max(by: { charged($0) < charged($1) }) {
            out += ["", "Largest set @ \(top): **\(largest.scene)**, \(megabytes(charged(largest))) MB "
                    + "(`largestScene4KSetBytes = \(charged(largest))`)."]
        }

        out += ["", "## Targets @ \(top)", "",
                "| Scene | Owner | Label | Size | Format | Storage | MB |", "|---|---|---|---|---|---|---|"]
        for scene in scenes {
            for target in row(scene, top)?.targets ?? [] {
                out.append("| \(scene) | \(target.owner) | \(target.label) | \(target.width)×\(target.height) | "
                           + "\(name(target.pixelFormat)) | \(name(target.storageMode)) | \(megabytes(target.bytes)) |")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func name(_ storage: MTLStorageMode) -> String {
        switch storage {
        case .shared: return "shared"
        case .private: return "private"
        case .memoryless: return "memoryless"
        case .managed: return "managed"
        @unknown default: return "?"
        }
    }

    private static let formatNames: [MTLPixelFormat: String] = [
        .bgra8Unorm_srgb: "bgra8Unorm_srgb", .bgra8Unorm: "bgra8Unorm", .rgba8Unorm: "rgba8Unorm",
        .rgba8Snorm: "rgba8Snorm", .rgba16Float: "rgba16Float", .rg16Float: "rg16Float", .r16Float: "r16Float",
        .r32Float: "r32Float", .rg32Float: "rg32Float", .rgba32Float: "rgba32Float", .depth32Float: "depth32Float",
    ]

    static func name(_ format: MTLPixelFormat) -> String { formatNames[format] ?? "raw \(format.rawValue)" }
}

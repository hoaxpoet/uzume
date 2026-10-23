// GPUCapability — the one launch line that says what this Mac's GPU is (VQ.0, D-264).
//
// Measured, not classified: chip, GPU core count (IORegistry `gpu-core-count`), physical memory,
// `recommendedMaxWorkingSetSize`, the render-target budget's ceiling and the drawable's native size.
// `DeviceTier` / `detectDeviceTier` are deliberately untouched — the tier feeds the Orchestrator's
// plans, and reclassifying it is decided later from the data this line collects.

import CoreGraphics
import Foundation
import IOKit
import Metal

// MARK: - GPUCapability

/// What this Mac's GPU is, for the session log and the Report a Problem bundle (BR.5).
public struct GPUCapability: Sendable, Equatable {
    public let chip: String
    public let gpuCores: Int?
    public let physicalMemoryBytes: UInt64
    public let recommendedWorkingSetBytes: UInt64
    public let budgetCeilingBytes: Int
    public let drawableNative: CGSize?

    public init(chip: String, gpuCores: Int?, physicalMemoryBytes: UInt64, recommendedWorkingSetBytes: UInt64,
                budgetCeilingBytes: Int, drawableNative: CGSize?) {
        self.chip = chip
        self.gpuCores = gpuCores
        self.physicalMemoryBytes = physicalMemoryBytes
        self.recommendedWorkingSetBytes = recommendedWorkingSetBytes
        self.budgetCeilingBytes = budgetCeilingBytes
        self.drawableNative = drawableNative
    }

    /// This Mac, now.
    public static func current(device: MTLDevice, budgetCeilingBytes: Int, drawableNative: CGSize?) -> GPUCapability {
        GPUCapability(chip: sysctlString("machdep.cpu.brand_string") ?? device.name,
                      gpuCores: gpuCoreCount(),
                      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                      recommendedWorkingSetBytes: device.recommendedMaxWorkingSetSize,
                      budgetCeilingBytes: budgetCeilingBytes,
                      drawableNative: drawableNative)
    }

    /// The line, e.g. `GPU_CAPABILITY chip="Apple M2 Pro" gpu_cores=16 memory_gb=16.0
    /// working_set_mb=12124 budget_ceiling_mb=… drawable_native=3840x2160`.
    public var logLine: String {
        let gib = Double(physicalMemoryBytes) / 1_073_741_824
        let drawable = drawableNative.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
        return "GPU_CAPABILITY chip=\"\(chip)\" gpu_cores=\(gpuCores.map(String.init) ?? "?") "
            + String(format: "memory_gb=%.1f ", gib)
            + "working_set_mb=\(recommendedWorkingSetBytes / 1_048_576) "
            + "budget_ceiling_mb=\(budgetCeilingBytes / 1_048_576) drawable_native=\(drawable)"
    }

    /// The most recent line logged this process (the problem report includes it). Main thread.
    nonisolated(unsafe) public static var lastLogged: String?

    // MARK: Probes

    /// `gpu-core-count` from the first `AGXAccelerator` in the IORegistry; nil if absent.
    public static func gpuCoreCount() -> Int? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AGXAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            let key = "gpu-core-count" as CFString
            let property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)
            if let value = property?.takeRetainedValue() as? NSNumber { return value.intValue }
        }
        return nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
    }
}

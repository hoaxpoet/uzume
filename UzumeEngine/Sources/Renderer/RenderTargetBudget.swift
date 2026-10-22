// RenderTargetBudget — the one allocator for every render target whose size follows the display (VQ.0, D-264).
//
// Every size-scaled texture (feedback, canvas, post-process, ray-march G-buffer, mv_warp, staged,
// the direct half-res target, MFX.2's targets, the size-scaled particle scenes) is made here, and
// the drawable pool and any MetalFX scaler are charged here as opaque reservations. The budget
// charges what Metal charges — each texture's `allocatedSize`, checked up front with
// `heapTextureSizeAndAlign` — never w×h×bpp, and refuses a request that would cross its ceiling.
// A request is all-or-nothing: a refusal creates nothing, so nothing partial is left behind.
//
// Live targets are tracked through WEAK references: the total is the sum of targets still alive (a
// command buffer in flight keeps its targets alive, so they stay charged until it completes) plus
// the reservations. So "release" means the owner drops its references — after the frames in flight
// have drained (`RenderPipeline.commitResize`) — and the total cannot drift from what Metal holds.

import Foundation
import Metal
import os.log

private let logger = Logger(subsystem: "io.uzume.renderer", category: "RenderTargetBudget")

// MARK: - RenderTargetBudget

/// Budgeted allocator for display-size-scaled render targets (VQ.0, D-264). Thread-safe.
public final class RenderTargetBudget: @unchecked Sendable {

    // MARK: Types

    /// One texture to create: its descriptor and the label it carries in captures and the inventory.
    public struct Request {
        public let descriptor: MTLTextureDescriptor
        public let label: String

        public init(_ descriptor: MTLTextureDescriptor, label: String) {
            self.descriptor = descriptor
            self.label = label
        }
    }

    /// A live target, as charged.
    public struct Allocation: Sendable, Equatable {
        public let owner: String
        public let label: String
        public let width: Int
        public let height: Int
        public let pixelFormat: MTLPixelFormat
        public let storageMode: MTLStorageMode
        /// Metal's own `allocatedSize`.
        public let bytes: Int
    }

    /// A request the budget declined.
    public struct Refusal: Sendable, Equatable {
        public let owner: String
        public let requestedBytes: Int
        public let totalBytes: Int
        public let ceilingBytes: Int
    }

    private struct Entry {
        weak var texture: MTLTexture?
        let allocation: Allocation
    }

    // MARK: State

    /// The device every target is created on.
    public let device: MTLDevice

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var reservations: [String: Int] = [:]
    private var _ceiling: Int
    private var _peakTotal = 0
    private var _refusals: [Refusal] = []
    private var _onRefusal: (@Sendable (Refusal) -> Void)?
    private var _reclaim: (@Sendable () -> Void)?

    // MARK: Init

    /// - Parameter ceiling: bytes the budget never crosses; nil derives it for this Mac.
    public init(device: MTLDevice, ceiling: Int? = nil) {
        self.device = device
        self._ceiling = ceiling ?? Self.ceiling(device: device)
    }

    // MARK: Ceiling

    /// The largest render set any certified scene needs at 3840×2160 with no BR.6b cap (what an
    /// M3/M4 allocates): targets + drawable pool + MetalFX reservation. Measured by the VQ.0
    /// inventory (`docs/diagnostics/VQ0_RENDER_MEMORY_INVENTORY.md`, Release, M2 Pro, 2026-10-22): Ferrofluid
    /// Ocean, 354.9 MB. Re-measure when a scene adds a size-scaled target. 0 = not measured (memory caps only).
    public static let largestScene4KSetBytes = 372_113_408

    /// The ceiling for a Mac: the largest scene's 4K set × 1.5, capped at
    /// `min(15 % of physical memory, 25 % of recommendedMaxWorkingSetSize)` (D-264).
    public static func ceiling(largestSetBytes: Int = largestScene4KSetBytes,
                               physicalMemory: UInt64,
                               recommendedWorkingSet: UInt64) -> Int {
        let fromMemory = Int(min(Double(physicalMemory) * 0.15, Double(recommendedWorkingSet) * 0.25))
        guard largestSetBytes > 0 else { return fromMemory }
        return min(largestSetBytes * 3 / 2, fromMemory)
    }

    /// This Mac's ceiling.
    public static func ceiling(device: MTLDevice) -> Int {
        ceiling(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                recommendedWorkingSet: device.recommendedMaxWorkingSetSize)
    }

    /// Bytes the budget never crosses. Settable for the floor simulation and tests.
    public var ceiling: Int {
        get { lock.withLock { _ceiling } }
        set { lock.withLock { _ceiling = newValue } }
    }

    // MARK: Storage policy

    /// True when GPU-only targets must stay CPU-readable: under XCTest, where suites read pipeline
    /// targets back, unless `UZUME_PRIVATE_TARGETS=1` forces production storage. Production: false.
    public static let cpuReadableTargets: Bool = {
        NSClassFromString("XCTestCase") != nil
            && ProcessInfo.processInfo.environment["UZUME_PRIVATE_TARGETS"] != "1"
    }()

    /// Storage for a size-scaled target: `.shared` only when the CPU reads it back, else `.private`
    /// (Apple GPUs compress private render targets losslessly: less bandwidth).
    public static func storageMode(cpuReads: Bool = false) -> MTLStorageMode {
        cpuReads || cpuReadableTargets ? .shared : .private
    }

    // MARK: Accounting

    /// Live targets + reservations, in bytes.
    public var totalBytes: Int { lock.withLock { unlockedTotal() } }

    /// The highest total seen since creation or the last `resetPeak()`.
    public var peakTotalBytes: Int { lock.withLock { _peakTotal } }

    /// Restart the peak from the current total.
    public func resetPeak() { lock.withLock { _peakTotal = unlockedTotal() } }

    /// Every target still alive, largest first.
    public var liveAllocations: [Allocation] {
        lock.withLock {
            prune()
            return entries.values.map(\.allocation).sorted { $0.bytes > $1.bytes }
        }
    }

    /// Current reservations by name.
    public var reservedBytes: [String: Int] { lock.withLock { reservations } }

    /// Every refusal so far.
    public var refusals: [Refusal] { lock.withLock { _refusals } }

    /// Called (outside the lock) when a request would cross the ceiling, before refusing it: the pipeline
    /// waits for the frames in flight, so targets a scene has already dropped — still alive only because
    /// a frame on the GPU uses them — free, and the request is checked again. Scene switches therefore
    /// never wait unless the budget is actually tight.
    public var reclaim: (@Sendable () -> Void)? {
        get { lock.withLock { _reclaim } }
        set { lock.withLock { _reclaim = newValue } }
    }

    /// Called for every refusal, synchronously on the allocating thread (so the caller can tell which
    /// scene it belongs to). Keep it cheap and never call back into the budget.
    public var onRefusal: (@Sendable (Refusal) -> Void)? {
        get { lock.withLock { _onRefusal } }
        set { lock.withLock { _onRefusal = newValue } }
    }

    // MARK: Allocation

    /// Create every texture in `requests`, or none: nil (and a refusal) when the set would cross the
    /// ceiling, nil (no refusal) when Metal cannot make one.
    public func makeTextures(owner: String, _ requests: [Request]) -> [MTLTexture]? {
        let estimate = requests.reduce(0) { $0 + estimatedBytes($1.descriptor) }
        guard admit(owner: owner, bytes: estimate) else { return nil }
        var made: [MTLTexture] = []
        for request in requests {
            guard let texture = device.makeTexture(descriptor: request.descriptor) else {
                logger.error("\(owner, privacy: .public): Metal could not make '\(request.label, privacy: .public)'")
                return nil
            }
            texture.label = request.label
            made.append(texture)
        }
        let actual = made.reduce(0) { $0 + $1.allocatedSize }
        let admitted: Bool = lock.withLock {
            // The estimate was low and the real set does not fit: drop it (nothing was charged).
            guard unlockedTotal() + actual <= _ceiling else { return false }
            for texture in made {
                let allocation = Allocation(
                    owner: owner,
                    label: texture.label ?? "",
                    width: texture.width,
                    height: texture.height,
                    pixelFormat: texture.pixelFormat,
                    storageMode: texture.storageMode,
                    bytes: texture.allocatedSize
                )
                entries[ObjectIdentifier(texture)] = Entry(texture: texture, allocation: allocation)
            }
            _peakTotal = max(_peakTotal, unlockedTotal())
            return true
        }
        guard admitted else {
            refuse(owner: owner, bytes: actual)
            return nil
        }
        return made
    }

    /// One texture (`makeTextures` with a single request).
    public func makeTexture(owner: String, label: String, descriptor: MTLTextureDescriptor) -> MTLTexture? {
        makeTextures(owner: owner, [Request(descriptor, label: label)])?.first
    }

    /// Charge an opaque reservation (the drawable pool, a MetalFX scaler), replacing any earlier one
    /// of the same name. Returns false — and charges nothing — when it would cross the ceiling, unless
    /// `force` (memory the OS allocates whatever we decide, such as the drawable pool).
    @discardableResult
    public func reserve(_ name: String, bytes: Int, force: Bool = false) -> Bool {
        func attempt() -> Bool {
            lock.withLock {
                let previous = reservations[name] ?? 0
                guard force || unlockedTotal() - previous + bytes <= _ceiling else { return false }
                reservations[name] = bytes
                _peakTotal = max(_peakTotal, unlockedTotal())
                return true
            }
        }
        if attempt() { return true }
        if let reclaim { reclaim(); if attempt() { return true } }
        refuse(owner: name, bytes: bytes)
        return false
    }

    /// Drop a reservation.
    public func releaseReservation(_ name: String) {
        _ = lock.withLock { reservations.removeValue(forKey: name) }
    }

    /// Bytes Metal will charge for `descriptor` (0 for memoryless).
    public func estimatedBytes(_ descriptor: MTLTextureDescriptor) -> Int {
        descriptor.storageMode == .memoryless ? 0 : device.heapTextureSizeAndAlign(descriptor: descriptor).size
    }

    // MARK: Private

    private func admit(owner: String, bytes: Int) -> Bool {
        func fits() -> Bool { lock.withLock { unlockedTotal() + bytes <= _ceiling } }
        if fits() { return true }
        if let reclaim { reclaim(); if fits() { return true } }
        refuse(owner: owner, bytes: bytes)
        return false
    }

    private func refuse(owner: String, bytes: Int) {
        let (refusal, callback): (Refusal, (@Sendable (Refusal) -> Void)?) = lock.withLock {
            let total = unlockedTotal()
            let refusal = Refusal(owner: owner, requestedBytes: bytes, totalBytes: total, ceilingBytes: _ceiling)
            _refusals.append(refusal)
            if _refusals.count > 1_024 { _refusals.removeFirst(_refusals.count - 1_024) }
            return (refusal, _onRefusal)
        }
        let previous = refusals.dropLast().last
        let repeated = previous.map { $0.owner == owner && $0.requestedBytes == bytes } ?? false
        if !repeated {   // a lazy allocator retrying every frame logs once
            logger.error("""
                refused \(owner, privacy: .public): \(bytes / 1_048_576) MB on \(refusal.totalBytes / 1_048_576) MB \
                of a \(refusal.ceilingBytes / 1_048_576) MB ceiling
                """)
        }
        callback?(refusal)
    }

    /// Caller holds `lock`.
    private func unlockedTotal() -> Int {
        prune()
        return entries.values.reduce(0) { $0 + $1.allocation.bytes } + reservations.values.reduce(0, +)
    }

    /// Caller holds `lock`. Forget targets nothing references any more.
    private func prune() {
        entries = entries.filter { $0.value.texture != nil }
    }
}

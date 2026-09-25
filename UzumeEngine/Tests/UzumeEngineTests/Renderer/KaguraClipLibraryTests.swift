// KaguraClipLibraryTests — KAG.1: the bundled Kagura clip resource, decoded through Renderer's
// `Bundle.module`. Nothing here is synthetic: every test reads the shipped `Resources/Kagura/` files
// that `tools/kagura/bake_clips.py` baked from CMU motion capture.

import CryptoKit
import Foundation
import Testing
@testable import Renderer

@Suite("KaguraClipLibrary")
struct KaguraClipLibraryTests {

    // MARK: - Fixtures

    /// The bake's library, in manifest order (`FAMILIES` in bake_clips.py; KAGURA_DESIGN §4).
    static let expected: [(id: String, dance: KaguraDance)] = [
        ("15_04@109.5-114", .twist), ("15_05@110-116", .twist),
        ("15_04@117-122.5", .cabbage), ("15_05@117-123", .cabbage),
        ("18_15@1-12.8", .chicken), ("20_01@0-10.7", .chicken),
        ("143_35@0.3-10.6", .macarena),
        ("15_04@98-104.5", .egyptian), ("15_05@98-104.5", .egyptian),
        ("05_12", .sway),
    ]

    /// `face_camera`'s target: camera yaw 35°, turned a further 35° (the three-quarter facing).
    static let facingTargetDegrees = 70.0

    let library: KaguraClipLibrary

    init() throws {
        library = try KaguraClipLibrary.shared()
    }

    private func joint(_ name: String) throws -> Int {
        try #require(library.jointNames.firstIndex(of: name))
    }

    private func frames(_ clip: KaguraClip) -> [[SIMD3<Float>]] {
        (0..<clip.frameCount).map { clip.pose(at: Double($0) / clip.fps) }
    }

    // MARK: - Decode

    @Test("every clip decodes: the library's ten clips, 15 joints at 60 fps")
    func everyClipDecodes() {
        #expect(library.clips.map(\.id) == Self.expected.map(\.id))
        #expect(library.clips.map(\.dance) == Self.expected.map(\.dance))
        #expect(library.jointNames.count == 15)
        #expect(library.sway?.id == "05_12")
        for clip in library.clips {
            #expect(clip.fps == 60, "\(clip.id)")
            #expect(clip.frameCount > 60, "\(clip.id)")
            #expect(clip.positions.count == clip.frameCount * 15, "\(clip.id)")
            #expect(clip.pose(at: clip.duration / 2).count == 15, "\(clip.id)")
        }
    }

    @Test("SHA256SUMS matches the bundled manifest and binary")
    func checksumsMatch() throws {
        let dir = try #require(KaguraClipLibrary.resourceDirectory)
        let sums = try String(contentsOf: dir.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        let lines = sums.split(separator: "\n")
        #expect(lines.count == 2)
        for line in lines {
            let parts = line.split(separator: " ")
            let name = String(try #require(parts.last))
            let data = try Data(contentsOf: dir.appendingPathComponent(name))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == String(parts[0]), "\(name)")
        }
    }

    // MARK: - Pulse

    @Test("every pulse map is strictly monotone and passes through its pulse events")
    func pulseMapsAreMonotone() {
        for clip in library.clips {
            guard clip.dance != .sway else {
                #expect(clip.pulseKind == nil && clip.pulseMap.isEmpty && clip.pulsePeriod == nil)
                continue
            }
            #expect(clip.pulseMap.count == (clip.pulseEvents.count - 1) * 64 + 1, "\(clip.id)")
            #expect(zip(clip.pulseMap, clip.pulseMap.dropFirst()).allSatisfy { $0 < $1 }, "\(clip.id)")
            for (k, event) in clip.pulseEvents.enumerated() {
                #expect(abs(clip.clipTime(atPulse: Double(k)) - event) < 1e-5, "\(clip.id) pulse \(k)")
            }
        }
    }

    @Test("each clip's pulse rate is within ±2 per minute of its manifest value")
    func pulseRateMatchesManifest() throws {
        for clip in library.clips where clip.dance != .sway {
            let period = try #require(clip.pulsePeriod)
            let intervals = (0..<Int(clip.pulseSpan)).map {
                clip.clipTime(atPulse: Double($0 + 1)) - clip.clipTime(atPulse: Double($0))
            }.sorted()
            let median = intervals.count % 2 == 1
                ? intervals[intervals.count / 2]
                : (intervals[intervals.count / 2 - 1] + intervals[intervals.count / 2]) / 2
            #expect(abs(60 / median - 60 / period) <= 2, "\(clip.id): \(60 / median) vs \(60 / period)")
        }
    }

    @Test("twist clips never list the ×½ level; the other dances do")
    func twistExcludesHalfTime() {
        for clip in library.clips where clip.dance != .sway {
            if clip.dance == .twist {
                #expect(clip.allowedLevels == [1, 2, 4], "\(clip.id)")
            } else {
                #expect(clip.allowedLevels == [0.5, 1, 2, 4], "\(clip.id)")
            }
        }
    }

    // MARK: - Pose

    @Test("every clip's mean hip line sits within ±2° of the common three-quarter facing")
    func hipLineFacesThreeQuarter() throws {
        let (lhip, rhip) = (try joint("lhip"), try joint("rhip"))
        #expect(library.facingTargetDegrees == Self.facingTargetDegrees)
        for clip in library.clips {
            let hip = frames(clip).reduce(SIMD3<Float>()) { $0 + $1[lhip] - $1[rhip] }
            let degrees = atan2(Double(hip.z), Double(hip.x)) * 180 / .pi
            #expect(abs(degrees - Self.facingTargetDegrees) <= 2, "\(clip.id): \(degrees)°")
        }
    }

    @Test("every clip's lowest ankle is within ±2 cm of the floor")
    func feetOnTheFloor() throws {
        let (lankle, rankle) = (try joint("lankle"), try joint("rankle"))
        for clip in library.clips {
            let lowest = frames(clip).map { min($0[lankle].y, $0[rankle].y) }.min() ?? .infinity
            #expect(abs(lowest) <= 0.02, "\(clip.id): \(lowest) m")
        }
    }
}

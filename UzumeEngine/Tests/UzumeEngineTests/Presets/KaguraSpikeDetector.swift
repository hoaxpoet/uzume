// KaguraSpikeDetector — the KAG.0 spike's pulse detector, ported verbatim for the pulse-lock replay.
//
// FA #73: the replay measures the build with the SAME instrument that produced the spike's 100 %
// twist figure, so the two numbers mean the same thing. Sources (docs/presets/kagura_spike/kagura.py):
//   `_extrema(sig, fps)`   — both local maxima and minima of a smoothed, detrended signal
//   `beat_events(..., pulse="hipyaw")` — each extreme of the hip line's yaw
// and the scipy pieces they call, with scipy's defaults:
//   `gaussian_filter1d`   — mode "reflect", truncate 4.0
//   `find_peaks`          — local maxima (plateau midpoints), then `distance`, then `prominence`
//   `np.unwrap`, `np.ptp`.

import Foundation
import simd

enum KaguraSpikeDetector {

    /// `beat_events(P, names, fps, pulse="hipyaw")[0]`: hip-yaw extrema, seconds from the window start.
    static func hipYawEvents(_ frames: [[SIMD3<Float>]], leftHip: Int, rightHip: Int, fps: Double) -> [Double] {
        let yaw = frames.map { joints -> Double in
            let hip = joints[leftHip] - joints[rightHip]
            return atan2(Double(hip.z), Double(hip.x))
        }
        return extrema(unwrap(yaw).map { $0 * 180 / .pi }, fps: fps)
    }

    /// `_extrema(sig, fps)`.
    static func extrema(_ sig: [Double], fps: Double) -> [Double] {
        let trend = gaussianFilter1d(sig, sigma: fps * 1.0)
        var x = zip(sig, trend).map { $0 - $1 }
        x = gaussianFilter1d(x, sigma: fps * 0.03)
        let distance = Int(0.2 * fps)
        let prominence = ((x.max() ?? 0) - (x.min() ?? 0)) * 0.15
        let peaks = findPeaks(x, distance: distance, prominence: prominence)
        let troughs = findPeaks(x.map { -$0 }, distance: distance, prominence: prominence)
        return (peaks + troughs).sorted().map { Double($0) / fps }
    }

    // MARK: - numpy / scipy

    /// `np.unwrap` (discontinuity π).
    static func unwrap(_ phase: [Double]) -> [Double] {
        guard var last = phase.first else { return [] }
        var offset = 0.0
        var out = [last]
        for value in phase.dropFirst() {
            let delta = value - last
            // numpy: ddmod = mod(dd + π, 2π) − π, with ddmod = π where ddmod == −π and dd > 0.
            var mod = (delta + .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if mod < 0 { mod += 2 * .pi }
            mod -= .pi
            if mod == -.pi && delta > 0 { mod = .pi }
            if abs(delta) >= .pi { offset += mod - delta }
            out.append(value + offset)
            last = value
        }
        return out
    }

    /// `scipy.ndimage.gaussian_filter1d(x, sigma)` — mode "reflect", truncate 4.0.
    static func gaussianFilter1d(_ x: [Double], sigma: Double) -> [Double] {
        let radius = Int(4.0 * sigma + 0.5)
        guard radius > 0, !x.isEmpty else { return x }
        let raw = (-radius...radius).map { exp(-0.5 * Double($0 * $0) / (sigma * sigma)) }
        let total = raw.reduce(0, +)
        let kernel = raw.map { $0 / total }
        let count = x.count
        // "reflect": (d c b a | a b c d | d c b a) — the edge sample repeats.
        func sample(_ index: Int) -> Double {
            let period = 2 * count
            var i = index % period
            if i < 0 { i += period }
            return i < count ? x[i] : x[period - 1 - i]
        }
        return (0..<count).map { centre in
            var acc = 0.0
            for (k, weight) in kernel.enumerated() { acc += weight * sample(centre + k - radius) }
            return acc
        }
    }

    /// `scipy.signal.find_peaks(x, distance=, prominence=)` — sample indices.
    static func findPeaks(_ x: [Double], distance: Int, prominence: Double) -> [Int] {
        var peaks = localMaxima(x)
        if distance > 1 { peaks = selectByDistance(peaks, x: x, distance: distance) }
        return peaks.filter { prominenceOf($0, in: x) >= prominence }
    }

    /// `_local_maxima_1d`: strict maxima and the midpoint of flat-topped plateaus.
    private static func localMaxima(_ x: [Double]) -> [Int] {
        var out: [Int] = []
        var i = 1
        let last = x.count - 1
        while i < last {
            if x[i - 1] < x[i] {
                var ahead = i + 1
                while ahead < last && x[ahead] == x[i] { ahead += 1 }
                if x[ahead] < x[i] {
                    out.append((i + ahead - 1) / 2)
                    i = ahead
                }
            }
            i += 1
        }
        return out
    }

    /// `_select_by_peak_distance`: highest peaks first, suppress neighbours closer than `distance`.
    private static func selectByDistance(_ peaks: [Int], x: [Double], distance: Int) -> [Int] {
        var keep = [Bool](repeating: true, count: peaks.count)
        let order = peaks.indices.sorted { x[peaks[$0]] < x[peaks[$1]] }
        for j in order.reversed() where keep[j] {
            var k = j - 1
            while k >= 0 && peaks[j] - peaks[k] < distance { keep[k] = false; k -= 1 }
            k = j + 1
            while k < peaks.count && peaks[k] - peaks[j] < distance { keep[k] = false; k += 1 }
        }
        return peaks.indices.filter { keep[$0] }.map { peaks[$0] }
    }

    /// `_peak_prominences` with no window: height above the higher of the two flanking minima.
    private static func prominenceOf(_ peak: Int, in x: [Double]) -> Double {
        var leftMin = x[peak], rightMin = x[peak]
        var i = peak
        while i >= 0 && x[i] <= x[peak] { leftMin = min(leftMin, x[i]); i -= 1 }
        i = peak
        while i < x.count && x[i] <= x[peak] { rightMin = min(rightMin, x[i]); i += 1 }
        return x[peak] - max(leftMin, rightMin)
    }
}

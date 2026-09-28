// KaguraSpikeDetector — the KAG.0 spike's pulse detector, ported verbatim for the pulse-lock replay.
//
// FA #73: the replay measures the build with the SAME instrument that produced the spike's 100 %
// twist figure, so the two numbers mean the same thing. Sources (docs/presets/kagura_spike/kagura.py):
//   `_extrema(sig, fps)`   — both local maxima and minima of a smoothed, detrended signal
//   `beat_events(..., pulse="hipyaw")` — each extreme of the hip line's yaw
//   `beat_events(..., pulse="wrists")` — each bottom of the summed wrist height (KAG.3, cabbage patch)
//   `cmd_film`'s gesture block — RAW landings (minima of arm speed relative to the pelvis) in the
//     output, not `beat_events`' re-fitted lattice, which can pick another phase (KAG.3; chicken
//     dance, macarena, Egyptian walk)
//   `beat_events(...)`'s footfall branch — contact onsets of either ankle, merged within 40 % of a step
//     (KAG.3, the Charleston); `_contacts` with scipy's `binary_closing` / `binary_opening`
// and the scipy pieces they call, with scipy's defaults:
//   `gaussian_filter1d`   — mode "reflect", truncate 4.0
//   `find_peaks`          — local maxima (plateau midpoints), then `distance`, then `prominence`
//   `np.unwrap`, `np.ptp`, `np.gradient`.

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

    /// `beat_events(P, names, fps, pulse="wrists")[0]`: arm-circle bottoms, seconds from the window start.
    static func wristBottoms(_ frames: [[SIMD3<Float>]], leftWrist: Int, rightWrist: Int, fps: Double) -> [Double] {
        wristBottoms(summedHeight: frames.map { Double($0[leftWrist].y) + Double($0[rightWrist].y) }, fps: fps)
    }

    static func wristBottoms(summedHeight: [Double], fps: Double) -> [Double] {
        let wy = gaussianFilter1d(summedHeight, sigma: fps * 0.03)
        let prominence = ((wy.max() ?? 0) - (wy.min() ?? 0)) * 0.15
        return findPeaks(wy.map { -$0 }, distance: Int(0.2 * fps), prominence: prominence).map { Double($0) / fps }
    }

    /// `cmd_film`'s gesture block: raw landings in the output, seconds from the window start.
    /// `speed = gaussian_filter1d(|∇(arm joints − pelvis)|.sum · fps, 0.06 fps)`, minima at least
    /// 0.6 beat apart with 5 % prominence.
    static func gestureLandings(_ frames: [[SIMD3<Float>]], pelvis: Int, arms: [Int], fps: Double,
                                beatPeriod: Double) -> [Double] {
        let relative = arms.map { joint in frames.map { $0[joint] - $0[pelvis] } }
        let gradients = relative.map { track in
            (0..<3).map { axis in gradient(track.map { Double($0[axis]) }) }
        }
        let raw = frames.indices.map { index in
            gradients.map { g in (g[0][index] * g[0][index] + g[1][index] * g[1][index] + g[2][index] * g[2][index]).squareRoot() }
                .reduce(0, +) * fps
        }
        return gestureLandings(speed: raw, fps: fps, beatPeriod: beatPeriod)
    }

    static func gestureLandings(speed: [Double], fps: Double, beatPeriod: Double) -> [Double] {
        let smooth = gaussianFilter1d(speed, sigma: fps * 0.06)
        let prominence = ((smooth.max() ?? 0) - (smooth.min() ?? 0)) * 0.05
        return findPeaks(smooth.map { -$0 }, distance: Int(0.6 * fps * beatPeriod), prominence: prominence)
            .map { Double($0) / fps }
    }

    /// `beat_events(P, names, fps)`'s footfall branch: contact onsets merged within 40 % of the median step,
    /// seconds from the window start. With fewer than 6 onsets the spike falls back to pelvis-downs; the
    /// replay returns no events instead (such a window is too short to measure either way).
    static func footfallEvents(_ frames: [[SIMD3<Float>]], leftAnkle: Int, rightAnkle: Int, fps: Double) -> [Double] {
        let falls = footfalls(frames, ankles: [leftAnkle, rightAnkle], fps: fps)
        guard falls.count >= 6 else { return [] }
        let steps = zip(falls.dropFirst(), falls).map { $0 - $1 }.sorted()
        let median = steps.count % 2 == 1 ? steps[steps.count / 2] : (steps[steps.count / 2 - 1] + steps[steps.count / 2]) / 2
        var keep = [falls[0]]
        for time in falls.dropFirst() where time - keep[keep.count - 1] > 0.4 * median { keep.append(time) }
        return keep
    }

    /// `footfalls(P, names, fps)`: contact-onset times of either ankle, sorted.
    static func footfalls(_ frames: [[SIMD3<Float>]], ankles: [Int], fps: Double) -> [Double] {
        ankles.flatMap { ankle -> [Double] in
            let contact = contacts(frames.map { Double($0[ankle].y) }, fps: fps)
            return (1..<contact.count).filter { contact[$0] && !contact[$0 - 1] }.map { Double($0) / fps }
        }.sorted()
    }

    /// `_contacts` for one ankle: within 4 cm of its floor (5th percentile) and moving < 0.35 m/s
    /// vertically, closed then opened with an 80 ms window (scipy, border 0).
    static func contacts(_ height: [Double], fps: Double) -> [Bool] {
        let floor = percentile(height, 5)
        let velocity = gradient(height).map { $0 * fps }
        let raw = zip(height, velocity).map { $0 - floor < 0.04 && abs($1) < 0.35 }
        let width = max(1, Int((0.08 * fps).rounded()))
        return dilate(erode(erode(dilate(raw, width), width), width), width)
    }

    /// `scipy.ndimage.binary_dilation` with `ones(n)`, origin 0, border 0.
    static func dilate(_ x: [Bool], _ n: Int) -> [Bool] {
        let c = n / 2
        return x.indices.map { i in (0..<n).contains { k in let j = i - k + c; return j >= 0 && j < x.count && x[j] } }
    }

    /// `scipy.ndimage.binary_erosion` with `ones(n)`, origin 0, border 0.
    static func erode(_ x: [Bool], _ n: Int) -> [Bool] {
        let c = n / 2
        return x.indices.map { i in (0..<n).allSatisfy { k in let j = i + k - c; return j >= 0 && j < x.count && x[j] } }
    }

    /// `np.percentile` (linear).
    static func percentile(_ x: [Double], _ percent: Double) -> Double {
        let sorted = x.sorted()
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = percent / 100 * Double(sorted.count - 1)
        let lower = Int(position), upper = min(Int(position) + 1, sorted.count - 1)
        return sorted[lower] + (position - Double(lower)) * (sorted[upper] - sorted[lower])
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

    /// `np.gradient(x)`: central differences inside, one-sided first differences at the ends.
    static func gradient(_ x: [Double]) -> [Double] {
        guard x.count > 1 else { return x.map { _ in 0 } }
        return x.indices.map { index in
            switch index {
            case 0: return x[1] - x[0]
            case x.count - 1: return x[index] - x[index - 1]
            default: return (x[index + 1] - x[index - 1]) / 2
            }
        }
    }

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

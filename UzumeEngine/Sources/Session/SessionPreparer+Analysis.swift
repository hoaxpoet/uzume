// SessionPreparer+Analysis — Static analysis helpers for offline preview processing.
// All functions are static (no self) so they can run inside Task.detached without
// capturing the @MainActor-isolated SessionPreparer.

import Accelerate
import Audio
import DSP
import Foundation
import ML
import Shared

// MARK: - Internal Types

/// Result of `analyzeMIR` — avoids a large tuple return type.
private struct MIRAnalysisResult {
    var key: String?
    var mood: EmotionalState
    var centroidAvg: Float
    var sectionCount: Int
}

// MARK: - Analysis Pipeline

extension SessionPreparer {

    // MARK: - analyzePreview
    //
    // `analyzePreview` runs sequential pipeline stages (stem separation →
    // analyzer warmup → MIR → beat grid → drums beat grid → grid-onset
    // calibration) — kept inline so the sequential structure stays readable.

    /// Run the full analysis pipeline on a decoded preview clip.
    ///
    /// Executes stem separation → StemAnalyzer warmup → MIR analysis in sequence.
    /// Called from a `Task.detached` block inside `prepareTrack(_:)` (streaming
    /// path) and from `VisualizerEngine.prepareAndStartLocalFilePlayback(url:)`
    /// (LF.2 path, 2026-05-27) to pre-warm local-file playback.
    ///
    /// `public` so the App-layer LF.2 entry point can drive pre-analysis
    /// directly without going through the full `SessionManager` /
    /// `SessionPreparer.prepare(tracks:)` orchestration (LF.2 is single-file
    /// + ad-hoc, no playlist).
    ///
    /// - Parameters:
    ///   - preview: Mono Float32 PCM from PreviewDownloader or local-file decode.
    ///   - separator: Stem separator to use (injected for testing).
    ///   - analyzer: Stem energy analyzer (injected for testing).
    ///   - classifier: Mood classifier (injected for testing).
    ///   - beatGridAnalyzer: Optional Beat This! analyzer. When `nil`, the
    ///     returned `CachedTrackData.beatGrid` is `.empty`.
    ///   - prefetchedProfile: Optional pre-fetched track metadata. When
    ///     `prefetchedProfile.timeSignature` is non-nil, the ML-detected
    ///     `BeatGrid.beatsPerBar` is overridden before caching.
    ///   - wholeTrackAudio: `true` when `preview` holds the ENTIRE track, so the beat grid
    ///     is built across all of it instead of the first 30 s. The local-file call site
    ///     passes `true` — the same split DYN.1c already uses for `loudnessProfile`, where
    ///     only that call site knows the decode was of the whole file. Streaming leaves it
    ///     `false`: a preview IS 30 s and there is nothing further to analyse.
    /// - Returns: Fully populated `CachedTrackData`.
    nonisolated public static func analyzePreview(
        _ preview: PreviewAudio,
        separator: any StemSeparating,
        analyzer: any StemAnalyzing,
        classifier: any MoodClassifying,
        beatGridAnalyzer: (any BeatGridAnalyzing)? = nil,
        familyAnalyzer: (any InstrumentFamilyAnalyzing)? = nil,
        prefetchedProfile: PreFetchedTrackProfile? = nil,
        wholeTrackAudio: Bool = false,
        probe: PrepStageProbe = .disabled
    ) throws -> CachedTrackData {

        // Step 1: Separate stems from preview PCM.
        let result = try probe.measure(PrepStage.stemSeparation) {
            try separator.separate(
                audio: preview.pcmSamples,
                channelCount: 1,
                sampleRate: Float(preview.sampleRate)
            )
        }

        // Step 2: Read the separated stems BY VALUE (CLEAN.1.2 / BUG-031) — never
        // from the shared `separator.stemBuffers`, which the live + prep paths
        // race over. `result.stemWaveforms` is this call's own data.
        let stemWaveforms = result.stemWaveforms

        // Step 3: Multi-frame AGC warmup → StemFeatures snapshot.
        // BUG-141: the stems are in the SEPARATOR's time base (44.1 kHz), not the preview's.
        // At the file's rate a 48 kHz file stepped the warmup at 46.9 fps through 43.1 fps audio.
        let stemFeatures = probe.measure(PrepStage.stemWarmup) {
            warmUpAndAnalyze(
                stemWaveforms: stemWaveforms,
                sampleRate: separator.outputSampleRate ?? Float(preview.sampleRate),
                analyzer: analyzer
            )
        }

        // Step 4: Offline MIR analysis (key, mood, centroid), at 44.1 kHz (BUG-146).
        let mir = probe.measure(PrepStage.mir) {
            analyzeMIR(preview: preview, classifier: classifier)
        }

        // Steps 5 + 6: offline beat grids (full mix + drums stem), with metadata meter override.
        let (beatGrid, drumsBeatGrid) = probe.measure(PrepStage.beatGrid) {
            computeBeatGrids(
                preview: preview,
                drumsStem: stemWaveforms.count > 1
                    ? (stemWaveforms[1], Double(separator.outputSampleRate ?? Float(preview.sampleRate)))
                    : nil,
                beatGridAnalyzer: beatGridAnalyzer,
                prefetchedProfile: prefetchedProfile,
                wholeTrackAudio: wholeTrackAudio
            )
        }

        // Step 7 (BUG-007.8): per-track grid-vs-onset offset calibration.
        let gridOnsetOffsetMs = probe.measure(PrepStage.gridOnsetCalibration) {
            Self.computeGridOnsetOffsetMs(preview: preview, grid: beatGrid)
        }

        // Step 8 (IFC.4 / D-177): PANNs family-activity sweep over the preview clip (Tier-1; nil → empty).
        // The PREPPERF.2 TIMING scaffolding (clock/stageStart/durationMs) was removed on main; the family
        // analysis itself is unchanged.
        let familySeries = probe.measure(PrepStage.instrumentFamily) {
            familyAnalyzer?.analyzeFamilyActivity(
                samples: preview.pcmSamples, sampleRate: Double(preview.sampleRate)) ?? []
        }

        let profile = TrackProfile(
            bpm: storedTempo(grid: beatGrid, drums: drumsBeatGrid),
            key: mir.key,
            mood: mir.mood,
            spectralCentroidAvg: mir.centroidAvg,
            genreTags: [],
            stemEnergyBalance: stemFeatures,
            estimatedSectionCount: mir.sectionCount
        )

        return CachedTrackData(
            stemWaveforms: stemWaveforms,
            stemFeatures: stemFeatures,
            trackProfile: profile,
            beatGrid: beatGrid,
            drumsBeatGrid: drumsBeatGrid,
            gridOnsetOffsetMs: gridOnsetOffsetMs,
            instrumentFamilySeries: familySeries
        )
    }

    /// Compute the full-mix and drums-stem offline beat grids (Steps 5 + 6).
    ///
    /// Full-mix grid gets the metadata-driven meter override (Round 26,
    /// 2026-05-15): the ML detector sometimes guesses the meter wrong on odd
    /// time-signature tracks (Money's 7/4 → detected as 2/X). When the external
    /// metadata source returns a `time_signature`, override the auto-detected
    /// meter before caching so the cached value is correct on disk and the live
    /// drift tracker installs the corrected meter from the moment playback
    /// begins (no runtime-correction race window). Drums grid is the DSP.4
    /// diagnostic on stem index 1 (StemSeparator.stemLabels: vocals, drums,
    /// bass, other) — same analyzer instance (the MPSGraph graph is reusable
    /// across calls, no re-init). `nil` analyzer → both `.empty`.
    nonisolated private static func computeBeatGrids(
        preview: PreviewAudio,
        drumsStem: (samples: [Float], sampleRate: Double)?,
        beatGridAnalyzer: (any BeatGridAnalyzing)?,
        prefetchedProfile: PreFetchedTrackProfile?,
        wholeTrackAudio: Bool
    ) -> (beatGrid: BeatGrid, drumsBeatGrid: BeatGrid) {
        let beatGridRaw: BeatGrid
        if let gridAnalyzer = beatGridAnalyzer {
            beatGridRaw = gridAnalyzer.analyzeBeatGrid(
                samples: preview.pcmSamples,
                sampleRate: Double(preview.sampleRate),
                wholeTrack: wholeTrackAudio
            )
        } else {
            beatGridRaw = .empty
        }

        let beatGrid: BeatGrid
        if let timeSignature = prefetchedProfile?.timeSignature,
           !beatGridRaw.beats.isEmpty {
            beatGrid = beatGridRaw.overridingBeatsPerBar(timeSignature)
        } else {
            beatGrid = beatGridRaw
        }

        let drumsBeatGrid: BeatGrid
        if let gridAnalyzer = beatGridAnalyzer, let drumsStem {
            // BUG-140: stems come back at the separator's output rate (44.1 kHz in
            // production), not the preview's. Passing `preview.sampleRate` scaled every
            // 48 kHz local file's drums tempo by 48000/44100 = 1.088 (96 kHz: 2.18).
            drumsBeatGrid = gridAnalyzer.analyzeBeatGrid(
                samples: drumsStem.samples,
                sampleRate: drumsStem.sampleRate,
                wholeTrack: wholeTrackAudio
            )
        } else {
            drumsBeatGrid = .empty
        }

        return (beatGrid, drumsBeatGrid)
    }

    /// Replay the preview audio through the live BeatDetector offline and
    /// return the median (gridBeat − onsetTime) offset in milliseconds
    /// (BUG-007.8). Stored on `CachedTrackData` and applied at playback time
    /// as the drift EMA's initial bias — eliminates the per-track drift
    /// wandering observed in session 2026-05-07T22-00-00Z (drift averages
    /// spanned −95 to +96 ms across a single playlist). Returns 0 when the
    /// grid is empty or there's insufficient data.
    nonisolated private static func computeGridOnsetOffsetMs(
        preview: PreviewAudio, grid: BeatGrid
    ) -> Double {
        GridOnsetCalibrator().calibrate(
            samples: preview.pcmSamples,
            sampleRate: Double(preview.sampleRate),
            grid: grid
        )
    }

    // MARK: - StemAnalyzer Warmup

    /// Iterate through stem waveforms in 1024-sample hops, warming up the
    /// BandEnergyProcessor AGC before returning the final `StemFeatures` snapshot.
    ///
    /// Mirrors the multi-frame warmup in `VisualizerEngine+Stems.runStemSeparation()`.
    nonisolated private static func warmUpAndAnalyze(
        stemWaveforms: [[Float]],
        sampleRate: Float,
        analyzer: any StemAnalyzing
    ) -> StemFeatures {
        let hopSize = 1024
        let fps = sampleRate / Float(hopSize)
        let sampleCount = stemWaveforms.first?.count ?? 0
        guard sampleCount >= hopSize else { return .zero }

        var lastFeatures = StemFeatures.zero
        var offset = 0
        while offset + hopSize <= sampleCount {
            var frameWaveforms: [[Float]] = []
            for stem in stemWaveforms {
                if offset < stem.count {
                    let end = min(offset + hopSize, stem.count)
                    frameWaveforms.append(Array(stem[offset..<end]))
                } else {
                    frameWaveforms.append([Float](repeating: 0, count: hopSize))
                }
            }
            lastFeatures = analyzer.analyze(stemWaveforms: frameWaveforms, fps: fps)
            offset += hopSize
        }
        return lastFeatures
    }

    // MARK: - MIR Analysis

    /// Process the preview audio frame-by-frame through a fresh `MIRPipeline`
    /// to extract BPM, key, mood, and spectral centroid average.
    ///
    /// Uses a 1024-point non-overlapping vDSP FFT at the preview's native sample
    /// rate (~43 frames/second at 44100 Hz). At 30 seconds this yields ~1290 frames,
    /// enough for `BeatDetector` and `ChromaExtractor` to converge on stable values.
    nonisolated private static func analyzeMIR(
        preview: PreviewAudio,
        classifier: any MoodClassifying
    ) -> MIRAnalysisResult {
        // BUG-146: MIR runs at the stems' 44.1 kHz whatever the file's rate. Its 1024-point FFT at
        // the file's rate moved the mood features with it — at 96 kHz the Nyquist-normalised
        // centroid halved and 93.75 Hz bins pushed the key correlations +1.6/+1.9 σ, so the same
        // song read arousal 0.21 instead of 0.52.
        let sampleRate = Int(StemSeparator.modelSampleRate)
        let samples = preview.sampleRate == sampleRate
            ? preview.pcmSamples
            : BeatThisPreprocessor.resample(
                preview.pcmSamples, from: Double(preview.sampleRate), to: Double(sampleRate))
        let fftSize = 1024
        let binCount = fftSize / 2   // 512

        // The window→magnitude formula (Hann → |FFT| × 2/fftSize) lives in the shared
        // FFTMagnitudeKernel — byte-identical to the live FFTProcessor (BUG-066 / MOOD-FLUX.3).
        guard let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else {
            return MIRAnalysisResult(
                key: nil, mood: .neutral, centroidAvg: 0, sectionCount: 0
            )
        }

        let mir = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
        let fps = Float(sampleRate) / Float(fftSize)
        let dt = 1.0 / fps

        var centroidSum: Float = 0
        var frameCount = 0
        var moodAccumulator = MoodFeatureAccumulator()   // DYN.7
        var moodTrace: [EmotionalState] = []             // BUG-144
        var offset = 0

        while offset + fftSize <= samples.count {
            // Copy this frame's window into the kernel scratch, then run the shared formula.
            samples.withUnsafeBufferPointer { srcBuf in
                fft.windowed.withUnsafeMutableBufferPointer { dstBuf in
                    guard let srcBase = srcBuf.baseAddress,
                          let dstBase = dstBuf.baseAddress else { return }
                    dstBase.update(from: srcBase.advanced(by: offset), count: fftSize)
                }
            }
            fft.computeMagnitudes()

            let time = Float(frameCount) * dt
            let fv = mir.process(magnitudes: fft.magnitudes, fps: fps, time: time, deltaTime: dt)
            centroidSum += fv.spectralCentroid
            frameCount += 1

            // DYN.7 — the SAME measurement the live path makes. Previously this fed the
            // classifier INSTANTANEOUS features every 30th frame while live fed a 1.67 s
            // EMA every frame, and the per-call output alpha turned that cadence gap into a
            // 6.96 s window here against 0.167 s live. A track was therefore prepared with
            // one mood and played with another.
            let smoothed = moodAccumulator.update(
                frameFeatures: MoodFeatureAccumulator.assemble(
                    bands: [fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high],
                    centroidNormalized: fv.spectralCentroid,
                    rawFlux: mir.rawSmoothedFlux,
                    majorCorrelation: mir.latestMajorKeyCorrelation,
                    minorCorrelation: mir.latestMinorKeyCorrelation
                ),
                deltaTime: dt
            )
            // Classify every frame, as live does. The output window is wall-clock now, so
            // the cadence no longer sets the smoothing — it only sets the cost, and the
            // forward pass is a 10→64→32→16→2 MLP over a 30 s window.
            if let state = try? classifier.classify(features: smoothed, deltaTime: dt) {
                moodTrace.append(state)
            }

            offset += fftSize
        }

        let centroidAvg = frameCount > 0 ? centroidSum / Float(frameCount) : 0
        let sectionCount = frameCount > 0
            ? Int(mir.latestStructuralPrediction.sectionIndex) + 1
            : 0
        // SECDET.3b (C.4), updated at D-170: the live StructuralAnalyzer keeps
        // its count role (sectionIndex → estimatedSectionCount) ONLY. Boundary
        // detection was REMOVED at D-170 (SectionDetector deleted; below the
        // perceptual bar + streaming has no full-track audio — do not
        // reintroduce); the planner segments with equal slices.
        // (`boundaryTimestamps` / `boundaryNoveltyScores` remain on
        // StructuralAnalyzer for diagnostics, unread.)

        return MIRAnalysisResult(
            key: mir.stableKey,
            mood: songMood(moodTrace),
            centroidAvg: centroidAvg,
            sectionCount: sectionCount
        )
    }

    /// The BPM a prepared track stores (BUG-145; Matt: no BPM for songs without a steady beat).
    /// The beat tracker's octave-folded tempo — never the MIR BeatDetector's, whose sub-bass
    /// onsets fire at their 400 ms cooldown on every song (130–143 BPM whatever the music).
    /// nil when the D-154 gate calls the beat irregular: the scorer's neutral, no readout.
    nonisolated static func storedTempo(grid: BeatGrid, drums: BeatGrid) -> Float? {
        guard assessBeatIrregularity(grid: grid, drums: drums) != true else { return nil }
        return octaveFoldedTempoBPM(beats: grid.beats).map(Float.init)
    }

    /// The song's typical mood (BUG-144, Matt's option A): the per-frame median of valence and
    /// arousal after the first sixth, which is the classifier's warm-up (the KAG.0 spike's
    /// `load_session` rule). `classifier.currentState` after the loop was a 0.7 s EMA, so it
    /// described only the last second or two. On the beta playlist its rank agreement with the
    /// production chain was 0.59; this statistic scores 0.85. `.neutral` when no frame was classified.
    nonisolated static func songMood(_ trace: [EmotionalState]) -> EmotionalState {
        guard !trace.isEmpty else { return .neutral }
        let settled = trace[(trace.count / 6)...]
        func median(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        }
        return EmotionalState(
            valence: median(settled.map(\.valence)),
            arousal: median(settled.map(\.arousal))
        )
    }
}

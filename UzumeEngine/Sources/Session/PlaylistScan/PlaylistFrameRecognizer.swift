// PlaylistFrameRecognizer — on-device text recognition for playlist scanning (SCAN, D-260).
//
// Apple Vision (`VNRecognizeTextRequest`), a system framework — no bundled model,
// no network (consistent with D-009). Language correction is OFF: it "fixes"
// song titles into dictionary words ("Gomd" → "Good"). Frames are processed in
// memory and never written anywhere.

import CoreGraphics
import Foundation
import Vision

// MARK: - Protocol

/// Turns an image into recognized text lines. Injectable so the scan view model
/// can be driven by recorded observations in tests.
public protocol PlaylistTextRecognizing: Sendable {
    /// Recognize every text line inside `region` of `image` (normalized, top-left
    /// origin; the unit rect for the whole image). Boxes come back in
    /// whole-image coordinates.
    func recognize(_ image: CGImage, in region: CGRect) throws -> [ScanTextObservation]
}

// MARK: - PlaylistFrameRecognizer

/// `VNRecognizeTextRequest`-backed recognizer, tuned for a streaming app's track list.
public struct PlaylistFrameRecognizer: PlaylistTextRecognizing {

    /// Recognition languages. English first; the Latin-script European languages
    /// let Vision keep diacritics on names ("Glückskind", "ROSALÍA", "Fantôme X").
    public static let languages = ["en-US", "de-DE", "fr-FR", "es-ES", "pt-BR", "it-IT"]

    /// Create a recognizer.
    public init() {}

    /// Recognize every text line in `region` of `image` (synchronous; call off
    /// the main thread). Recognizing only the list pane matters: Vision
    /// downsamples a whole window, and short names ("i_o") drop out.
    public func recognize(_ image: CGImage, in region: CGRect) throws -> [ScanTextObservation] {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let area = region.intersection(unit)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixels = CGRect(
            x: area.minX * width,
            y: area.minY * height,
            width: area.width * width,
            height: area.height * height
        ).integral
        guard let cropped = area == unit ? image : image.cropping(to: pixels) else { return [] }
        return try recognizeWhole(cropped).map { observation in
            let box = observation.box
            let mapped = CGRect(
                x: area.minX + box.minX * area.width,
                y: area.minY + box.minY * area.height,
                width: box.width * area.width,
                height: box.height * area.height
            )
            return ScanTextObservation(text: observation.text, confidence: observation.confidence, box: mapped)
        }
    }

    private func recognizeWhole(_ image: CGImage) throws -> [ScanTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = Self.languages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision: normalized, bottom-left origin → flip to top-left.
            let flipped = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            return ScanTextObservation(text: best.string, confidence: Double(best.confidence), box: flipped)
        }
    }
}

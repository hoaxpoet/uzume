// PlaylistScreenReader — image → PlaylistScanFrame, remembering where the list is (SCAN, D-260).
//
// Two passes the first time: the whole window, to find the playlist pane, then
// just the pane (Vision downsamples a whole window; small names drop out). Later
// frames go straight to the remembered pane — the pane doesn't move while the
// user scrolls. If the pane read finds no list (window moved or resized), the
// next call starts over from the whole window.

import CoreGraphics
import Foundation

// MARK: - PlaylistScreenReader

/// Reads one image at a time; not thread-safe (one reader per scan).
public final class PlaylistScreenReader {

    private let recognizer: any PlaylistTextRecognizing
    private var listRegion: CGRect?

    /// Create a reader.
    public init(recognizer: any PlaylistTextRecognizing = PlaylistFrameRecognizer()) {
        self.recognizer = recognizer
    }

    /// Read one image of the playlist.
    public func read(_ image: CGImage) throws -> PlaylistScanFrame {
        if let region = listRegion {
            let frame = PlaylistFrameParser.parse(try recognizer.recognize(image, in: region))
            if !frame.rows.isEmpty || frame.reachedEnd { return frame }
            listRegion = nil
        }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let whole = PlaylistFrameParser.parse(try recognizer.recognize(image, in: unit))
        guard let region = whole.listRegion else { return whole }
        listRegion = region
        let pane = PlaylistFrameParser.parse(try recognizer.recognize(image, in: region))
        return pane.rows.count >= whole.rows.count ? pane : whole
    }

    /// Forget the pane position (e.g. a new batch of unrelated screenshots).
    public func reset() {
        listRegion = nil
    }
}

// BuildFlavor — the developer build vs the public build (CLEAN.2.5b, BUG-157).
//
// The public build is the notarized DMG `Scripts/release.sh` produces; only that
// script sets `UZUME_BUILD_FLAVOR = public`, which lands in Info.plist as
// `UzumeBuildFlavor` (so it is signed, and checkable on the artifact). Every other
// build — Debug and Release alike, including Release builds used for measurement —
// is the developer build (`Uzume.xcconfig` default).
// Matt (2026-09-29): "We need to start distinguishing between the developer
// version of the app and the public release, which would have few features."

import Foundation

// MARK: - BuildFlavor

/// Which audience this binary was built for. Gate developer-only features on
/// the capability properties below, not on `DEBUG`.
enum BuildFlavor: Sendable {
    /// Every build except the notarized release.
    case developer
    /// The notarized DMG testers install (`Scripts/release.sh`).
    case `public`

    /// The flavor this app was built as, from Info.plist `UzumeBuildFlavor`.
    static let current: BuildFlavor =
        Bundle.main.object(forInfoDictionaryKey: "UzumeBuildFlavor") as? String == "public" ? .public : .developer

    /// Whether the app keeps a diagnostic record of each session in
    /// `~/Documents/uzume_sessions`. Off in the public build: touching Documents
    /// makes macOS ask a new user for Documents access at launch (BUG-157).
    var recordsSessions: Bool { self == .developer }
}

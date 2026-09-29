// AudioStallOverlayView — Prominent center card shown when no fresh audio is
// reaching the visualizer while playing (the silent-tap family: BUG-057/055/058).
//
// More prominent than the bottom-right toast because this is a total loss of
// function. Non-blocking (click-through) — it overlays the frozen/black
// visualizer and auto-clears when audio returns; the parent drives `isVisible`
// from PlaybackErrorBridge's stall detector. The developer build keeps the Terminal fix
// ladder; the public build shows tester steps only (BR.4 / I2, F3, A9, D-165).

import SwiftUI

// MARK: - AudioStallOverlayView

/// Center overlay card with a plain-language explanation and a fix ladder for
/// the "Uzume isn't receiving audio" condition. Fades in/out on `isVisible`.
struct AudioStallOverlayView: View {

    static let accessibilityID = "uzume.playback.audioStallCard"

    let isVisible: Bool
    let reduceMotion: Bool
    var flavor: BuildFlavor = .current

    /// The numbered steps: `(text, Terminal command?)`. No Terminal step in the public build.
    static func steps(for flavor: BuildFlavor) -> [(String, String?)] {
        guard flavor.showsDeveloperDiagnostics else {
            return [
                (String(localized: "playback.audioStall.public.step1"), nil),
                (String(localized: "playback.audioStall.step3"), nil),
                (String(localized: "playback.audioStall.public.step3"), nil)
            ]
        }
        return [
            (String(localized: "playback.audioStall.step1"), "sudo killall coreaudiod"),
            (String(localized: "playback.audioStall.step2"), nil),
            (String(localized: "playback.audioStall.step3"), nil)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(UzumeAppColor.textSecondary)
                Text(String(localized: "playback.audioStall.headline"))
                    .font(.headline)
                    .foregroundStyle(UzumeAppColor.textPrimary)
            }

            Text(String(localized: "playback.audioStall.body"))
                .font(.subheadline)
                .foregroundStyle(UzumeAppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(Self.steps(for: flavor).enumerated()), id: \.offset) { index, step in
                    stepRow(number: index + 1, text: step.0, command: step.1)
                }
            }

            Text(String(localized: "playback.audioStall.autoClearHint"))
                .font(.caption)
                .foregroundStyle(UzumeAppColor.textTertiary)
        }
        .padding(24)
        .frame(maxWidth: 460, alignment: .leading)
        .performanceBackdrop()
        .opacity(isVisible ? 1 : 0)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.4), value: isVisible)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityLabel(String(localized: "a11y.audioStallCard.label"))
        .accessibilityHidden(!isVisible)
    }

    // MARK: - Step row

    /// One numbered step. When `command` is non-nil it is rendered verbatim in a
    /// monospaced pill (a literal Terminal command — not localizable copy).
    @ViewBuilder
    private func stepRow(number: Int, text: String, command: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(UzumeAppColor.onAccent)
                .frame(width: 20, height: 20)
                .background(UzumeAppColor.Performance.indicatorFill, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(UzumeAppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let command {
                    Text(verbatim: command)
                        .font(.callout.monospaced())
                        .foregroundStyle(UzumeAppColor.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(UzumeAppColor.Performance.fillStrong,
                                    in: RoundedRectangle(cornerRadius: UzumeAppRadius.sm))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

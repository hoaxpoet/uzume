// PhotosensitivityNoticeView — One-time sheet, presented by ContentView until acknowledged.
//
// Two CTAs (UX_SPEC §3.3): "Enable Reduce motion" sets the in-app Reduced motion to
// Always on and acknowledges (BR.1 / F6 — it used to open System Settings, a system-wide
// change the app then ignored at launch, F1); "I understand" acknowledges. ContentView
// persists the acknowledgement, so the notice does not reappear after either.

import SwiftUI

// MARK: - PhotosensitivityNoticeView

@MainActor
struct PhotosensitivityNoticeView: View {
    static let accessibilityID = "uzume.view.photosensitivityNotice"

    /// "Enable Reduce motion": the caller sets the in-app setting, then acknowledges.
    let onEnableReducedMotion: () -> Void
    let onAcknowledge: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "onboarding.photosensitivity.headline"))
                .font(.headline)

            Text(String(localized: "onboarding.photosensitivity.body"))
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(String(localized: "onboarding.photosensitivity.enable_reduce")) {
                    onEnableReducedMotion()
                }
                .accessibilityIdentifier("uzume.photosensitivity.openAccessibility")

                Button(String(localized: "onboarding.photosensitivity.acknowledge")) {
                    onAcknowledge()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .accessibilityIdentifier("uzume.photosensitivity.acknowledge")
            }
        }
        .padding(32)
        .frame(width: 480)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

// AboutSettingsSection — App version, license, and debug info (U.8 Part B).

import SwiftUI

// MARK: - AboutSettingsSection

struct AboutSettingsSection: View {

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.about.app.title", comment: "")) {
                LabeledContent(
                    NSLocalizedString("settings.about.version.label", comment: ""),
                    value: "\(viewModel.about.appVersion) (\(viewModel.about.buildNumber))"
                )
                LabeledContent(
                    NSLocalizedString("settings.about.macos.label", comment: ""),
                    value: viewModel.about.macOSVersion
                )
                LabeledContent(
                    NSLocalizedString("settings.about.gpu.label", comment: ""),
                    value: viewModel.about.gpuFamily
                )
            }

            Section(NSLocalizedString("settings.about.license.title", comment: "")) {
                Text(NSLocalizedString("settings.about.license.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // BR.16 (K7 / H9): the credit each licence asks for, where a tester can see it.
            Section(NSLocalizedString("settings.about.ack.title", comment: "")) {
                ForEach(Self.acknowledgements, id: \.key) { entry in
                    Link(destination: entry.url) {
                        Text(NSLocalizedString(entry.key, comment: ""))
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                }
                Link(NSLocalizedString("settings.about.ack.full", comment: ""), destination: Self.creditsURL)
            }

            Section {
                Button(NSLocalizedString("settings.about.copy_debug_info", comment: "")) {
                    viewModel.copyDebugInfo()
                }
                Text(NSLocalizedString("settings.about.copy_debug_info.caption", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.about", comment: ""))
    }
}

// MARK: - Acknowledgements (BR.16)

extension AboutSettingsSection {

    /// One row per obligation in `docs/CREDITS.md`, linking to the source. Adding bundled
    /// third-party work means adding a row here and a section there.
    static let acknowledgements: [(key: String, url: URL)] = [
        ("settings.about.ack.beat_this", url("https://github.com/CPJKU/beat_this")),
        ("settings.about.ack.open_unmix", url("https://github.com/sigsep/open-unmix-pytorch")),
        ("settings.about.ack.panns", url("https://zenodo.org/records/3987831")),
        ("settings.about.ack.auroras", url("https://www.shadertoy.com/view/XtGGRt")),
        ("settings.about.ack.fluid", url("https://github.com/PavelDoGreat/WebGL-Fluid-Simulation")),
        ("settings.about.ack.cmu", url("http://mocap.cs.cmu.edu/")),
        ("settings.about.ack.milkdrop", url("https://github.com/projectM-visualizer/presets-cream-of-the-crop"))
    ]

    static let creditsURL = url("https://github.com/hoaxpoet/uzume/blob/main/docs/CREDITS.md")

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { preconditionFailure("bad literal URL \(string)") }
        return url
    }
}

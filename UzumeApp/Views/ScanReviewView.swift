// ScanReviewView — what the scan found, before preparation starts (SCAN.3, D-260; UX_SPEC §4.4).
//
// Always shown (D-260 decision 2, default A): the user sees every row, can fix a
// misread or remove a row, scan again, or Continue into preparation.

import Session
import SwiftUI

// MARK: - ScanReviewView

struct ScanReviewView: View {
    static let accessibilityID = "uzume.view.spotify.scanReview"

    @ObservedObject var viewModel: SpotifyScanViewModel
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void

    @State private var editing: Int?
    @State private var draftTitle = ""
    @State private var draftArtist = ""
    @State private var isContinuing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.heading(count: viewModel.reviewRows.count, name: viewModel.reviewName))
                .font(.title3.weight(.semibold))
                .foregroundColor(UzumeAppColor.textPrimary)
                .accessibilityIdentifier("uzume.spotify.scanReview.heading")
            if !viewModel.reviewMissing.isEmpty {
                Text(String(format: String(localized: "scan.review.missing"),
                            Self.describe(viewModel.reviewMissing)))
                    .font(.callout)
                    .foregroundColor(StatusTone.warning.foreground)
                    .accessibilityIdentifier("uzume.spotify.scanReview.missing")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.reviewRows, id: \.number) { row in
                        rowView(row)
                        Divider().overlay(UzumeAppColor.lineSubtle)
                    }
                }
            }
            .background(UzumeAppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: UzumeAppRadius.md))
            HStack(spacing: 12) {
                Button(String(localized: "scan.review.scan_again")) { viewModel.scanAgain() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("uzume.spotify.scanReview.scanAgain")
                Spacer()
                Button(String(localized: "scan.review.continue")) {
                    isContinuing = true
                    Task { await viewModel.continueToPreparation(startSession: onConnect) }
                }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.reviewRows.isEmpty || isContinuing || editing != nil)
                .accessibilityIdentifier("uzume.spotify.scanReview.continue")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: 640)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: ScannedRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(row.number)")
                .font(.callout.monospacedDigit())
                .foregroundColor(UzumeAppColor.textTertiary)
                .frame(width: 32, alignment: .trailing)
            if editing == row.number {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(String(localized: "scan.review.title_placeholder"), text: $draftTitle)
                    TextField(String(localized: "scan.review.artist_placeholder"), text: $draftArtist)
                }
                .textFieldStyle(.roundedBorder)
                Button(String(localized: "scan.review.save")) {
                    viewModel.updateRow(number: row.number, title: draftTitle, artist: draftArtist)
                    editing = nil
                }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.title + (row.titleTruncated ? "…" : ""))
                        .font(.body)
                        .foregroundColor(UzumeAppColor.textPrimary)
                        .lineLimit(1)
                    Text(verbatim: row.artist.isEmpty ? "—" : row.artist + (row.artistTruncated ? "…" : ""))
                        .font(.callout)
                        .foregroundColor(UzumeAppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if row.isUnsure {
                    Label(String(localized: "scan.review.unsure"), systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundColor(StatusTone.warning.foreground)
                }
                Button {
                    draftTitle = row.title
                    draftArtist = row.artist
                    editing = row.number
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "scan.review.edit"))
                .accessibilityLabel(String(localized: "scan.review.edit"))
                Button {
                    viewModel.removeRow(number: row.number)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "scan.review.remove"))
                .accessibilityLabel(String(localized: "scan.review.remove"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityIdentifier("uzume.spotify.scanReview.row.\(row.number)")
    }

    // MARK: - Copy

    /// "Found 38 songs from [name]" / "Found 38 songs" (UX_SPEC §4.4).
    static func heading(count: Int, name: String?) -> String {
        switch (count == 1, name) {
        case (true, let name?): return String(format: String(localized: "scan.review.heading.named.one"), name)
        case (true, nil): return String(localized: "scan.review.heading.one")
        case (false, let name?): return String(format: String(localized: "scan.review.heading.named"), count, name)
        case (false, nil): return String(format: String(localized: "scan.review.heading"), count)
        }
    }

    /// "14–16, 22" — missing row numbers as runs.
    static func describe(_ gaps: [ScanGap]) -> String {
        gaps.map { $0.first == $0.last ? "\($0.first)" : "\($0.first)–\($0.last)" }.joined(separator: ", ")
    }
}

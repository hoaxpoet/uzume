// LocalFileTransportBar — LF.5.fix D-LF5-3; GAP C redesign (2026-05-28); DS.6 retokenized.
//
// Transport for local-file sessions only — it renders because Uzume owns this playback
// (COMPONENTS.md §LocalPlaybackTransport); a streaming session never sees it. Per the
// design system (DESIGN.md §Colors): violet is the interaction accent, so the play/pause
// disc is `UzumeAppColor.accent`; skip/stop glyphs sit at `textTertiary` and brighten
// to `textPrimary` on hover. The custom geometric Shape glyphs stay — they exist so the
// bar does not read as Spotify chrome. The bar is a solid `surfaceRaised` (not the
// blurred backdrop: an opaque surface owes the live frame no contrast measurement),
// bordered in `line`, and because it genuinely floats over the frame it takes the one
// shadow the system publishes, `--shadow-raised` — no glow (DESIGN.md §Don't).
//
// DS.1 moved the disc to violet; DS.6 finished the bar. Every colour here is a token
// from `UzumeTokens+App.swift`; the Phosphene-era dashboard palette this bar used to
// draw from is now confined to the diagnostic dashboard.

import SwiftUI

// MARK: - LocalFileTransportBar

struct LocalFileTransportBar: View {

    static let accessibilityID = "uzume.playback.lfTransport"

    let isPaused: Bool
    let onStop: () -> Void
    let onPrev: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    /// LFSEEK.1: the current track's position and length, and the jump the track bar asks for.
    var progress: () -> (position: TimeInterval, duration: TimeInterval)? = { nil }
    var onSeek: (TimeInterval) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            TrackSeekBar(progress: progress, onSeek: onSeek)
            buttons
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: UzumeAppRadius.lg, style: .continuous)
                .fill(UzumeAppColor.surfaceRaised)
                .shadow(
                    color: UzumeAppShadow.raisedColor,
                    radius: UzumeAppShadow.raisedRadius,
                    x: 0,
                    y: UzumeAppShadow.raisedY
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: UzumeAppRadius.lg, style: .continuous)
                .stroke(UzumeAppColor.line, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            MutedTransportButton(
                glyph: AnyShape(StopGlyph()),
                tooltip: String(localized: "playback.transport.stop.tooltip"),
                a11yLabel: String(localized: "playback.transport.stop.a11y"),
                action: onStop
            )
            MutedTransportButton(
                glyph: AnyShape(PrevGlyph()),
                tooltip: String(localized: "playback.transport.prev.tooltip"),
                a11yLabel: String(localized: "playback.transport.prev.a11y"),
                action: onPrev
            )
            PlayPauseTransportButton(
                isPaused: isPaused,
                action: onPlayPause,
                tooltip: String(localized: isPaused
                    ? "playback.transport.play.tooltip"
                    : "playback.transport.pause.tooltip"),
                a11yLabel: String(localized: isPaused
                    ? "playback.transport.play.a11y"
                    : "playback.transport.pause.a11y")
            )
            MutedTransportButton(
                glyph: AnyShape(NextGlyph()),
                tooltip: String(localized: "playback.transport.next.tooltip"),
                a11yLabel: String(localized: "playback.transport.next.a11y"),
                action: onNext
            )
        }
    }
}

// MARK: - TrackSeekBar (LFSEEK.1)

/// The current track's position, elapsed and total time either side. Click or drag to jump; the
/// jump lands on release, so a drag across the track restarts the audio once, not per step. It
/// polls `progress` four times a second while shown rather than publishing a clock at render rate.
struct TrackSeekBar: View {

    static let accessibilityID = "uzume.playback.lfTransport.seek"

    let progress: () -> (position: TimeInterval, duration: TimeInterval)?
    let onSeek: (TimeInterval) -> Void

    /// Where the pointer is while dragging (0…1); nil otherwise.
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let now = progress()
            let duration = now?.duration ?? 0
            let fraction = dragFraction ?? (duration > 0 ? (now?.position ?? 0) / duration : 0)
            HStack(spacing: 10) {
                Text(verbatim: Self.clock(fraction * duration))
                    .frame(width: 38, alignment: .trailing)
                track(fraction: fraction, duration: duration)
                Text(verbatim: Self.clock(duration))
                    .frame(width: 38, alignment: .leading)
            }
            .font(.caption2.monospacedDigit())
            .foregroundColor(UzumeAppColor.textTertiary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "playback.transport.seek.a11y"))
            .accessibilityHint(String(localized: "playback.transport.seek.tooltip"))
            .accessibilityValue(String(
                format: String(localized: "playback.transport.seek.value"),
                Self.clock(fraction * duration),
                Self.clock(duration)
            ))
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                let step: TimeInterval = direction == .increment ? 10 : -10
                onSeek(min(max(0, fraction * duration + step), duration))
            }
            .accessibilityIdentifier(Self.accessibilityID)
        }
        .frame(width: 300)
    }

    private func track(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(UzumeAppColor.line)
                Capsule().fill(UzumeAppColor.accent)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(max($0.location.x / geo.size.width, 0), 1) }
                    .onEnded { value in
                        let landed = min(max(value.location.x / geo.size.width, 0), 1)
                        dragFraction = nil
                        if duration > 0 { onSeek(landed * duration) }
                    }
            )
        }
        .frame(height: 16)
        .help(String(localized: "playback.transport.seek.tooltip"))
    }

    /// m:ss.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

// MARK: - PlayPauseTransportButton (violet disc — the primary action)

private struct PlayPauseTransportButton: View {

    let isPaused: Bool
    let action: () -> Void
    let tooltip: String
    let a11yLabel: String

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Group {
                if isPaused {
                    PlayGlyph().fill(UzumeAppColor.Performance.glyph)
                } else {
                    PauseGlyph().fill(UzumeAppColor.Performance.glyph)
                }
            }
            .frame(width: 18, height: 18)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(UzumeAppColor.accent)
                    .brightness(isHovered ? 0.06 : 0)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(UzumeAppMotion.easeOut(UzumeAppMotion.feedback), value: isHovered)
        .help(tooltip)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - MutedTransportButton (skip / stop — muted, no background until hover)

private struct MutedTransportButton: View {

    let glyph: AnyShape
    let tooltip: String
    let a11yLabel: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            glyph
                .fill(isHovered ? UzumeAppColor.textPrimary : UzumeAppColor.textTertiary)
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(UzumeAppColor.Performance.fillHoverFaint.opacity(isHovered ? 1 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(UzumeAppMotion.easeOut(UzumeAppMotion.feedback), value: isHovered)
        .help(tooltip)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - Custom geometric glyphs

/// Filled square. ◼
private struct StopGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.18
            path.addRect(rect.insetBy(dx: inset, dy: inset))
        }
    }
}

/// Right-pointing equilateral triangle. ▶
/// Apex shifted slightly right to optically centre the mass inside the disc.
private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.16
            let region = rect.insetBy(dx: inset, dy: inset * 0.6)
            let opticalOffset = region.width * 0.06    // mass-balance shift
            path.move(to: CGPoint(x: region.minX + opticalOffset, y: region.minY))
            path.addLine(to: CGPoint(x: region.maxX, y: region.midY))
            path.addLine(to: CGPoint(x: region.minX + opticalOffset, y: region.maxY))
            path.closeSubpath()
        }
    }
}

/// Two vertical bars. ❚❚
private struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let insetY = rect.height * 0.16
            let region = rect.insetBy(dx: 0, dy: insetY)
            let barWidth = region.width * 0.24
            let gap = region.width * 0.18
            let leftX = region.midX - gap / 2 - barWidth
            let rightX = region.midX + gap / 2
            path.addRect(CGRect(x: leftX, y: region.minY, width: barWidth, height: region.height))
            path.addRect(CGRect(x: rightX, y: region.minY, width: barWidth, height: region.height))
        }
    }
}

/// Left-pointing triangle + vertical bar on its left. ⏮
private struct PrevGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.14
            let region = rect.insetBy(dx: inset, dy: inset)
            let barWidth = region.width * 0.18
            // Vertical bar on the left
            path.addRect(CGRect(x: region.minX, y: region.minY, width: barWidth, height: region.height))
            // Triangle pointing left; right edge anchors at region.maxX
            let triLeftEdge = region.minX + barWidth + region.width * 0.06
            path.move(to: CGPoint(x: region.maxX, y: region.minY))
            path.addLine(to: CGPoint(x: triLeftEdge, y: region.midY))
            path.addLine(to: CGPoint(x: region.maxX, y: region.maxY))
            path.closeSubpath()
        }
    }
}

/// Right-pointing triangle + vertical bar on its right. ⏭
private struct NextGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.14
            let region = rect.insetBy(dx: inset, dy: inset)
            let barWidth = region.width * 0.18
            // Triangle pointing right; left edge anchors at region.minX
            let triRightEdge = region.maxX - barWidth - region.width * 0.06
            path.move(to: CGPoint(x: region.minX, y: region.minY))
            path.addLine(to: CGPoint(x: triRightEdge, y: region.midY))
            path.addLine(to: CGPoint(x: region.minX, y: region.maxY))
            path.closeSubpath()
            // Vertical bar on the right
            path.addRect(CGRect(x: region.maxX - barWidth, y: region.minY, width: barWidth, height: region.height))
        }
    }
}

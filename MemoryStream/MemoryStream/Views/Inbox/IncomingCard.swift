import SwiftUI

/// Proto-card for a clip that's still on the way in. Same shape as
/// a ready `SessionCard` so the visual hierarchy of the list reads
/// the same — but the action pill is replaced with a `PhasePill`
/// and the body region is replaced with phase-specific content
/// (progress bar for downloading, shimmer placeholders for
/// transcribing, line-up message for waiting, partial-progress
/// message for paused).
///
/// Spec: `screens-captured-clips-sessions.jsx` § SYNC / INCOMING.
struct IncomingCard: View {
    let capturedAt: Date
    let durationSeconds: TimeInterval
    let placeName: String?
    let phase: InboxArrivalTracker.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Meta row — same shape as SessionCard's meta, with the
            // PhasePill trailing where the chevron / disclosure would
            // live on a ready card.
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    metaTimeRow
                    if let placeName, !placeName.isEmpty {
                        metaPlaceRow(placeName)
                    }
                }
                Spacer(minLength: 0)
                PhasePill(phase: phase)
            }
            phaseBody
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Waiting cards read as backgrounded — they're real, but
        // not what's happening right now. Matches the spec's
        // `opacity: effPhase === 'waiting' ? 0.72 : 1`.
        .opacity(phase == .waiting ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Meta rows

    private var metaTimeRow: some View {
        HStack(spacing: 6) {
            Text(timeString)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text("·").foregroundStyle(Crucible.Color.ink4)
            Text("1 clip")
            Text("·").foregroundStyle(Crucible.Color.ink4)
            Text(durationString)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Crucible.Color.ink3)
        .monospacedDigit()
    }

    private func metaPlaceRow(_ place: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink4)
            Text(place)
                .lineLimit(1)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Crucible.Color.ink3)
    }

    // MARK: - Phase body

    @ViewBuilder
    private var phaseBody: some View {
        switch phase {
        case .waiting:
            // Honest queue copy — no false progress bar, just the
            // line-up status. Spec mock copy verbatim.
            Text("In line behind the clip downloading now.")
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .downloading:
            VStack(alignment: .leading, spacing: 7) {
                IndeterminateBarberPole()
                    .frame(height: 6)
                Text("Receiving audio · \(durationString)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .monospacedDigit()
            }
        case .transcribing:
            VStack(alignment: .leading, spacing: 6) {
                ShimmerLine(widthFraction: 0.96)
                ShimmerLine(widthFraction: 1.0)
                ShimmerLine(widthFraction: 0.64)
                Text("Audio's here. Reading it now.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, 2)
            }
        case .paused:
            // Honest — no blame, no exhortation. Spec voice.
            Text("Sync paused. Picks up when your Watch is near.")
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Formatting

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: capturedAt)
    }

    private var durationString: String {
        let s = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var accessibilityLabel: String {
        let phaseDescription: String
        switch phase {
        case .waiting:      phaseDescription = "waiting in line"
        case .downloading:  phaseDescription = "receiving from watch"
        case .transcribing: phaseDescription = "transcribing"
        case .paused:       phaseDescription = "paused; watch out of range"
        }
        return "Clip from \(timeString), \(durationString), \(phaseDescription)"
    }
}

/// Striped barber-pole progress indicator that animates indefinitely.
/// iOS's WC layer doesn't expose incoming transfer progress on the
/// receiving side, so we can't show a byte-accurate bar; this
/// honestly reads as "something is happening" without claiming a
/// specific completion %. Matches the spec's `ccBar` keyframes
/// (repeating linear gradient sliding left to right).
private struct IndeterminateBarberPole: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(Crucible.Color.sunk)
                .overlay(
                    LinearGradient(
                        colors: [
                            Crucible.Color.accent.opacity(0.85),
                            Crucible.Color.accent.opacity(0.55),
                            Crucible.Color.accent.opacity(0.85),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 70)
                    .offset(x: phase * (geo.size.width + 70))
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .onAppear {
            phase = -1
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

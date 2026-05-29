import SwiftUI

/// Proto-card for a clip that's still on the way in. Same shape as
/// a ready `SessionCard` so the visual hierarchy of the list reads
/// the same — but the action pill is replaced with a `PhasePill`
/// and the body region is replaced with phase-specific content
/// (shimmer placeholders for transcribing; progress for downloading
/// in future phases; etc).
///
/// Spec: `screens-captured-clips-sessions.jsx` § SYNC / INCOMING.
/// Phase 2 (this commit) ships only the `.transcribing` body. The
/// other cases land as future phases extend the
/// `InboxArrivalTracker.Phase` enum.
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
        case .transcribing: phaseDescription = "transcribing"
        }
        return "Clip from \(timeString), \(durationString), \(phaseDescription)"
    }
}

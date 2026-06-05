import SwiftUI

/// Global "system knows, and it's working" banner that sits under
/// the Captured Clips header whenever there are in-flight clips.
/// Spec § SYNC / INCOMING (`screens-captured-clips-sessions.jsx`).
///
/// Two visual states based on the tracker's aggregate phase:
///   - Active (at least one downloading or transcribing) →
///     ochre dot pulsing, "Receiving from your Watch · N of M"
///   - Paused (all in-flight clips are paused) → warn-tint dot
///     static, "Waiting for your Watch" honest copy
///
/// Status is never color alone — both states ship with a label.
/// Border color shifts between hairline (active) and warnTint
/// (paused) so the at-a-glance read is unambiguous.
struct SyncStrip: View {
    let receivingIndex: Int
    let totalInFlight: Int
    let allPaused: Bool

    @State private var pulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .opacity(allPaused || !pulse ? 1 : 0.35)
                Text(titleText)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Spacer(minLength: 0)
                if !allPaused && totalInFlight > 1 {
                    Text("\(receivingIndex) of \(totalInFlight)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .monospacedDigit()
                }
            }
            Text(subtitleText)
                .font(.system(size: 11))
                .foregroundStyle(Crucible.Color.ink3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Crucible.Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            guard !allPaused else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText). \(subtitleText)")
    }

    private var dotColor: Color {
        allPaused ? Crucible.Color.warn : Crucible.Color.accent
    }

    private var borderColor: Color {
        allPaused ? Crucible.Color.warnTint : Crucible.Color.hairline
    }

    private var titleText: String {
        allPaused
            ? "Waiting for your Watch"
            : "Receiving from your Watch"
    }

    private var subtitleText: String {
        allPaused
            ? "Your Watch went out of range. Sync picks up where it left off when it's near."
            : "Keep HiMem open to finish faster — it also syncs in the background."
    }
}

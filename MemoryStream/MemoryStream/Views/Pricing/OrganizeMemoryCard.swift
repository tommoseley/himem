import SwiftUI

/// "Organize this memory" card. Two states after the assist-quota
/// retirement:
///
///   • **idle** — never organized. Cream card with an "Organize"
///     button. Tap runs the on-device organize pass (Free) or
///     manually fires the same pipeline (Plus, but Plus normally
///     auto-runs on capture so this surface is rare for Plus users).
///   • **reorganize** — dashed accent callout: "N new clips since
///     last organize · Re-organize". Compact, secondary action.
///
/// Per `pricing-screens-lifecycle.jsx`:
///   - Idle copy: "Organize this memory" / "Suggests a title,
///     summary, and topics — drafted right on your device."
///   - Footer line: "On-device · private · free."
///   - No "1 ASSIST" pill, no "STARTER USED" / "MONTHLY USED" badges
///     — those tracked the retired assist-quota model.
struct OrganizeMemoryCard: View {
    let state: OrganizeCardState
    var onOrganize: () -> Void
    /// While true, the sparkle glyph is replaced with a spinner and
    /// the card disables taps so the user can't fire a second pass
    /// mid-flight.
    var isProcessing: Bool = false

    var body: some View {
        switch state {
        case .idle:
            idleCard
        case .reorganize(let count):
            reorganizeCallout(newClipCount: count)
        case .failed(let offline):
            failedCard(offline: offline)
        }
    }

    // MARK: - Failed (retryable)

    /// Ruling 2 (2026-07-25): an organize that produced no pass shows this
    /// honest, retryable card instead of resetting to idle. Copy carries NO
    /// blame and never surfaces "unsafe"/"flagged"/"sensitive" — a refusal is
    /// Apple's judgment, not ours, and naming it in a memory-keeper is a
    /// betrayal. Tapping re-runs organize.
    private func failedCard(offline: Bool) -> some View {
        Button(action: onOrganize) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Crucible.Color.aiBlue)
                        .frame(width: 36, height: 36)
                    if isProcessing {
                        ProgressView().controlSize(.regular).tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(isProcessing ? "Working…" : "Couldn't organize this one")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink)
                    Text(isProcessing
                         ? "Drafting a title, summary, and topics on your device."
                         : (offline ? "Try again when you're back online."
                                    : "Tap to try again."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Idle

    private var idleCard: some View {
        Button(action: onOrganize) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Crucible.Color.aiBlue)
                            .frame(width: 36, height: 36)
                        if isProcessing {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isProcessing ? "Working…" : "Organize this memory")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink)
                        Text(isProcessing
                             ? "Drafting a title, summary, and topics on your device."
                             : "Suggests a title, summary, and topics — drafted right on your device.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Crucible.Color.ink3)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Text("On-device · private · free")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Reorganize callout (organized + new clips since pass)

    private func reorganizeCallout(newClipCount count: Int) -> some View {
        Button(action: onOrganize) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reorganizeTitle(count: count))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink)
                    Text("Re-organize folds them in.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer()
                Text("Re-organize")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Crucible.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Crucible.Color.accent.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        Crucible.Color.accent.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func reorganizeTitle(count: Int) -> String {
        if count == 1 { return "1 new clip since last organize" }
        return "\(count) new clips since last organize"
    }
}

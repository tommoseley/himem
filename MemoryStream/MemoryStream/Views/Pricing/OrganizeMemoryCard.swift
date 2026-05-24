import SwiftUI

/// Whole-memory "Organize with AI" card. Three states:
///
///   • **idle** — never organized OR re-org of an already-organized
///     memory. "Organize with AI" title, ochre sparkle icon, "1 ASSIST"
///     pill, supporting copy enumerating what the pass produces.
///   • **reorganize** — dashed accent-tinted callout, "N new clips since
///     last organize · Re-organize · 1 assist". Compact, secondary.
///   • **exhausted** — same shape as idle but muted: warn-amber icon,
///     "Used this month's AI · resets [date]", quiet "See options →".
///
/// The card never decrements the assist counter — `ProcessingEngine`
/// does that on success only. The view's job is to surface the action
/// and route through to the pack-purchase sheet when the user taps the
/// "See options →" affordance.
///
/// Replaces the previous `OrganizeAIPanel` (which had a separate hard-100
/// inline panel + FREE pill + "N assists left" subtitle). Per the v2
/// design, all of that loud "buy more" framing is collapsed into the
/// muted exhausted state — pricing math stays in Settings · Your AI,
/// the upgrade hub, and the pack-purchase sheet.
enum OrganizeCardState {
    case idle
    case reorganize(newClipCount: Int)
    case exhausted
}

struct OrganizeMemoryCard: View {
    let state: OrganizeCardState
    var resetDate: Date?
    var onOrganize: () -> Void
    var onSeeOptions: () -> Void
    /// While true, the sparkle glyph is replaced with a spinner and
    /// the card disables taps so the user can't fire a second assist
    /// mid-flight. Drives the "we're inquiring" signal Tom called out
    /// 2026-05-18.
    var isProcessing: Bool = false

    var body: some View {
        switch state {
        case .idle:
            idleCard
        case .reorganize(let count):
            reorganizeCallout(newClipCount: count)
        case .exhausted:
            exhaustedCard
        }
    }

    // MARK: - Idle

    private var idleCard: some View {
        Button(action: onOrganize) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Crucible.Color.AI.base)
                        .frame(width: 36, height: 36)
                    if isProcessing {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white)
                    } else {
                        AISparkleGlyph(size: 18, color: .white)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isProcessing ? "Working…" : "Organize with AI")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink)
                        Spacer()
                        if !isProcessing {
                            Text("1 ASSIST")
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Crucible.Color.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Crucible.Color.accentTint)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text(isProcessing
                         ? "Inquiring with the AI — title, summary, topics, mentions, and next steps."
                         : "Suggests a title, summary, topics, mentions, and next steps.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
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

    // MARK: - Reorganize callout (after new clips added since last pass)

    private func reorganizeCallout(newClipCount count: Int) -> some View {
        Button(action: onOrganize) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reorganizeTitle(count: count))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink)
                    Text("Re-organize folds them in · 1 assist")
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

    // MARK: - Exhausted (Plus/Founders out, Free out)

    private var exhaustedCard: some View {
        Button(action: onSeeOptions) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(red: 0.96, green: 0.91, blue: 0.82))
                        .frame(width: 36, height: 36)
                    AISparkleGlyph(size: 18, color: Color(red: 0.48, green: 0.29, blue: 0.06))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organize with AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink)
                    Text(exhaustedSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer()
                Text("See options →")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Crucible.Color.accent)
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
    }

    private var exhaustedSubtitle: String {
        guard let resetDate else { return "No assists available" }
        return "Used this month's AI · resets \(OrganizeMemoryCard.resetDateFormatter.string(from: resetDate))"
    }

    private static let resetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

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
    /// When set on the `.idle` state, adds a warn-color "1 LEFT ·
    /// FREE" caption under the `1 ASSIST` pill. Per pricing spec
    /// § 14 (Paywall 1): free users about to consume their last
    /// starter assist see the meter without a modal. Pass nil to
    /// suppress the cue (Plus users, free users with > 1 left).
    var assistsLeft: Int? = nil
    /// `.idle` only. True when Plus user has drained their monthly
    /// allowance and is now drawing from a purchased pack — adds a
    /// quiet `from your pack` micro-caption under the `1 ASSIST`
    /// pill so the user knows where the next assist comes from.
    /// Per pricing spec C5.
    var fromPack: Bool = false

    var body: some View {
        switch state {
        case .idle:
            idleCard
        case .reorganize(let count):
            reorganizeCallout(newClipCount: count)
        case .exhausted(let variant):
            exhaustedCard(variant: variant)
        case .stale(let variant):
            staleCard(variant: variant)
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
                    HStack(alignment: .top, spacing: 8) {
                        Text(isProcessing ? "Working…" : "Organize with AI")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink)
                        Spacer()
                        if !isProcessing {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("1 ASSIST")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .tracking(0.4)
                                    .foregroundStyle(Crucible.Color.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Crucible.Color.accentTint)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                if assistsLeft == 1 {
                                    // Pricing spec § 14 Paywall 1:
                                    // ambient urgency cue, no modal.
                                    Text("1 LEFT · FREE")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .tracking(0.3)
                                        .foregroundStyle(Crucible.Color.warning)
                                } else if fromPack {
                                    // Pricing spec C5: Plus user is
                                    // drawing from their pack now
                                    // that the monthly bucket is dry.
                                    Text("from your pack")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .tracking(0.2)
                                        .foregroundStyle(Crucible.Color.ink3)
                                }
                            }
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

    // MARK: - Stale (organized + new clips since pass)

    /// "Reorganize with AI" — mirrors the `.idle` shape but the title
    /// reflects that a pass already ran. Per pricing spec § 16, the
    /// variant carries the tier-specific status pill, body copy, and
    /// tap target:
    ///   • `.available`     → ochre `1 ASSIST` pill, refresh fires.
    ///   • `.freeExhausted` → amber `STARTER USED` badge, names the
    ///     spent 3 starters; tap routes to Upgrade Hub.
    ///   • `.plusExhausted` → amber `MONTHLY USED` badge, names the
    ///     reset date; tap routes to the pack purchase modal.
    private func staleCard(variant: OrganizeCardState.StaleVariant) -> some View {
        let isExhausted = variant != .available
        return Button(action: variant == .available ? onOrganize : onSeeOptions) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isExhausted
                              ? Crucible.Color.sunk
                              : Crucible.Color.AI.base)
                        .frame(width: 36, height: 36)
                    if isProcessing {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white)
                    } else {
                        AISparkleGlyph(
                            size: 18,
                            color: isExhausted ? Crucible.Color.ink3 : .white
                        )
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isProcessing ? "Working…" : "Reorganize with AI")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isExhausted ? Crucible.Color.ink2 : Crucible.Color.ink)
                        Spacer()
                        if !isProcessing {
                            stalePill(for: variant)
                        }
                    }
                    staleBody(for: variant)
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
            .opacity(isExhausted ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    @ViewBuilder
    private func stalePill(for variant: OrganizeCardState.StaleVariant) -> some View {
        switch variant {
        case .available:
            Text("1 ASSIST")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Crucible.Color.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Crucible.Color.accentTint)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .freeExhausted:
            exhaustedPill(label: "STARTER USED")
        case .plusExhausted:
            exhaustedPill(label: "MONTHLY USED")
        }
    }

    private func exhaustedPill(label: String) -> some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Crucible.Color.warnInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Crucible.Color.warnTint)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func staleBody(for variant: OrganizeCardState.StaleVariant) -> some View {
        staleBodyText(for: variant)
            .font(.system(size: 12.5))
            .foregroundStyle(Crucible.Color.ink3)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
    }

    private func staleBodyText(for variant: OrganizeCardState.StaleVariant) -> Text {
        switch variant {
        case .available:
            let base = isProcessing
                ? "Inquiring with the AI — title, summary, topics, mentions, and next steps."
                : "Spends 1 assist to fold the new clips in and refresh title, summary, topics, and mentions."
            return Text(base)
        case .freeExhausted:
            return Text("Your ")
                + Text("3 free starter assists").fontWeight(.semibold)
                + Text(" are spent. Add a pack or get 50/month with Plus. ")
                + Text("See options →").foregroundColor(Crucible.Color.accent)
        case .plusExhausted(let resetDate):
            let dateStr = Self.resetDateFormatter.string(from: resetDate ?? Date())
            return Text("This month's 50 assists are used. Resets ")
                + Text(dateStr).fontWeight(.semibold)
                + Text(". ")
                + Text("Get more →").foregroundColor(Crucible.Color.accent)
        }
    }

    // MARK: - Exhausted (never-organized memory, user out of assists)

    /// Mirrors the `.stale` card's tier-aware treatment per pricing
    /// spec A3 (free) + C3 (plus). Same icon, same body, same pill
    /// swap as the Reorganize card so the user sees a consistent
    /// exhaustion treatment on both first-pass and reorganize
    /// surfaces.
    private func exhaustedCard(variant: OrganizeCardState.ExhaustedVariant) -> some View {
        Button(action: onSeeOptions) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Crucible.Color.sunk)
                        .frame(width: 36, height: 36)
                    AISparkleGlyph(size: 18, color: Crucible.Color.ink3)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Organize with AI")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink2)
                        Spacer()
                        switch variant {
                        case .freeExhausted:
                            exhaustedPill(label: "STARTER USED")
                        case .plusExhausted:
                            exhaustedPill(label: "MONTHLY USED")
                        }
                    }
                    exhaustedBody(variant: variant)
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
            .opacity(0.92)
        }
        .buttonStyle(.plain)
    }

    private func exhaustedBody(variant: OrganizeCardState.ExhaustedVariant) -> Text {
        switch variant {
        case .freeExhausted:
            return Text("Your ")
                + Text("3 free starter assists").fontWeight(.semibold)
                + Text(" are spent. Add a pack or get 50/month with Plus. ")
                + Text("See options →").foregroundColor(Crucible.Color.accent)
        case .plusExhausted(let resetDate):
            let dateStr = Self.resetDateFormatter.string(from: resetDate ?? Date())
            return Text("This month's 50 assists are used. Resets ")
                + Text(dateStr).fontWeight(.semibold)
                + Text(". ")
                + Text("Get more →").foregroundColor(Crucible.Color.accent)
        }
    }

    private static let resetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

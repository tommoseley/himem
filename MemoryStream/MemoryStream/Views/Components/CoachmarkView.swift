import SwiftUI

/// The anchored coachmark presentation surface per
/// `docs/design/Tutorials · triggers spec.md` §"Two tutorial formats"
/// and §"Per-tab coachmark on first arrival."
///
/// Layout: dim scrim + centered caption card (intent-first copy per
/// `Kingfisher Language.md` §"why before how"). **Skip** on the left,
/// plain ink — dismisses the entire tour instantly (guardrail #5).
/// **Got it** on the right, ochre — commits and marks seen.
///
/// v1 shape: single-step captions (no anchored spotlight geometry
/// yet — the caption is centered rather than boxed against a specific
/// control). Spec allows this as the "screens with no content to
/// anchor" fallback; per-control spotlight rings are a follow-up.
struct CoachmarkView: View {
    let kind: CoachmarkOrchestrator.Kind
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dim scrim — tap-through dismiss counts as Skip.
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            captionCard
                .padding(.horizontal, 28)
        }
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Crucible.Color.ink3)

            Text(kind.headline)
                .font(.system(size: 24, design: .serif))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(Crucible.Color.ink)

            Text(kind.body)
                .font(.system(size: 14))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(4)

            // F2b · recoverability (2026-07-26): every coachmark card teaches
            // the way back. Quiet label register (ink3, no border, not
            // tappable) — information, not an action; it must not read as a
            // button. Shown every time the card is dismissed, not just the
            // first. Copy is design-authority (locked). Since each tab's
            // coachmark is a single self-contained card, this IS the final
            // beat of that card.
            Text("That's it! You can bring this tour back any time from ? → Show me around.")
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink3)
                .lineSpacing(3)

            HStack {
                Button("Skip", action: onDismiss)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink2)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Skip tour")

                Spacer(minLength: 0)

                Button("Got it", action: onDismiss)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accentInk)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(
                        Crucible.Color.accent,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityLabel("Got it")
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Crucible.Color.paper,
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Per-tab copy

extension CoachmarkOrchestrator.Kind {
    /// Small uppercase eyebrow above the headline.
    var eyebrow: String {
        switch self {
        case .clips:    return "Clips"
        case .memories: return "Memories"
        case .projects: return "Projects"
        }
    }

    /// Serif headline — intent-first per `Kingfisher Language.md`
    /// ("why before how"). Not "This is the X tab" — the *purpose*.
    var headline: String {
        switch self {
        case .clips:
            return "Everything you've caught, before it's placed."
        case .memories:
            return "Where thoughts settle once they belong somewhere."
        case .projects:
            return "Threads pulled across memories."
        }
    }

    /// Body copy — one plain sentence about what the tab is for.
    ///
    /// **Clips body is source-agnostic** per Locked Decisions § Clips
    /// surface + `CLAUDE.md` Phone corollary — no headline leads with
    /// one source (Watch, +, or Siri). Wording matches the empty-state
    /// pattern in `SessionListView.emptyState` so the two educational
    /// surfaces speak the same sentence.
    var body: String {
        switch self {
        case .clips:
            return "Clips you capture — with the + button, on your Watch, or with Siri — land here. Sort what belongs together, or just leave them — nothing's lost."
        case .memories:
            return "Each card is one memory. Tap it to open, edit, or reorganize. Cold launch always lands here."
        case .projects:
            return "Group memories around a topic you're following. Find the thread reads across them and pulls out what connects."
        }
    }
}

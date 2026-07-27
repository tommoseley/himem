import SwiftUI

/// F8 (2/n) · the guided-walkthrough overlay. Renders `WalkthroughOrchestrator`'s
/// current beat over the live app. Two registers, by beat kind:
///
/// - **Reinforcing beats** (`offer` · `concept` · `clipLanded` · `done`) — a
///   modal card over a dim scrim; the user reads and taps to continue. These
///   don't require touching a real control, so blocking is correct.
/// - **Action beats** (`record` · `makeMemory` · `organize`) — a **non-blocking
///   coaching banner** pinned to the bottom, NO scrim: the user must actually
///   tap the real control (+, Start a Memory, Organize), and the beat advances
///   on the real signal (the spine's invariant). A blocking scrim here would
///   defeat the whole "do it with me" premise.
///
/// Precise per-control spotlight cutouts are a follow-up (the coachmark spec
/// carries the same "centered/banner card is the fallback, rings later" note).
/// Copy is design-authority (F7e); no "evidence" (F7g).
struct WalkthroughOverlay: View {
    @ObservedObject var orchestrator: WalkthroughOrchestrator = .shared
    /// The user's tier — only the `organize` beat reads it (Free guides the tap,
    /// Plus narrates). Injected by the host so this view stays testable/pure.
    let isPlus: Bool

    var body: some View {
        if let beat = orchestrator.activeBeat {
            switch beat {
            case .offer, .concept, .clipLanded, .done:
                modalCard(beat)
            case .record, .makeMemory, .organize:
                coachingBanner(beat)
            }
        }
    }

    // MARK: - Reinforcing beats — modal card over a scrim

    private func modalCard(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea()
                .accessibilityHidden(true)
                // Tap-through does nothing on a modal beat — the buttons drive it
                // (so a stray scrim tap can't skip the concept card).

            VStack(alignment: .leading, spacing: 14) {
                if let title = beat.title {
                    Text(title)
                        .font(.system(size: 24, design: .serif))
                        .tracking(-0.3)
                        .lineSpacing(3)
                        .foregroundStyle(Crucible.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(beat.body(isPlus: isPlus))
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if beat == .done {
                    Text(WalkthroughOrchestrator.Beat.recoverabilityLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionRow(beat)
                    .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Crucible.Color.hairline, lineWidth: 1))
            .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private func actionRow(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        HStack {
            // "Not now" / "Skip" always present and always instant.
            Button(beat == .offer ? "Not now" : "Skip", action: orchestrator.skip)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
                .frame(minHeight: 44)
                .accessibilityLabel("Skip the walkthrough")

            Spacer(minLength: 0)

            // Primary — ochre, user action.
            Button(primaryLabel(beat), action: primaryAction(beat))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.accentInk)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func primaryLabel(_ beat: WalkthroughOrchestrator.Beat) -> String {
        switch beat {
        case .offer:   return "Start"
        case .done:    return "Done"
        default:       return "Continue"
        }
    }

    private func primaryAction(_ beat: WalkthroughOrchestrator.Beat) -> () -> Void {
        switch beat {
        case .offer: return orchestrator.beginFromOffer
        default:     return orchestrator.advance
        }
    }

    // MARK: - Action beats — non-blocking coaching banner (real control stays live)

    private func coachingBanner(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        // VStack { Spacer(); banner } fills the screen but the Spacer draws
        // nothing, so taps in the empty area pass THROUGH to the real control
        // the beat points at (the +, Start a Memory, Organize). Only the banner
        // — which has a background — captures touches. That's the do-it-with-me
        // premise: guide without blocking.
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Text(beat.body(isPlus: isPlus))
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Skip", action: orchestrator.skip)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Skip the walkthrough")
            }
            .padding(16)
            .background(Crucible.Color.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crucible.Color.accent.opacity(0.4), lineWidth: 1.5))
            .padding(.horizontal, 16)
            // Float above the tab bar so it doesn't cover the FAB the user must tap.
            .padding(.bottom, 96)
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

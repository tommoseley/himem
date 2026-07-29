import SwiftUI

/// F8 (2/n) · the guided-walkthrough overlay. Renders `WalkthroughOrchestrator`'s
/// current beat over the live app, in two registers:
///
/// - **Modal card** (`offer`) — the invite, no real target to reveal; a card
///   over a dim scrim, driven by its buttons.
/// - **Top banner** (`record` · `clipLanded` · `makeMemory` · `openMemory` ·
///   `organize` · `done`) — every beat that points at a real control. Pinned to
///   the TOP so it never occludes the target; the empty area passes touches
///   through, so the target stays both visible and tappable.
///
/// **F10 channels rendered here (2026-07-28):** a quiet **progress** eyebrow
/// ("Step N of 5", `beat.progressLabel`); a **confirmation** check on the Saved /
/// Done beats (and organize-when-already-done); and a **deviation** chip when the
/// orchestrator reports an observed wrong action (`deviationMessage`) — a gentle
/// redirect, never blame.
///
/// `onARoll` (1b) is NOT drawn here — it renders in-composer (`VoiceCaptureScreen`)
/// as an un-numbered tip; `rolling` is a silent hold. Both fall through to
/// `EmptyView`. Copy/colour are design-authority (F7e); no "evidence" (F7g).
struct WalkthroughOverlay: View {
    @ObservedObject var orchestrator: WalkthroughOrchestrator = .shared

    var body: some View {
        if let beat = orchestrator.activeBeat {
            switch beat {
            case .offer:
                modalCard(beat)
            case .record, .clipLanded, .makeMemory, .openMemory, .organize, .done:
                // "Got it." on a signal beat retires its banner; the walkthrough
                // stays armed for the real signal.
                if orchestrator.currentBannerRetired {
                    EmptyView()
                } else {
                    topBanner(beat)
                }
            case .onARoll, .rolling:
                // 1b renders in-composer; `rolling` is a silent hold.
                EmptyView()
            }
        }
    }

    // MARK: - Shared "Got it." acknowledgement (one pattern with CoachmarkBanner)

    private var gotItButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Got it", action: orchestrator.gotIt)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.accentInk)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Got it — dismiss this tip")
        }
    }

    /// The quiet breadcrumb caption under "Got it." — where to re-run later.
    private var skipBreadcrumbCaption: some View {
        Text(WalkthroughOrchestrator.Beat.skipBreadcrumb)
            .font(.system(size: 12))
            .foregroundStyle(Crucible.Color.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Quiet "Step N of 5" eyebrow — the F10 progress channel. Never a scold;
    /// nil on the offer and the un-numbered on-a-roll tip.
    @ViewBuilder
    private func progressEyebrow(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        if let label = beat.progressLabel {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Crucible.Color.ink3)
                .accessibilityLabel(label)
        }
    }

    /// Beat 1's FAB-stack illustration, rendered as a small side DIAGRAM (F11) —
    /// 72pt, beside the copy, never the centered hero that read as the button
    /// itself. Tapping the picture (not the real +) is the wrong action Judi hit,
    /// so it feeds the deviation channel instead of doing nothing (F10 ch.2).
    /// A precise spotlight on the real + FAB is a separate, reported item awaiting
    /// a ruling.
    private var fabDiagram: some View {
        Image("walkthrough-fab-stack")
            .resizable()
            .scaledToFit()
            .frame(width: 72)
            .contentShape(Rectangle())
            .onTapGesture { orchestrator.observedTappedFabIllustration() }
            .accessibilityLabel("A picture of the + button and its options — the real + is in the bottom corner")
    }

    /// The F10 deviation chip — shown only on an observed wrong action. A gentle
    /// redirect in ink on a faint accent tint; never red, never blame.
    @ViewBuilder
    private var deviationChip: some View {
        if let message = orchestrator.deviationMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.accentTint2, in: RoundedRectangle(cornerRadius: 10))
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Modal beats (no real target) — card over a scrim

    private func modalCard(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea()
                .accessibilityHidden(true)
                // No tap-through dismiss — the buttons drive the offer.

            VStack(alignment: .leading, spacing: 14) {
                if let title = beat.title {
                    Text(title)
                        .font(.system(size: 24, design: .serif))
                        .tracking(-0.3)
                        .lineSpacing(3)
                        .foregroundStyle(Crucible.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(beat.body(alreadyOrganized: orchestrator.organizeAlreadyDone))
                    .font(.system(size: 15))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // The offer's decline is an INFORMED choice, not a dead end — it
                // names where the coaching lives (Tom 2026-07-27).
                VStack(spacing: 12) {
                    Button("Start", action: orchestrator.beginFromOffer)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 12))
                    Button("Not now — you'll find this in Settings → Learn.", action: orchestrator.skip)
                        .font(.system(size: 13))
                        .foregroundStyle(Crucible.Color.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("Not now — you'll find this later in Settings, under Learn")
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Crucible.Color.hairline, lineWidth: 1))
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Target beats — top banner (never occludes the control)

    private func topBanner(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        // F10 confirmation: the Saved / Done beats (and organize once already
        // done, on Plus) lead with a completion check so a landed step never
        // passes unremarked (Q6, twice).
        let showsConfirmation = beat.isConfirmation
            || (beat == .organize && orchestrator.organizeAlreadyDone)

        // VStack { banner; Spacer() } pins the banner to the TOP; the empty area
        // draws nothing, so taps pass through to the real control.
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                progressEyebrow(beat)

                // The record beat sits the FAB illustration BESIDE the copy as a
                // small diagram (F11 — she tapped the 150pt centered hero because
                // it *was* the button as far as the eye was concerned). Every
                // other beat is the copy line, with a leading confirmation check
                // where the step just landed.
                if beat == .record {
                    HStack(alignment: .top, spacing: 12) {
                        Text(beat.body(alreadyOrganized: false))
                            .font(.system(size: 14))
                            .foregroundStyle(Crucible.Color.ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        fabDiagram
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if showsConfirmation {
                            // Ochre, not green: green is semantic confirmed/
                            // success, but a landed step is a *user state* (she
                            // committed the action), not a success event (Tom
                            // 2026-07-28). Keep the ✓ — status is never colour alone.
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Crucible.Color.accent)
                                .accessibilityHidden(true)
                        }
                        Text(beat.body(alreadyOrganized: orchestrator.organizeAlreadyDone))
                            .font(.system(size: 14))
                            .foregroundStyle(Crucible.Color.ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                deviationChip

                if beat == .done {
                    // The single closing line lives on the final beat now that the
                    // ontology beat is retired: the ? hand-off (F7c) + re-run path.
                    Text(WalkthroughOrchestrator.Beat.closingLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                gotItButton
                // Breadcrumb caption — except the final `done` beat, which
                // already carries `closingLine`.
                if beat != .done {
                    skipBreadcrumbCaption
                }
            }
            .padding(16)
            // Reads as an overlay at a glance: raised `card` surface, full-weight
            // ochre border, real drop shadow. Non-blocking to taps.
            .background(Crucible.Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crucible.Color.accent, lineWidth: 2))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .shadow(color: Color.black.opacity(0.20), radius: 18, y: 6)

            Spacer(minLength: 0)
        }
    }
}

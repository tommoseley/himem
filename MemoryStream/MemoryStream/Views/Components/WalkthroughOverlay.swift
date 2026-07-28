import SwiftUI

/// F8 (2/n) · the guided-walkthrough overlay. Renders `WalkthroughOrchestrator`'s
/// current beat over the live app. Two registers, by whether the beat points at
/// a real control:
///
/// - **Modal card** (`offer` · `concept`) — beats with NO real target to reveal;
///   a card over a dim scrim, driven by its buttons.
/// - **Top banner** (`record` · `clipLanded` · `makeMemory` · `openMemory` ·
///   `organize` · `done`) — every beat that points at a real control (the
///   `openMemory` banner names the "Memory created · View" toast). Pinned to the TOP so it
///   never **occludes** the target (device pass 2026-07-26: a bottom banner sat
///   over the Voice row in the FAB stack — non-blocking-to-taps but hiding the
///   one control the copy names). The empty area passes touches through, so the
///   target stays both **visible and tappable**. Signal beats
///   (record/makeMemory/organize) carry only Skip and advance on the real
///   signal; tap beats (clipLanded/done) carry a Continue/Done button.
///
/// The `onARoll` beat (1b) is NOT drawn here — it points at the Next glyph on
/// the recording screen, which sits in a `fullScreenCover` this root overlay
/// can't reach over, so `VoiceCaptureScreen` renders it. `rolling` is a silent
/// hold. Both fall through to `EmptyView`.
///
/// Precise per-control spotlight cutouts remain a follow-up. Copy is
/// design-authority (F7e); no "evidence" (F7g).
struct WalkthroughOverlay: View {
    @ObservedObject var orchestrator: WalkthroughOrchestrator = .shared
    /// The user's tier — only the `organize` beat reads it (Free guides the tap,
    /// Plus narrates). Injected by the host so this view stays pure.
    let isPlus: Bool

    var body: some View {
        if let beat = orchestrator.activeBeat {
            switch beat {
            case .offer, .concept:
                modalCard(beat)
            case .record, .clipLanded, .makeMemory, .openMemory, .organize, .done, .ontology:
                // "Got it." on a signal beat retires its banner; the walkthrough
                // stays armed for the real signal (only signal beats ever set
                // this flag — read beats advance instead).
                if orchestrator.currentBannerRetired {
                    EmptyView()
                } else {
                    topBanner(beat)
                }
            case .onARoll, .rolling:
                // 1b is rendered in-composer (`VoiceCaptureScreen`) — the root
                // overlay can't reach over the recording `fullScreenCover`;
                // `rolling` is a silent hold. Nothing to draw here.
                EmptyView()
            }
        }
    }

    // MARK: - Shared "Got it." acknowledgement (one pattern with CoachmarkBanner)

    /// The single "Got it." — CoachmarkBanner's exact shape, so the walkthrough
    /// and the coachmarks read as one pattern. Retires the current beat's card
    /// (`gotIt()`): never abandons; on a signal beat the walkthrough stays armed.
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

    // MARK: - Modal beats (no real target) — card over a scrim

    private func modalCard(_ beat: WalkthroughOrchestrator.Beat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .ignoresSafeArea()
                .accessibilityHidden(true)
                // No tap-through dismiss — the buttons drive modal beats so a
                // stray scrim tap can't skip the concept card.

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

                if beat == .offer {
                    // The re-run offer's decline is an INFORMED choice, not a
                    // dead end — it names where the coaching lives (Tom
                    // 2026-07-27). Stacked so the long decline label fits;
                    // it carries the breadcrumb itself, so no separate line.
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
                } else {
                    // Concept: one "Got it." (retires the card — for this
                    // gated read beat that's its continue) + breadcrumb.
                    gotItButton.padding(.top, 4)
                    skipBreadcrumbCaption
                }
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
        // VStack { banner; Spacer() } pins the banner to the TOP; the empty area
        // draws nothing, so taps pass through to the real control (bottom FAB
        // stack for record, content-area controls for the rest).
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(beat.body(isPlus: isPlus))
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if beat == .record {
                    // Beat 1's FAB-stack illustration — so "tap +, tap Voice"
                    // points at something recognizable before the user has
                    // opened the stack. The banner sits at the TOP and the real
                    // + is at the bottom, so it never crowds the control it
                    // points at. Rendered at 150pt wide (labels readable);
                    // height follows the art's 0.557 ratio (~269pt), no
                    // letterbox. Clean 480×862 @3x export (Tom, 2026-07-27) —
                    // crisp at this width on @3x.
                    Image("walkthrough-fab-stack")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("The + button expands to Attach, Note, Video, Photo, and Voice")
                }

                if beat == .ontology {
                    // The single closing line lives on the final beat (ontology),
                    // the one ending: F7c ? hand-off + F2b recoverability.
                    Text(WalkthroughOrchestrator.Beat.closingLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // One "Got it." on every beat — retires this card (its continue
                // on the tap-gated read beats; hides it on signal beats while
                // the walkthrough waits for the real action). No Skip, no second
                // control (Tom 2026-07-27).
                gotItButton
                // Breadcrumb caption — except the final ontology beat, which
                // already carries `closingLine`.
                if beat != .ontology {
                    skipBreadcrumbCaption
                }
            }
            .padding(16)
            // Must read as an overlay at a glance, not part of the list — a
            // raised `card` surface (distinct from the `paper` page), a
            // full-weight ochre border (not a hairline), and a real drop shadow
            // (device pass 2026-07-27: paper-on-paper + a 0.4 hairline blended
            // into the page). Non-blocking to taps is unchanged.
            .background(Crucible.Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crucible.Color.accent, lineWidth: 2))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .shadow(color: Color.black.opacity(0.20), radius: 18, y: 6)

            Spacer(minLength: 0)
        }
    }

}

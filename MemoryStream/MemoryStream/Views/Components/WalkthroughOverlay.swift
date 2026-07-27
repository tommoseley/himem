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
            case .record, .clipLanded, .makeMemory, .openMemory, .organize, .done:
                topBanner(beat)
            case .onARoll, .rolling:
                // 1b is rendered in-composer (`VoiceCaptureScreen`) — the root
                // overlay can't reach over the recording `fullScreenCover`;
                // `rolling` is a silent hold. Nothing to draw here.
                EmptyView()
            }
        }
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

                HStack {
                    Button(beat == .offer ? "Not now" : "Skip", action: orchestrator.skip)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink2)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Skip the walkthrough")
                    Spacer(minLength: 0)
                    Button(beat == .offer ? "Start" : "Continue",
                           action: beat == .offer ? orchestrator.beginFromOffer : orchestrator.advance)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accentInk)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 12))
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
                    // + is at the bottom, so the illustration never crowds the
                    // control it points at. Height-constrained: the source is a
                    // tall portrait (302×613) and low-res, so it can soften
                    // above ~100pt on @3x — this frame is the device-tunable knob.
                    Image("walkthrough-fab-stack")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 190)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("The + button expands to Attach, Note, Video, Photo, and Voice")
                }

                if beat == .done {
                    // One closing line: the F7c ? hand-off + F2b recoverability,
                    // merged so the final beat reads as an exhale, not a wall.
                    Text(WalkthroughOrchestrator.Beat.closingLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Skip", action: orchestrator.skip)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crucible.Color.ink3)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Skip the walkthrough")
                    Spacer(minLength: 0)
                    // Tap beats carry a primary button; signal beats advance on
                    // the real pipeline signal and show only Skip.
                    if let label = primaryLabel(beat) {
                        Button(label, action: orchestrator.advance)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.accentInk)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 10))
                    }
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

    /// The primary-button label for the TAP-advance banner beats, nil for the
    /// signal beats (which advance on the real pipeline signal).
    private func primaryLabel(_ beat: WalkthroughOrchestrator.Beat) -> String? {
        switch beat {
        case .clipLanded: return "Continue"
        case .done:       return "Done"
        default:          return nil   // record / makeMemory / organize
        }
    }
}

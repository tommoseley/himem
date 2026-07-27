import SwiftUI
import AVFoundation
import CoreLocation

/// Phone voice composer — **tight cluster + live transcript** spec
/// (May 25 2026, `docs/design/Himem · Voice Composer.html` →
/// "Proposal · tight cluster + live transcript").
///
/// Mirrors the watch's capture surface, with the upper third packed
/// tight: REC dot → big tabular timer → live waveform breathe as one
/// cluster. The persistent "Clip N · on a roll" state line anchors
/// DIRECTLY BELOW the waveform (it labels the active moment rather
/// than separating timer from waveform). A live-transcript Source
/// Serif italic strip sits below — Crucible's audio-as-hero
/// principle made literal. Stop & save (84pt ochre circle) + Next
/// satellite (56pt ochre-tinted) at the bottom; ✕ corner glyph for
/// cancel; optional "Adding to · [Memory]" header pill when the
/// screen is presented from inside an existing Memory.
///
/// **Live transcript band**: italic Source Serif 17pt in `ink3`,
/// center-aligned, with a fainter `Listening…` (15pt ink4) empty
/// state. The cap surface stays a capture surface — no edit
/// affordances here. Final editing happens on the resulting Memory
/// after Done.
///
/// "On a roll" support (`docs/watch/On a roll · spec.md`): the Next
/// button records an offset from session start at each tap. On
/// Done, the master audio file is split at those offsets into N
/// per-clip files and each is re-transcribed locally. Mic NEVER
/// pauses across Next — the engine + analyzer + AVAudioFile keep
/// running; per-clip splitting is a Save-time post-process.
struct VoiceCaptureScreen: View {
    /// Fired when the user finishes a recording. Always at least one
    /// fragment unless the recording produced nothing — caller decides
    /// what to do with a zero-clip session (typically: nothing).
    let onFinish: (_ clips: [VoiceClipFragment], _ rollGroupId: UUID) -> Void
    let onCancel: () -> Void

    @ObservedObject var speechService: SpeechService
    /// When non-nil, renders an "Adding to · X" pill in place of the
    /// "VOICE" eyebrow. Tells the user the clips will append to that
    /// Memory rather than start a fresh one.
    let appendingTo: String?
    /// How this capture was initiated. `.handsFree` (Siri) gets the recording
    /// cap below; `.manual` (a composer the user is actively holding) never
    /// does — a held recording is unbounded. See `CaptureSource`.
    let captureSource: CaptureSource

    /// Hands-free recording cap in minutes; `0` = No limit. Voice Settings.
    @AppStorage("handsFreeRecordingLimitMinutes") private var handsFreeLimitMinutes = 10
    /// Fires the auto-save exactly once when the cap is reached (the elapsed
    /// tick is 10 Hz; without this the save would re-enter every 100 ms).
    @State private var didHitCap = false
    @ObservedObject private var captureRequests = CaptureRequestBus.shared

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nextController: NextClipController
    /// Owns elapsed timer + rolling waveform buffer. Extracted from
    /// this view in the CRAP audit 2026-05-28 (Batch 6) so the
    /// recording-phase state cluster is unit-testable.
    @StateObject private var recording = VoiceRecordingController()
    @State private var didAutoStart = false
    @State private var isFinalizing = false
    @State private var finalizingClipCount = 0
    /// Captured at the moment `startRecording()` fires the SpeechService
    /// + NextClipController. Threaded through the orchestrator's
    /// `capturedAtSequence` so each split clip lands with an honest
    /// per-clip wall-clock instead of the all-at-save-time `Date()`
    /// the codebase used pre-fix. Tom 2026-06-09.
    @State private var recordingStartedAt: Date? = nil
    /// REC dot pulse phase (~1.4s ease-in-out per watch spec; mirrored
    /// here for visual continuity between capture surfaces).
    @State private var recPulse: Bool = false
    /// One-shot location fix captured at recording start; stamped
    /// onto every `VoiceClipFragment` in this session at Done so the
    /// resulting `MediaReference`s carry their own place name. Nil
    /// when the user hasn't granted location, the request times out,
    /// or the global `tagMemoriesWithLocation` default is off. The
    /// fetch races recording — recording proceeds either way.
    @State private var sessionLocation: CLLocation? = nil
    /// One-breath entry per the May 27 2026 spec revision. A single
    /// ochre ring fills clockwise in ~800ms with a 200ms tail; an
    /// italic serif caption rotates across recordings, cycling
    /// through five copies. Soft haptic at start, slightly stronger
    /// at the moment recording begins. Tap to cancel. Bypassed on
    /// Next-clip (mic never pauses). Replaced the previous 3·2·1
    /// two-phase countdown — felt too long, broke the "you press,
    /// it listens" rhythm.
    @State private var phase: ComposerPhase
    @State private var countdownTask: Task<Void, Never>? = nil
    @State private var breathProgress: CGFloat = 0
    /// Caption index for the current breath. Read from UserDefaults
    /// on first appear; the persisted store is bumped (mod count)
    /// only when the user commits to recording, not on cancel.
    @State private var breathCaptionIndex: Int = 0

    /// Observes the orchestrator's `visible` so we can defer the
    /// breath / mic-permission flow until the tutorial overlay (if
    /// it auto-fires) dismisses. Without this gate the mic permission
    /// system prompt would land *under* the tutorial sheet.
    @ObservedObject private var tutorialOrchestrator = TutorialOrchestrator.shared

    /// F8 · beat 1b ("on a roll"). The root walkthrough overlay can't reach over
    /// this screen's `fullScreenCover`, and the beat is anchored to the Next
    /// glyph, so the composer renders it. Signals: `recordingDidStart()` at mic
    /// start, `nextClipStarted()` on a fired Next tap, `recordingDidCancel()` on
    /// discard. All are no-ops unless the walkthrough is on the matching beat.
    @ObservedObject private var walkthrough = WalkthroughOrchestrator.shared

    enum ComposerPhase: Equatable {
        case breathing
        case recording
        case denied
    }

    // Caption rotation is the shared `BreathCaption` source so the
    // phone and watch composers stay in lockstep. See
    // `Shared/BreathCaption.swift`.

    init(
        onFinish: @escaping (_ clips: [VoiceClipFragment], _ rollGroupId: UUID) -> Void,
        onCancel: @escaping () -> Void,
        speechService: SpeechService,
        appendingTo: String? = nil,
        captureSource: CaptureSource = .manual
    ) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.speechService = speechService
        self.appendingTo = appendingTo
        self.captureSource = captureSource
        self._nextController = StateObject(wrappedValue: NextClipController(handoff: speechService))
        // Initial phase is always `.breathing`. The Capture tutorial
        // surfaces (if it's going to) via the root-level orchestrator
        // overlay; `bootBreathPhase()` waits on `orchestrator.visible`
        // so the mic permission prompt doesn't fire under the tutorial.
        self._phase = State(initialValue: .breathing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                Group {
                    switch phase {
                    case .breathing:
                        breathContent
                    case .denied:
                        permissionDeniedContent
                    case .recording:
                        composerBody
                            // Beat 1b floats above the action row, anchored
                            // toward Next; non-interactive so it never blocks
                            // Stop & save / Next / Done (see the banner).
                            .overlay(alignment: .bottomTrailing) { walkthroughOnARollBanner }
                    }
                }
                .opacity(isFinalizing ? 0.4 : 1.0)
                .disabled(isFinalizing)

                if isFinalizing {
                    finalizingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Per v2 spec: ✕ corner glyph is hidden during the
                // countdown — the whole screen is the cancel target
                // (single affordance). ✕ re-appears once we're in
                // the recording phase as the explicit discard path.
                // Tutorial phase suppresses ALL toolbar items — it's
                // a self-contained intro page, dismissed only by
                // Start recording (or swipe-down).
                if phase == .recording {
                    ToolbarItem(placement: .navigationBarLeading) {
                        cancelGlyph
                    }
                }
                ToolbarItem(placement: .principal) {
                    headerCenter
                }
                if phase == .recording {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            Task { await finishOrAbandon(saveResult: true) }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.accent)
                        .disabled(isFinalizing)
                    }
                }
            }
        }
        .onAppear {
            // Attempt to fire the Capture tutorial. Append flow opts
            // out per the spec's content-framing (tutorial assumes a
            // new memory, not an add-to-existing).
            //
            // If the orchestrator fires it, the root-level overlay
            // (mounted in `MemoryStreamApp`) presents the one-pager
            // *above* this screen. `bootBreathPhase()` is gated below
            // on `orchestrator.visible == nil` so the mic permission
            // prompt doesn't land under the tutorial sheet — it waits
            // for the user to dismiss.
            if appendingTo == nil {
                TutorialOrchestrator.shared.tryFire(.capture)
            }
            if !didAutoStart && phase == .breathing && tutorialOrchestrator.visible == nil {
                bootBreathPhase()
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                recPulse = true
            }
        }
        .onChange(of: tutorialOrchestrator.visible) { _, newValue in
            // Tutorial dismissed → start the breath (and the mic
            // permission flow that lives inside it). The orchestrator
            // has already marked Capture as seen via its `dismiss(_:)`
            // on the overlay's onDisappear.
            if newValue == nil && !didAutoStart && phase == .breathing {
                bootBreathPhase()
            }
        }
        .onDisappear {
            recording.stop()
            // Belt-and-braces: if the host dismisses us without going
            // through Cancel/Done (rare), don't leave the recorder running.
            if speechService.isRecording {
                speechService.stopRecording()
            }
        }
        .onReceive(speechService.$audioLevel) { sample in
            ingest(sample: sample)
        }
        // Hands-free recording cap — auto-save at the limit (never discard).
        // Held (manual) recordings are unbounded; see `shouldAutoSaveAtLimit`.
        .onChange(of: recording.elapsed) { _, _ in
            checkRecordingCap()
        }
        // "Hey Siri, stop recording" — stop-and-save any in-flight recording.
        .onChange(of: captureRequests.stopRequested) { _, requested in
            guard requested else { return }
            captureRequests.stopRequested = false
            if speechService.isRecording && !isFinalizing {
                stampSavedDuration()
                Task { await finishOrAbandon(saveResult: true) }
            }
        }
    }

    // MARK: - Body layout

    /// Vertical stack per the May-25 2026 "tight cluster + live
    /// transcript" spec: REC → timer → waveform packed into one tight
    /// upper cluster; "Clip N · on a roll" anchored DIRECTLY BELOW the
    /// waveform; live transcript serif strip below that. The bottom
    /// row floats to the safe area via a flexible `Spacer`.
    private var composerBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            recIndicator
                .padding(.top, 14)
            timerLabel
                .padding(.top, 12)
            waveform
                .padding(.top, 18)
            stateLine
                .padding(.top, 6)
                // Reserve the slot even when hidden so layout doesn't
                // bounce when the user crosses into clip 2.
                .frame(height: 16)
            liveTranscript
                .padding(.top, 22)
            Spacer()
            bottomActionRow
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Live transcript band

    /// Source Serif italic strip beneath the on-a-roll line that
    /// surfaces what the engine has heard so far. Centered, dimmed
    /// (`ink3`) so it reads as a quiet supportive feedback channel
    /// rather than a competing hero — the waveform stays the live
    /// edge. Empty state surfaces a fainter `Listening…` (ink4) so
    /// the user knows the engine is alive even before any word lands.
    ///
    /// The full transcript accumulates in
    /// `speechService.transcribedText` and rides to the resulting
    /// Memory at Done. The on-screen view caps the visible string
    /// from the tail so long sessions don't expand the slot
    /// arbitrarily — newer words stay readable, older words drift
    /// off the top (which the parent layout clips at its bounds).
    @ViewBuilder
    private var liveTranscript: some View {
        let full = speechService.transcribedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if full.isEmpty {
            Text("Listening…")
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Crucible.Color.ink4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
                .accessibilityLabel("Listening")
        } else {
            // Cap the visible string to the tail so the slot stays
            // bounded as the user records. 180 chars ≈ 2–3 lines at
            // the spec's font/width — matches the artboards.
            let tail = full.count > 180 ? "…" + String(full.suffix(180)) : full
            Text(tail)
                .font(.system(size: 17, design: .serif).italic())
                .foregroundStyle(Crucible.Color.ink3)
                .kerning(-0.1)
                .lineSpacing(6) // ≈ lineHeight 1.55 at 17pt
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
                .animation(.easeOut(duration: 0.18), value: tail)
                .accessibilityLabel("Live transcript")
                .accessibilityValue(tail)
        }
    }

    // MARK: - Breath content (phase = .breathing)

    /// One-breath panel per the May 27 2026 spec. Faint accent-tint
    /// ring underneath; bright accent ring fills clockwise from 12
    /// o'clock over ~1s; italic serif caption inside (rotates across
    /// recordings). Tap anywhere cancels and dismisses the composer.
    @ViewBuilder
    private var breathContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text("TAP TO CANCEL")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.top, 2)
            Spacer(minLength: 24)
            ZStack {
                BreathRing(progress: breathProgress, stroke: 14)
                Text(BreathCaption.caption(forIndex: breathCaptionIndex))
                    .font(.system(size: 22, design: .serif).italic())
                    .tracking(-0.2)
                    .foregroundStyle(Crucible.Color.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 18)
            }
            .frame(width: 200, height: 200)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { cancelCountdown() }
    }

    /// Permission denied. Composer can't do anything — show a clear
    /// message and let the user dismiss to Settings via the ✕.
    private var permissionDeniedContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Crucible.Color.ink3)
            Text("Microphone access denied")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text("Enable in Settings to record voice memories.")
                .font(.footnote)
                .foregroundStyle(Crucible.Color.ink2)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Header chrome (toolbar items)

    /// ✕ glyph in a subtle circle. Replaces the previous text "Cancel"
    /// button — the spec demotes destructive escapes to a corner glyph
    /// across every capture surface.
    private var cancelGlyph: some View {
        Button {
            // During breathing / denied, the recorder isn't hot —
            // cancel just dismisses the composer back to its
            // presenter. In the recording phase, fall through to the
            // existing discard path (which deletes any captured
            // audio and re-uses finishOrAbandon's cleanup).
            switch phase {
            case .breathing, .denied:
                cancelCountdown()
            case .recording:
                Task { await finishOrAbandon(saveResult: false) }
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
                .frame(width: 32, height: 32)
                .background(Crucible.Color.ink.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isFinalizing)
        .accessibilityLabel("Cancel recording")
    }

    /// "VOICE" eyebrow when starting fresh, or "Adding to · <Memory>"
    /// pill when appending. The pill clips with ellipsis on long
    /// Memory titles so the toolbar never wraps.
    @ViewBuilder
    private var headerCenter: some View {
        if let appendingTo, !appendingTo.isEmpty {
            HStack(spacing: 6) {
                Text("Adding to ·")
                    .foregroundStyle(Crucible.Color.ink3)
                Text(appendingTo)
                    .fontWeight(.medium)
                    .foregroundStyle(Crucible.Color.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Crucible.Color.card)
            .overlay(
                Capsule().stroke(Crucible.Color.hairline, lineWidth: 1)
            )
            .clipShape(Capsule())
        } else {
            Text("VOICE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink)
        }
    }

    // MARK: - REC indicator

    /// ● REC — ochre dot + small-caps "REC" label. Pulses 1.4s
    /// ease-in-out so the user has a tactile-feeling "audio is alive"
    /// cue independent of the waveform. Dot is 6pt per the May-25 2026
    /// tight-cluster spec (was 7pt) so it reads as a tighter cap on
    /// the upper rhythm.
    private var recIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Crucible.Color.accent)
                .frame(width: 6, height: 6)
                .opacity(recPulse ? 0.4 : 1.0)
            Text("REC")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Crucible.Color.accent)
        }
        .accessibilityLabel("Recording")
    }

    // MARK: - Timer hero

    /// 72pt SF Pro Display thin tabular — the visual hero. Reads
    /// from across the room.
    private var timerLabel: some View {
        Text(timerString)
            .font(.system(size: 72, weight: .thin).monospacedDigit())
            .tracking(-2.4)
            .foregroundStyle(Crucible.Color.ink)
            .accessibilityLabel("Recording \(timerString)")
    }

    /// Persistent "Clip N · on a roll" line. Visible from the first
    /// Next tap until the user commits or cancels; hidden during the
    /// initial clip (`currentClipIndex == 1`). Sits directly under
    /// the waveform per the May-25 2026 spec — anchored to the
    /// cluster as a label on the active moment, not as a separator
    /// between timer and waveform.
    @ViewBuilder
    private var stateLine: some View {
        if nextController.currentClipIndex > 1 {
            Text("Clip \(nextController.currentClipIndex) · on a roll")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(Crucible.Color.accent)
        }
    }

    // MARK: - Live waveform

    /// 56 bars, full-width, scaled to fill horizontally so the band
    /// reads as the hero the watch spec calls for. Bars are 3pt wide
    /// at 1pt gap nominally but scale to the container; right edge
    /// = newest sample. All bars at full ochre — the recency cue
    /// comes from values sliding left, not a dim gradient. No
    /// SwiftUI animation: each 100ms tick snaps to the new state for
    /// max apparent liveness (animating between 56-element arrays
    /// merges adjacent frames visually into ~1 Hz motion).
    private var waveform: some View {
        GeometryReader { geo in
            let barCount = VoiceRecordingController.waveBarCount
            let gap: CGFloat = 1
            let barWidth = max(
                2,
                (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            )
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<barCount, id: \.self) { idx in
                    let level = sampleAt(displayIndex: idx)
                    let h = barHeight(for: level, available: geo.size.height)
                    Capsule(style: .continuous)
                        .fill(Crucible.Color.accent)
                        .frame(width: barWidth, height: h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
    }

    /// Reads the audio level for a display position. Right-anchored:
    /// `idx == waveBarCount - 1` is the newest sample. Positions
    /// before the buffer's filled length read 0 (a 3pt stub) so the
    /// band has a stable width while warming up.
    private func sampleAt(displayIndex idx: Int) -> CGFloat {
        let offsetFromRight = (VoiceRecordingController.waveBarCount - 1) - idx
        return recording.sample(atOffsetFromRight: offsetFromRight)
    }

    /// Maps 0…1 level to a bar height. Floor of 3pt so a quiet room
    /// still shows a faint pulse — a perfectly flat row reads as
    /// "stopped recording," which is the exact signal we don't want.
    private func barHeight(for level: CGFloat, available: CGFloat) -> CGFloat {
        let minH: CGFloat = 3
        let scaled = max(level, 0.0)
        return max(minH, min(available, scaled * available))
    }

    /// Appends a fresh sample to the rolling buffer; trims to the
    /// visible window. Driven by `speechService.$audioLevel` ticks
    /// at the service's 10 Hz throttle.
    private func ingest(sample: CGFloat) {
        guard speechService.isRecording else { return }
        recording.ingest(sample: sample)
    }

    // MARK: - Bottom action row (Stop & save + Next satellite)

    /// Centered Stop button with the Next satellite at a fixed gap
    /// to its right. ZStack so the Stop button sits horizontally
    /// centered regardless of Next's presence; Next is positioned
    /// `Stop.center + Stop.radius + 36pt` per spec.
    private var bottomActionRow: some View {
        ZStack {
            stopColumn
            HStack {
                Spacer()
                nextColumn
                    .padding(.trailing, 28)
            }
        }
        .padding(.horizontal, 16)
    }

    /// 84pt ochre circle with a rounded-square stop glyph inside.
    /// Tap = commit + dismiss (same as Done). "Stop & save" caption
    /// below at 11pt weight 600 in ink2.
    private var stopColumn: some View {
        VStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                Task { await finishOrAbandon(saveResult: true) }
            } label: {
                ZStack {
                    Circle()
                        .fill(Crucible.Color.accent)
                        .frame(width: 84, height: 84)
                        .shadow(color: Crucible.Color.accent.opacity(0.40),
                                radius: 22, x: 0, y: 6)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Crucible.Color.accentInk)
                        .frame(width: 26, height: 26)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop and save")
            Text("Stop & save")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Crucible.Color.ink2)
        }
    }

    /// 56×56 ochre-tinted button with a chevron + trailing dot
    /// glyph. "Next" caption in 11pt weight 600 ochre below.
    /// Disabled (35% opacity) before recording begins — the gesture
    /// only means something mid-record.
    private var nextColumn: some View {
        VStack(spacing: 6) {
            Button {
                handleNextTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(Crucible.Color.accent.opacity(0.18))
                        .frame(width: 56, height: 56)
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                        Circle()
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(Crucible.Color.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next clip — end this clip, start a new one")
            .opacity(speechService.isRecording ? 1.0 : 0.35)
            .disabled(!speechService.isRecording)
            Text("Next")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Crucible.Color.accent)
        }
    }

    // MARK: - Walkthrough · beat 1b ("on a roll")

    /// F8 1b — an informational callout anchored toward the Next satellite,
    /// shown only while the walkthrough is on the `onARoll` beat. Floats ABOVE
    /// the bottom action row (the `.bottom` padding clears the 84pt Stop button
    /// + "Stop & save" caption + safe area) so it never obscures Stop & save or
    /// the timer, and `allowsHitTesting(false)` guarantees it never blocks Next,
    /// Stop, or Done. It carries no controls: beat 1b retires on the real signal
    /// (Next tapped, or recording stopped), never on a tap of the banner.
    ///
    /// Precise glyph-anchored positioning is a follow-up; this floats near the
    /// Next corner and names the control. Copy is design-authority (F7e), tier-
    /// independent — passing `isPlus: false` reads identically to `true`.
    @ViewBuilder
    private var walkthroughOnARollBanner: some View {
        if walkthrough.activeBeat == .onARoll {
            VStack(alignment: .trailing, spacing: 6) {
                Text(WalkthroughOrchestrator.Beat.onARoll.body(isPlus: false))
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.turn.right.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Crucible.Color.accent)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: 260, alignment: .trailing)
            .background(Crucible.Color.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Crucible.Color.accent.opacity(0.4), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.trailing, 20)
            .padding(.bottom, 132)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Finalizing overlay

    /// Shown when Done is tapped — split + re-transcribe runs
    /// locally; clips are short and transcription is fast.
    private var finalizingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(finalizingClipCount > 1
                 ? "Transcribing \(finalizingClipCount) clips…"
                 : "Saving…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
    }

    // MARK: - Breath driver

    /// One-breath fresh-start animation per the May 27 2026 spec:
    ///  • Single ochre ring fills clockwise from 12 o'clock over
    ///    ~800ms with a 200ms tail. Italic serif caption inside the
    ///    ring; caption rotates across recordings (index persisted
    ///    in UserDefaults).
    ///  • Soft haptic at start; slightly stronger haptic at the
    ///    moment recording begins.
    ///  • Tap anywhere cancels and dismisses the composer.
    ///  • Bypassed on Next-clip — the mic never pauses on Next, so
    ///    this driver only runs at composer open.
    ///
    /// Reduced Motion: progress snaps instead of animating; haptics
    /// still fire per spec (start + commit).
    @MainActor
    private func runBreath() async {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let softHaptic = UIImpactFeedbackGenerator(style: .soft)
        let commitHaptic = UIImpactFeedbackGenerator(style: .light)
        softHaptic.prepare()
        commitHaptic.prepare()

        phase = .breathing
        snap(&breathProgress, to: 0, animated: false)
        softHaptic.impactOccurred()
        // 800ms fill + 200ms tail. The tail is purely visual settle
        // time so the ring doesn't pop at 1.0 and immediately
        // disappear into the recording UI — gives the eye a beat
        // to land on the full ochre ring before the camera cuts.
        snap(&breathProgress, to: 1, animated: !reduceMotion)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        // Commit haptic — slightly stronger than the start.
        commitHaptic.impactOccurred()

        // Bump the persisted caption index now that the user has
        // committed to recording. Cancels never advance the index
        // so the same caption sticks across abandoned starts.
        let next = BreathCaption.nextIndex(after: breathCaptionIndex)
        breathCaptionIndex = next
        UserDefaults.standard.set(next, forKey: BreathCaption.defaultsKey)

        phase = .recording
        startRecording()
    }

    /// Mic-permission + breath-start sequence. Was inline in `.onAppear`
    /// pre-tutorial; extracted so the first-run tutorial's Start
    /// recording button can call exactly the same boot path. Idempotent
    /// via `didAutoStart` so a re-presentation of the screen doesn't
    /// fire twice.
    private func bootBreathPhase() {
        didAutoStart = true
        breathCaptionIndex = UserDefaults.standard.integer(
            forKey: BreathCaption.defaultsKey
        )
        countdownTask = Task { @MainActor in
            let granted = await speechService.requestAuthorization()
            guard !Task.isCancelled else { return }
            guard granted else { phase = .denied; return }
            await runBreath()
        }
    }

    /// Assigns `value` to `target`. When `animated` is false, wraps
    /// the assignment in a no-animation transaction so the view-
    /// level `.animation(...)` modifier doesn't interpolate. Reduced
    /// Motion users get instant value changes.
    @MainActor
    private func snap(_ target: inout CGFloat, to value: CGFloat, animated: Bool) {
        if animated {
            target = value
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { target = value }
        }
    }

    /// Cancel the countdown before the recorder fires. Dismisses the
    /// composer back to its presenter. Recording cancellation in the
    /// `.recording` phase uses the existing `finishOrAbandon(saveResult:
    /// false)` path.
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        dismiss()
    }

    // MARK: - Timer + recording lifecycle

    private var timerString: String {
        let total = Int(recording.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Whether a hands-free recording has reached its cap and should auto-save.
    /// Pure so the cap policy is unit-testable. `.manual` (held) is never
    /// capped; `limitMinutes == 0` means No limit.
    static func shouldAutoSaveAtLimit(source: CaptureSource, elapsed: TimeInterval, limitMinutes: Int) -> Bool {
        guard source == .handsFree, limitMinutes > 0 else { return false }
        return elapsed >= TimeInterval(limitMinutes) * 60
    }

    /// The uniform save confirmation — the SAME string for a Siri "stop
    /// recording" and a cap-triggered auto-save, so the limit never reads as an
    /// error. Real duration, rounded to whole minutes (min 1 — a sub-minute
    /// clip still saved).
    static func savedConfirmation(minutes: Int) -> String {
        let m = max(1, minutes)
        return "Saved — \(m) \(m == 1 ? "minute" : "minutes")."
    }

    /// Stamp the just-recorded duration so a Siri "stop recording" can speak it.
    private func stampSavedDuration() {
        captureRequests.lastSavedMinutes = max(1, Int((recording.elapsed / 60).rounded()))
    }

    /// Auto-save when a hands-free recording hits its cap — mirrors the watch
    /// wrist-off rule (`stop(save: true)`, never discards). Fires once.
    private func checkRecordingCap() {
        guard !didHitCap, speechService.isRecording, !isFinalizing else { return }
        guard Self.shouldAutoSaveAtLimit(source: captureSource,
                                         elapsed: recording.elapsed,
                                         limitMinutes: handsFreeLimitMinutes) else { return }
        didHitCap = true
        stampSavedDuration()
        Task { await finishOrAbandon(saveResult: true) }
    }

    private func startRecording() {
        speechService.startRecording()
        // VoiceRecordingController owns the elapsed counter +
        // waveform buffer + their reset/lifecycle. See
        // `Views/Input/VoiceRecordingController.swift`.
        recording.start()
        nextController.sessionDidStart()
        recordingStartedAt = Date()
        // F8 1b — mic is hot; move the walkthrough onto the on-a-roll beat
        // (no-op unless it's on the record beat).
        walkthrough.recordingDidStart()
        // Snapshot a one-shot location fix in parallel with the
        // recording. The result lands in `sessionLocation` whenever
        // CoreLocation returns; if Done fires before the fix arrives
        // the clips ship without coords (and the clip-row header
        // falls back to date + time). Mirrors the watch's
        // `WatchLocationProvider.requestOneShot` pattern.
        sessionLocation = nil
        Task { @MainActor in
            let toggleOn = UserDefaults.standard.object(forKey: "tagMemoriesWithLocation") as? Bool ?? true
            guard toggleOn else { return }
            let granted = await LocationService.shared.requestWhenInUseAuthorization()
            guard granted else { return }
            sessionLocation = await LocationService.shared.currentLocation()
        }
    }

    /// Routes a Next tap. `NextClipController` handles the 2s
    /// debounce — silent no-op if too soon. After a fired tap, write
    /// the offsets sidecar so a recovery split can run on relaunch
    /// if we crash.
    private func handleNextTap() {
        guard speechService.isRecording else { return }
        let prevCount = nextController.nextTapOffsets.count
        _ = nextController.handleNextTap()
        if nextController.nextTapOffsets.count > prevCount {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // F8 1b — the on-a-roll teaching has landed; retire its banner.
            walkthrough.nextClipStarted()
            // Crash-safety sidecar so an in-progress session can be
            // recovered after relaunch. The orchestrator owns the
            // JSON write; the view supplies the session metadata.
            if let masterFilename = speechService.lastRecordingPath {
                VoiceCaptureOrchestrator.writeOffsetsSidecar(
                    masterURL: SpeechService.audioURL(for: masterFilename),
                    rollGroupId: nextController.rollGroupId,
                    offsets: nextController.nextTapOffsets
                )
            }
        }
    }

    /// Save: stop recording, split the master file, re-transcribe
    /// each clip, emit the session. Cancel: stop and delete
    /// everything. The split / compress / transcribe loop lives in
    /// `VoiceCaptureOrchestrator`; this method only manages view
    /// state (`isFinalizing`, `dismiss`, `onFinish`/`onCancel`).
    private func finishOrAbandon(saveResult: Bool) async {
        if speechService.isRecording {
            speechService.stopRecording()
        }
        recording.stop()

        guard saveResult else {
            if let path = speechService.lastRecordingPath {
                AudioPlayerService.deleteAudio(filename: path)
                VoiceCaptureOrchestrator.deleteOffsetsSidecarIfAny(
                    masterURL: SpeechService.audioURL(for: path)
                )
            }
            nextController.sessionDidEnd()
            // F8 1b — discarded without a clip; return the walkthrough to the
            // record prompt so it isn't stranded on an in-composer beat.
            walkthrough.recordingDidCancel()
            onCancel()
            dismiss()
            return
        }

        guard let masterFilename = speechService.lastRecordingPath else {
            nextController.sessionDidEnd()
            onFinish([], nextController.rollGroupId ?? UUID())
            dismiss()
            return
        }

        let masterURL = SpeechService.audioURL(for: masterFilename)
        let offsets = nextController.nextTapOffsets
        let rollId = nextController.rollGroupId ?? UUID()
        let liveTranscript = speechService.transcribedText
        let lat = sessionLocation?.coordinate.latitude
        let lon = sessionLocation?.coordinate.longitude
        finalizingClipCount = offsets.count + 1
        isFinalizing = true

        // Falls back to "now" if the start anchor was somehow not
        // captured (defensive — `startRecording()` always sets it
        // before SpeechService starts, but a future call-site could
        // bypass that). The fallback collapses to the pre-fix
        // behavior for that one session, not a crash.
        let startedAt = recordingStartedAt ?? Date()
        let fragments: [VoiceClipFragment]
        if #available(iOS 26.0, *) {
            fragments = await VoiceCaptureOrchestrator.runSplitAndTranscribe(
                masterURL: masterURL,
                offsets: offsets,
                rollGroupId: rollId,
                liveTranscript: liveTranscript,
                recordingStartedAt: startedAt,
                sessionLatitude: lat,
                sessionLongitude: lon
            )
        } else {
            fragments = await VoiceCaptureOrchestrator.runSplitWithoutTranscription(
                masterURL: masterURL,
                offsets: offsets,
                rollGroupId: rollId,
                liveTranscript: liveTranscript,
                recordingStartedAt: startedAt,
                sessionLatitude: lat,
                sessionLongitude: lon
            )
        }

        // 2026-06-07 fix (#43): only delete the master if no fragment
        // references it. The orchestrator's single-clip and
        // split-fallback paths compress the master in place and
        // return it as the fragment file; deleting it then orphans
        // the persisted MediaReference at a phantom path. Tom's QA
        // device log showed `exists=false` for every clip and an
        // empty `Documents/VoiceEntries`. See
        // `VoiceCaptureOrchestrator.shouldDeleteMaster`.
        if VoiceCaptureOrchestrator.shouldDeleteMaster(masterFilename: masterFilename, fragments: fragments) {
            AudioPlayerService.deleteAudio(filename: masterFilename)
        }
        VoiceCaptureOrchestrator.deleteOffsetsSidecarIfAny(masterURL: masterURL)
        nextController.sessionDidEnd()

        onFinish(fragments, rollId)
        dismiss()
    }

}

/// One-breath fresh-start ring per the May 27 2026 spec. A faint
/// accent-tint ring underneath gives the bright fill something to
/// fill against; the bright accent stroke trims from 0 → 1
/// clockwise starting at 12 o'clock. Caption (italic serif) sits
/// inside via the parent ZStack — this view only handles the ring.
struct BreathRing: View {
    var progress: CGFloat
    var stroke: CGFloat = 14

    var body: some View {
        ZStack {
            // Faint underlay so the partial fill reads against
            // something solid. accentTint2 picks up the dark-mode
            // flip automatically via the asset catalog.
            Circle()
                .stroke(Crucible.Color.accentTint2,
                        style: StrokeStyle(lineWidth: stroke))

            // Bright ochre fill, clockwise from 12 o'clock. Linear
            // 1s drive (800ms fill + 200ms visual tail) matches the
            // JSX timing and keeps the breath feeling intentional
            // rather than rushed.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Crucible.Color.accent,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: progress)
        }
    }
}

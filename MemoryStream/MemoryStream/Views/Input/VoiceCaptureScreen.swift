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

    @Environment(\.dismiss) private var dismiss
    @StateObject private var nextController: NextClipController
    @State private var startedAt: Date? = nil
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var didAutoStart = false
    @State private var isFinalizing = false
    @State private var finalizingClipCount = 0
    /// REC dot pulse phase (~1.4s ease-in-out per watch spec; mirrored
    /// here for visual continuity between capture surfaces).
    @State private var recPulse: Bool = false
    /// Rolling history of audio levels for the live waveform.
    /// Newest at the end; capped at `Self.waveBarCount`.
    @State private var waveSamples: [CGFloat] = []
    /// One-shot location fix captured at recording start; stamped
    /// onto every `VoiceClipFragment` in this session at Done so the
    /// resulting `MediaReference`s carry their own place name. Nil
    /// when the user hasn't granted location, the request times out,
    /// or the global `tagMemoriesWithLocation` default is off. The
    /// fetch races recording — recording proceeds either way.
    @State private var sessionLocation: CLLocation? = nil
    /// Two-phase entry per the v2 spec. Every fresh start lands on
    /// the "Ready" phase first (bright ring draws in clockwise from
    /// 180° over ~600ms), then transitions to the 3·2·1 phase (dim
    /// overlay sweeps CCW from 180° continuously over 3s). No
    /// "Listening" beat — the ring closing at 12 o'clock is the
    /// "go." Cancel during countdown dismisses the composer.
    /// Recording cancel is the existing two-tap path via Cancel ✕.
    @State private var phase: ComposerPhase = .ready
    @State private var countdownTask: Task<Void, Never>? = nil
    /// Phase 1 progress — bright stroke drawing in.
    @State private var drawProgress: CGFloat = 0
    /// Phase 2 progress — dim overlay sweep over the bright ring.
    @State private var sweepProgress: CGFloat = 0

    enum ComposerPhase: Equatable {
        case ready            // Phase 1 — bright draw-in (~600ms)
        case countdown(Int)   // Phase 2 — 3, 2, 1 with CCW dim sweep
        case recording
        case denied
    }

    /// Phone composer has more horizontal room than the watch, so the
    /// band carries more bars. 56 keeps each bar at ~3pt + 1pt gap
    /// across the typical iPhone composer width with 16pt side
    /// padding.
    private static let waveBarCount: Int = 56

    init(
        onFinish: @escaping (_ clips: [VoiceClipFragment], _ rollGroupId: UUID) -> Void,
        onCancel: @escaping () -> Void,
        speechService: SpeechService,
        appendingTo: String? = nil
    ) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.speechService = speechService
        self.appendingTo = appendingTo
        self._nextController = StateObject(wrappedValue: NextClipController(handoff: speechService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Crucible.Color.paper.ignoresSafeArea()
                Group {
                    switch phase {
                    case .ready, .countdown:
                        countdownContent
                    case .denied:
                        permissionDeniedContent
                    case .recording:
                        composerBody
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
            // Run the fresh-start countdown the first time the
            // composer appears. Recording begins only after the
            // countdown finishes its "Listening" beat — see
            // `runCountdown()`.
            if !didAutoStart {
                didAutoStart = true
                countdownTask = Task { @MainActor in
                    let granted = await speechService.requestAuthorization()
                    guard !Task.isCancelled else { return }
                    guard granted else { phase = .denied; return }
                    await runCountdown()
                }
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                recPulse = true
            }
        }
        .onDisappear {
            stopTimer()
            // Belt-and-braces: if the host dismisses us without going
            // through Cancel/Done (rare), don't leave the recorder running.
            if speechService.isRecording {
                speechService.stopRecording()
            }
        }
        .onReceive(speechService.$audioLevel) { sample in
            ingest(sample: sample)
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

    // MARK: - Countdown content (phase = .countdown / .listening)

    /// Two-phase countdown panel per the v2 spec. Phase 1 shows
    /// "Ready" with the bright ring drawing in clockwise from 180°
    /// (~600ms); Phase 2 shows 3 → 2 → 1 with a dim overlay sweeping
    /// CCW from 180° continuously over 3s. Tap anywhere cancels and
    /// dismisses the composer.
    @ViewBuilder
    private var countdownContent: some View {
        let display = countdownLabel
        let isWord = phase == .ready
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text("TAP TO CANCEL")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.top, 12)
            Spacer(minLength: 24)
            ZStack {
                CountdownRing(
                    phase: phase,
                    drawProgress: drawProgress,
                    sweepProgress: sweepProgress,
                    stroke: 15
                )
                Text(display)
                    .font(.system(size: isWord ? 44 : 108,
                                  weight: isWord ? .medium : .thin)
                        .monospacedDigit())
                    .tracking(isWord ? -0.6 : -3.6)
                    .foregroundStyle(Crucible.Color.ink)
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

    private var countdownLabel: String {
        switch phase {
        case .ready:            return "Ready"
        case .countdown(let n): return "\(n)"
        default:                return ""
        }
    }

    // MARK: - Header chrome (toolbar items)

    /// ✕ glyph in a subtle circle. Replaces the previous text "Cancel"
    /// button — the spec demotes destructive escapes to a corner glyph
    /// across every capture surface.
    private var cancelGlyph: some View {
        Button {
            // During ready / countdown / denied, the recorder isn't
            // hot — cancel just dismisses the composer back to its
            // presenter. In the recording phase, fall through to the
            // existing discard path (which deletes any captured
            // audio and re-uses finishOrAbandon's cleanup).
            switch phase {
            case .ready, .countdown, .denied:
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
            let barCount = Self.waveBarCount
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
        let offsetFromRight = (Self.waveBarCount - 1) - idx
        let bufIdx = waveSamples.count - 1 - offsetFromRight
        return bufIdx >= 0 ? waveSamples[bufIdx] : 0
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
        waveSamples.append(sample)
        if waveSamples.count > Self.waveBarCount {
            waveSamples.removeFirst(waveSamples.count - Self.waveBarCount)
        }
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

    // MARK: - Countdown driver

    /// Two-phase countdown per the v2 spec:
    ///  • Phase 1 ("Ready"): bright ring draws in clockwise from
    ///    180° over 600ms.
    ///  • Phase 2 (3 → 2 → 1): bright ring stays full; dim overlay
    ///    sweeps CCW from 180° continuously over 3s. Numerals swap
    ///    at second ticks with a `selectionChanged` haptic. When the
    ///    bright crescent closes at 12 o'clock, recording starts —
    ///    no "Listening" beat.
    ///
    /// Reduced Motion: progress values snap instead of animating;
    /// numerals still change per spec.
    @MainActor
    private func runCountdown() async {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let selection = UISelectionFeedbackGenerator()
        selection.prepare()

        // Phase 1: Ready (600ms, bright ring draws in). Animation
        // is declared at the view level — just assign the target
        // value. For Reduced Motion, wrap in a no-animation
        // transaction so the view modifier doesn't interpolate.
        phase = .ready
        snap(&drawProgress, to: 0, animated: false)
        snap(&sweepProgress, to: 0, animated: false)
        snap(&drawProgress, to: 1, animated: !reduceMotion)
        try? await Task.sleep(nanoseconds: 600_000_000)
        if Task.isCancelled { return }

        // Phase 2: 3 · 2 · 1 (3s continuous dim sweep CCW).
        phase = .countdown(3)
        selection.selectionChanged()
        snap(&sweepProgress, to: 1, animated: !reduceMotion)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        phase = .countdown(2)
        selection.selectionChanged()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        phase = .countdown(1)
        selection.selectionChanged()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        // Ring crescent has closed — recording begins now.
        phase = .recording
        startRecording()
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
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func startRecording() {
        speechService.startRecording()
        startedAt = Date()
        elapsed = 0
        stopTimer()
        // 100ms cadence so the timer is fluid — counter and waveform
        // share visual rhythm.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let s = startedAt { elapsed = Date().timeIntervalSince(s) }
        }
        nextController.sessionDidStart()
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

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
            writeOffsetsSidecarIfPossible()
        }
    }

    /// Crash-safety sidecar — JSON file `<sessionId>.offsets.json`
    /// next to the master audio file. Recovery on relaunch: if both
    /// master file and sidecar exist for an in-progress session, run
    /// the split + transcribe pass and surface the clips. (Recovery
    /// wiring is forward-looking; this method writes the sidecar.)
    private func writeOffsetsSidecarIfPossible() {
        guard let masterFilename = speechService.lastRecordingPath else { return }
        let baseURL = SpeechService.audioURL(for: masterFilename)
            .deletingPathExtension()
        let sidecarURL = baseURL.appendingPathExtension("offsets.json")
        let payload: [String: Any] = [
            "rollGroupId": nextController.rollGroupId?.uuidString ?? "",
            "offsets": nextController.nextTapOffsets
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            try? data.write(to: sidecarURL, options: [.atomic])
        }
    }

    private func deleteOffsetsSidecarIfAny(masterFilename: String) {
        let baseURL = SpeechService.audioURL(for: masterFilename)
            .deletingPathExtension()
        let sidecarURL = baseURL.appendingPathExtension("offsets.json")
        try? FileManager.default.removeItem(at: sidecarURL)
    }

    /// Save: stop recording, split the master file, re-transcribe
    /// each clip, emit the session. Cancel: stop and delete
    /// everything.
    private func finishOrAbandon(saveResult: Bool) async {
        if speechService.isRecording {
            speechService.stopRecording()
        }
        stopTimer()

        guard saveResult else {
            if let path = speechService.lastRecordingPath {
                AudioPlayerService.deleteAudio(filename: path)
                deleteOffsetsSidecarIfAny(masterFilename: path)
            }
            nextController.sessionDidEnd()
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
        finalizingClipCount = offsets.count + 1
        isFinalizing = true

        let fragments = await runSplitAndTranscribe(
            masterURL: masterURL,
            offsets: offsets,
            rollGroupId: rollId,
            liveTranscript: liveTranscript
        )

        AudioPlayerService.deleteAudio(filename: masterFilename)
        deleteOffsetsSidecarIfAny(masterFilename: masterFilename)
        nextController.sessionDidEnd()

        onFinish(fragments, rollId)
        dismiss()
    }

    /// Splits the master file at the recorded offsets and runs a
    /// local transcription pass on each split. Single-clip case (no
    /// Next taps) short-circuits the split work and reuses the live
    /// transcript, since splitting a 1-clip session would just
    /// re-encode the same audio for no benefit.
    private func runSplitAndTranscribe(
        masterURL: URL,
        offsets: [TimeInterval],
        rollGroupId: UUID,
        liveTranscript: String
    ) async -> [VoiceClipFragment] {
        let lat = sessionLocation?.coordinate.latitude
        let lon = sessionLocation?.coordinate.longitude
        if offsets.isEmpty {
            // Single-clip session — master IS the clip. Compress before
            // returning so the journal entry attaches a small AAC file
            // instead of the multi-megabyte PCM master.
            await Self.compressIfPossible(at: masterURL, label: "phone single-clip master")
            let duration = audioDuration(at: masterURL)
            return [VoiceClipFragment(
                audioFilename: masterURL.lastPathComponent,
                transcript: liveTranscript,
                duration: duration,
                latitude: lat,
                longitude: lon
            )]
        }
        do {
            let outputDir = masterURL.deletingLastPathComponent()
            let splits = try await VoiceClipSplitter.split(
                masterURL: masterURL,
                nextTapOffsets: offsets,
                outputDir: outputDir,
                rollGroupId: rollGroupId
            )
            var fragments: [VoiceClipFragment] = []
            if #available(iOS 26.0, *) {
                for split in splits {
                    let url = SpeechService.audioURL(for: split.audioFilename)
                    // Compress each split before transcribing — saves
                    // disk, and SpeechAnalyzer reads AAC fine.
                    await Self.compressIfPossible(at: url, label: "phone split \(split.audioFilename)")
                    let result = await TranscriptionService.shared.transcribe(audioURL: url)
                    fragments.append(VoiceClipFragment(
                        audioFilename: split.audioFilename,
                        transcript: result.text,
                        duration: split.duration,
                        latitude: lat,
                        longitude: lon
                    ))
                }
            } else {
                fragments = splits.map {
                    VoiceClipFragment(
                        audioFilename: $0.audioFilename,
                        transcript: "",
                        duration: $0.duration,
                        latitude: lat,
                        longitude: lon
                    )
                }
            }
            return fragments
        } catch {
            ErrorState.shared.report(.mediaError("Voice clip split failed: \(error.localizedDescription)"))
            // Split failed — surface the unsplit master as one fragment.
            // Compress it so the fallback isn't penalized by size either.
            await Self.compressIfPossible(at: masterURL, label: "phone split-fallback master")
            let duration = audioDuration(at: masterURL)
            return [VoiceClipFragment(
                audioFilename: masterURL.lastPathComponent,
                transcript: liveTranscript,
                duration: duration,
                latitude: lat,
                longitude: lon
            )]
        }
    }

    private func audioDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        return TimeInterval(file.length) / sampleRate
    }

    /// Compress a finalized audio file in place to AAC. Failure is
    /// logged and swallowed — losing the size win is better than losing
    /// the clip. Mirrors `WatchSessionDelegate.compressIfPossible`.
    static func compressIfPossible(at url: URL, label: String) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let before = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        do {
            try await AudioCompressor.compressInPlace(at: url)
            let after = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let ratio = before > 0 && after > 0 ? Double(before) / Double(after) : 0
            NSLog("[Himem][Compress] \(label): \(before)→\(after) bytes (\(String(format: "%.1fx", ratio)))")
        } catch {
            NSLog("[Himem][Compress] failed for \(label): \(error.localizedDescription) — keeping raw PCM")
        }
    }
}

/// Two-phase fresh-start countdown ring per the v2 spec — phone
/// composer side. Mirrors `WatchRecordingView.CountdownRing` so
/// both surfaces share the visual vocabulary, scaled up for the
/// phone (200pt diameter, 15pt stroke).
///
///  • Phase 1 (`.ready`): bright ochre stroke draws in clockwise
///    from 180° as `drawProgress` goes 0 → 1.
///  • Phase 2 (`.countdown`): bright full ring is the base; a dim
///    ochre overlay (`#6B2510`) sweeps CCW from 180° as
///    `sweepProgress` goes 0 → 1.
struct CountdownRing: View {
    var phase: VoiceCaptureScreen.ComposerPhase
    var drawProgress: CGFloat
    var sweepProgress: CGFloat
    var stroke: CGFloat = 15

    /// Countdown-specific ochre palette — intentionally brighter
    /// than the brand `Crucible.Color.accent` (`#C64A1C`) per spec
    /// `Watch · spec-2.md`: "a brightened ochre, more saturated
    /// than the brand --accent for countdown readability." Sourced
    /// from the catalog (`accent-bright` / `accent-dim`) so the
    /// values automatically flip in dark mode without per-call
    /// branching.
    private var brightOchre: Color { Crucible.Color.accentBright }
    private var dimOchre: Color    { Crucible.Color.accentDim }

    private var isCountdown: Bool {
        if case .countdown = phase { return true } else { return false }
    }

    var body: some View {
        // All three layers are ALWAYS rendered, just opacity-gated
        // per phase. Stable view identity across phase transitions
        // lets the `.animation(value:)` modifier interpolate trim
        // changes cleanly — the previous switch-based version
        // created the dim overlay fresh on phase change, leaving it
        // with no prior value to animate from.
        ZStack {
            // Phase 1: bright stroke drawing in clockwise from 180°.
            Circle()
                .trim(from: 0, to: drawProgress)
                .stroke(brightOchre,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(90))
                .opacity(phase == .ready ? 1 : 0)
                .animation(.linear(duration: 0.6), value: drawProgress)

            // Phase 2: bright full base ring.
            Circle()
                .stroke(brightOchre, lineWidth: stroke)
                .opacity(isCountdown ? 1 : 0)

            // Phase 2: dim overlay — single arc, CCW from 12
            // o'clock, 120°/sec (full circle in 3s).
            Circle()
                .trim(from: 0, to: sweepProgress)
                .stroke(dimOchre,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .scaleEffect(x: -1, y: 1)
                .opacity(isCountdown ? 1 : 0)
                .animation(.linear(duration: 3.0), value: sweepProgress)
        }
    }
}

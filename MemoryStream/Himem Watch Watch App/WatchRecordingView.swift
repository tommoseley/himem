import SwiftUI
import WatchConnectivity

/// Watch recording surface — **V1 canonical** (`docs/watch/Watch · spec.md §2`).
///
/// Layout, top to bottom:
///   ✕ corner   ·   ● REC pulse   ·   big tabular timer   ·
///   persistent `Clip N · on a roll` (when N>1)   ·
///   live waveform (34 rolling bars)   ·
///   Stop & save pill   +   Next 52×52 ochre disc
///
/// Supersedes the V0 "mic disc with counter inside, Next below the
/// disc" design. Reasons for the retirement live in the spec (§2 Why
/// this layout). Don't reintroduce the disc — the waveform is the
/// "audio is rolling" contract.
struct WatchRecordingView: View {
    @EnvironmentObject var coordinator: WatchAppCoordinator
    /// Observed directly so `elapsed` ticks update the timer label
    /// every 100ms. `coordinator.recording` wouldn't cascade through
    /// `@Published` changes on the nested service.
    @ObservedObject var recording: WatchRecordingService
    @StateObject private var nextController: NextClipController
    @State private var didAutoStart = false
    @State private var showDiscardConfirm = false
    /// Two-phase entry into the recording surface per the v2 spec:
    /// every fresh start (complication, app-icon, Siri) lands on the
    /// "Ready" phase first (bright ring draws in clockwise from 180°
    /// over ~600ms), then transitions to the 3·2·1 countdown phase
    /// (dim overlay sweeps CCW from 180° continuously over 3s). No
    /// "Listening" beat — the ring closing at 12 o'clock is the "go."
    /// Next taps within a roll skip the countdown entirely.
    @State private var phase: RecordingPhase = .ready
    /// Handle to the active countdown driver Task so cancel (tap
    /// anywhere) can abort the timer before it transitions to
    /// `.recording` and starts the mic.
    @State private var countdownTask: Task<Void, Never>? = nil
    /// Ring progress for Phase 1 (bright stroke drawing in). 0…1
    /// driven by an explicit SwiftUI `withAnimation`.
    @State private var drawProgress: CGFloat = 0
    /// Ring progress for Phase 2 (dim overlay sweeping over the
    /// bright ring). 0…1 driven by an explicit SwiftUI animation
    /// scheduled to last the full 3s of the count.
    @State private var sweepProgress: CGFloat = 0

    enum RecordingPhase: Equatable {
        case ready            // Phase 1 — bright draw-in (~600ms)
        case countdown(Int)   // Phase 2 — 3, 2, 1 with CCW dim sweep
        case recording        // mic hot
        case denied           // permission refused
    }
    /// Rolling history of audio levels for the live waveform.
    /// Newest sample at the end; capped at `Self.waveBarCount` so
    /// the visible bars are exactly the most recent N samples.
    @State private var waveSamples: [CGFloat] = []
    /// Pulse phase for the ● REC indicator (~1.4s ease-in-out).
    @State private var recPulse: Bool = false

    /// 24 bars — chosen so the waveform fits cleanly across every
    /// shipping watch size (49mm Ultra down to 44mm Series). At 2pt
    /// bar + 1pt gap that's ~71pt of waveform. AOD freezes the bars
    /// on whatever was last drawn (SwiftUI animations stop under
    /// watchOS power rules); the REC dot and timer carry the
    /// "audio is rolling" contract in dimmed mode.
    private static let waveBarCount: Int = 24
    private static let lowStorageLabel: String = "Sync soon"
    private static let thirtySecondsLeftMark: TimeInterval = WatchRecordingService.maxDuration - 30

    init(recording: WatchRecordingService) {
        self.recording = recording
        _nextController = StateObject(wrappedValue: NextClipController(handoff: recording))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch phase {
            case .ready, .countdown:
                countdownContent
            case .denied:
                permissionDeniedContent
            case .recording:
                recordingContent
            }
            // Per v2 spec: ✕ corner glyph is hidden during the
            // countdown. The whole screen is the cancel target —
            // single affordance. The ✕ only re-renders once we're in
            // the recording phase, where it's the explicit discard
            // path with the two-tap confirm.
            if phase == .recording {
                cancelButton
                    .padding(.leading, 8)
                    .padding(.top, 4)
            }
        }
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onReceive(recording.$audioLevel) { sample in
            ingest(sample: sample)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                recPulse = true
            }
        }
        .alert("Discard this clip?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { discard() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text(nextController.currentClipIndex > 1
                 ? "Earlier clips in this recording are already saved."
                 : "This audio won't be saved.")
        }
    }

    // MARK: - Recording content (phase = .recording)

    private var recordingContent: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 4)
            recIndicator
            timerLabel
            stateLine
            if isInClosingWindow {
                thirtySecondsLeftLabel
            }
            Spacer(minLength: 2)
            waveform
            Spacer(minLength: 4)
            bottomActionRow
        }
        .padding(.bottom, 8)
    }

    // MARK: - Countdown content (phase = .ready / .countdown)

    /// Two-phase countdown panel per the v2 spec. Phase 1 ("Ready")
    /// shows the bright ring drawing in clockwise from 180°. Phase 2
    /// (3 · 2 · 1) shows the full bright ring with a dim overlay
    /// sweeping CCW from 180° continuously over 3 seconds. Numerals
    /// swap at second ticks but the ring is the primary signal.
    /// Tap anywhere cancels and routes back to home.
    @ViewBuilder
    private var countdownContent: some View {
        let display = countdownLabel
        let isWord = phase == .ready
        VStack(spacing: 0) {
            Spacer(minLength: 6)
            Text("TAP TO CANCEL")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 6)
            Spacer()
            ZStack {
                CountdownRing(
                    phase: phase,
                    drawProgress: drawProgress,
                    sweepProgress: sweepProgress,
                    stroke: 12
                )
                Text(display)
                    .font(.system(size: isWord ? 30 : 64,
                                  weight: isWord ? .medium : .thin)
                        .monospacedDigit())
                    .tracking(isWord ? -0.6 : -2.2)
                    .foregroundStyle(Color.white)
            }
            .frame(width: 128, height: 128)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { cancelCountdown() }
    }

    /// Permission was denied during the pre-countdown check. We don't
    /// silently sit on a non-recording surface — bounce home with a
    /// brief message so the user understands why nothing happened.
    private var permissionDeniedContent: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Microphone access denied")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Text("Enable in iPhone Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var countdownLabel: String {
        switch phase {
        case .ready:            return "Ready"
        case .countdown(let n): return "\(n)"
        default:                return ""
        }
    }

    // MARK: - REC indicator

    /// `● REC` — small, ochre, pulsing ~1.4s ease-in-out per spec.
    /// Pulses subtly to reinforce that audio is being captured;
    /// distinct from the heavy V0 mic disc, which carried the
    /// counter inside it.
    private var recIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(WatchTheme.accent)
                .frame(width: 7, height: 7)
                .opacity(recPulse ? 0.4 : 1.0)
            Text("REC")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(WatchTheme.accent)
        }
        .accessibilityLabel("Recording")
    }

    // MARK: - Timer hero

    /// Big timer — display-weight (`.thin`) tabular numerals,
    /// 44pt+. Reads from across the room. Shifts to warn-amber in
    /// the closing 30-second window before the 5-min auto-stop.
    private var timerLabel: some View {
        Text(timeString)
            .font(.system(size: 44, weight: .thin).monospacedDigit())
            .tracking(-1)
            .foregroundStyle(isInClosingWindow ? WatchTheme.warnAmber : WatchTheme.cream)
            .accessibilityLabel("Recording \(timeString)")
    }

    /// Persistent `Clip N · on a roll` line. Visible from the first
    /// Next tap until Stop & save or Cancel; hidden during the
    /// initial clip (`N == 1`). Per spec: a 1.5s flash is too easy
    /// to miss while mid-thought.
    @ViewBuilder
    private var stateLine: some View {
        if nextController.currentClipIndex > 1 {
            Text("Clip \(nextController.currentClipIndex) · on a roll")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchTheme.accent)
                .transition(.opacity)
        }
    }

    /// `30s left` — small amber label inside the closing window of
    /// the 5-min cap. Pairs with the warn-amber timer color.
    private var thirtySecondsLeftLabel: some View {
        Text("30s left")
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(WatchTheme.warnAmber)
    }

    // MARK: - Waveform

    /// Rolling 24-bar waveform — the "audio is rolling" contract.
    /// Always renders a full row of 24 bars (zero-padded on the left
    /// while the buffer is still filling) so the band has a stable
    /// width and centered position. Newest sample is the right edge;
    /// older samples scroll left. All bars are full ochre — the
    /// motion of values sliding left carries the recency cue; a
    /// dim-tail opacity gradient made the left half look "off."
    ///
    /// Bar width scales to fill the available container width —
    /// fixed 2pt was too narrow on the 49mm Ultra and made the band
    /// look ornamental rather than the hero it's supposed to be.
    ///
    /// No SwiftUI animation on `waveSamples` — each 100ms tick
    /// SNAPS bars to their new heights. Animating between two
    /// 24-element arrays at 10 Hz makes the band look interpolated
    /// and visually merge into ~1 Hz motion; snapping reads as the
    /// live capture it is.
    private var waveform: some View {
        GeometryReader { geo in
            let barCount = Self.waveBarCount
            let gap: CGFloat = 1.5
            let barWidth = max(
                2,
                (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            )
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<barCount, id: \.self) { idx in
                    let level = sampleAt(displayIndex: idx)
                    let barH = barHeight(for: level, available: geo.size.height)
                    Capsule(style: .continuous)
                        .fill(WatchTheme.accent)
                        .frame(width: barWidth, height: barH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }

    /// Returns the audio level for a given *display* position in the
    /// 24-bar row. The right edge (`idx == 23`) reads the newest
    /// sample; positions to the left of the buffer's filled length
    /// return 0 so the band stays a stable width while the buffer
    /// is still warming up.
    private func sampleAt(displayIndex idx: Int) -> CGFloat {
        let offsetFromRight = (Self.waveBarCount - 1) - idx
        let bufIdx = waveSamples.count - 1 - offsetFromRight
        return bufIdx >= 0 ? waveSamples[bufIdx] : 0
    }

    /// Maps a 0…1 audio level to a bar height in the given band.
    /// Floor of 3pt so a quiet room still shows a faint pulse (a
    /// totally flat row reads as "nothing happening" — the very
    /// signal we're trying not to send). The 1.4× gain pushes
    /// conversational speech (~0.4–0.7) up into the upper half of
    /// the band where it reads as actual movement; loud peaks still
    /// cap at the band height.
    private func barHeight(for level: CGFloat, available: CGFloat) -> CGFloat {
        let minH: CGFloat = 3
        let amplified = max(level, 0.0) * 1.4
        return max(minH, min(available, amplified * available))
    }

    /// Appends a sample to the rolling buffer and trims to the
    /// visible window. Called on every `audioLevel` publish so the
    /// bars advance at the recorder's 100ms cadence.
    private func ingest(sample: CGFloat) {
        guard recording.isRecording else { return }
        waveSamples.append(sample)
        if waveSamples.count > Self.waveBarCount {
            waveSamples.removeFirst(waveSamples.count - Self.waveBarCount)
        }
    }

    // MARK: - Bottom action row (Stop & save + Next)

    /// Stop & save pill + Next disc on the same horizontal axis.
    /// Stop is the cream-on-dark hero (flex:1); Next is the 52×52
    /// ochre disc to its right. Cancel does *not* live here.
    private var bottomActionRow: some View {
        HStack(spacing: 8) {
            stopSavePill
            nextDisc
        }
        .padding(.horizontal, 10)
    }

    private var stopSavePill: some View {
        Button {
            stopAndSave()
        } label: {
            Text("Stop & save")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(WatchTheme.cream)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Next-clip disc — ochre fill, cream glyph. Spec: "forward
    /// chevron with trailing dot. Reads as 'advance, mark.'" Built
    /// as `chevron.right` + a small dot so the glyph reads as the
    /// pairing intended; the SF symbol library doesn't carry the
    /// exact composite.
    private var nextDisc: some View {
        Button {
            _ = nextController.handleNextTap()
        } label: {
            ZStack {
                Circle()
                    .fill(WatchTheme.accent)
                    .frame(width: 42, height: 42)
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                    Circle()
                        .frame(width: 3, height: 3)
                }
                .foregroundStyle(WatchTheme.cream)
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .opacity(isNextDimmed ? 0.4 : 1.0)
        .disabled(isNextDimmed)
        .overlay(alignment: .bottom) {
            // "Sync soon" sub-label at storage cap. Sits below the
            // disc inside the same column; doesn't disturb the
            // pill's vertical centering.
            if isNextDimmed {
                Text(Self.lowStorageLabel)
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(WatchTheme.warnAmber)
                    .offset(y: 12)
            }
        }
        .accessibilityLabel("Next clip — end this clip, start a new one")
    }

    /// Next dims to 40% at 49/50 unsynced clips. Stop & save is
    /// never blocked (spec: "we always let the user commit what
    /// they're saying").
    private var isNextDimmed: Bool {
        coordinator.pending.isAtCap
    }

    // MARK: - Cancel ✕ (top-left corner)

    /// Compact ✕ glyph, top-left corner, visually demoted from the
    /// commit row. Never sits beside Stop & save as a peer pill —
    /// that's the V3 anti-pattern.
    private var cancelButton: some View {
        Button {
            // During the ready / countdown / denied phases the
            // recorder isn't hot yet — cancel routes straight home
            // without a confirm. In the recording phase, behavior
            // matches before: empty clip on the first clip discards
            // silently; otherwise the two-tap confirm fires.
            switch phase {
            case .ready, .countdown, .denied:
                cancelCountdown()
            case .recording:
                let currentClipEmpty = recording.elapsed < 1.0 || recording.peakAudioLevel < 0.1
                if currentClipEmpty && nextController.currentClipIndex == 1 {
                    discard()
                } else {
                    showDiscardConfirm = true
                }
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discard recording")
    }

    // MARK: - Derived state

    private var timeString: String {
        let total = Int(recording.elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// True when we're inside the last 30 seconds of the 5-minute
    /// clip cap. Drives both the amber timer color and the "30s
    /// left" sub-label. Per spec §2 Recording rules.
    private var isInClosingWindow: Bool {
        recording.isRecording && recording.elapsed >= Self.thirtySecondsLeftMark
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        guard !didAutoStart else { return }
        didAutoStart = true
        countdownTask = Task { @MainActor in
            // Pre-fetch mic permission before the sweep so the system
            // prompt doesn't interrupt the countdown on first launch.
            let granted = await recording.ensureMicPermission()
            guard !Task.isCancelled else { return }
            guard granted else { phase = .denied; return }
            await runCountdown()
        }
    }

    /// Drives the two-phase countdown:
    ///  • Phase 1 ("Ready"): bright ring draws in clockwise from
    ///    180° over 600ms. Anchors the eye before the numbers arrive.
    ///  • Phase 2 (3 → 2 → 1): bright ring is full; dim overlay
    ///    sweeps CCW from 180° continuously over 3s. Numerals swap
    ///    each second with a `.click` haptic. No "Listening" beat —
    ///    the ring closing at 12 o'clock IS the "go," and recording
    ///    starts the moment the count reaches zero.
    ///
    /// Reduced Motion: progress values snap instead of animating;
    /// the numerals still change per spec.
    @MainActor
    private func runCountdown() async {
        let reduceMotion = WKAccessibilityIsReduceMotionEnabled()

        // Phase 1: Ready (600ms, bright ring draws in). Animation
        // is declared at the view level via `.animation(...)`; just
        // assign the target value here. For Reduced Motion, wrap the
        // assignment in a no-animation transaction so the view
        // modifier doesn't kick in either.
        phase = .ready
        snap(&drawProgress, to: 0, animated: false)
        snap(&sweepProgress, to: 0, animated: false)
        snap(&drawProgress, to: 1, animated: !reduceMotion)
        try? await Task.sleep(nanoseconds: 600_000_000)
        if Task.isCancelled { return }

        // Phase 2: 3 · 2 · 1 (3s continuous dim sweep CCW).
        phase = .countdown(3)
        WKInterfaceDevice.current().play(.click)
        snap(&sweepProgress, to: 1, animated: !reduceMotion)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        phase = .countdown(2)
        WKInterfaceDevice.current().play(.click)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        phase = .countdown(1)
        WKInterfaceDevice.current().play(.click)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        // Ring crescent has closed — recording begins now.
        await recording.start()
        if recording.isRecording {
            nextController.sessionDidStart()
            phase = .recording
        } else {
            // Recorder failed to start (most likely permission was
            // revoked between the pre-check and start). Bounce home.
            coordinator.route = .home
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

    /// Tap-anywhere on the countdown surface OR the ✕ corner glyph
    /// during the countdown phase. Cancels the timer Task before it
    /// transitions to `.recording`, then routes home.
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        coordinator.route = .home
    }

    /// Wrist-off / nav-away safety net. Spec: "We never discard
    /// work the user walked away from." Only auto-saves when there's
    /// any real audio captured — a sub-1s clip with no audio level
    /// is a tap-and-leave, not a save-worthy thought. If the user
    /// walks away during the countdown (recorder never started),
    /// just cancel the task — there's nothing to save.
    private func handleDisappear() {
        countdownTask?.cancel()
        countdownTask = nil
        guard recording.isRecording else { return }
        let isEffectivelyEmpty =
            recording.elapsed < 1.0 &&
            recording.peakAudioLevel < 0.1
        _ = recording.stop(save: !isEffectivelyEmpty)
        nextController.sessionDidEnd()
    }

    private func stopAndSave() {
        let offsets = nextController.nextTapOffsets
        guard let clip = recording.stop(save: true, nextTapOffsets: offsets) else {
            nextController.sessionDidEnd()
            coordinator.route = .home
            return
        }
        nextController.sessionDidEnd()
        coordinator.transfer.send(clip: clip)
        let isReachable = WCSessionReachable.isReachable
        let isStorageFull = coordinator.pending.isAtCap
        let confirmation: WatchConfirmation
        if isStorageFull {
            confirmation = .storageFull
        } else if isReachable {
            confirmation = .syncing(duration: clip.duration)
        } else {
            confirmation = .savedOnWatch(duration: clip.duration)
        }
        coordinator.route = .confirmation(confirmation)
    }

    private func discard() {
        // Per spec: Cancel discards ONLY the current in-progress
        // clip. Earlier clips in the roll committed at each Next
        // tap and stay in pending.
        _ = recording.stop(save: false)
        nextController.sessionDidEnd()
        coordinator.flashDiscardedToast()
        coordinator.route = .home
    }
}

/// Two-phase fresh-start countdown ring per the v2 spec.
///
///  • Phase 1 (`.ready`): bright ochre stroke **draws in clockwise
///    from 180°** (6 o'clock) as `drawProgress` goes 0 → 1. Round
///    cap so the leading edge reads cleanly.
///  • Phase 2 (`.countdown`): bright full ring is the base; a dim
///    ochre overlay (`#6B2510`) **sweeps counter-clockwise from
///    180°** as `sweepProgress` goes 0 → 1, "eating" the bright
///    ring down to a crescent at 12 o'clock. Butt cap on the dim
///    overlay so the sweep edge is a clean radial line.
///
/// The animations themselves are driven by the parent via explicit
/// `withAnimation` calls — this view just reads the current values.
struct CountdownRing: View {
    var phase: WatchRecordingView.RecordingPhase
    var drawProgress: CGFloat
    var sweepProgress: CGFloat
    var stroke: CGFloat = 12

    /// Countdown-specific ochre palette — intentionally brighter
    /// than the brand `WatchTheme.accent` (`#C64A1C`) per spec
    /// `Watch · spec-2.md`: "a brightened ochre, more saturated
    /// than the brand --accent for countdown readability." Both
    /// values inlined here rather than in `WatchTheme` because they
    /// only exist for the countdown surface.
    private var brightOchre: Color {
        Color(red: 0xE5/255, green: 0x5A/255, blue: 0x22/255)
    }
    private var dimOchre: Color {
        Color(red: 0x9A/255, green: 0x38/255, blue: 0x15/255)
    }

    private var isCountdown: Bool {
        if case .countdown = phase { return true } else { return false }
    }

    var body: some View {
        // All three layers are ALWAYS rendered, just opacity-gated
        // per phase. That gives SwiftUI a stable view identity
        // across `.ready → .countdown` transitions so the
        // `.animation(value:)` modifier can interpolate trim
        // changes cleanly. The previous switch-based structure
        // created the dim overlay fresh on phase change, which left
        // it with no prior value to animate from — sweepProgress
        // jumped to 1 instantly.
        ZStack {
            // Phase 1: bright stroke drawing in clockwise from 180°.
            Circle()
                .trim(from: 0, to: drawProgress)
                .stroke(brightOchre,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(90))
                .opacity(phase == .ready ? 1 : 0)
                .animation(.linear(duration: 0.6), value: drawProgress)

            // Phase 2: bright full base ring. Identical to the
            // completed Phase 1 draw-in — invisible swap between
            // phases.
            Circle()
                .stroke(brightOchre, lineWidth: stroke)
                .opacity(isCountdown ? 1 : 0)

            // Phase 2: dim overlay — single arc, CCW from 12
            // o'clock, 120°/sec (full circle in 3s). Default
            // SwiftUI circle path is CW from 3 o'clock;
            // `rotationEffect(-90°)` moves the start to 12,
            // `scaleEffect(x: -1)` flips the visual direction to
            // CCW. `trim(from: 0, to: sweepProgress)` grows the
            // arc from 12 toward 9 → 6 → 3 → 12.
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

/// Tiny indirection so the view can read iPhone reachability inline.
enum WCSessionReachable {
    static var isReachable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
    }
}

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
    /// One-breath entry into the recording surface per the May 27
    /// 2026 spec revision. A single ochre ring fills clockwise in
    /// ~1s; italic serif caption inside rotates across recordings
    /// from the shared `BreathCaption` list. Next taps within a
    /// roll skip the breath entirely — the mic never pauses on
    /// Next per the on-a-roll contract.
    @State private var phase: RecordingPhase = .breathing
    /// Handle to the active breath driver Task so cancel (tap
    /// anywhere) can abort before the mic goes hot.
    @State private var countdownTask: Task<Void, Never>? = nil
    /// Ring progress 0…1 driven by an explicit SwiftUI animation
    /// over the 1s breath.
    @State private var breathProgress: CGFloat = 0
    /// Caption index for the current breath. Read from UserDefaults
    /// on first appear; the persisted store is bumped only when the
    /// user commits to recording, not on cancel.
    @State private var breathCaptionIndex: Int = 0

    enum RecordingPhase: Equatable {
        case breathing        // one-breath ring fill (~1s)
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
            case .breathing:
                breathContent
            case .denied:
                permissionDeniedContent
            case .recording:
                recordingContent
            }
            // ✕ corner glyph is hidden during the breath. The whole
            // screen is the cancel target — single affordance. The
            // ✕ only re-renders once we're in the recording phase,
            // where it's the explicit discard path with the two-tap
            // confirm.
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

    // MARK: - Breath content (phase = .breathing)

    /// One-breath panel per the May 27 2026 spec. Faint accent
    /// underlay; bright accent ring fills clockwise from 12 o'clock
    /// over ~1s; italic serif caption inside (from the shared
    /// `BreathCaption` rotation). Tap anywhere cancels and routes
    /// back to home.
    @ViewBuilder
    private var breathContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)
            Text("TAP TO CANCEL")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 0)
                .offset(y: -4)
            Spacer()
            ZStack {
                BreathRing(progress: breathProgress, stroke: 10)
                Text(BreathCaption.caption(forIndex: breathCaptionIndex))
                    .font(.system(size: 15, design: .serif).italic())
                    .tracking(-0.2)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .padding(.horizontal, 14)
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
            // During the breathing / denied phases the recorder
            // isn't hot yet — cancel routes straight home without a
            // confirm. In the recording phase, behavior matches
            // before: empty clip on the first clip discards
            // silently; otherwise the two-tap confirm fires.
            switch phase {
            case .breathing, .denied:
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
        // Snapshot the persisted caption index NOW so we show the
        // right line on the first frame. The index only moves
        // forward in `runBreath`'s commit path.
        breathCaptionIndex = UserDefaults.standard.integer(forKey: BreathCaption.defaultsKey)
        countdownTask = Task { @MainActor in
            // Pre-fetch mic permission before the breath so the
            // system prompt doesn't interrupt the animation on
            // first launch.
            let granted = await recording.ensureMicPermission()
            guard !Task.isCancelled else { return }
            guard granted else { phase = .denied; return }
            await runBreath()
        }
    }

    /// Drives the one-breath fresh-start per the May 27 2026 spec:
    ///  • Single ochre ring fills clockwise from 12 o'clock over
    ///    ~800ms with a 200ms tail. Italic serif caption inside
    ///    rotates across recordings.
    ///  • Two `.click` haptics — one at the start of the breath,
    ///    one at the moment recording begins (the "go" cue).
    ///    Both are tactile-only; `.success` was rejected because
    ///    watchOS pairs it with an audible chime that doesn't fit
    ///    the quiet "you're free to speak" mood.
    ///  • Tap anywhere cancels; bypassed on Next-clip.
    ///
    /// Reduced Motion: progress snaps to 1 instead of animating,
    /// but the same ~1s wait still elapses so the rhythm of "you
    /// have a beat before mic-hot" is preserved.
    @MainActor
    private func runBreath() async {
        let reduceMotion = WKAccessibilityIsReduceMotionEnabled()

        phase = .breathing
        snap(&breathProgress, to: 0, animated: false)
        WKInterfaceDevice.current().play(.click)
        snap(&breathProgress, to: 1, animated: !reduceMotion)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        // Commit haptic — the "go." Tactile-only `.click`; no
        // chime.
        WKInterfaceDevice.current().play(.click)

        // Bump the persisted caption index now that the user has
        // committed to recording. Cancels never advance the index.
        let next = BreathCaption.nextIndex(after: breathCaptionIndex)
        breathCaptionIndex = next
        UserDefaults.standard.set(next, forKey: BreathCaption.defaultsKey)

        // Ring is full — recording begins now.
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

/// One-breath fresh-start ring per the May 27 2026 spec — watch
/// side. Faint accent underlay against pure black so the partial
/// fill reads against something; bright accent stroke trims from
/// 0 → 1 clockwise starting at 12 o'clock. Mirrors the phone's
/// `BreathRing` in `VoiceCaptureScreen.swift`; sized for the watch
/// (128pt frame, 10pt stroke).
struct BreathRing: View {
    var progress: CGFloat
    var stroke: CGFloat = 10

    var body: some View {
        ZStack {
            // Faint underlay — `accent` at low alpha against the
            // OLED-black background. Watch palette doesn't have
            // an explicit `accentTint2` token so we derive one
            // inline.
            Circle()
                .stroke(WatchTheme.accent.opacity(0.18),
                        style: StrokeStyle(lineWidth: stroke))

            // Bright ochre fill, clockwise from 12 o'clock. 1s
            // linear matches the phone driver.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(WatchTheme.accent,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: progress)
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

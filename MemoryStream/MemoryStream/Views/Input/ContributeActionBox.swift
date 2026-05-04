import SwiftUI
import AVFoundation

/// Contribute Mode's primary surface. Replaces the legacy ComposerView in the
/// new-memory and append-to-memory flows.
///
/// Layout:
///
///   ┌──────────────────────────────────┐  ← top toolbar: X + Done
///   │ [Tiles ScrollView, top-down]     │
///   │ [tile] [tile] [tile]             │
///   │ [tile]                           │
///   ├──────────────────────────────────┤
///   │ [Voice]  [Photo]                 │  ← Action Box, fixed-height
///   │ [Video]  [Text]                  │
///   └──────────────────────────────────┘
///
/// The Action Box is bottom-anchored so it never moves as tiles accumulate.
/// Voice and Video buttons render their own recording-state UI inline (red dot,
/// elapsed time, tap to stop). Tap a capture-type button to begin that capture.
///
/// Wired to ContributeSessionViewModel for the lifecycle (Done / X) and to
/// track each capture's id for the silent-discard rule and X-discard cleanup.
/// Capture *plumbing* (SpeechService, camera presentation, photo picker) is
/// added incrementally in subsequent commits — this commit is the layout shell.
struct ContributeActionBox: View {
    @ObservedObject var session: ContributeSessionViewModel
    @ObservedObject var speechService: SpeechService
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @State private var recordingStartedAt: Date? = nil
    @State private var cameraMode: CameraPickerView.CaptureMode? = nil
    @State private var isMountingCamera = false
    @State private var showTextEditor = false
    @State private var textDraft: String = ""
    @State private var selectedTileMedia: MediaDisplayItem? = nil
    @State private var showLibraryPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    tilesArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    actionBox
                }
                if isMountingCamera {
                    cameraMountingOverlay
                }
            }
            .background(Crucible.Color.paper)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        handleDiscardTap()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink2)
                    }
                    .accessibilityLabel("Discard contribution")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        handleDoneTap()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.accent)
                    .accessibilityHint("Save these contributions and exit")
                }
            }
            .navigationTitle("Contribute")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: speechService.isRecording) { wasRecording, isRecording in
            // Recording transitioned from on → off: persist the result.
            guard wasRecording, !isRecording else { return }
            handleRecordingStopped()
        }
        .onAppear {
            // session.enter(autoStartVoice: true) marks activeCapture=.voice
            // but doesn't itself touch SpeechService — the view owns that.
            // Honor the auto-start now that we're on screen.
            if session.activeCapture == .voice && !speechService.isRecording {
                startVoiceRecording()
            }
        }
        .fullScreenCover(item: $cameraMode) { mode in
            CameraPickerView(
                captureMode: mode,
                onCapture: { result in
                    cameraMode = nil
                    handleCameraCapture(result)
                },
                onDismiss: { cameraMode = nil }
            )
            .onAppear {
                // Cover is on screen; user can see the camera UI now, drop
                // the mounting spinner.
                isMountingCamera = false
            }
        }
        .fullScreenCover(isPresented: $showTextEditor) {
            ContributeTextEditor(
                draft: $textDraft,
                onCommit: { text in
                    session.trackTypedNote(text)
                    textDraft = ""
                    session.setActiveCapture(nil)
                    showTextEditor = false
                },
                onCancel: {
                    textDraft = ""
                    session.setActiveCapture(nil)
                    showTextEditor = false
                }
            )
        }
        .sheet(isPresented: $session.showDiscardConfirmation) {
            DiscardConfirmationSheet(
                summary: discardSummary,
                onDiscard: { mute in
                    session.confirmDiscard(muteFutureConfirmations: mute)
                },
                onKeep: {
                    session.showDiscardConfirmation = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLibraryPicker) {
            PhotoLibraryPicker { identifiers in
                handleLibraryAttach(identifiers)
                showLibraryPicker = false
            }
        }
    }

    private func handleLibraryAttach(_ identifiers: [String]) {
        for id in identifiers {
            session.persistMediaCapture(localIdentifier: id, mediaType: .image)
        }
    }

    /// Plain-language enumeration of what's about to be discarded — used in
    /// the X confirmation. Pluralization handled per type; voice clips and
    /// transcribed/typed text segments are listed separately because the
    /// user thinks of them as different things.
    private var discardSummary: String {
        let voice = session.sessionCaptures.filter { $0.mediaType == .voice }.count
        let photo = session.sessionCaptures.filter { $0.mediaType == .image }.count
        let video = session.sessionCaptures.filter { $0.mediaType == .video }.count
        let text = session.sessionTypedNotes.count

        var parts: [String] = []
        if voice > 0 { parts.append("\(voice) voice clip" + (voice == 1 ? "" : "s")) }
        if photo > 0 { parts.append("\(photo) photo" + (photo == 1 ? "" : "s")) }
        if video > 0 { parts.append("\(video) video" + (video == 1 ? "" : "s")) }
        if text > 0 { parts.append("\(text) note" + (text == 1 ? "" : "s")) }

        switch parts.count {
        case 0: return "this contribution"
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default:
            let head = parts.dropLast().joined(separator: ", ")
            return "\(head), and \(parts.last!)"
        }
    }

    // MARK: - Tiles

    private var tilesArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                liveRecordingCard
                if !hasAnyCapture && !speechService.isRecording {
                    emptyState
                } else {
                    voiceCaptureCards
                    photoVideoGrid
                    typedNoteCards
                }
            }
            .padding(16)
        }
        .fullScreenCover(item: $selectedTileMedia) { item in
            MediaViewerView(item: item)
        }
    }

    private var hasAnyCapture: Bool {
        !session.sessionCaptures.isEmpty || !session.sessionTypedNotes.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.bubble")
                .font(.title)
                .foregroundStyle(Crucible.Color.ink4)
                .accessibilityHidden(true)
            Text("Tap a button below to capture")
                .font(.caption)
                .foregroundStyle(Crucible.Color.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Live recording card

    @ViewBuilder
    private var liveRecordingCard: some View {
        if speechService.isRecording {
            HStack(alignment: .top, spacing: 10) {
                // Pulsing red dot + animated waveform
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        ElapsedTimeLabel(
                            startedAt: recordingStartedAt,
                            font: .system(size: 13, weight: .semibold)
                        )
                        .foregroundStyle(Crucible.Color.ink2)
                    }
                    LiveWaveform()
                        .frame(width: 56, height: 24)
                }
                .frame(width: 60)

                VStack(alignment: .leading, spacing: 0) {
                    Text(speechService.transcribedText.isEmpty
                         ? "Listening…"
                         : speechService.transcribedText)
                        .font(.callout)
                        .foregroundStyle(speechService.transcribedText.isEmpty
                                         ? Crucible.Color.ink3 : Crucible.Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Crucible.Color.Media.audio.opacity(0.6), lineWidth: 1.5)
            )
        }
    }

    // MARK: Voice capture cards

    @ViewBuilder
    private var voiceCaptureCards: some View {
        ForEach(session.sessionCaptures.filter { $0.mediaType == .voice }, id: \.id) { capture in
            VoiceContributionCard(capture: capture)
        }
    }

    // MARK: Photo + video grid

    @ViewBuilder
    private var photoVideoGrid: some View {
        let visualCaptures = session.sessionCaptures.filter { $0.mediaType == .image || $0.mediaType == .video }
        if !visualCaptures.isEmpty {
            GeometryReader { geo in
                let cols = 3
                let spacing: CGFloat = 8
                let tileSize = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(tileSize), spacing: spacing), count: cols),
                    spacing: spacing
                ) {
                    ForEach(visualCaptures, id: \.id) { capture in
                        MediaTile(
                            localIdentifier: capture.osIdentifier,
                            mediaType: capture.mediaType,
                            onTap: {
                                selectedTileMedia = MediaDisplayItem(
                                    id: capture.id,
                                    localIdentifier: capture.osIdentifier,
                                    mediaType: capture.mediaType,
                                    thumbnailCacheFilename: nil,
                                    isAccessible: true
                                )
                            }
                        )
                        .frame(width: tileSize, height: tileSize)
                    }
                }
            }
            .frame(height: gridHeight(for: visualCaptures.count))
        }
    }

    private func gridHeight(for visualCount: Int) -> CGFloat {
        let rows = max(1, (visualCount + 2) / 3)
        return min(CGFloat(rows) * 116, 360)
    }

    // MARK: Typed notes

    @ViewBuilder
    private var typedNoteCards: some View {
        ForEach(Array(session.sessionTypedNotes.enumerated()), id: \.offset) { _, text in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Camera mounting overlay

    private var cameraMountingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(Crucible.Color.accent)
                Text("Opening camera…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening camera")
    }

    // MARK: - Action Box

    /// True when this session is appending to an existing memory (rather
    /// than creating a new one). The Attach-from-library button shows only
    /// in this mode — it's for surfacing an old photo against a memory the
    /// user is already inside.
    private var isAppendingToExisting: Bool {
        if case .existingMemory = session.anchor { return true }
        return false
    }

    private var actionBox: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(.voice, label: "Voice", icon: "mic.fill")
                actionButton(.photo, label: "Photo", icon: "camera.fill")
            }
            HStack(spacing: 10) {
                actionButton(.video, label: "Video", icon: "video.fill")
                actionButton(.text, label: "Note", icon: "text.alignleft")
            }
            if isAppendingToExisting {
                actionButton(.attach, label: "Attach", icon: "photo.on.rectangle")
            }
        }
        .padding(16)
        .background(Crucible.Color.sunk)
        .overlay(
            Rectangle()
                .fill(Crucible.Color.divider)
                .frame(height: 1),
            alignment: .top
        )
    }

    private enum ActionKind { case voice, photo, video, text, attach }

    private func actionButton(_ kind: ActionKind, label: String, icon: String) -> some View {
        let isActive = isActiveCapture(kind)
        let isVoiceRecording = (kind == .voice) && speechService.isRecording
        return Button {
            handleActionTap(kind)
        } label: {
            VStack(spacing: 6) {
                if isVoiceRecording {
                    // Inline recording state: red dot + elapsed time. Tap to stop.
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        ElapsedTimeLabel(
                            startedAt: recordingStartedAt,
                            font: .system(size: 14, weight: .semibold)
                        )
                    }
                    Text("Tap to stop")
                        .font(.caption2.weight(.semibold))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(isActive ? Crucible.Color.accent : Crucible.Color.card)
            .foregroundStyle(isActive ? .white : Crucible.Color.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isVoiceRecording ? "Stop recording" : label)
        .accessibilityAddTraits(.isButton)
    }

    private func isActiveCapture(_ kind: ActionKind) -> Bool {
        switch (kind, session.activeCapture) {
        case (.voice, .voice), (.video, .video), (.text, .text): return true
        default: return false
        }
    }

    // MARK: - Capture handlers

    /// Done while a recording is live needs to stop and synchronously persist
    /// the in-flight recording before exiting — otherwise the audio file gets
    /// finalized to disk but the session never tracks it as a capture, and
    /// the user is left with a no-op tap on Done.
    private func handleDoneTap() {
        finalizeActiveRecordingIfNeeded()
        session.exitDone()
    }

    /// X while recording: stop the recording and persist it so the session's
    /// discard path knows to delete the just-created audio file. (If we
    /// don't persist, the session has nothing to clean up and the audio
    /// file is leaked on disk.)
    private func handleDiscardTap() {
        finalizeActiveRecordingIfNeeded()
        session.requestExitDiscard()
    }

    /// Synchronously stops any active recording and runs the persistence
    /// path inline — avoids the .onChange race where the view tears down
    /// before the isRecording false-transition handler fires.
    /// `SpeechService.stopRecording()` is synchronous and populates
    /// `lastRecordingPath` before returning, so this is safe.
    private func finalizeActiveRecordingIfNeeded() {
        guard speechService.isRecording else { return }
        speechService.stopRecording()
        handleRecordingStopped()
    }

    private func handleActionTap(_ kind: ActionKind) {
        switch kind {
        case .voice:
            toggleVoiceRecording()
        case .photo:
            openCamera(mode: .photo)
        case .video:
            openCamera(mode: .video)
        case .text:
            openTextEditor()
        case .attach:
            if speechService.isRecording { speechService.stopRecording() }
            showLibraryPicker = true
        }
    }

    private func openTextEditor() {
        if speechService.isRecording { speechService.stopRecording() }
        session.setActiveCapture(.text)
        showTextEditor = true
    }

    private func openCamera(mode: CameraPickerView.CaptureMode) {
        if speechService.isRecording { speechService.stopRecording() }
        // Camera mount takes ~1-2s on first open (AVCaptureSession setup). Show
        // a mid-page spinner so the user knows something's happening between
        // the tap and the camera UI sliding up.
        isMountingCamera = true
        Task {
            let granted = await CameraService.shared.ensureCameraAccess()
            if granted {
                cameraMode = mode
                // Spinner clears when CameraPickerView's .onAppear fires below
                // (cover finished presenting).
            } else {
                isMountingCamera = false
            }
        }
    }

    private func handleCameraCapture(_ result: CameraPickerView.CaptureResult) {
        Task { @MainActor in
            do {
                switch result {
                case .photo(let image):
                    let id = try await CameraService.shared.savePhoto(image)
                    session.persistMediaCapture(localIdentifier: id, mediaType: .image)
                case .video(let url):
                    let id = try await CameraService.shared.saveVideo(at: url)
                    let duration = await videoDuration(at: url)
                    session.persistMediaCapture(localIdentifier: id, mediaType: .video, duration: duration)
                }
            } catch {
                ErrorState.shared.report(.mediaError(error.localizedDescription))
            }
        }
    }

    private func videoDuration(at url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        do {
            let cm = try await asset.load(.duration)
            return cm.seconds.isFinite ? cm.seconds : nil
        } catch {
            return nil
        }
    }

    private func toggleVoiceRecording() {
        if speechService.isRecording {
            // Stop — the .onChange handler picks up the transition and
            // persists what we've got.
            speechService.stopRecording()
        } else {
            startVoiceRecording()
        }
    }

    private func startVoiceRecording() {
        recordingStartedAt = Date()
        session.setActiveCapture(.voice)
        speechService.transcribedText = ""
        speechService.lastRecordingPath = nil
        speechService.startRecording()
    }

    private func handleRecordingStopped() {
        let duration: TimeInterval = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let transcript = speechService.transcribedText
        let path = speechService.lastRecordingPath

        session.persistVoiceCapture(
            audioPath: path,
            transcript: transcript,
            duration: duration,
            saveAudio: saveVoiceEntries
        )

        // Reset speech service buffers so the next recording starts clean.
        speechService.transcribedText = ""
        speechService.lastRecordingPath = nil
        recordingStartedAt = nil
        session.setActiveCapture(nil)
    }

}

// MARK: - Elapsed time label

/// Renders an mm:ss elapsed-time label that ticks once per second using
/// SwiftUI's TimelineView, independent of any other state changes. Without
/// this, the label only refreshed when SpeechService published transcript
/// updates — so it appeared frozen during silence.
private struct ElapsedTimeLabel: View {
    let startedAt: Date?
    let font: Font

    var body: some View {
        TimelineView(.periodic(from: startedAt ?? Date(), by: 1.0)) { context in
            Text(label(for: context.date))
                .font(font.monospacedDigit())
        }
    }

    private func label(for now: Date) -> String {
        guard let startedAt else { return "0:00" }
        let total = Int(now.timeIntervalSince(startedAt).rounded(.down))
        let m = max(0, total) / 60
        let s = max(0, total) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Voice contribution card

/// Wide card showing the transcript of a finished voice clip with a small
/// audio-tile playback control on the right. Tap the audio tile to play.
/// If there's no transcript, falls back to a duration label.
private struct VoiceContributionCard: View {
    let capture: ContributeSessionViewModel.SessionCapture

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                if let transcript = capture.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(.callout)
                        .foregroundStyle(Crucible.Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Voice clip · \(durationLabel)")
                        .font(.callout)
                        .foregroundStyle(Crucible.Color.ink3)
                        .italic()
                }
            }

            // Inline audio tile — small, tap to play. Reuses MediaTile's
            // voice rendering (waveform + tap-to-play via AudioPlayerService).
            MediaTile(
                localIdentifier: capture.osIdentifier,
                mediaType: .voice
            )
            .frame(width: 52, height: 52)
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }

    private var durationLabel: String {
        let total = Int((capture.duration ?? 0).rounded())
        let minutes = total / 60
        let seconds = total % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, seconds) : "\(seconds)s"
    }
}

// MARK: - Live waveform

/// Animated bar waveform shown while a voice capture is live. Purely
/// decorative — does not actually sample audio levels (cheap, predictable,
/// and avoids the complexity of an audio metering tap).
private struct LiveWaveform: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Crucible.Color.Media.audio)
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 6
        let amplitude: CGFloat = 14
        let phaseOffset = Double(index) * 0.6
        let wave = sin(phase * .pi * 2 + phaseOffset)
        return base + amplitude * CGFloat(abs(wave))
    }
}

// MARK: - Discard confirmation

/// Sheet shown when the user taps X with a non-empty session and hasn't muted
/// the prompt. Enumerates what's about to be discarded ("1 voice clip and 3
/// photos…") and offers a "Don't ask me this" toggle whose state is committed
/// only on Discard. Cancel closes the sheet without writing the toggle.
private struct DiscardConfirmationSheet: View {
    let summary: String
    let onDiscard: (Bool) -> Void
    let onKeep: () -> Void

    @State private var muteFuture: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Discard contribution?")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.ink)
                    Text("You've added \(summary) to this memory. Discarding can't be undone.")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Don't ask me this again", isOn: $muteFuture)
                        .font(.callout)
                        .tint(Crucible.Color.accent)
                    Text("You can re-enable this in Settings → Confirmations.")
                        .font(.caption2)
                        .foregroundStyle(Crucible.Color.ink4)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button(role: .destructive) {
                        onDiscard(muteFuture)
                    } label: {
                        Text("Discard")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Crucible.Color.danger)

                    Button {
                        onKeep()
                    } label: {
                        Text("Keep editing")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(Crucible.Color.ink2)
                }
            }
            .padding(20)
            .background(Crucible.Color.paper)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Text Editor

/// Full-screen text editor presented from Contribute Mode. Done returns the
/// (trimmed, non-empty) text to the caller as a session text tile; Cancel
/// discards the draft. Symmetric with how camera takes the screen during
/// photo/video capture.
private struct ContributeTextEditor: View {
    @Binding var draft: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .focused($isFocused)
                .padding(16)
                .background(Crucible.Color.paper)
                .scrollContentBackground(.hidden)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { onCancel() }
                            .foregroundStyle(Crucible.Color.ink2)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                onCancel()
                            } else {
                                onCommit(trimmed)
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.accent)
                    }
                }
                .navigationTitle("Add a note")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { isFocused = true }
        }
    }
}

#Preview("Empty") {
    ContributeActionBox(
        session: previewSession(captures: [], typedNotes: []),
        speechService: SpeechService()
    )
}

#Preview("Mixed captures") {
    ContributeActionBox(
        session: previewSession(
            captures: [
                .init(id: UUID(), mediaType: .voice, osIdentifier: "voice1", duration: 8.4, transcript: "The tomatoes in bed 3 are coming in earlier than last year. Two cherry plants showed first flowers yesterday."),
                .init(id: UUID(), mediaType: .image, osIdentifier: "img1", duration: nil, transcript: nil),
                .init(id: UUID(), mediaType: .image, osIdentifier: "img2", duration: nil, transcript: nil),
                .init(id: UUID(), mediaType: .video, osIdentifier: "vid1", duration: 21.2, transcript: nil)
            ],
            typedNotes: ["Remember to mulch bed 5 before the weekend."]
        ),
        speechService: SpeechService()
    )
}

@MainActor
private func previewSession(
    captures: [ContributeSessionViewModel.SessionCapture],
    typedNotes: [String]
) -> ContributeSessionViewModel {
    let storage = StorageService(inMemory: true)
    let lifecycle = EntryLifecycleService(storage: storage, processingEngine: nil)
    let session = ContributeSessionViewModel(
        lifecycle: lifecycle,
        userDefaults: UserDefaults(suiteName: "ContributeActionBox.preview")!
    )
    session.enter(anchor: .newMemory)
    for c in captures {
        session.trackCapture(id: c.id, mediaType: c.mediaType, osIdentifier: c.osIdentifier, duration: c.duration, transcript: c.transcript)
    }
    for n in typedNotes {
        session.trackTypedNote(n)
    }
    return session
}

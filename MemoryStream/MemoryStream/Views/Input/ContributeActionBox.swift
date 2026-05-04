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
    @State private var showTextEditor = false
    @State private var textDraft: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tilesArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                actionBox
            }
            .background(Crucible.Color.paper)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        session.requestExitDiscard()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink2)
                    }
                    .accessibilityLabel("Discard contribution")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        session.exitDone()
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
        }
        .fullScreenCover(isPresented: $showTextEditor) {
            ContributeTextEditor(
                draft: $textDraft,
                onCommit: { text in
                    session.trackTextSegment(text)
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
    }

    /// Plain-language enumeration of what's about to be discarded — used in
    /// the X confirmation. Pluralization handled per type; voice clips and
    /// transcribed/typed text segments are listed separately because the
    /// user thinks of them as different things.
    private var discardSummary: String {
        let voice = session.sessionCaptures.filter { $0.mediaType == .voice }.count
        let photo = session.sessionCaptures.filter { $0.mediaType == .image }.count
        let video = session.sessionCaptures.filter { $0.mediaType == .video }.count
        let text = session.sessionTextSegments.count

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
                if session.sessionCaptures.isEmpty && session.sessionTextSegments.isEmpty {
                    emptyState
                } else {
                    captureTiles
                    textTiles
                }
            }
            .padding(16)
        }
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

    private var captureTiles: some View {
        // Three-up grid using GeometryReader so MediaTile (square aspect) fits.
        GeometryReader { geo in
            let cols = 3
            let spacing: CGFloat = 8
            let tileSize = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(tileSize), spacing: spacing), count: cols),
                spacing: spacing
            ) {
                ForEach(session.sessionCaptures, id: \.id) { capture in
                    MediaTile(
                        localIdentifier: capture.id.uuidString, // placeholder until capture wiring lands
                        mediaType: capture.mediaType
                    )
                    .frame(width: tileSize, height: tileSize)
                }
            }
        }
        .frame(height: tileGridHeight)
    }

    private var tileGridHeight: CGFloat {
        // Three columns, rows of tiles ~110pt tall. Cap so the grid doesn't
        // dominate the screen on a long session.
        let rows = max(1, (session.sessionCaptures.count + 2) / 3)
        return min(CGFloat(rows) * 116, 360)
    }

    private var textTiles: some View {
        ForEach(Array(session.sessionTextSegments.enumerated()), id: \.offset) { _, text in
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

    // MARK: - Action Box

    private var actionBox: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(.voice, label: "Voice", icon: "mic.fill")
                actionButton(.photo, label: "Photo", icon: "camera.fill")
            }
            HStack(spacing: 10) {
                actionButton(.video, label: "Video", icon: "video.fill")
                actionButton(.text, label: "Text", icon: "text.alignleft")
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

    private enum ActionKind { case voice, photo, video, text }

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
                        Text(elapsedRecordingLabel)
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
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
        }
    }

    private func openTextEditor() {
        if speechService.isRecording { speechService.stopRecording() }
        session.setActiveCapture(.text)
        showTextEditor = true
    }

    private func openCamera(mode: CameraPickerView.CaptureMode) {
        if speechService.isRecording { speechService.stopRecording() }
        Task {
            if await CameraService.shared.ensureCameraAccess() {
                cameraMode = mode
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

    private var elapsedRecordingLabel: String {
        let total = Int((recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0).rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
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
                .navigationTitle("Add text")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { isFocused = true }
        }
    }
}

#Preview("Empty") {
    ContributeActionBox(
        session: previewSession(captures: [], textSegments: []),
        speechService: SpeechService()
    )
}

#Preview("Mixed captures") {
    ContributeActionBox(
        session: previewSession(
            captures: [
                .init(id: UUID(), mediaType: .voice, duration: 8.4),
                .init(id: UUID(), mediaType: .image, duration: nil),
                .init(id: UUID(), mediaType: .image, duration: nil),
                .init(id: UUID(), mediaType: .video, duration: 21.2)
            ],
            textSegments: ["The tomatoes in bed 3 are coming in earlier than last year."]
        ),
        speechService: SpeechService()
    )
}

@MainActor
private func previewSession(
    captures: [ContributeSessionViewModel.SessionCapture],
    textSegments: [String]
) -> ContributeSessionViewModel {
    let storage = StorageService(inMemory: true)
    let lifecycle = EntryLifecycleService(storage: storage, processingEngine: nil)
    let session = ContributeSessionViewModel(
        lifecycle: lifecycle,
        userDefaults: UserDefaults(suiteName: "ContributeActionBox.preview")!
    )
    session.enter(anchor: .newMemory)
    for capture in captures {
        session.trackCapture(id: capture.id, mediaType: capture.mediaType, duration: capture.duration)
    }
    for text in textSegments {
        session.trackTextSegment(text)
    }
    return session
}

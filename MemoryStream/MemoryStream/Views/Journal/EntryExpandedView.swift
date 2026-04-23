import SwiftUI

enum EntryViewMode {
    case reading, editing
}

private enum ExpandedSheet: Identifiable {
    case camera(CameraPickerView.CaptureMode)
    case newTopic

    var id: String {
        switch self {
        case .camera: return "camera"
        case .newTopic: return "newTopic"
        }
    }
}

struct EntryExpandedView: View {
    let entry: EntryDisplayModel
    var backLabel: String = "Today"
    let allTopics: [String]
    let cameraService: CameraService
    @ObservedObject var speechService: SpeechService
    let onSave: (UUID, String, Set<UUID>, Set<UUID>, Set<String>, Set<String>, Bool) -> Void
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    /// One-shot commit of a batch of appends. Fires at most once per session.
    /// additionalContent: typed text + concatenated transcripts.
    /// mediaCaptures: staged photo/video/voice assets.
    var onCommit: ((UUID, String, [(localIdentifier: String, mediaType: MediaReference.MediaType)]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var mode: EntryViewMode = .reading

    // Editing state
    @State private var editedTitle = ""
    @State private var editedText = ""
    @State private var removedTagIds: Set<UUID> = []
    @State private var removedMediaIds: Set<UUID> = []
    @State private var addedTopics: Set<String> = []
    @State private var removedTopics: Set<String> = []
    @State private var discardAudio = false
    @State private var isCleaningUp = false
    @State private var mentionsExpanded = false
    @State private var newTopicName = ""
    @State private var newTopicColorKey = Crucible.Color.topicPalette[0].key

    // Inline staging state (reading mode). Commit flushes these in one batch.
    @State private var activeSheet: ExpandedSheet?
    @State private var showTextAppender = false
    @State private var pendingTypedText = ""
    @State private var pendingTranscripts: [String] = []
    @State private var pendingMedia: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
    @State private var pendingAudioAppend = false
    @State private var showDiscardConfirm = false
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true

    private var currentTopics: [String] {
        entry.topicNames.filter { !removedTopics.contains($0) } + addedTopics.sorted()
    }

    private var availableToAdd: [String] {
        allTopics.filter { topic in
            !entry.topicNames.contains(topic) && !addedTopics.contains(topic)
            || removedTopics.contains(topic)
        }
    }

    private var visibleTags: [TagDisplayModel] {
        entry.tags.filter { !removedTagIds.contains($0.id) }
    }

    private var hasChanges: Bool {
        editedTitle != entry.displayTitle
            || editedText != entry.content
            || !removedTagIds.isEmpty
            || !removedMediaIds.isEmpty
            || !addedTopics.isEmpty
            || !removedTopics.isEmpty
            || discardAudio
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Topic + status row
                HStack(spacing: 8) {
                    ForEach(currentTopics, id: \.self) { topic in
                        let hue = Crucible.Color.topicHue(for: topic)
                        HStack(spacing: 4) {
                            Circle().fill(hue.fg).frame(width: 7, height: 7)
                            Text(topic)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(hue.fg)
                            if mode == .editing {
                                Button {
                                    if addedTopics.contains(topic) {
                                        addedTopics.remove(topic)
                                    } else {
                                        removedTopics.insert(topic)
                                    }
                                } label: {
                                    Text("×")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(hue.fg.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(hue.bg)
                        .clipShape(Capsule())
                    }

                    if mode == .editing {
                        Menu {
                            ForEach(availableToAdd, id: \.self) { topic in
                                Button(topic) {
                                    if removedTopics.contains(topic) {
                                        removedTopics.remove(topic)
                                    } else {
                                        addedTopics.insert(topic)
                                    }
                                }
                            }
                            if !availableToAdd.isEmpty { Divider() }
                            Button {
                                newTopicName = ""
                                newTopicColorKey = Crucible.Color.topicPalette[0].key
                                activeSheet = .newTopic
                            } label: {
                                Label("New Topic…", systemImage: "plus.circle")
                            }
                        } label: {
                            Text("+ Add")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Crucible.Color.ink2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Crucible.Color.sunk)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Crucible.Color.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                    }

                    Spacer()

                    if let status = entry.displayStatus {
                        StatusBadge(text: status.text, style: status.style)
                    }
                }

                // Title
                if mode == .editing {
                    TextField("Title", text: $editedTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(10)
                        .background(Crucible.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1.5))
                } else {
                    Text(entry.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink)
                        .onTapGesture { enterEditing() }
                }

                // Timestamp
                Text(fullTimestamp)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)

                // Body
                if mode == .editing {
                    TextEditor(text: $editedText)
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                        .frame(minHeight: 120)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Crucible.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))

                    // Clean up text (editing only)
                    Button {
                        cleanUpText()
                    } label: {
                        HStack(spacing: 4) {
                            if isCleaningUp {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "sparkles").font(.system(size: 11))
                            }
                            Text("Clean up text")
                        }
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.AI.base)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCleaningUp)
                } else {
                    Text(entry.content)
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(4)
                        .onTapGesture { enterEditing() }
                }

                // Inference card (if pending)
                if let inference = entry.inferenceSummary, entry.feedbackState == nil {
                    InferenceCard(
                        summary: inference,
                        feedbackState: entry.feedbackState,
                        onFeedback: { state in onFeedback?(entry.id, state) }
                    )
                }

                // Media rows
                if entry.hasAudio || !entry.mediaItems.isEmpty {
                    VStack(spacing: 8) {
                        // Audio row
                        if let audioFile = entry.audioFilePath, !discardAudio {
                            AttachmentRow(
                                color: Crucible.Color.Media.audio,
                                icon: "mic",
                                label: "Audio"
                            ) {
                                VoicePlaybackRow(filename: audioFile)
                            } actions: {
                                if mode == .editing {
                                    Menu {
                                        Button(role: .destructive) {
                                            discardAudio = true
                                        } label: {
                                            Label("Remove audio", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.caption)
                                            .foregroundStyle(Crucible.Color.ink3)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                            }
                        }

                        // Photo/video/voice rows
                        ForEach(entry.mediaItems) { item in
                            if !removedMediaIds.contains(item.id) {
                                AttachmentRow(
                                    color: attachmentColor(for: item.mediaType),
                                    icon: attachmentIcon(for: item.mediaType),
                                    label: attachmentLabel(for: item.mediaType)
                                ) {
                                    if item.mediaType == .voice {
                                        VoicePlaybackRow(filename: item.localIdentifier)
                                    } else {
                                        MediaThumbnailView(item: item, size: 52) {}
                                    }
                                } actions: {
                                    if mode == .editing {
                                        Menu {
                                            Button(role: .destructive) {
                                                removedMediaIds.insert(item.id)
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.caption)
                                                .foregroundStyle(Crucible.Color.ink3)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Mentions section (entity tags)
                if !entry.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation { mentionsExpanded.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text("MENTIONS")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .tracking(0.5)
                                    .foregroundStyle(Crucible.Color.ink3)
                                Image(systemName: mentionsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Crucible.Color.ink3)
                                Spacer()
                                Text("\(visibleTags.count)")
                                    .font(.caption)
                                    .foregroundStyle(Crucible.Color.ink3)
                            }
                        }
                        .buttonStyle(.plain)

                        if mentionsExpanded {
                            FlowLayout(spacing: 6) {
                                ForEach(visibleTags) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag.value)
                                        if mode == .editing {
                                            Button {
                                                removedTagIds.insert(tag.id)
                                            } label: {
                                                Text("×")
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(Crucible.Color.ink3)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Crucible.Color.ink2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Crucible.Color.sunk)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Crucible.Color.hairline).frame(height: 0.5)
                    }
                }

                // Inline staging (reading mode only)
                if mode == .reading {
                    if hasPending {
                        PendingStagingSection(
                            typedText: pendingTypedText,
                            transcripts: pendingTranscripts,
                            media: pendingMedia,
                            isRecording: speechService.isRecording,
                            onRemoveMedia: { index in
                                guard pendingMedia.indices.contains(index) else { return }
                                pendingMedia.remove(at: index)
                            },
                            onRemoveTranscript: { index in
                                guard pendingTranscripts.indices.contains(index) else { return }
                                pendingTranscripts.remove(at: index)
                            },
                            onClearTypedText: { pendingTypedText = "" }
                        )
                    }

                    InlineAddToolbar(
                        isRecording: speechService.isRecording,
                        onPhotoTap: { activeSheet = .camera(.photo) },
                        onVideoTap: { activeSheet = .camera(.video) },
                        onAudioTap: toggleAudioRecording,
                        onTextTap: { showTextAppender = true }
                    )

                    if showTextAppender {
                        InlineTextAppender(
                            text: $pendingTypedText,
                            onCommit: { showTextAppender = false },
                            onCancel: {
                                pendingTypedText = ""
                                showTextAppender = false
                            }
                        )
                    }

                    if hasPending {
                        CommitFooter(
                            pendingItemCount: pendingItemCount,
                            onCommit: commitPending
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Crucible.Color.paper)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if mode == .editing {
                    Button("Cancel") { cancelEditing() }
                        .foregroundStyle(Crucible.Color.accent)
                } else {
                    Button {
                        if hasPending {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(backLabel)
                        }
                        .foregroundStyle(Crucible.Color.accent)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                if mode == .editing {
                    Text("Editing")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if mode == .editing {
                    Button("Done") { commitEdits() }
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.accent)
                        .disabled(!hasChanges)
                }
            }
        }
        .onAppear {
            editedTitle = entry.displayTitle
            editedText = entry.content
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .camera(let mode):
                CameraPickerView(
                    captureMode: mode,
                    onCapture: { result in
                        activeSheet = nil
                        Task { @MainActor in
                            do {
                                switch result {
                                case .photo(let image):
                                    let id = try await cameraService.savePhoto(image)
                                    pendingMedia.append((localIdentifier: id, mediaType: .image))
                                case .video(let url):
                                    let id = try await cameraService.saveVideo(at: url)
                                    pendingMedia.append((localIdentifier: id, mediaType: .video))
                                }
                            } catch {
                                print("Inline capture failed: \(error)")
                            }
                        }
                    },
                    onDismiss: { activeSheet = nil }
                )
            case .newTopic:
                NewTopicSheet(
                    name: $newTopicName,
                    colorKey: $newTopicColorKey,
                    onAdd: { name, colorKey in
                        addedTopics.insert(name)
                        TopicPaletteStore.shared.set(key: colorKey, for: name)
                    }
                )
            }
        }
        .onChange(of: speechService.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard pendingAudioAppend else { return }
            pendingAudioAppend = false

            let transcript = speechService.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = speechService.lastRecordingPath {
                if saveVoiceEntries {
                    pendingMedia.append((localIdentifier: path, mediaType: .voice))
                    if !transcript.isEmpty { pendingTranscripts.append(transcript) }
                } else {
                    // Primary audio discarded by user preference; derived transcript still retained.
                    AudioPlayerService.deleteAudio(filename: path)
                    if !transcript.isEmpty { pendingTranscripts.append(transcript) }
                }
            } else if !transcript.isEmpty {
                pendingTranscripts.append(transcript)
            }
            speechService.transcribedText = ""
            speechService.lastRecordingPath = nil
        }
        .confirmationDialog(
            "Discard pending additions?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                discardPending()
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: - Staging

    private var hasPending: Bool {
        !pendingMedia.isEmpty
            || !pendingTranscripts.isEmpty
            || !pendingTypedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pendingItemCount: Int {
        var count = pendingMedia.count
        count += pendingTranscripts.count
        if !pendingTypedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        return count
    }

    private func commitPending() {
        let typed = pendingTypedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let allText = ([typed] + pendingTranscripts)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        onCommit?(entry.id, allText, pendingMedia)
        pendingTypedText = ""
        pendingTranscripts = []
        pendingMedia = []
    }

    private func discardPending() {
        // Delete saved assets we staged but will never commit.
        for item in pendingMedia {
            if item.mediaType == .voice {
                AudioPlayerService.deleteAudio(filename: item.localIdentifier)
            }
            // photo/video assets live in the PHPhotoLibrary — leave them alone;
            // the user may want them outside the app regardless.
        }
        pendingTypedText = ""
        pendingTranscripts = []
        pendingMedia = []
    }

    private func toggleAudioRecording() {
        if speechService.isRecording {
            speechService.stopRecording()
        } else {
            pendingAudioAppend = true
            speechService.transcribedText = ""
            speechService.startRecording()
        }
    }

    // MARK: - Attachment styling

    private func attachmentColor(for type: MediaReference.MediaType) -> Color {
        switch type {
        case .image: return Crucible.Color.Media.photo
        case .video: return Crucible.Color.Media.video
        case .voice: return Crucible.Color.Media.audio
        }
    }

    private func attachmentIcon(for type: MediaReference.MediaType) -> String {
        switch type {
        case .image: return "camera"
        case .video: return "video"
        case .voice: return "mic"
        }
    }

    private func attachmentLabel(for type: MediaReference.MediaType) -> String {
        switch type {
        case .image: return "Photo"
        case .video: return "Video"
        case .voice: return "Audio"
        }
    }

    // MARK: - Mode transitions

    private func enterEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .editing
        }
    }

    private func cancelEditing() {
        editedTitle = entry.displayTitle
        editedText = entry.content
        removedTagIds = []
        removedMediaIds = []
        addedTopics = []
        removedTopics = []
        discardAudio = false
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .reading
        }
    }

    private func commitEdits() {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(entry.id, trimmed, removedTagIds, removedMediaIds, addedTopics, removedTopics, discardAudio)
        dismiss()
    }

    private func cleanUpText() {
        isCleaningUp = true
        Task {
            do {
                let cleaned = try await ClaudeAPIService.shared.cleanupTranscription(editedText)
                editedText = cleaned
            } catch {
                print("Cleanup failed: \(error)")
            }
            isCleaningUp = false
        }
    }

    private var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d · h:mm a"
        return formatter.string(from: entry.createdAt) + " · " + entry.inputType.displayLabel
    }
}

// MARK: - Inline Add Toolbar

private struct InlineAddToolbar: View {
    let isRecording: Bool
    let onPhotoTap: () -> Void
    let onVideoTap: () -> Void
    let onAudioTap: () -> Void
    let onTextTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ToolbarIcon(kind: .photo, icon: "camera", label: "Photo", isActive: false, action: onPhotoTap)
            ToolbarIcon(kind: .video, icon: "video", label: "Video", isActive: false, action: onVideoTap)
            ToolbarIcon(
                kind: .audio,
                icon: isRecording ? "stop.fill" : "mic",
                label: isRecording ? "Stop" : "Audio",
                isActive: isRecording,
                action: onAudioTap
            )
            ToolbarIcon(kind: .text, icon: "pencil", label: "Text", isActive: false, action: onTextTap)
        }
        .padding(4)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }
}

private enum InlineToolbarKind {
    case photo, video, audio, text

    var color: Color {
        switch self {
        case .photo: return Crucible.Color.Media.photo
        case .video: return Crucible.Color.Media.video
        case .audio: return Crucible.Color.Media.audio
        case .text: return Crucible.Color.Media.text
        }
    }
}

private struct ToolbarIcon: View {
    let kind: InlineToolbarKind
    let icon: String
    let label: String
    let isActive: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? .white : (disabled ? Crucible.Color.ink4 : kind.color))
                    .frame(width: 28, height: 28)
                    .background(isActive ? kind.color : Crucible.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.clear : Crucible.Color.hairline, lineWidth: 1)
                    )

                Text(label)
                    .font(.caption2)
                    .fontWeight(isActive ? .bold : .medium)
                    .foregroundStyle(isActive ? kind.color : (disabled ? Crucible.Color.ink4 : Crucible.Color.ink2))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(isActive ? kind.color.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Inline Text Appender

private struct InlineTextAppender: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(Crucible.Color.ink)
                .frame(minHeight: 80)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Crucible.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1))
                .focused($focused)

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.footnote)
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Button("Done", action: onCommit)
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 4)
        .onAppear { focused = true }
    }
}

// MARK: - Pending Staging Section

private struct PendingStagingSection: View {
    let typedText: String
    let transcripts: [String]
    let media: [(localIdentifier: String, mediaType: MediaReference.MediaType)]
    let isRecording: Bool
    let onRemoveMedia: (Int) -> Void
    let onRemoveTranscript: (Int) -> Void
    let onClearTypedText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PENDING")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(Crucible.Color.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRecording {
                AttachmentRow(
                    color: Crucible.Color.Media.audio,
                    icon: "mic",
                    label: "Recording",
                    emphasized: true
                ) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Crucible.Color.Media.audio)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Crucible.Color.Media.audio)
                    }
                }
            }

            ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                PendingMediaRow(item: item) { onRemoveMedia(index) }
            }

            ForEach(Array(transcripts.enumerated()), id: \.offset) { index, transcript in
                AttachmentRow(
                    color: Crucible.Color.Media.text,
                    icon: "pencil",
                    label: "Transcript"
                ) {
                    Text(transcript)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(3)
                } actions: {
                    Button {
                        onRemoveTranscript(index)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Crucible.Color.ink3)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }

            let trimmedTyped = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTyped.isEmpty {
                AttachmentRow(
                    color: Crucible.Color.Media.text,
                    icon: "pencil",
                    label: "Note"
                ) {
                    Text(trimmedTyped)
                        .font(.footnote)
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(3)
                } actions: {
                    Button(action: onClearTypedText) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Crucible.Color.ink3)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct PendingMediaRow: View {
    let item: (localIdentifier: String, mediaType: MediaReference.MediaType)
    let onRemove: () -> Void

    var body: some View {
        let color: Color = {
            switch item.mediaType {
            case .image: return Crucible.Color.Media.photo
            case .video: return Crucible.Color.Media.video
            case .voice: return Crucible.Color.Media.audio
            }
        }()
        let icon: String = {
            switch item.mediaType {
            case .image: return "camera"
            case .video: return "video"
            case .voice: return "mic"
            }
        }()
        let label: String = {
            switch item.mediaType {
            case .image: return "Photo"
            case .video: return "Video"
            case .voice: return "Audio"
            }
        }()

        AttachmentRow(color: color, icon: icon, label: label) {
            if item.mediaType == .voice {
                VoicePlaybackRow(filename: item.localIdentifier)
            } else {
                PendingMediaThumbnail(localIdentifier: item.localIdentifier, isVideo: item.mediaType == .video)
            }
        } actions: {
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PendingMediaThumbnail: View {
    let localIdentifier: String
    let isVideo: Bool
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Crucible.Color.sunk
            }
        }
        .frame(width: 52, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .overlay {
            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
        .task {
            if let cached = await ThumbnailService.shared.cacheThumbnail(for: localIdentifier) {
                thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
            }
        }
    }
}

// MARK: - Commit Footer

private struct CommitFooter: View {
    let pendingItemCount: Int
    let onCommit: () -> Void

    var body: some View {
        Button(action: onCommit) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Attach \(pendingItemCount) item\(pendingItemCount == 1 ? "" : "s")")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Crucible.Color.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

import SwiftUI

enum EntryViewMode {
    case reading, editing
}

private enum ExpandedSheet: Identifiable {
    case newTopic

    var id: String {
        switch self {
        case .newTopic: return "newTopic"
        }
    }
}

/// Identifies the voice tile a user tapped, so the AudioPlayerSheet can be
/// presented via SwiftUI's `sheet(item:)` API. `filename` is the audio file
/// path (matching the MediaReference.osIdentifier), `recordedAt` is shown
/// as a header timestamp, and `transcript` is the per-clip transcript
/// (nil for legacy voice refs from before the schema gained the field —
/// the sheet falls back to entry.content in that case).
struct AudioPlayerTarget: Identifiable {
    let filename: String
    let recordedAt: Date?
    let transcript: String?
    var id: String { filename }
}

struct EntryExpandedView: View {
    let entry: EntryDisplayModel
    var backLabel: String = "Today"
    let allTopics: [String]
    let cameraService: CameraService
    @ObservedObject var speechService: SpeechService
    let onSave: (UUID, String, Set<UUID>, Set<UUID>, Set<String>, Set<String>, Bool) -> Void
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var onAdjust: ((UUID, String) -> Void)? = nil
    /// One-shot commit of a batch of appends. Fires at most once per session.
    /// additionalContent: typed text + concatenated transcripts.
    /// mediaCaptures: staged photo/video/voice assets.
    var onCommit: ((UUID, String, [(localIdentifier: String, mediaType: MediaReference.MediaType)]) -> Void)? = nil
    var onRecycle: ((UUID) -> Void)? = nil
    var onAddToProject: ((UUID, UUID) -> Void)? = nil  // entryId, projectId
    var availableProjects: [ProjectDisplayModel] = []

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
    @State private var selectedMedia: MediaDisplayItem? = nil
    @State private var audioPlayerForFile: AudioPlayerTarget? = nil
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var newTopicName = ""
    @State private var newTopicColorKey = Crucible.Color.topicPalette[0].key

    /// Append-mode Contribute session. Tapping the Contribute button on this
    /// view enters this session anchored at the current entry; captures
    /// persist directly to the entry as they're taken (no inline staging).
    @StateObject private var contributeSession = ContributeSessionViewModel(lifecycle: EntryLifecycleService())
    @State private var activeSheet: ExpandedSheet?
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
        ZStack(alignment: .bottomTrailing) {
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

                    if let status = entry.displayStatus, entry.inferenceSummary == nil {
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

                // Tappable location chip — variant E (Himem · Location.html).
                // Pin glyph in accent, place name in ink, chevron implies tap.
                // Tap opens Apple Maps centered on the entry's coordinates.
                if let name = entry.locationName, let lat = entry.latitude, let lon = entry.longitude {
                    Button {
                        openInMaps(name: name, latitude: lat, longitude: lon)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "mappin")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Crucible.Color.accent)
                            // Detail shows the full string — let it wrap to
                            // a second line rather than truncate.
                            Text(name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Crucible.Color.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Crucible.Color.ink3)
                                .padding(.leading, 2)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 14)
                        .padding(.vertical, 8)
                        .background(Crucible.Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Crucible.Color.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }

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
                        onFeedback: { state in onFeedback?(entry.id, state) },
                        onAdjust: { correction in onAdjust?(entry.id, correction) }
                    )
                }

                // Media tile grid
                if entry.hasAudio || !entry.mediaItems.isEmpty || mode == .editing {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                    LazyVGrid(columns: columns, spacing: 8) {
                        // Audio tile (legacy single-audio entries — older
                        // memories stored their voice clip on
                        // entry.audioFilePath rather than a MediaReference).
                        if let audioFile = entry.audioFilePath, !discardAudio {
                            MediaTile(
                                localIdentifier: audioFile,
                                mediaType: .voice,
                                createdAt: entry.createdAt,
                                onRemove: { discardAudio = true; if mode != .editing { enterEditing() } },
                                onTap: { audioPlayerForFile = AudioPlayerTarget(filename: audioFile, recordedAt: entry.createdAt, transcript: nil) }
                            )
                        }

                        // Photo/video/voice tiles
                        ForEach(entry.mediaItems) { item in
                            if !removedMediaIds.contains(item.id) {
                                MediaTile(
                                    localIdentifier: item.localIdentifier,
                                    mediaType: item.mediaType,
                                    createdAt: item.mediaType == .voice ? entry.createdAt : nil,
                                    onRemove: { removedMediaIds.insert(item.id); if mode != .editing { enterEditing() } },
                                    onTap: {
                                        if item.mediaType == .voice {
                                            audioPlayerForFile = AudioPlayerTarget(
                                                filename: item.localIdentifier,
                                                recordedAt: entry.createdAt,
                                                transcript: item.transcript
                                            )
                                        } else {
                                            selectedMedia = item
                                        }
                                    }
                                )
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

            }
            .padding(16)
            // Bottom inset so the floating Contribute button doesn't cover content.
            .padding(.bottom, 80)
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
                        dismiss()
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
                    Button("Done") {
                        if hasChanges {
                            commitEdits()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { mode = .reading }
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.accent)
                } else {
                    HStack(spacing: 16) {
                        Button { showDeleteConfirmation = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                        .accessibilityLabel("Delete memory")
                        if !availableProjects.isEmpty {
                            Menu {
                                ForEach(availableProjects) { project in
                                    Button {
                                        onAddToProject?(entry.id, project.id)
                                    } label: {
                                        Label(project.name, systemImage: "folder")
                                    }
                                }
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Crucible.Color.ink2)
                            }
                            .accessibilityLabel("Add to project")
                        }
                        Button { showShareSheet = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                        .accessibilityLabel("Share memory")
                        Button { enterEditing() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15))
                                .foregroundStyle(Crucible.Color.ink2)
                        }
                        .accessibilityLabel("Edit memory")
                    }
                }
            }
        }
        .onAppear {
            editedTitle = entry.displayTitle
            editedText = entry.content
        }
        .sheet(item: $audioPlayerForFile) { target in
            // Prefer the per-clip transcript captured at recording time;
            // fall back to entry.content (the joined-transcript blob) for
            // legacy voice refs from before the schema gained the field.
            AudioPlayerSheet(
                filename: target.filename,
                recordedAt: target.recordedAt,
                transcriptFallback: target.transcript ?? entry.content
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaViewerView(item: item)
        }
        .sheet(isPresented: $showShareSheet) {
            let composed = "\(entry.displayTitle)\n\n\(entry.content)"
            ShareSheet(items: [composed])
        }
        .alert("Move to Recently Deleted?", isPresented: $showDeleteConfirmation) {
            Button("Move to Recently Deleted", role: .destructive) {
                onRecycle?(entry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This memory will be moved to the Recently Deleted. You can restore it from Settings.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
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

            // Contribute button — append to this memory.
            // Same gesture mapping as the home FAB (tap = Action Box,
            // long-press = quick voice) for consistency across the app.
            // Hidden while a session is active (entry/exit via Action Box).
            if !contributeSession.isPresented && mode == .reading {
                ContributeButton(
                    isOpen: false,
                    idleIcon: "plus",
                    accessibilityLabel: "Add to memory",
                    accessibilityHint: "Tap to choose a capture type. Long-press for quick voice capture."
                ) {
                    contributeSession.enter(anchor: .existingMemory(entry.id), autoStartVoice: false)
                } onLongPress: {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    contributeSession.enter(anchor: .existingMemory(entry.id), autoStartVoice: true)
                }
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $contributeSession.isPresented) {
            ContributeActionBox(
                session: contributeSession,
                speechService: speechService
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(true)
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
                ErrorState.shared.report(.processingFailed(error.localizedDescription))
            }
            isCleaningUp = false
        }
    }

    private var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d · h:mm a"
        return formatter.string(from: entry.createdAt)
    }

    private func openInMaps(name: String, latitude: Double, longitude: Double) {
        let coords = "\(latitude),\(longitude)"
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?q=\(encoded)&ll=\(coords)") {
            UIApplication.shared.open(url)
        }
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
            ToolbarIcon(
                kind: .audio,
                icon: isRecording ? "stop.fill" : "mic",
                label: isRecording ? "Stop" : "Audio",
                isActive: isRecording,
                action: onAudioTap
            )
            ToolbarIcon(kind: .text, icon: "pencil", label: "Text", isActive: false, action: onTextTap)
            ToolbarIcon(kind: .photo, icon: "camera", label: "Photo", isActive: false, action: onPhotoTap)
            ToolbarIcon(kind: .video, icon: "video", label: "Video", isActive: false, action: onVideoTap)
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
                HStack(spacing: 6) {
                    Circle()
                        .fill(Crucible.Color.Media.audio)
                        .frame(width: 8, height: 8)
                    Text("Recording...")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.Media.audio)
                }
            }

            // Transcripts (body text, not tiles)
            ForEach(Array(transcripts.enumerated()), id: \.offset) { index, transcript in
                HStack(alignment: .top) {
                    Text(transcript)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(3)
                    Spacer()
                    Button { onRemoveTranscript(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                    }
                    .buttonStyle(.plain)
                }
            }

            let trimmedTyped = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTyped.isEmpty {
                HStack(alignment: .top) {
                    Text(trimmedTyped)
                        .font(.footnote)
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(3)
                    Spacer()
                    Button(action: onClearTypedText) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Media tile grid
            if !media.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                        MediaTile(
                            localIdentifier: item.localIdentifier,
                            mediaType: item.mediaType,
                            onRemove: { onRemoveMedia(index) }
                        )
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

// PendingMediaRow and PendingMediaThumbnail retired — replaced by MediaTile grid

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

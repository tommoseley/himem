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
/// presented via SwiftUI's `sheet(item:)` API. `mediaId` is the
/// MediaReference id (so the sheet's transcript edit can save back to the
/// right ref); `filename` is the audio file path; `recordedAt` is shown as
/// a header timestamp; `transcript` is the per-clip transcript (nil for
/// legacy voice refs from before the schema gained the field, in which
/// case the sheet falls back to entry.content).
struct AudioPlayerTarget: Identifiable {
    let mediaId: UUID?
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
    /// (entryId, newContent, newTitle, removedTagIds, removedMediaIds, addedTopics, removedTopics).
    /// `newTitle == nil` means "leave the title alone"; an empty string clears it
    /// so `displayTitle` falls back to the AI/derived ladder.
    let onSave: (UUID, String, String?, Set<UUID>, Set<UUID>, Set<String>, Set<String>) -> Void
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
    @State private var removedTagIds: Set<UUID> = []
    @State private var removedMediaIds: Set<UUID> = []
    @State private var addedTopics: Set<String> = []
    @State private var removedTopics: Set<String> = []
    @State private var mentionsExpanded = false
    @State private var selectedMedia: MediaDisplayItem? = nil
    @State private var audioPlayerForFile: AudioPlayerTarget? = nil
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var newTopicName = ""
    @State private var newTopicColorKey = Crucible.Color.topicPalette[0].key

    /// Direct lifecycle reference for per-panel edit/delete operations on the
    /// chronological capture stream and for the Append spec's per-modality
    /// capture flows (which call lifecycle.append directly when the user
    /// finishes a pill capture).
    private let lifecycle = EntryLifecycleService()
    @State private var activeCaptureModality: CaptureModality? = nil
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
            || !removedTagIds.isEmpty
            || !removedMediaIds.isEmpty
            || !addedTopics.isEmpty
            || !removedTopics.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topicChipsRow
                titleSection
                Text(fullTimestamp)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
                locationChip
                bodyContent
                inferenceCardSection
                mentionsSection
            }
            .padding(16)
            // Bottom inset so the floating Contribute button doesn't cover content.
            .padding(.bottom, 80)
        }
        .background(Crucible.Color.paper)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { leadingToolbar }
            ToolbarItem(placement: .principal) { principalToolbar }
            ToolbarItem(placement: .navigationBarTrailing) { trailingToolbar }
        }
        .onAppear {
            editedTitle = entry.displayTitle
        }
        .sheet(item: $audioPlayerForFile) { target in
            // Prefer the per-clip transcript captured at recording time;
            // fall back to entry.content (the joined-transcript blob) for
            // legacy voice refs from before the schema gained the field.
            AudioPlayerSheet(
                filename: target.filename,
                recordedAt: target.recordedAt,
                initialTranscript: target.transcript ?? entry.content,
                onSaveTranscript: { newText in
                    if let mediaId = target.mediaId {
                        updateMediaTranscript(id: mediaId, text: newText)
                    } else {
                        // Legacy voice entry — transcript IS entry.content.
                        // Persist through lifecycle.edit so search +
                        // inference re-derive from the new text.
                        lifecycle.edit(entryId: entry.id, newContent: newText)
                    }
                }
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

            // Append-spec FAB — pick a modality, capture, append to this memory.
            if mode == .reading {
                AppendFAB(
                    onSelect: { modality in
                        activeCaptureModality = modality
                    },
                    accessibilityLabel: "Add to memory"
                )
            }
        }
        .captureFlowHost(
            activeModality: $activeCaptureModality,
            speechService: speechService,
            onCaptured: { item in
                handleCapturedItemForAppend(item)
            }
        )
    }

    // MARK: - Body sections (decomposed from var body)

    /// Topic chips + (edit-mode) Add menu + (read-mode) status badge.
    private var topicChipsRow: some View {
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
                addTopicMenu
            }

            Spacer()

            if let status = entry.displayStatus, entry.inferenceSummary == nil {
                StatusBadge(text: status.text, style: status.style)
            }
        }
    }

    /// Edit-mode menu for toggling existing topics or creating a new one.
    private var addTopicMenu: some View {
        Menu {
            // Show every topic. Currently-applied ones are marked with a
            // checkmark; tapping toggles membership so the user can switch
            // topics in a single gesture without first having to × the
            // existing chip.
            ForEach(allTopics, id: \.self) { topic in
                let isSelected = currentTopics.contains(topic)
                Button {
                    toggleTopic(topic, currentlySelected: isSelected)
                } label: {
                    if isSelected {
                        Label(topic, systemImage: "checkmark")
                    } else {
                        Text(topic)
                    }
                }
            }
            if !allTopics.isEmpty { Divider() }
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

    /// Title field swaps between an editable `TextField` and a read-mode
    /// `Text` that taps into editing.
    @ViewBuilder
    private var titleSection: some View {
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
    }

    /// Tappable location chip — variant E (Himem · Location.html). Pin
    /// glyph in accent, place name in ink, chevron implies tap. Tap opens
    /// Apple Maps centered on the entry's coordinates.
    @ViewBuilder
    private var locationChip: some View {
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
    }

    /// Body — every entry renders through ChronologicalCaptureStream
    /// post-FragmentMigration v2. Voice / note / image / video are all
    /// MediaReferences interleaved in createdAt order. Entries that the
    /// migration couldn't process (per-entry skip logged in NSLog) fall
    /// through to a plain content render so the user sees something.
    @ViewBuilder
    private var bodyContent: some View {
        if entry.mediaItems.isEmpty {
            Text(entry.content)
                .font(.body)
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(4)
        } else {
            ChronologicalCaptureStream(
                entry: entry,
                onDeleteVoice: { id in
                    removedMediaIds.insert(id)
                    applyEditsImmediately()
                },
                onDeleteNote: { id in
                    deleteNoteFragment(id: id)
                },
                onDeleteMedia: { id in
                    removedMediaIds.insert(id)
                    applyEditsImmediately()
                },
                onEditNote: { id, newText in
                    updateNoteFragment(id: id, text: newText)
                },
                onOpenVoice: { item in
                    audioPlayerForFile = AudioPlayerTarget(
                        mediaId: item.id,
                        filename: item.localIdentifier,
                        recordedAt: item.createdAt,
                        transcript: item.transcript
                    )
                },
                onTapPhoto: { item in
                    selectedMedia = item
                }
            )
        }
    }

    /// AI inference card — visible while the user hasn't yet acted on
    /// the suggestion (no feedback state set).
    @ViewBuilder
    private var inferenceCardSection: some View {
        if let inference = entry.inferenceSummary, entry.feedbackState == nil {
            InferenceCard(
                summary: inference,
                feedbackState: entry.feedbackState,
                onFeedback: { state in onFeedback?(entry.id, state) },
                onAdjust: { correction in onAdjust?(entry.id, correction) }
            )
        }
    }

    /// Mentions section — collapsible row of extracted entity tags.
    @ViewBuilder
    private var mentionsSection: some View {
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
                .accessibilityLabel("\(mentionsExpanded ? "Collapse" : "Expand") mentions, \(visibleTags.count) item\(visibleTags.count == 1 ? "" : "s")")

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

    // MARK: - Toolbar items (decomposed from var body)

    @ViewBuilder
    private var leadingToolbar: some View {
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
            .accessibilityLabel("Back to \(backLabel)")
        }
    }

    @ViewBuilder
    private var principalToolbar: some View {
        if mode == .editing {
            Text("Editing")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Crucible.Color.ink)
        }
    }

    @ViewBuilder
    private var trailingToolbar: some View {
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

    // MARK: - Append spec — single-modality capture results

    /// Append the captured artifact to this memory. One pill press = one
    /// append call. Attach with multiple selections bundles them into a
    /// single append batch so they show as a contiguous group in the
    /// chronological capture stream.
    private func handleCapturedItemForAppend(_ item: CapturedItem) {
        switch item {
        case .voice(let filename, let transcript):
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard filename != nil || !trimmed.isEmpty else { return }
            lifecycle.append(
                entryId: entry.id,
                additionalContent: trimmed,
                voiceFilename: filename
            )

        case .photo(let id):
            lifecycle.append(
                entryId: entry.id,
                additionalContent: "",
                mediaCaptures: [(id, .image)]
            )

        case .video(let id):
            lifecycle.append(
                entryId: entry.id,
                additionalContent: "",
                mediaCaptures: [(id, .video)]
            )

        case .note(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            lifecycle.append(entryId: entry.id, additionalContent: text)

        case .attach(let ids):
            guard !ids.isEmpty else { return }
            let captures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] =
                ids.map { ($0, .image) }
            lifecycle.append(entryId: entry.id, additionalContent: "", mediaCaptures: captures)
        }
    }

    // MARK: - Attachment styling

    private func attachmentColor(for type: MediaReference.MediaType) -> Color {
        switch type {
        case .image: return Crucible.Color.Media.photo
        case .video: return Crucible.Color.Media.video
        case .voice: return Crucible.Color.Media.audio
        case .note:  return Crucible.Color.Media.text
        }
    }

    private func attachmentIcon(for type: MediaReference.MediaType) -> String {
        switch type {
        case .image: return "camera"
        case .video: return "video"
        case .voice: return "mic"
        case .note:  return "text.alignleft"
        }
    }

    private func attachmentLabel(for type: MediaReference.MediaType) -> String {
        switch type {
        case .image: return "Photo"
        case .video: return "Video"
        case .voice: return "Audio"
        case .note:  return "Note"
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
        removedTagIds = []
        removedMediaIds = []
        addedTopics = []
        removedTopics = []
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .reading
        }
    }

    private func commitEdits() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pass nil when the title field wasn't touched so we don't overwrite
        // the entry's actual title with the displayTitle fallback that
        // `enterEditing` seeded into editedTitle.
        let titleToSave: String? = (trimmedTitle == entry.displayTitle) ? nil : trimmedTitle
        // Body editing happens per-fragment now (NotePanel inline edit,
        // AudioPlayerSheet transcript edit). Pass entry.content unchanged so
        // the save round-trip touches only title/tags/media/topics.
        onSave(entry.id, entry.content, titleToSave, removedTagIds, removedMediaIds, addedTopics, removedTopics)
        dismiss()
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

    // MARK: - Topic toggle (edit mode)

    /// Flips a topic's membership on the current entry. Maintains the
    /// staged `addedTopics` / `removedTopics` sets so the change can be
    /// committed atomically by Done or rolled back by Cancel.
    private func toggleTopic(_ topic: String, currentlySelected: Bool) {
        if currentlySelected {
            // Currently selected → remove it.
            if entry.topicNames.contains(topic) {
                // Was on the entry originally; stage a removal.
                removedTopics.insert(topic)
            } else {
                // Was just added in this edit session; un-stage.
                addedTopics.remove(topic)
            }
        } else {
            // Not currently selected → add it.
            if removedTopics.contains(topic) {
                // Was originally on the entry, then staged for removal —
                // un-stage the removal.
                removedTopics.remove(topic)
            } else {
                addedTopics.insert(topic)
            }
        }
    }

    // MARK: - Chronological capture stream helpers

    /// Removes a media reference immediately rather than batching it with
    /// title/content edits via the existing onSave path. Used by the
    /// chronological capture stream's per-panel delete.
    private func applyEditsImmediately() {
        let ids = removedMediaIds
        guard !ids.isEmpty else { return }
        lifecycle.deleteMediaReferences(ids: ids)
        lifecycle.regenerateContent(forEntryId: entry.id)
        removedMediaIds = []
    }

    private func deleteNoteFragment(id: UUID) {
        lifecycle.deleteMediaReferences(ids: [id])
        lifecycle.regenerateContent(forEntryId: entry.id)
    }

    private func updateNoteFragment(id: UUID, text: String) {
        lifecycle.updateNoteFragment(id: id, text: text, entryId: entry.id)
    }

    private func updateMediaTranscript(id: UUID, text: String) {
        lifecycle.updateMediaTranscript(mediaId: id, transcript: text, entryId: entry.id)
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
        .accessibilityLabel(label)
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
                    .accessibilityLabel("Remove transcript")
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
                    .accessibilityLabel("Clear typed text")
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

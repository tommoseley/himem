import SwiftUI

enum EntryViewMode {
    case reading, editing
}

struct EntryExpandedView: View {
    let entry: EntryDisplayModel
    var backLabel: String = "Today"
    let allTopics: [String]
    let onSave: (UUID, String, Set<UUID>, Set<UUID>, Set<String>, Set<String>, Bool) -> Void
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var onAppend: ((EntryDisplayModel) -> Void)? = nil

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
    @State private var showNewTopicSheet = false
    @State private var newTopicName = ""
    @State private var newTopicColorKey = Crucible.Color.topicPalette[0].key

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
                                showNewTopicSheet = true
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

                        // Photo/video rows
                        ForEach(entry.mediaItems) { item in
                            if !removedMediaIds.contains(item.id) {
                                let isVideo = item.mediaType == .video
                                AttachmentRow(
                                    color: isVideo ? Crucible.Color.Media.video : Crucible.Color.Media.photo,
                                    icon: isVideo ? "video" : "camera",
                                    label: isVideo ? "Video" : "Photo"
                                ) {
                                    MediaThumbnailView(item: item, size: 52) {}
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

                // Append button
                if let onAppend, mode == .reading {
                    HStack {
                        Spacer()
                        Button {
                            onAppend(entry)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Add to this memory")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(Crucible.Color.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Crucible.Color.sunk)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
        .sheet(isPresented: $showNewTopicSheet) {
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

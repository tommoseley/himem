import SwiftUI

struct EntryDetailView: View {
    let entryId: UUID
    let originalText: String
    let tags: [TagDisplayModel]
    let audioFilePath: String?
    let mediaItems: [MediaDisplayItem]
    let onSave: (UUID, String, Set<UUID>, Set<UUID>, Bool) -> Void // entryId, text, removedTagIds, removedMediaIds, discardAudio

    @Environment(\.dismiss) private var dismiss
    @State private var editedText = ""
    @State private var removedTagIds: Set<UUID> = []
    @State private var removedMediaIds: Set<UUID> = []
    @State private var discardAudio = false
    @State private var selectedMedia: MediaDisplayItem? = nil

    private var hasChanges: Bool {
        editedText != originalText
            || !removedTagIds.isEmpty
            || !removedMediaIds.isEmpty
            || discardAudio
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Media filmstrip
                    if !mediaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MEDIA")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .tracking(0.5)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(mediaItems) { item in
                                        EditableMediaThumbnail(
                                            item: item,
                                            isMarkedForRemoval: removedMediaIds.contains(item.id),
                                            onTap: { selectedMedia = item },
                                            onToggleRemoval: {
                                                if removedMediaIds.contains(item.id) {
                                                    removedMediaIds.remove(item.id)
                                                } else {
                                                    removedMediaIds.insert(item.id)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                        Divider()
                    }

                    // Text editor
                    TextEditor(text: $editedText)
                        .font(.body)
                        .frame(minHeight: 160)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)

                    // Entity tags
                    if !tags.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ENTITY TAGS")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .tracking(0.5)
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 6) {
                                ForEach(tags) { tag in
                                    let isRemoved = removedTagIds.contains(tag.id)
                                    Button {
                                        if isRemoved {
                                            removedTagIds.remove(tag.id)
                                        } else {
                                            removedTagIds.insert(tag.id)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(tag.value)
                                            Image(systemName: isRemoved ? "arrow.uturn.backward" : "xmark")
                                                .font(.caption2)
                                        }
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isRemoved
                                            ? Color(.tertiarySystemGroupedBackground).opacity(0.5)
                                            : Color(.tertiarySystemGroupedBackground))
                                        .foregroundStyle(isRemoved ? .tertiary : .primary)
                                        .strikethrough(isRemoved)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }

                    // Voice recording
                    if audioFilePath != nil {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("VOICE RECORDING")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .tracking(0.5)
                                .foregroundStyle(.secondary)

                            if discardAudio {
                                HStack {
                                    Image(systemName: "waveform.slash")
                                        .foregroundStyle(.red)
                                    Text("Recording will be deleted on save")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Button("Undo") { discardAudio = false }
                                        .font(.caption)
                                }
                            } else {
                                HStack {
                                    VoicePlaybackRow(filename: audioFilePath!)
                                    Spacer()
                                    Button(role: .destructive) { discardAudio = true } label: {
                                        Label("Discard", systemImage: "trash")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .padding()
                    }

                    // Status footer
                    Divider()

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Entry Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(entryId, trimmed, removedTagIds, removedMediaIds, discardAudio)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { editedText = originalText }
        .fullScreenCover(item: $selectedMedia) { item in
            MediaViewerView(item: item)
        }
    }

    private var statusText: String {
        if editedText != originalText {
            return "Saving will update the entry and re-run AI processing."
        }
        if !removedMediaIds.isEmpty {
            return "\(removedMediaIds.count) media item\(removedMediaIds.count == 1 ? "" : "s") will be removed on save."
        }
        if !removedTagIds.isEmpty {
            return "Removed tags will be deleted. AI processing will not re-run."
        }
        if discardAudio {
            return "Voice recording will be permanently deleted."
        }
        return "Edit text, tap media to view full-screen, or tap × to mark for removal."
    }
}

// MARK: - Editable Media Thumbnail

private struct EditableMediaThumbnail: View {
    let item: MediaDisplayItem
    let isMarkedForRemoval: Bool
    let onTap: () -> Void
    let onToggleRemoval: () -> Void

    @State private var thumbnail: UIImage? = nil

    private let size: CGFloat = 88

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail — tappable to view full-screen
            Button(action: onTap) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else if !item.isAccessible {
                        Color(.secondarySystemGroupedBackground)
                        Image(systemName: "photo.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        Color(.secondarySystemGroupedBackground)
                        ProgressView()
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isMarkedForRemoval ? Color.red.opacity(0.35) : .clear)
                )
                .opacity(isMarkedForRemoval ? 0.55 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isMarkedForRemoval)
            }
            .buttonStyle(.plain)

            // Video badge
            if item.mediaType == .video {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(5)
                    .frame(width: size, height: size, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }

            // Remove / undo button
            Button(action: onToggleRemoval) {
                Image(systemName: isMarkedForRemoval ? "arrow.uturn.backward" : "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(isMarkedForRemoval ? Color.blue : Color.red)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .offset(x: 6, y: -6)
        }
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        if let filename = item.thumbnailCacheFilename,
           let cached = ThumbnailService.shared.cachedThumbnail(filename: filename) {
            thumbnail = cached
            return
        }
        thumbnail = await ThumbnailService.shared.fullImage(for: item.localIdentifier)
    }
}

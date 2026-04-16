import SwiftUI

struct EntryEditorView: View {
    let entryId: UUID
    let originalText: String
    let tags: [TagDisplayModel]
    let audioFilePath: String?
    let onSave: (UUID, String, Set<UUID>, Bool) -> Void // last bool = discardAudio
    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String = ""
    @State private var removedTagIds: Set<UUID> = []
    @State private var discardAudio = false

    private var textChanged: Bool {
        editedText != originalText
    }

    private var tagsChanged: Bool {
        !removedTagIds.isEmpty
    }

    private var hasChanges: Bool {
        textChanged || tagsChanged || discardAudio
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editedText)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)

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
                                    .background(isRemoved ? Color(.tertiarySystemGroupedBackground).opacity(0.5) : Color(.tertiarySystemGroupedBackground))
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

                Divider()

                Text(textChanged
                    ? "Saving will update the entry and re-run AI processing."
                    : tagsChanged
                        ? "Removed tags will be deleted. AI processing will not re-run."
                        : discardAudio
                            ? "Voice recording will be permanently deleted."
                            : "Edit the text or tap tags to remove them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(entryId, trimmed, removedTagIds, discardAudio)
                        dismiss()
                    }
                    .disabled(!hasChanges || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            editedText = originalText
        }
    }
}

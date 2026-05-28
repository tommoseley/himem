import SwiftUI

/// Edit an existing topic: rename, change color, or delete.
struct TopicEditorSheet: View {
    let topic: Topic
    let onSave: (String, String) -> Void   // newName, newPaletteKey
    let onDelete: () -> Void

    @State private var name: String = ""
    @State private var colorKey: String = ""
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TextField("Topic name", text: $name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Crucible.Color.ink)
                        .padding(12)
                        .background(Crucible.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1.5))

                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        let hue = Crucible.Color.topicHue(forKey: colorKey)
                        Text(name.trimmingCharacters(in: .whitespaces))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(hue.bg)
                            .foregroundStyle(hue.fg)
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("COLOR")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(0.5)
                            .foregroundStyle(Crucible.Color.ink3)

                        TopicColorPicker(selectedKey: $colorKey)
                    }

                    VStack(spacing: 4) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete Topic")
                                .font(.footnote)
                                .fontWeight(.semibold)
                    }
                    Text("\(topic.entryCount) entries will keep their text but lose this topic.")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                }
                .padding(24)
            }
            .navigationTitle("Edit Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, colorKey)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Topic?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(topic.entryCount) entries will keep their text but lose the \"\(topic.name)\" topic assignment.")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            name = topic.name
            colorKey = topic.paletteKey ?? Crucible.Color.topicHue(for: topic.name).key
        }
    }

    private var hasChanges: Bool {
        let currentKey = topic.paletteKey ?? Crucible.Color.topicHue(for: topic.name).key
        return name.trimmingCharacters(in: .whitespaces) != topic.name || colorKey != currentKey
    }
}

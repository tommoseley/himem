import SwiftUI

/// Sheet-presented full-screen note editor — the note-equivalent of
/// `AudioPlayerSheet`. Mirrors the same header / Done-Cancel-toolbar shape,
/// minus the audio player; the editor fills the available height so a long
/// note can be read and edited without inline-panel scroll conflicts.
///
/// Cancel discards changes; Done saves the (trimmed) text via `onSave` if
/// it differs from the initial value.
struct NoteEditorSheet: View {
    let recordedAt: Date?
    /// Text to seed the editor with.
    let initialText: String
    /// Persists the edited text. Called on Done if the trimmed text differs
    /// from `initialText`. Skipped on Cancel and on Done with no changes.
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                editor
            }
            .padding(20)
            .background(Crucible.Color.paper)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        editorFocused = false
                        dismiss()
                    }
                    .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        editorFocused = false
                        commitIfChanged()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Crucible.Color.accent)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            draftText = initialText
            // Tiny delay so the keyboard rises after the sheet finishes its
            // present animation — focusing too early causes the keyboard to
            // appear behind the sheet on iOS 26.
            try? await Task.sleep(nanoseconds: 250_000_000)
            editorFocused = true
        }
        // Explicit focus release on dismiss. Without this, the TextEditor's
        // underlying UITextView can hold first-responder briefly after the
        // sheet tears down, leaving the keyboard's scroll-avoidance state
        // attached to the parent ScrollView — symptom is that the journal
        // detail page can no longer be panned until the next interaction
        // resets the gesture state.
        .onDisappear {
            editorFocused = false
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let recordedAt {
            Text(Self.timestampFormatter.string(from: recordedAt))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Crucible.Color.ink2)
        }
    }

    // MARK: - Editor

    private var editor: some View {
        TextEditor(text: $draftText)
            .font(.body)
            .foregroundStyle(Crucible.Color.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(Crucible.Color.paper)
            .focused($editorFocused)
    }

    // MARK: - Save

    private func commitIfChanged() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != original else { return }
        onSave(trimmed)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

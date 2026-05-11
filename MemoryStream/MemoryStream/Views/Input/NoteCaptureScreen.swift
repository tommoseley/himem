import SwiftUI

/// Single-modality typed note, presented when the user picks the Note pill
/// from the Append FAB. Bare TextEditor with autofocus, Cancel + Done.
struct NoteCaptureScreen: View {
    let onFinish: (_ text: String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.title3)
                .foregroundStyle(Crucible.Color.ink)
                .scrollContentBackground(.hidden)
                .background(Crucible.Color.paper)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .focused($focused)
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                        .foregroundStyle(Crucible.Color.ink2)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            onFinish(trimmed)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.accent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .onAppear {
            // Tiny delay so the keyboard rises smoothly after the sheet
            // finishes its present animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                focused = true
            }
        }
    }
}

import SwiftUI

struct TextEntrySheet: View {
    var initialText: String = ""
    let pendingMediaCount: Int
    let onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if pendingMediaCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                        Text("\(pendingMediaCount) media item\(pendingMediaCount == 1 ? "" : "s") attached")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingMediaCount == 0)
                }
            }
            .onAppear { text = initialText }
        }
        .presentationDetents([.medium, .large])
    }
}

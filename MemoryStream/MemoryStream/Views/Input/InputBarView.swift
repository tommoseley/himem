import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    var isRecording: Bool = false
    var pendingMediaCount: Int = 0
    let onSave: (String) -> Void
    let onMicTap: () -> Void
    let onCameraTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // Microphone button
                Button(action: onMicTap) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.body)
                        .foregroundStyle(isRecording ? .red : .primary)
                        .frame(width: 36, height: 36)
                        .background(isRecording ? Color.red.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                }

                // Camera button
                Button(action: onCameraTap) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "camera")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Circle())

                        if pendingMediaCount > 0 {
                            Text("\(pendingMediaCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }

                // Text field
                HStack {
                    TextField("Tell me what happened...", text: $text)
                        .font(.subheadline)
                        .disabled(isRecording)

                    if !isRecording {
                        Text("Siri ready")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Capsule())
                    } else {
                        Text("Listening...")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(Capsule())

                // Save button
                Button(action: {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSave(text)
                }) {
                    Text("Save entry")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(canSave ? Color.orange : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(canSave ? .white : .secondary)
                        .clipShape(Capsule())
                }
                .disabled(!canSave)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.background)
        }
    }

    private var canSave: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingMediaCount > 0) && !isRecording
    }
}

#Preview {
    VStack {
        Spacer()
        InputBarView(text: .constant(""), onSave: { _ in }, onMicTap: {}, onCameraTap: {})
    }
}

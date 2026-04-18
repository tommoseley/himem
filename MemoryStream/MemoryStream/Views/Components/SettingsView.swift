import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [Topic] = []
    @State private var newTopicName: String = ""
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay: Double = 7

    private let storage = StorageService.shared

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Topics
                Section {
                    ForEach(topics) { topic in
                        HStack {
                            Text(topic.name)
                            Spacer()
                            Text("\(topic.entryCount) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteTopic)

                    HStack {
                        TextField("New topic...", text: $newTopicName)
                        Button(action: addTopic) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newTopicName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Topics")
                } footer: {
                    Text("Topics are the top-level categories shown in the tab bar. When the AI suggests a new topic, you'll be asked to approve it first.")
                }

                // MARK: - Capture
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Auto-save delay")
                            Spacer()
                            Text(autoSaveDelay == 0 ? "Immediate" : "\(Int(autoSaveDelay))s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $autoSaveDelay, in: 0...60, step: 1)
                            .tint(.orange)
                    }
                    .padding(.vertical, 4)

                    Toggle("Save voice recordings", isOn: $saveVoiceEntries)
                } header: {
                    Text("Capture")
                } footer: {
                    Text(autoSaveDelay == 0
                        ? "Entries save immediately after capture with no grace period."
                        : "After recording or capturing media, entries auto-save after \(Int(autoSaveDelay)) seconds. Tap the mic button during the countdown to cancel and edit instead.")
                        + Text(saveVoiceEntries
                            ? " Voice recordings are saved on device."
                            : " Voice recordings are discarded after transcription.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadTopics()
            }
        }
    }

    // MARK: - Topics

    private func loadTopics() {
        let request = Topic.fetchAll()
        do {
            topics = try storage.viewContext.fetch(request)
        } catch {
            print("Failed to load topics: \(error)")
        }
    }

    private func addTopic() {
        let name = newTopicName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let _ = try storage.findOrCreateTopic(name: name)
            newTopicName = ""
            loadTopics()
        } catch {
            print("Failed to add topic: \(error)")
        }
    }

    private func deleteTopic(at offsets: IndexSet) {
        for index in offsets {
            let topic = topics[index]
            storage.viewContext.delete(topic)
        }
        do {
            try storage.save(context: storage.viewContext)
            loadTopics()
        } catch {
            print("Failed to delete topic: \(error)")
        }
    }
}

#Preview {
    SettingsView()
}

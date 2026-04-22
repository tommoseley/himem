import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [Topic] = []
    @State private var newTopicName: String = ""
    @State private var newTopicColorKey: String = Crucible.Color.topicPalette[0].key
    @State private var showNewTopicSheet = false
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay: Double = 7

    private let storage = StorageService.shared

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Topics
                Section {
                    ForEach(topics) { topic in
                        HStack(spacing: 10) {
                            let hue = Crucible.Color.topicHue(for: topic.name)
                            Circle()
                                .fill(hue.fg)
                                .frame(width: 10, height: 10)
                            Text(topic.name)
                            Spacer()
                            Text("\(topic.entryCount) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteTopic)

                    Button {
                        newTopicName = ""
                        newTopicColorKey = Crucible.Color.topicPalette[0].key
                        showNewTopicSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Crucible.Color.accent)
                            Text("New Topic")
                                .foregroundStyle(Crucible.Color.accent)
                        }
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
            .sheet(isPresented: $showNewTopicSheet) {
                NewTopicSheet(
                    name: $newTopicName,
                    colorKey: $newTopicColorKey,
                    onAdd: { name, colorKey in
                        addTopic(name: name, colorKey: colorKey)
                    }
                )
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

    private func addTopic(name: String, colorKey: String) {
        do {
            let _ = try storage.findOrCreateTopic(name: name, paletteKey: colorKey)
            TopicPaletteStore.shared.set(key: colorKey, for: name)
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

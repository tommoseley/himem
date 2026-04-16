import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var saved = false
    @State private var topics: [Topic] = []
    @State private var newTopicName: String = ""
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true

    private let keychain = KeychainService.shared
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

                // MARK: - Voice
                Section {
                    Toggle("Save voice entries", isOn: $saveVoiceEntries)
                } header: {
                    Text("Voice")
                } footer: {
                    Text(saveVoiceEntries
                        ? "Voice recordings are saved on device. You can play them back from entry cards and discard them in the edit screen."
                        : "Voice recordings are discarded after transcription. Only the text is kept.")
                }

                // MARK: - API Key
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored in iOS Keychain on this device only.")
                }

                Section {
                    Button(action: saveKey) {
                        HStack {
                            Text("Save Key")
                            Spacer()
                            if saved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    if keychain.retrieve(key: "anthropic_api_key") != nil {
                        Button(role: .destructive, action: deleteKey) {
                            Text("Remove Key")
                        }
                    }
                }

                Section {
                    HStack {
                        Text("API Status")
                        Spacer()
                        if keychain.retrieve(key: "anthropic_api_key") != nil {
                            Text("Configured")
                                .foregroundStyle(.green)
                        } else {
                            Text("Not configured")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Without an API key, the app uses local-only entity extraction. With a key, you get rich extraction, topic inference, and summaries.")
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
                if let existing = keychain.retrieve(key: "anthropic_api_key") {
                    apiKey = existing
                }
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

    // MARK: - API Key

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let success = keychain.save(key: "anthropic_api_key", value: trimmed)
        if success {
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saved = false
            }
        }
    }

    private func deleteKey() {
        let _ = keychain.delete(key: "anthropic_api_key")
        apiKey = ""
    }
}

#Preview {
    SettingsView()
}

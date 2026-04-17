import SwiftUI
import UIKit

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var topicApproval = TopicApprovalService.shared
    @State private var inputText = ""
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var editingEntry: EntryDisplayModel? = nil
    @State private var speechErrorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            JournalHeaderView(
                onSearchTap: { showSearch = true },
                onSettingsTap: { showSettings = true }
            )

            List {
                Section {
                    Text("Today")
                        .font(.title)
                        .fontWeight(.bold)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    SiriShortcutBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    TopicTabBar(
                        topics: viewModel.topics,
                        selected: $viewModel.selectedTopic
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No entries yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Type below or use Siri to capture your first thought.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(filteredEntries) { entry in
                    EntryCardView(
                        entry: entry,
                        onFeedback: { entryId, state in
                            viewModel.submitFeedback(entryId: entryId, state: state)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteEntry(entryId: entry.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            editingEntry = entry
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            InputBarView(
                text: $inputText,
                isRecording: speechService.isRecording,
                onSave: { text in
                    viewModel.saveEntry(content: text, inputType: .typed)
                    inputText = ""
                },
                onMicTap: {
                    handleMicTap()
                }
            )
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditorView(
                entryId: entry.id,
                originalText: entry.content,
                tags: entry.tags,
                audioFilePath: entry.audioFilePath,
                onSave: { entryId, newContent, removedTagIds, discardAudio in
                    viewModel.editEntry(entryId: entryId, newContent: newContent, removedTagIds: removedTagIds, discardAudio: discardAudio)
                }
            )
        }
        .alert(
            "New Topic Suggested",
            isPresented: Binding(
                get: { topicApproval.pendingTopic != nil },
                set: { if !$0 { topicApproval.reject() } }
            )
        ) {
            Button("Add") { topicApproval.approve() }
            Button("Not Now", role: .cancel) { topicApproval.reject() }
        } message: {
            if let pending = topicApproval.pendingTopic {
                Text("The AI wants to create a new topic: \"\(pending.name)\". Add it to your topics?")
            }
        }
        .onAppear {
            Task { let _ = await speechService.requestAuthorization() }
        }
        .onChange(of: speechService.error) { _, error in
            speechErrorMessage = error?.localizedDescription
        }
        .alert("Voice Recording Error", isPresented: Binding(
            get: { speechErrorMessage != nil },
            set: { if !$0 { speechErrorMessage = nil } }
        )) {
            Button("OK") { speechErrorMessage = nil }
            if speechService.error == .notAuthorized {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(speechErrorMessage ?? "")
        }
    }

    private var filteredEntries: [EntryDisplayModel] {
        guard let selected = viewModel.selectedTopic else {
            return viewModel.entries
        }
        return viewModel.entries.filter { $0.topicNames.contains(selected) }
    }

    private func handleMicTap() {
        if speechService.isRecording {
            speechService.stopRecording()
            if !speechService.transcribedText.isEmpty {
                let audioPath = saveVoiceEntries ? speechService.lastRecordingPath : nil
                // Delete audio file if user doesn't want to save
                if !saveVoiceEntries, let path = speechService.lastRecordingPath {
                    AudioPlayerService.deleteAudio(filename: path)
                }
                viewModel.saveEntry(content: speechService.transcribedText, inputType: .voiceInApp, audioFilePath: audioPath)
                speechService.transcribedText = ""
                speechService.lastRecordingPath = nil
            }
        } else {
            speechService.transcribedText = ""
            speechService.startRecording()
        }
    }
}

// MARK: - Header

struct JournalHeaderView: View {
    let onSearchTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        HStack {
            Text("HI MEM")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

#Preview {
    JournalView()
}

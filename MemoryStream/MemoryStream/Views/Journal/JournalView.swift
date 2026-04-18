import SwiftUI
import UIKit

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @StateObject private var topicApproval = TopicApprovalService.shared
    @State private var inputText = ""
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var editingEntry: EntryDisplayModel? = nil
    @State private var speechErrorMessage: String? = nil
    @State private var pendingMediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []

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
                pendingMediaCount: pendingMediaCaptures.count,
                onSave: { text in
                    let content = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No text provided."
                        : text
                    let inputType: JournalEntry.InputType = pendingMediaCaptures.isEmpty ? .typed : .camera
                    viewModel.saveEntry(content: content, inputType: inputType, mediaCaptures: pendingMediaCaptures)
                    inputText = ""
                    pendingMediaCaptures = []
                },
                onMicTap: {
                    handleMicTap()
                },
                onCameraTap: {
                    handleCameraTap()
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(
                onCapture: { result in
                    handleCameraCapture(result)
                },
                onDismiss: {
                    showCamera = false
                }
            )
        }
        .onAppear {
            Task {
                let _ = await speechService.requestAuthorization()
                await cameraService.requestAuthorization()
            }
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
        .alert("Camera Error", isPresented: Binding(
            get: { cameraService.error != nil },
            set: { if !$0 { cameraService.error = nil } }
        )) {
            Button("OK") { cameraService.error = nil }
            if cameraService.error == .notAuthorized {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(cameraService.error?.localizedDescription ?? "")
        }
    }

    private var filteredEntries: [EntryDisplayModel] {
        guard let selected = viewModel.selectedTopic else {
            return viewModel.entries
        }
        return viewModel.entries.filter { $0.topicNames.contains(selected) }
    }

    private func handleCameraTap() {
        guard cameraService.isAuthorized else {
            cameraService.error = .notAuthorized
            return
        }
        showCamera = true
    }

    private func handleCameraCapture(_ result: CameraPickerView.CaptureResult) {
        showCamera = false
        Task {
            do {
                switch result {
                case .photo(let image):
                    let identifier = try await cameraService.savePhoto(image)
                    pendingMediaCaptures.append((localIdentifier: identifier, mediaType: .image))
                case .video(let url):
                    let identifier = try await cameraService.saveVideo(at: url)
                    pendingMediaCaptures.append((localIdentifier: identifier, mediaType: .video))
                }
            } catch let error as CameraService.CameraError {
                cameraService.error = error
            } catch {
                cameraService.error = .saveFailed(error.localizedDescription)
            }
        }
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

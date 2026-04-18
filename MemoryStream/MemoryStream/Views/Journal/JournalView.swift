import SwiftUI
import UIKit

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @StateObject private var topicApproval = TopicApprovalService.shared
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay: Double = 7
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var cameraMode: CameraPickerView.CaptureMode = .both
    @State private var showTextEntry = false
    @State private var showFABOptions = false
    @State private var editingEntry: EntryDisplayModel? = nil
    @State private var speechErrorMessage: String? = nil
    @State private var pendingMediaCaptures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []

    // Auto-save countdown
    @State private var autoSaveProgress: Double = 0   // 0 = idle, 0…1 = counting
    @State private var isCountingDown = false
    @State private var countdownIsForVoice = false
    @State private var countdownVoiceText = ""
    @State private var countdownVoiceAudioPath: String? = nil

    // Text entry sheet context (set when opening sheet, from either long-press or cancelled countdown)
    @State private var textEntryInitialText = ""
    @State private var textEntryIsForVoice = false
    @State private var textEntryVoiceAudioPath: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                            Label("View", systemImage: "eye")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 96)
            }
        }
        .background(Color(.systemGroupedBackground))

        // Dim overlay — tap outside to dismiss FAB options
        if showFABOptions {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        showFABOptions = false
                    }
                }
        }

        // FAB
        JournalFAB(
            isRecording: speechService.isRecording,
            pendingMediaCount: pendingMediaCaptures.count,
            autoSaveProgress: autoSaveProgress,
            showOptions: $showFABOptions,
            onMicTap: { handleFABTap() },
            onTextTap: {
                textEntryInitialText = ""
                textEntryIsForVoice = false
                showTextEntry = true
            },
            onPhotoTap: { cameraMode = .photo; handleCameraTap() },
            onVideoTap: { cameraMode = .video; handleCameraTap() }
        )
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        } // ZStack
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTextEntry) {
            TextEntrySheet(
                initialText: textEntryInitialText,
                pendingMediaCount: pendingMediaCaptures.count
            ) { text in
                let content = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "No text provided."
                    : text
                if textEntryIsForVoice {
                    viewModel.saveEntry(
                        content: content,
                        inputType: .voiceInApp,
                        audioFilePath: textEntryVoiceAudioPath
                    )
                    textEntryIsForVoice = false
                    textEntryVoiceAudioPath = nil
                } else {
                    let inputType: JournalEntry.InputType = pendingMediaCaptures.isEmpty ? .typed : .camera
                    viewModel.saveEntry(content: content, inputType: inputType, mediaCaptures: pendingMediaCaptures)
                    pendingMediaCaptures = []
                }
                textEntryInitialText = ""
            }
        }
        .sheet(item: $editingEntry) { entry in
            EntryDetailView(
                entryId: entry.id,
                originalText: entry.content,
                tags: entry.tags,
                audioFilePath: entry.audioFilePath,
                mediaItems: entry.mediaItems,
                onSave: { entryId, newContent, removedTagIds, removedMediaIds, discardAudio in
                    viewModel.editEntry(
                        entryId: entryId,
                        newContent: newContent,
                        removedTagIds: removedTagIds,
                        removedMediaIds: removedMediaIds,
                        discardAudio: discardAudio
                    )
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
                captureMode: cameraMode,
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
        Task { @MainActor in
            do {
                switch result {
                case .photo(let image):
                    let identifier = try await cameraService.savePhoto(image)
                    pendingMediaCaptures.append((localIdentifier: identifier, mediaType: .image))
                case .video(let url):
                    let identifier = try await cameraService.saveVideo(at: url)
                    pendingMediaCaptures.append((localIdentifier: identifier, mediaType: .video))
                }
                countdownIsForVoice = false
                startCountdown()
            } catch let error as CameraService.CameraError {
                cameraService.error = error
            } catch {
                cameraService.error = .saveFailed(error.localizedDescription)
            }
        }
    }

    private func handleFABTap() {
        if isCountingDown {
            // Cancel the countdown and open the text sheet so the user can review/edit
            cancelCountdown(openSheet: true)
        } else {
            handleMicTap()
        }
    }

    private func handleMicTap() {
        if speechService.isRecording {
            speechService.stopRecording()
            guard !speechService.transcribedText.isEmpty else { return }
            let audioPath = saveVoiceEntries ? speechService.lastRecordingPath : nil
            if !saveVoiceEntries, let path = speechService.lastRecordingPath {
                AudioPlayerService.deleteAudio(filename: path)
            }
            countdownVoiceText = speechService.transcribedText
            countdownVoiceAudioPath = audioPath
            countdownIsForVoice = true
            speechService.transcribedText = ""
            speechService.lastRecordingPath = nil
            startCountdown()
        } else {
            if isCountingDown { cancelCountdown(openSheet: false) }
            speechService.transcribedText = ""
            speechService.startRecording()
        }
    }

    // MARK: - Auto-save countdown

    private func startCountdown() {
        guard autoSaveDelay > 0 else {
            commitAutoSave()
            return
        }
        isCountingDown = true
        autoSaveProgress = 0
        withAnimation(.linear(duration: autoSaveDelay)) {
            autoSaveProgress = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
            guard isCountingDown else { return }
            commitAutoSave()
        }
    }

    private func commitAutoSave() {
        isCountingDown = false
        autoSaveProgress = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if countdownIsForVoice {
            viewModel.saveEntry(
                content: countdownVoiceText,
                inputType: .voiceInApp,
                audioFilePath: countdownVoiceAudioPath
            )
            countdownVoiceText = ""
            countdownVoiceAudioPath = nil
        } else {
            let content = "No text provided."
            viewModel.saveEntry(content: content, inputType: .camera, mediaCaptures: pendingMediaCaptures)
            pendingMediaCaptures = []
        }
    }

    private func cancelCountdown(openSheet: Bool) {
        isCountingDown = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            autoSaveProgress = 0
        }
        guard openSheet else { return }
        if countdownIsForVoice {
            textEntryInitialText = countdownVoiceText
            textEntryIsForVoice = true
            textEntryVoiceAudioPath = countdownVoiceAudioPath
            countdownVoiceText = ""
            countdownVoiceAudioPath = nil
        } else {
            textEntryInitialText = ""
            textEntryIsForVoice = false
        }
        showTextEntry = true
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

// MARK: - FAB

struct JournalFAB: View {
    var isRecording: Bool
    var pendingMediaCount: Int
    var autoSaveProgress: Double
    @Binding var showOptions: Bool
    let onMicTap: () -> Void
    let onTextTap: () -> Void
    let onPhotoTap: () -> Void
    let onVideoTap: () -> Void

    private var isCountingDown: Bool { autoSaveProgress > 0 }

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if showOptions {
                FABOption(icon: "video.fill", label: "Video", color: .purple, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onVideoTap()
                })
                FABOption(icon: "camera.fill", label: "Photo", color: .blue, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onPhotoTap()
                })
                FABOption(icon: "pencil", label: "Text", color: .green, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onTextTap()
                })
            }

            // Main button + countdown ring
            ZStack {
                // Countdown ring — fills clockwise from 12 o'clock
                Circle()
                    .trim(from: 0, to: autoSaveProgress)
                    .stroke(
                        Color.orange,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))

                Button(action: {
                    if showOptions {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    } else {
                        onMicTap()
                    }
                }) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(isRecording ? Color.red : Color.orange)
                            .frame(width: 60, height: 60)
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

                        Image(systemName: isRecording ? "stop.fill" : (isCountingDown ? "hand.tap.fill" : "mic.fill"))
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)

                        if pendingMediaCount > 0 && !isRecording && !isCountingDown {
                            Text("\(pendingMediaCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        guard !isRecording && !isCountingDown else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showOptions = true
                        }
                    }
                )
                .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
        }
    }
}

struct FABOption: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.background)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .font(.body)
                            .foregroundStyle(color)
                    )
                    .shadow(color: color.opacity(0.2), radius: 4, y: 2)
            }
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

#Preview {
    JournalView()
}

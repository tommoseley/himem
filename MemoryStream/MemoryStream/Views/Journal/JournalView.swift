import SwiftUI
import UIKit

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @StateObject private var topicApproval = TopicApprovalService.shared
    @StateObject private var albumSync = AlbumSyncService.shared
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("autoSaveDelay") private var autoSaveDelay: Double = 7
    @AppStorage("cardDensity") private var cardDensityRaw: String = CardDensity.standard.rawValue
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
    @State private var entityFilter: String? = nil

    private var cardDensity: CardDensity {
        CardDensity(rawValue: cardDensityRaw) ?? .standard
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
            JournalHeaderView(
                density: cardDensity,
                onSearchTap: { showSearch = true },
                onDensityTap: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        cardDensityRaw = cardDensity.next.rawValue
                    }
                },
                onSettingsTap: { showSettings = true }
            )

            List {
                Section {
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

                    // Entity filter indicator
                    if let filter = entityFilter {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(.blue)
                            Text(filter)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button {
                                withAnimation { entityFilter = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                if displayEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No entries yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Tap the mic button to record, or hold it for more options.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(groupedEntries, id: \.date) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            EntryCardView(
                                entry: entry,
                                density: cardDensity,
                                onFeedback: { entryId, state in
                                    viewModel.submitFeedback(entryId: entryId, state: state)
                                },
                                onEntityTap: { value in
                                    withAnimation { entityFilter = value }
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
                    } header: {
                        Text(group.label)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 110)
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

        // Live transcription card
        if speechService.isRecording {
            VStack {
                Spacer()
                HStack(alignment: .top, spacing: 10) {
                    // Pulsing red dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                        .opacity(speechService.transcribedText.isEmpty ? 1 : 0.7)

                    if speechService.transcribedText.isEmpty {
                        Text("Listening...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Text(speechService.transcribedText)
                            .font(.subheadline)
                            .lineSpacing(3)
                            .frame(maxHeight: 120)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: speechService.isRecording)
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
        .alert(
            "Photos Album",
            isPresented: Binding(
                get: { albumSync.pendingProposal != nil },
                set: { if !$0 { albumSync.reject() } }
            )
        ) {
            Button("Create Album") { albumSync.approve() }
            Button("Not Now", role: .cancel) { albumSync.reject() }
        } message: {
            if let proposal = albumSync.pendingProposal {
                Text("Add all media from \"\(proposal.topicName)\" entries to a \"\(proposal.topicName)\" Photos album? Future captures in this topic will be added automatically.")
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

    private var displayEntries: [EntryDisplayModel] {
        var entries = viewModel.entries
        if let selected = viewModel.selectedTopic {
            entries = entries.filter { $0.topicNames.contains(selected) }
        }
        if let filter = entityFilter {
            entries = entries.filter { entry in
                entry.tags.contains { $0.value.localizedCaseInsensitiveContains(filter) }
            }
        }
        return entries
    }

    private struct DayGroup: Identifiable {
        let date: Date
        let label: String
        let entries: [EntryDisplayModel]
        var id: Date { date }
    }

    private var groupedEntries: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: displayEntries) { entry in
            calendar.startOfDay(for: entry.createdAt)
        }
        return grouped.sorted { $0.key > $1.key }.map { date, entries in
            DayGroup(date: date, label: dateLabel(for: date), entries: entries)
        }
    }

    private func dateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        // Prepare the haptic engine now so it's warm when the ring completes
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        withAnimation(.linear(duration: autoSaveDelay)) {
            autoSaveProgress = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
            guard isCountingDown else { return }
            commitAutoSave(haptic: generator)
        }
    }

    private func commitAutoSave(haptic: UIImpactFeedbackGenerator? = nil) {
        isCountingDown = false
        autoSaveProgress = 0
        haptic?.impactOccurred()
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
    var density: CardDensity = .standard
    let onSearchTap: () -> Void
    let onDensityTap: () -> Void
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

            Button(action: onDensityTap) {
                Image(systemName: density.icon)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 8)

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

    private var fabFill: Color {
        if isRecording { return .red }
        if showOptions { return Color(.systemGray2) }
        return .orange
    }

    private var fabIcon: String {
        if isRecording { return "stop.fill" }
        if showOptions { return "xmark" }
        if isCountingDown { return "hand.tap.fill" }
        return "mic.fill"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showOptions {
                FABOption(icon: "video.fill", label: "Video", color: .purple) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onVideoTap()
                }
                FABOption(icon: "camera.fill", label: "Photo", color: .blue) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onPhotoTap()
                }
                FABOption(icon: "pencil", label: "Text", color: .green) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onTextTap()
                }
                FABOption(icon: "mic.fill", label: "Audio", color: .orange) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    onMicTap()
                }
            }

            // Main button + countdown ring
            ZStack {
                // Countdown ring — fills clockwise from 12 o'clock
                Circle()
                    .trim(from: 0, to: autoSaveProgress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))

                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(fabFill)
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

                    Image(systemName: fabIcon)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)

                    if pendingMediaCount > 0 && !isRecording && !isCountingDown && !showOptions {
                        Text("\(pendingMediaCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(Circle())
                // Long press and tap are mutually exclusive: highPriorityGesture wins when
                // held ≥0.4s, preventing the tap from also firing on finger-lift.
                .onTapGesture {
                    if showOptions {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showOptions = false }
                    } else {
                        onMicTap()
                    }
                }
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        guard !isRecording && !isCountingDown else { return }
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
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
            HStack(spacing: 12) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.background)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)

                Circle()
                    .fill(color)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(.white)
                    )
                    .shadow(color: color.opacity(0.35), radius: 5, y: 3)
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

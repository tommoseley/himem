import SwiftUI
import UIKit

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @StateObject private var topicApproval = TopicApprovalService.shared
    @StateObject private var albumSync = AlbumSyncService.shared
    @StateObject private var composer = ComposerViewModel()
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("cardDensity") private var cardDensityRaw: String = CardDensity.standard.rawValue
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var selectedEntryId: UUID? = nil
    @State private var speechErrorMessage: String? = nil
    @State private var entityFilter: String? = nil
    @State private var undoEntry: EntryDisplayModel? = nil
    @State private var showUndo = false

    private var cardDensity: CardDensity {
        CardDensity(rawValue: cardDensityRaw) ?? .standard
    }

    var body: some View {
        NavigationStack {
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
                                .foregroundStyle(Crucible.Color.accent)
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
                        Text("Tap + to create a memory, or hold for hands-free voice.")
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
                                },
                                onAppend: { entry in
                                    selectedEntryId = entry.id
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    viewModel.recycleEntry(entryId: entry.id)
                                    showUndoToast(for: entry)
                                } label: {
                                    Label("Remove", systemImage: "tray.and.arrow.down")
                                }
                                .tint(Color(.systemGray))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntryId = entry.id }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    selectedEntryId = entry.id
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

                // Summary with recycled count (below all entries)
                if !displayEntries.isEmpty || viewModel.selectedTopic != nil {
                    let recycledCount: Int = {
                        if let topic = viewModel.selectedTopic {
                            return viewModel.recycledCountForTopic(topic)
                        }
                        return viewModel.loadRecycledEntries().count
                    }()
                    HStack {
                        Text("\(displayEntries.count) memor\(displayEntries.count == 1 ? "y" : "ies")")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink3)
                        if recycledCount > 0 {
                            Text("·")
                                .foregroundStyle(Crucible.Color.ink4)
                            Text("\(recycledCount) in Recently Deleted")
                                .font(.caption)
                                .foregroundStyle(Crucible.Color.ink4)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 90)
            }
        }
        .background(Crucible.Color.paper)

        // Composer FAB
        ComposerFAB(isOpen: composer.isPresented) {
            composer.speechService = speechService
            composer.cameraService = cameraService
            composer.open()
        } onLongPress: {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            composer.speechService = speechService
            composer.cameraService = cameraService
            composer.open(withRecording: true)
        }
        .padding(.trailing, 14)
        .padding(.bottom, 14)

        // Undo toast
        if showUndo, let entry = undoEntry {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Text("Moved to Recently Deleted")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        viewModel.restoreEntry(entryId: entry.id)
                        withAnimation { showUndo = false }
                    } label: {
                        Text("Undo")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Crucible.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Crucible.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        } // ZStack
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $composer.isPresented, onDismiss: {
            composer.close()
        }) {
            ComposerView(
                composer: composer,
                speechService: speechService,
                topics: viewModel.topics,
                onCommit: { handleCommit() }
            )
        }
        .navigationDestination(item: $selectedEntryId) { entryId in
            if let entry = viewModel.currentEntry(id: entryId) {
                EntryExpandedView(
                    entry: entry,
                    backLabel: dateLabel(for: entry.createdAt),
                    allTopics: viewModel.topics,
                    cameraService: cameraService,
                    speechService: speechService,
                    onSave: { entryId, newContent, removedTagIds, removedMediaIds, addedTopics, removedTopics, discardAudio in
                        viewModel.editEntry(
                            entryId: entryId,
                            newContent: newContent,
                            removedTagIds: removedTagIds,
                            removedMediaIds: removedMediaIds,
                            addedTopicNames: addedTopics,
                            removedTopicNames: removedTopics,
                            discardAudio: discardAudio
                        )
                    },
                    onFeedback: { entryId, state in
                        viewModel.submitFeedback(entryId: entryId, state: state)
                    },
                    onCommit: { entryId, additionalContent, mediaCaptures in
                        viewModel.appendToEntry(
                            entryId: entryId,
                            additionalContent: additionalContent,
                            mediaCaptures: mediaCaptures
                        )
                    },
                    onRecycle: { entryId in
                        viewModel.recycleEntry(entryId: entryId)
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { topicApproval.pendingTopic != nil },
            set: { if !$0 { topicApproval.reject() } }
        )) {
            if let pending = topicApproval.pendingTopic {
                TopicApprovalSheet(
                    topicName: pending.name,
                    onApprove: { paletteKey in topicApproval.approve(paletteKey: paletteKey) },
                    onReject: { topicApproval.reject() }
                )
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
        .navigationBarHidden(true)
        } // NavigationStack
    }

    // MARK: - Data

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

    // MARK: - Undo toast

    private func showUndoToast(for entry: EntryDisplayModel) {
        undoEntry = entry
        withAnimation(.spring(response: 0.3)) { showUndo = true }
        // Auto-dismiss after 5 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation { showUndo = false }
        }
    }

    // MARK: - Composer handlers

    private func handleCommit() {
        viewModel.saveEntry(
            content: composer.commitContent,
            inputType: .composed,
            mediaCaptures: composer.mediaCaptures,
            topicName: composer.selectedTopicName
        )
        composer.reset()
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
                .font(.system(size: 11, weight: .bold))
                .tracking(2.0)
                .foregroundStyle(Crucible.Color.ink3)

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

// MARK: - Composer FAB

struct ComposerFAB: View {
    let isOpen: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(isOpen ? Crucible.Color.accentPressed : Crucible.Color.accent)
                .frame(width: 56, height: 56)
                .shadow(color: Color(red: 40/255, green: 25/255, blue: 15/255).opacity(0.22), radius: 10, y: 4)

            Image(systemName: isOpen ? "xmark" : "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOpen)
        }
        .contentShape(Circle())
        .onTapGesture { onTap() }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                onLongPress()
            }
        )
    }
}

// MARK: - Topic Approval Sheet

struct TopicApprovalSheet: View {
    let topicName: String
    let onApprove: (String) -> Void
    let onReject: () -> Void

    @State private var selectedKey = Crucible.Color.topicPalette[0].key
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("The AI suggests a new topic:")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)

                    let hue = Crucible.Color.topicHue(forKey: selectedKey)
                    Text(topicName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(hue.bg)
                        .foregroundStyle(hue.fg)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CHOOSE A COLOR")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .foregroundStyle(Crucible.Color.ink3)

                    TopicColorPicker(selectedKey: $selectedKey)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("New Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        onReject()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onApprove(selectedKey)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    JournalView()
}

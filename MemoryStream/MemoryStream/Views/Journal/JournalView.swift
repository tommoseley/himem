import SwiftUI
import UIKit

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @ObservedObject private var topicApproval = TopicApprovalService.shared
    @ObservedObject private var albumSync = AlbumSyncService.shared
    @StateObject private var projectVM = ProjectViewModel()
    @ObservedObject private var errorState = ErrorState.shared
    @EnvironmentObject private var quickAction: QuickActionState
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("cardDensity") private var cardDensityRaw: String = CardDensity.standard.rawValue
    @State private var viewMode: ViewMode = .memories

    enum ViewMode: String, CaseIterable {
        case memories = "Memories"
        case projects = "Projects"
    }
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showInbox = false
    /// One-shot guard: auto-open Captured Clips on launch only. Prevents
    /// the sheet from re-popping after the user explicitly dismissed it
    /// (and prevents in-session arrivals from triggering it — those go
    /// through notifications instead).
    @ObservedObject private var inbox = InboxManifest.shared
    @ObservedObject private var upgradePromptCoord = UpgradePromptCoordinator.shared
    /// Set by `StartVoiceRecordingIntent` when Siri ("Record in
    /// HiMem") fires. Observed below to present the voice composer
    /// automatically. The composer auto-starts recording on appear,
    /// so flipping this flag is enough to land in mic-hot state.
    @ObservedObject private var captureRequests = CaptureRequestBus.shared
    @State private var selectedEntryId: UUID? = nil
    @State private var speechErrorMessage: String? = nil
    @State private var undoEntry: EntryDisplayModel? = nil
    @State private var showUndo = false
    @State private var activeCaptureModality: CaptureModality? = nil
    @State private var pendingNoteForNewEntry: String? = nil

    private var cardDensity: CardDensity {
        CardDensity(rawValue: cardDensityRaw) ?? .standard
    }

    var body: some View {
        NavigationStack {
        ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
            JournalHeaderView(
                viewMode: $viewMode,
                density: cardDensity,
                onSearchTap: { showSearch = true },
                onDensityTap: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        cardDensityRaw = cardDensity.next.rawValue
                    }
                },
                onSettingsTap: { showSettings = true }
            )

            // Soft 75% AI-assist banner — once per monthly period for
            // Plus / Founders. Free users never see this.
            Soft75Banner()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Inbox banner — appears when there are watch clips waiting to
            // be organized. Per the Append-Watch design rule: calm by
            // default, but when the inbox is non-empty surface a single
            // banner-only nag.
            if !inbox.isEmpty && viewMode == .memories {
                inboxBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Topic bar (shared across both modes)
            TopicTabBar(
                topics: viewModel.topics,
                selected: $viewModel.selectedTopic
            )
            .padding(.vertical, 4)

            entityFilterChip

            if viewMode == .projects {
                ProjectListView(
                    projectVM: projectVM,
                    selectedTopic: viewModel.selectedTopic
                )
            } else {
                memoriesList
            }
        }
        .background(Crucible.Color.paper)

        // Append-spec FAB — tap opens the action stack; pick a modality and
        // the corresponding capture surface presents. The result lands as a
        // new memory. Hidden in Projects tab — the inline "+ New project"
        // row is the create affordance there (per Projects MVP design).
        if viewMode == .memories {
            AppendFAB(
                onSelect: { modality in
                    activeCaptureModality = modality
                },
                accessibilityLabel: "Add memory"
            )
        }

        errorBannerOverlay

        undoToastOverlay

        } // ZStack
        .navigationDestination(isPresented: $showSearch) {
            SearchView(
                onSelectEntry: { id in
                    showSearch = false
                    selectedEntryId = id
                },
                onCaptureNewWith: { text in
                    showSearch = false
                    // Seed the search query as the body of a new note. The
                    // user can edit before hitting Done.
                    pendingNoteForNewEntry = text
                    activeCaptureModality = .note
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $upgradePromptCoord.shouldShow, onDismiss: {
            upgradePromptCoord.markShown()
        }) {
            UpgradePromptSheet()
                .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $showInbox) {
            SessionListView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.openInboxNotification)) { _ in
            // Tap on inbox-arrival notification → open the inbox sheet.
            showInbox = true
        }
        // Per the Watch → Memory flow spec (2026-05-14): the iPhone app
        // always lands on Today. No auto-open of the inbox; the
        // inboxBanner pinned above the topic filter chips is the only
        // nag. Tapping a notification still opens Captured Clips
        // directly (`openInboxNotification` handler above).
        .captureFlowHost(
            activeModality: $activeCaptureModality,
            speechService: speechService,
            onCaptured: { item in
                handleCapturedItemForNewEntry(item)
            }
        )
        .navigationDestination(item: $selectedEntryId) { entryId in
            if let entry = viewModel.currentEntry(id: entryId) {
                EntryExpandedView(
                    entry: entry,
                    backLabel: dateLabel(for: entry.createdAt),
                    allTopics: viewModel.topics,
                    cameraService: cameraService,
                    speechService: speechService,
                    onSave: { entryId, newContent, newTitle, removedTagIds, removedMediaIds, addedTopics, removedTopics in
                        viewModel.editEntry(
                            entryId: entryId,
                            newContent: newContent,
                            newTitle: newTitle,
                            removedTagIds: removedTagIds,
                            removedMediaIds: removedMediaIds,
                            addedTopicNames: addedTopics,
                            removedTopicNames: removedTopics
                        )
                    },
                    onFeedback: { entryId, state in
                        viewModel.submitFeedback(entryId: entryId, state: state)
                    },
                    onAdjust: { entryId, correction in
                        viewModel.submitFeedback(entryId: entryId, state: .edited, correction: correction)
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
                    },
                    onAddToProject: { entryId, projectId in
                        projectVM.addMemory(entryId: entryId, toProjectId: projectId)
                    },
                    availableProjects: projectVM.projects
                )
                .onAppear { viewModel.markEntryViewed(entryId) }
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
            // Check whether the upgrade prompt should fire on launch.
            // Idempotent — won't re-fire if already shown.
            upgradePromptCoord.evaluate()
            handlePendingVoiceRecordRequest()
        }
        .onChange(of: captureRequests.pendingVoiceRecord) { _, pending in
            if pending { handlePendingVoiceRecordRequest() }
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
        .onChange(of: quickAction.pendingAction) { _, action in
            guard let action else { return }
            quickAction.pendingAction = nil
            switch action {
            case "com.himem.app.voice-capture":
                activeCaptureModality = .voice
            case "com.himem.app.new-entry":
                // No specific modality — open the FAB stack equivalent: just
                // jump to the typed-note capture as the safe default.
                activeCaptureModality = .note
            default:
                break
            }
        }
        } // NavigationStack
    }


    private func dateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    /// Drains a pending `StartVoiceRecordingIntent` request by
    /// presenting the voice composer. Clears the bus flag so the
    /// next Siri invocation re-triggers. Called both on `.onAppear`
    /// (cold-launch path: Siri fires the intent, app opens, the bus
    /// already has the flag set) and on `.onChange` of the flag
    /// (warm path: app is already foreground, Siri flips the flag).
    private func handlePendingVoiceRecordRequest() {
        guard captureRequests.pendingVoiceRecord else { return }
        captureRequests.pendingVoiceRecord = false
        // Defer one tick so any in-flight sheet/cover dismiss can
        // settle before we present the voice composer.
        DispatchQueue.main.async {
            activeCaptureModality = .voice
        }
    }

    // MARK: - Memories list

    /// The List of grouped memory entries. Mirrors the original inline
    /// layout: empty-state placeholder, grouped Sections with swipe
    /// actions, and a summary footer with the Recently-Deleted count.
    private var memoriesList: some View {
        List {
            emptyMemoriesState

            if viewMode == .memories {
                ForEach(viewModel.groupedEntries) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            EntryCardView(
                                entry: entry,
                                density: cardDensity,
                                onFeedback: { entryId, state in
                                    viewModel.submitFeedback(entryId: entryId, state: state)
                                },
                                onAdjust: { entryId, correction in
                                    viewModel.submitFeedback(entryId: entryId, state: .edited, correction: correction)
                                },
                                onEntityTap: { value in
                                    withAnimation { viewModel.entityFilter = value }
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

            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            // Reload journal AND nudge the watch to re-send any pending
            // clips — covers the "watch was out of range" case where the
            // system's automatic retry hasn't fired yet. No-op when the
            // watch isn't reachable.
            viewModel.refresh()
            WatchSessionDelegate.shared.requestWatchPendingFlush()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            memoriesPinnedFooter
        }
    }

    /// Permanent pinned footer at the very bottom of the feed: hairline
    /// divider + centered "N memories · M in Recently Deleted". The
    /// background and hairline ignore the home-indicator safe area so
    /// the footer extends to the actual bottom edge of the screen. The
    /// text itself uses an explicit small bottom padding so it doesn't
    /// overlap the home indicator's gesture surface.
    @ViewBuilder
    private var memoriesPinnedFooter: some View {
        if !viewModel.filteredEntries.isEmpty || viewModel.selectedTopic != nil {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 4) {
                    Text("\(viewModel.filteredEntries.count) memor\(viewModel.filteredEntries.count == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                    if viewModel.recycledCount > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                        Text("\(viewModel.recycledCount) in Recently Deleted")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }
            .background(Crucible.Color.paper)
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    // MARK: - Entity filter chip

    @ViewBuilder
    private var entityFilterChip: some View {
        if let filter = viewModel.entityFilter, viewMode == .memories {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(Crucible.Color.accent)
                    .accessibilityHidden(true)
                Text(filter)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    withAnimation { viewModel.entityFilter = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty memories state

    @ViewBuilder
    private var emptyMemoriesState: some View {
        if viewModel.filteredEntries.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "text.book.closed")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
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
    }

    // MARK: - Error banner overlay

    @ViewBuilder
    private var errorBannerOverlay: some View {
        if let error = errorState.current {
            VStack {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Crucible.Color.danger)
                        .accessibilityHidden(true)
                    Text(error.errorDescription ?? "Something went wrong")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        errorState.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Crucible.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: errorState.current?.id)
        }
    }

    // MARK: - Undo toast overlay

    @ViewBuilder
    private var undoToastOverlay: some View {
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
    }

    // MARK: - Inbox banner

    /// Pinned banner above the topic filter chips. Per the Watch →
    /// Memory flow spec: single line, count-leading, dot-separated, no
    /// emoji, no app subtitle. Hidden when the inbox is empty — the
    /// banner is the only nag (no auto-open, no per-clip push for v1).
    private var inboxBanner: some View {
        Button {
            showInbox = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Crucible.Color.accent)
                Text("\(inbox.count) new from Apple Watch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text("·")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink4)
                Text("Tap to review")
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Crucible.Color.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(inbox.count) new clip\(inbox.count == 1 ? "" : "s") from Apple Watch")
        .accessibilityHint("Opens the inbox to review and process pending watch recordings.")
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

    // MARK: - Capture handlers (Append spec — capture-new path)

    /// Maps a CapturedItem from the FAB action stack to a new memory.
    /// One pill press = one new entry. Attach with multiple selections
    /// bundles them into a single new memory with all media on it.
    /// On success, navigates to the new memory's detail view so the user
    /// sees their contribution as the top item.
    private func handleCapturedItemForNewEntry(_ item: CapturedItem) {
        let newId: UUID?
        switch item {
        case .voice(let filename, let transcript):
            // Drop empty voice if both fields are empty (user hit Done before
            // saying anything).
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard filename != nil || !trimmed.isEmpty else { return }
            newId = viewModel.saveEntry(
                content: trimmed,
                inputType: .voiceInApp,
                voiceFilename: filename
            )

        case .photo(let id):
            newId = viewModel.saveEntry(
                content: "",
                inputType: .camera,
                mediaCaptures: [(id, .image)]
            )

        case .video(let id):
            newId = viewModel.saveEntry(
                content: "",
                inputType: .camera,
                mediaCaptures: [(id, .video)]
            )

        case .note(let text):
            // If we seeded a search-query value, prepend it.
            let body: String
            if let pending = pendingNoteForNewEntry, !pending.isEmpty {
                pendingNoteForNewEntry = nil
                body = pending + (text.isEmpty ? "" : "\n\n" + text)
            } else {
                body = text
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            newId = viewModel.saveEntry(content: body, inputType: .typed)
            // Also create a `.note` MediaReference so the text shows up
            // in the chronological capture stream alongside any later
            // appends. Without this, the detail view would only show
            // photos/videos and the typed text would be invisible until
            // the user enters edit mode.
            if let id = newId {
                viewModel.createNoteFragment(forEntryId: id, text: body)
            }

        case .attach(let ids):
            guard !ids.isEmpty else { return }
            // PHPicker doesn't separate photos from videos in its return
            // shape; classify as image by default. The asset's actual type
            // will be picked up by ThumbnailService at render time.
            let captures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] =
                ids.map { ($0, .image) }
            newId = viewModel.saveEntry(content: "", inputType: .camera, mediaCaptures: captures)

        case .voiceSession(let clips, _):
            // "On a roll" — multi-clip phone voice session. First clip
            // creates the Memory; subsequent clips append voice
            // fragments to that same Memory so the whole roll lands
            // as one entry. `rollGroupId` is informational; on phone
            // the create-then-append path is already in one memory by
            // construction, so we don't need to stamp it.
            guard let first = clips.first else { return }
            newId = viewModel.saveEntry(
                content: first.transcript,
                inputType: .voiceInApp,
                voiceFilename: first.audioFilename
            )
            if let entryId = newId {
                for clip in clips.dropFirst() {
                    viewModel.appendToEntry(
                        entryId: entryId,
                        additionalContent: clip.transcript,
                        voiceFilename: clip.audioFilename
                    )
                }
            }
            // Stamp the session's location fix onto every fragment's
            // MediaReference + kick off reverse-geocode for the
            // clip-row header (Memory Detail v3). All clips in a
            // phone roll share the one session-start fix.
            for clip in clips {
                ClipLocationResolver.stamp(
                    osIdentifier: clip.audioFilename,
                    latitude: clip.latitude,
                    longitude: clip.longitude,
                    in: StorageService.shared.viewContext
                )
            }
        }

        // Navigate into the new memory so the captured contribution lands as
        // the top item rather than dropping the user back on Today. The slight
        // dispatch lets the capture sheet finish its dismiss animation first.
        if let newId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                selectedEntryId = newId
            }
        }
    }
}

// MARK: - Header

struct JournalHeaderView: View {
    @Binding var viewMode: JournalView.ViewMode
    var density: CardDensity = .standard
    let onSearchTap: () -> Void
    let onDensityTap: () -> Void
    let onSettingsTap: () -> Void

    @ObservedObject private var entitlement = EntitlementService.shared

    var body: some View {
        ZStack {
            // Center: segmented toggle
            Picker("", selection: $viewMode) {
                ForEach(JournalView.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            // Left: HI MEM + tier mark
            HStack(spacing: 6) {
                Text("HiMem")
                    .font(.caption2.bold())
                    .tracking(2.0)
                    .foregroundStyle(Crucible.Color.ink3)
                TierMark(
                    tier: entitlement.tier,
                    supporter: entitlement.isSupporter,
                    size: 10
                )
                Spacer()
            }

            // Right: icons
            HStack {
                Spacer()

                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Search")

                Button(action: onDensityTap) {
                    Image(systemName: density.icon)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Card density: \(density.label)")
                .padding(.leading, 8)

                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Settings")
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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

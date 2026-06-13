import SwiftUI
import UIKit
import WatchConnectivity

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @StateObject private var projectVM = ProjectViewModel()
    @ObservedObject private var errorState = ErrorState.shared
    @EnvironmentObject private var quickAction: QuickActionState
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @State private var viewMode: ViewMode = .memories

    enum ViewMode: String, CaseIterable {
        case memories = "Memories"
        case projects = "Projects"
    }
    @State private var showSearch = false
    @State private var showSettings = false
    /// Drives presentation of the Tutorials hub from the `?` toolbar
    /// glyph. Same `NavigationStack`, so the hub pushes; back-chevron
    /// returns to the journal. Spec: `docs/design/screens-settings.jsx`
    /// → `ScrTutorialsHub`.
    @State private var showTutorials = false
    @State private var showInbox = false
    /// One-shot guard: auto-open Captured Clips on launch only. Prevents
    /// the sheet from re-popping after the user explicitly dismissed it
    /// (and prevents in-session arrivals from triggering it — those go
    /// through notifications instead).
    @ObservedObject private var inbox = InboxManifest.shared
    /// Set by `StartVoiceRecordingIntent` when Siri ("Record in
    /// HiMem") fires. Observed below to present the voice composer
    /// automatically. The composer auto-starts recording on appear,
    /// so flipping this flag is enough to land in mic-hot state.
    @ObservedObject private var captureRequests = CaptureRequestBus.shared
    @State private var selectedEntryId: UUID? = nil
    @State private var speechErrorMessage: String? = nil
    @State private var activeCaptureModality: CaptureModality? = nil
    @State private var pendingNoteForNewEntry: String? = nil

    var body: some View {
        NavigationStack {
        ZStack(alignment: .bottomTrailing) {
        VStack(spacing: 0) {
            JournalHeaderView(
                viewMode: $viewMode,
                onSearchTap: { showSearch = true },
                onSettingsTap: { showSettings = true },
                onHelpTap: { showTutorials = true }
            )

            // Inbox banner — appears when there are watch clips waiting to
            // be organized. Per the Append-Watch design rule: calm by
            // default, but when the inbox is non-empty surface a single
            // banner-only nag.
            if !inbox.isEmpty && viewMode == .memories {
                JournalInboxBanner(count: inbox.count, onTap: { showInbox = true })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Topic bar (shared across both modes)
            TopicTabBar(
                topics: viewModel.topics,
                selected: $viewModel.selectedTopic
            )
            .padding(.vertical, 4)

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

        JournalErrorBanner()

        } // ZStack
        .navigationDestination(isPresented: $showTutorials) {
            TutorialsHubView()
        }
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
        .navigationDestination(isPresented: $showInbox) {
            SessionListView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.openInboxNotification)) { _ in
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
            entryDetailDestination(for: entryId)
        }
        .onAppear {
            // Arm the tutorial orchestrator now that the user is
            // actually looking at the journal (onboarding is done by
            // construction — this branch only renders when
            // `splashComplete && onboardingComplete`). Trigger sites
            // (Capture / Organize / Find-the-thread / Captured Clips /
            // Today Watch-discovery) become live as of this call. Per
            // the spec: "Never during onboarding, never on cold
            // launch" — this is the cold-launch gate flipping.
            TutorialOrchestrator.shared.armForReadyState()
            attemptWatchDiscoveryTutorial()

            // Cold-launch fix 2026-06-02: removed the pre-fetch of speech +
            // photo-library authorization. On fresh install, these two
            // requestAuthorization calls fired the iOS permission prompts
            // immediately on the user's first cold launch — each prompt
            // suspends the app, and a typical user takes 4–5 seconds total
            // to dismiss both. That dead time dominated the perceived
            // cold-launch experience on first install.
            //
            // Both permissions are now requested on demand at the moment
            // they're needed: SpeechService.requestAuthorization is
            // already wired in VoiceCaptureScreen.onAppear (the voice
            // composer's first body evaluation); Photos auth fires when
            // CameraService.savePhoto / saveVideo invoke PHPhotoLibrary;
            // Camera auth fires when UIImagePickerController is presented
            // for .camera source. Net first-install impact: 4–5s back.
            //
            // Subsequent cold launches were unaffected by the pre-fetch
            // (cached auth status returns instantly with no prompt), so
            // this change is a pure win for the fresh-install experience
            // and a no-op for everyone else.
            handlePendingVoiceRecordRequest()
        }
        // Cold-launch fix 2026-06-02: both view-model initial loads
        // run here via `.task` after first paint. Previously their
        // init() ran the fetches synchronously, blocking the splash
        // for seconds while the @StateObject chain constructed. Now
        // JournalView renders its empty state, then both VMs publish
        // their data via @Published. ProjectViewModel.loadInitial
        // is small (project list) but still on main; ordering it
        // after viewModel.loadInitial keeps the Memories tab
        // responsive first (the default landing tab).
        .task {
            await viewModel.loadInitial()
            await projectVM.loadInitial()
        }
        .onChange(of: captureRequests.pendingVoiceRecord) { _, pending in
            if pending { handlePendingVoiceRecordRequest() }
        }
        .onChange(of: speechService.error) { _, error in
            speechErrorMessage = error?.localizedDescription
        }
        .modifier(JournalServiceErrorAlerts(
            speechService: speechService,
            cameraService: cameraService,
            speechErrorMessage: $speechErrorMessage
        ))
        .navigationBarHidden(true)
        .onChange(of: quickAction.pendingAction) { _, action in
            if let action { handleQuickAction(action) }
        }
        } // NavigationStack
    }

    /// Routes a Siri / shortcut action to the right capture surface.
    /// Extracted from `body`'s `.onChange(of: quickAction.pendingAction)`
    /// — keeps the body free of the inline switch and the early-return
    /// guard. Returns immediately for unrecognized actions.
    private func handleQuickAction(_ action: String) {
        quickAction.pendingAction = nil
        switch action {
        case "com.himem.app.voice-capture":
            activeCaptureModality = .voice
        case "com.himem.app.new-entry":
            // No specific modality — fall back to the typed-note path
            // as the safe default.
            activeCaptureModality = .note
        default:
            break
        }
    }

    /// Builds the entry-detail destination for a given UUID. The
    /// guard-let was inline in `body`'s `.navigationDestination(item:)`
    /// closure with all eight EntryExpandedView callbacks — that
    /// stacked CC inside the body for no decomposition win. Lifted
    /// into a `@ViewBuilder` so the body stays a one-liner.
    @ViewBuilder
    private func entryDetailDestination(for entryId: UUID) -> some View {
        if let entry = viewModel.currentEntry(id: entryId) {
            EntryExpandedView(
                entry: entry,
                backLabel: dateLabel(for: entry.createdAt),
                allTopics: viewModel.topics,
                cameraService: cameraService,
                speechService: speechService,
                onSave: { entryId, newContent, newTitle in
                    // Title-only save path from inline tap-to-edit.
                    // Tag/topic/media deltas have their own dedicated
                    // lifecycle calls now (ManagedChipEdit, ManageTopicsSheet,
                    // applyEditsImmediately) — we pass empty sets to
                    // `editEntry` for the legacy delta args.
                    viewModel.editEntry(
                        entryId: entryId,
                        newContent: newContent,
                        newTitle: newTitle,
                        removedTagIds: [],
                        removedMediaIds: [],
                        addedTopicNames: [],
                        removedTopicNames: []
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
        } else {
            // Hold the nav frame during the brief window where the
            // Core Data refresh hasn't repopulated `entries` after a
            // background save (typical: ProcessingEngine writes a new
            // OrganizePass → 250ms debounced `loadEntries` re-fetch).
            // Returning an implicit EmptyView here makes
            // `.navigationDestination(item:)` interpret the destination
            // as "no view for this id" and pop the stack — which also
            // tears down any sheet that was mid-presentation (the
            // Review-draft rises-then-recedes race the troika diagnosed
            // 2026-06-12). A placeholder Color keeps the destination
            // resolver happy until the entry returns.
            Color(Crucible.Color.paper)
                .ignoresSafeArea()
        }
    }


    private func dateLabel(for date: Date) -> String {
        Self.dateLabel(for: date, calendar: .current)
    }

    /// Pure label-formatter — hoisted as a static so the day-group
    /// header strings can be unit-tested without instantiating the
    /// view. CRAP audit Batch 1 (2026-05-28).
    static func dateLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        formatter.calendar = calendar
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
                            EntryCardView(entry: entry)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            // Swipe-to-delete and swipe-to-view both
                            // retired per `HiMem · Buttons & Actions §3`
                            // (June 12 2026). The card is a tap target;
                            // destruction lives inside the opened memory.
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntryId = entry.id }
                        }
                    } header: {
                        // Memories list spec §6 — Source Serif, quiet
                        // (orientation, not titles); opaque paper bg so
                        // sticky headers don't bleed card text through
                        // them mid-scroll.
                        HStack(spacing: 0) {
                            Text(group.label)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(Crucible.Color.ink2)
                                .tracking(-0.2)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Crucible.Color.paper)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                // Spec §8 — "The beginning · Your first memory, ‹month year›"
                // tail marker. The anti-doomscroll signal: the list is
                // finite and you've seen all of it. Only renders when
                // there are memories to anchor against.
                if let firstMonth = viewModel.firstMemoryMonthLabel,
                   !viewModel.filteredEntries.isEmpty {
                    BeginningMarker(firstMemoryMonthLabel: firstMonth)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            // Reload journal, nudge the watch to re-send any pending
            // clips (covers "watch was out of range"), AND re-broadcast
            // acks for every inbox clip so the watch can clear any
            // pending row whose original ack was lost. No-op when the
            // watch isn't reachable. Both watch-side handlers are
            // idempotent.
            viewModel.refresh()
            WatchSessionDelegate.shared.requestWatchPendingFlush()
            WatchSessionDelegate.shared.reconcileWatchAcks()
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
                Text("Your Memory Box is empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Tap the orange button in the bottom-right to capture your first memory — voice, photo, video, or text.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // errorBannerOverlay / undoToastOverlay / inboxBanner moved to
    // their own files in the CRAP audit 2026-05-28 (Batch 1):
    //   - Views/Journal/JournalErrorBanner.swift
    //   - Views/Journal/JournalUndoToast.swift
    //   - Views/Journal/JournalInboxBanner.swift

    // MARK: - Capture handlers (Append spec — capture-new path)

    /// Maps a CapturedItem from the FAB action stack to a new memory.
    /// One pill press = one new entry. Attach with multiple selections
    /// bundles them into a single new memory with all media on it.
    /// On success, navigates to the new memory's detail view so the user
    /// sees their contribution as the top item.
    private func handleCapturedItemForNewEntry(_ item: CapturedItem) {
        // Per-modality dispatch lives on `JournalCaptureCoordinator`
        // since the CRAP audit 2026-05-28 (Batch 5). The view holds
        // pendingNoteForNewEntry + selectedEntryId; the coordinator
        // composes the body and creates the memory.
        let coordinator = JournalCaptureCoordinator()
        let seed = pendingNoteForNewEntry
        let newId = coordinator.createNewMemory(
            from: item,
            viewModel: viewModel,
            seedNote: seed
        )
        // Clear the pending seed AFTER the successful create — only
        // when the dispatch case was `.note` would the coordinator
        // have consumed it; the bookkeeping is fine either way since
        // a non-note capture leaves the seed intact for the next
        // note attempt, and the success of `.note` resets it.
        if case .note = item, newId != nil {
            pendingNoteForNewEntry = nil
        }
        // Navigate into the new memory so the captured contribution
        // lands as the top item rather than dropping the user back
        // on Today. The slight dispatch lets the capture sheet
        // finish its dismiss animation first.
        if let newId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                selectedEntryId = newId
            }
        }
    }

    /// Tutorial #5 (Watch discovery). App-side gate per spec:
    /// `WCSession.isPaired && !isWatchAppInstalled && !hasSeen`. No
    /// permission, no system prompt — entirely the app's own UI on
    /// the app's own timing. Surfaced once on Today (this is Today,
    /// since JournalView is the landing surface), after onboarding
    /// (enforced by the orchestrator's `isArmed` gate which we just
    /// flipped above).
    ///
    /// **Suppression cases per spec:**
    /// - *Paired and installed* → user already has it. Skip.
    /// - *No watch paired* → never advertise hardware the user doesn't
    ///   own. Skip.
    /// - *Paired but app not installed* → THE discovery moment. Fire.
    private func attemptWatchDiscoveryTutorial() {
        let session = WCSession.default
        guard WCSession.isSupported() else { return }
        guard session.activationState == .activated else { return }
        guard session.isPaired else { return }
        guard !session.isWatchAppInstalled else { return }
        TutorialOrchestrator.shared.tryFire(.watchDiscovery)
    }
}

// MARK: - Body sub-modifiers

/// Stacks the two recoverable-error alerts driven by the speech
/// and camera services. Both share the same "OK / Open Settings"
/// shape, but each has its own underlying service. Extracted
/// from `JournalView.body` — CRAP audit 2026-06-07.
private struct JournalServiceErrorAlerts: ViewModifier {
    @ObservedObject var speechService: SpeechService
    @ObservedObject var cameraService: CameraService
    @Binding var speechErrorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("Couldn't record", isPresented: Binding(
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
            .alert("Couldn't open the camera", isPresented: Binding(
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
}

// MARK: - Header

struct JournalHeaderView: View {
    @Binding var viewMode: JournalView.ViewMode
    let onSearchTap: () -> Void
    let onSettingsTap: () -> Void
    /// Fires when the user taps the `?` glyph between search and
    /// settings. Routes to `TutorialsHubView` per `docs/design/
    /// screens-settings.jsx` → `ToolbarHelpDemo`. Defaulted so older
    /// callers still compile while the host wires it.
    var onHelpTap: (() -> Void)? = nil

    @ObservedObject private var entitlement = Entitlement.shared

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
                    isPlus: entitlement.isPlus,
                    size: 10
                )
                Spacer()
            }

            // Right: icons — warm ink per Memories list spec §9
            // ("Header chrome de-blued"). Density toggle retired with
            // the single-card model — see spec §2.
            HStack {
                Spacer()

                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                }
                .accessibilityLabel("Search")

                // The `?` opens the Tutorials hub. Warm-ink, never blue
                // — per spec, status/info glyphs in the toolbar share
                // the same quiet ink as search and settings; AI blue is
                // reserved for actions that invoke AI.
                if let onHelpTap {
                    Button(action: onHelpTap) {
                        Image(systemName: "questionmark.circle")
                            .font(.body)
                            .foregroundStyle(Crucible.Color.ink)
                    }
                    .accessibilityLabel("Tutorials")
                    .padding(.leading, 12)
                }

                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                }
                .accessibilityLabel("Settings")
                .padding(.leading, 12)
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

// MARK: - Beginning Marker (Memories list spec §8)

/// "The beginning · Your first memory, ‹month year›" — the anti-doomscroll
/// tail marker at the bottom of the Memories list. A Memory Box has a
/// bottom; reaching it should feel like arrival, not a spinner that gave up.
struct BeginningMarker: View {
    let firstMemoryMonthLabel: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Crucible.Color.hairline)
                .frame(width: 30, height: 1)
                .padding(.bottom, 14)
            Text("The beginning")
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Crucible.Color.ink2)
            Text("Your first memory, \(firstMemoryMonthLabel)")
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink3)
                .monospacedDigit()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .padding(.horizontal, 14)
    }
}

#Preview {
    JournalView()
}

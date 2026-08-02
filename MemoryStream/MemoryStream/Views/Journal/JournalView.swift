import SwiftUI
import UIKit
import WatchConnectivity

struct JournalView: View {
    @StateObject private var viewModel = JournalViewModel()
    @StateObject private var speechService = SpeechService()
    @StateObject private var cameraService = CameraService()
    @StateObject private var projectVM = ProjectViewModel()
    @ObservedObject private var errorState = ErrorState.shared
    /// F22 · the one fact this view reads before it claims to be empty.
    @ObservedObject private var firstImport = FirstImportState.shared
    /// F16 · drives the walkthrough ring on the row she just made.
    @ObservedObject private var walkthrough = WalkthroughOrchestrator.shared
    @EnvironmentObject private var quickAction: QuickActionState
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @State private var viewMode: ViewMode

    /// When true, `JournalHeaderView` hides its Memories/Projects
    /// segmented control — used by `HiMemTabView` where the tab bar
    /// is the mode switcher. Defaults to false so any pre-Phase-5
    /// callsite still shows the picker.
    private let hidesModeToggle: Bool

    init(initialMode: ViewMode = .memories,
         hidesModeToggle: Bool = false,
         learnPresented: Binding<Bool> = .constant(false)) {
        self._viewMode = State(initialValue: initialMode)
        self.hidesModeToggle = hidesModeToggle
        // F28 · defaulted so previews and any non-shell call site compile
        // unchanged; the shell always passes its own per-tab slot.
        self._learnPresented = learnPresented
    }

    /// The memory the walkthrough is pointing at, or nil.
    ///
    /// **Window = from creation to the end of the walkthrough** (F20a,
    /// 2026-07-31). It was originally scoped to step 3 only, which made the
    /// ring unreachable on the path people actually take: the View toast sends
    /// her from creation straight to Memory Detail, so she first sees the
    /// Memories list *after* `done`, by which point a step-scoped ring is long
    /// gone. Observed on device — "not highlighted at any point".
    ///
    /// The pointing was anchored to the step rather than to the moment she
    /// needs it. `walkthroughMemoryId` is set at creation and cleared in
    /// `finish()`, so keying off it gives exactly the right window and matches
    /// the promise `done` already makes: "You'll find it under Memories
    /// anytime."
    /// Tells the walkthrough its memory is visible in the list, so step 3 can
    /// re-anchor from the View toast to her ringed row. Guarded inside the
    /// orchestrator; safe to call repeatedly.
    private func announceIfWalkthroughRow(_ entry: EntryDisplayModel) {
        guard entry.id == walkthrough.walkthroughMemoryId else { return }
        walkthrough.memoriesListDidShowWalkthroughMemory()
    }

    private var walkthroughTargetId: UUID? {
        walkthrough.isRunning ? walkthrough.walkthroughMemoryId : nil
    }

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
    /// **F28 · owned by the shell** — see `HiMemTabView.learnOpenOn`. A
    /// tab-local flag survived a tab round-trip and re-presented the hub
    /// out of context.
    @Binding var learnPresented: Bool
    @ObservedObject private var inbox = InboxManifest.shared
    /// Set by `StartVoiceRecordingIntent` when Siri ("Record in
    /// HiMem") fires. Observed below to present the voice composer
    /// automatically. The composer auto-starts recording on appear,
    /// so flipping this flag is enough to land in mic-hot state.
    @ObservedObject private var captureRequests = CaptureRequestBus.shared
    /// Signals "open Memory Detail for this id" from the Clips →
    /// Sessions Create-one-memory flow. Only the memories-mode
    /// instance responds (guarded in the `.onChange` handler).
    @ObservedObject private var memoryNavigation = MemoryNavigationBus.shared
    /// Consumes topic read-chip navigation (memories instance only).
    @ObservedObject private var topicFilter = TopicFilterBus.shared
    /// Consumes mention read-chip navigation (memories instance only).
    @ObservedObject private var mentionFilter = MentionFilterBus.shared
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
                hidesModeToggle: hidesModeToggle,
                onSearchTap: { showSearch = true },
                onSettingsTap: { showSettings = true },
                onHelpTap: { learnPresented = true }
            )

            // Arrival banner retired 2026-07-10 per `CLAUDE.md` §Phone:
            // "banner retired — it predated the three-tab model, when
            // Captured Clips was a hidden window; now Clips is an
            // always-visible tab, so a banner pointing at it is
            // redundant chrome on the reflective Memories surface."
            // Arrival status now lives on the Clips tab bar item as
            // an ochre presence dot (see `HiMemTabView`).

            // Topic bar (shared across both modes)
            TopicTabBar(
                topics: viewModel.topics,
                selected: $viewModel.selectedTopic
            )
            .padding(.vertical, 4)

            // Mention filter banner (B4) — the visible indicator + clear
            // for a mention-chip-driven filter (there's no filter strip
            // for mentions). Memories mode only.
            if viewMode == .memories, let mention = viewModel.selectedMention {
                mentionFilterBanner(mention)
            }

            if viewMode == .projects {
                ProjectListView(
                    projectVM: projectVM,
                    selectedTopic: viewModel.selectedTopic,
                    viewModel: viewModel,
                    cameraService: cameraService,
                    speechService: speechService
                )
            } else {
                memoriesList
            }
        }
        .background(Crucible.Color.paper)

        // Capture FAB moved to HiMemTabView (2026-07-10 per
        // `HiMem · evidence and context.md:143` — capture floats on
        // every tab, in the same position). The tab-level host owns
        // the composer sheet and routes commits back to Clips.

        JournalErrorBanner()

        } // ZStack
        .navigationDestination(isPresented: $learnPresented) {
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
        // Captured Clips notification tap routes to the Clips tab per
        // spec v4 (no standalone modal). Same rule as the arrival
        // banner: deep-link into the tab, don't push a sheet.
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.openInboxNotification)) { _ in
            CaptureLandingBus.shared.pendingReturnToClips = true
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
            attemptSiriTutorial()

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
            //
            // Cold-launch Siri drain moved to HiMemTabView (owns the
            // tab-level capture flow now).
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
        // Siri `pendingVoiceRecord` observer moved to HiMemTabView
        // (owns the tab-level capture flow now).
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
        // Create-one-memory landing (`Himem · Memory Detail.html`
        // §Just created, July 12 2026): consume the bus signal
        // and push into `EntryExpandedView`. Only the memories-
        // instance responds; the projects-instance ignores. Reloads
        // the viewModel first so `entryDetailDestination(for:)` can
        // resolve the just-saved entry (Clips-tab viewModel and
        // this instance are separate `JournalViewModel`s — a save
        // in one doesn't refresh the other unless we ask).
        .onChange(of: memoryNavigation.pendingOpenMemoryId) { _, pending in
            guard let pending, viewMode == .memories else { return }
            viewModel.refresh()
            selectedEntryId = pending
            memoryNavigation.pendingOpenMemoryId = nil
        }
        // Topic read-chip navigation (unified associations read model):
        // a topic tapped on any opened memory routes here. Only the
        // memories instance consumes it — pop any pushed detail back to
        // the list, then set the filter (the same `selectedTopic` the
        // top strip drives). HiMemTabView has already switched the tab.
        .onChange(of: topicFilter.pendingTopicFilter) { _, pending in
            guard let pending, viewMode == .memories else { return }
            selectedEntryId = nil
            viewModel.selectedTopic = pending
            topicFilter.pendingTopicFilter = nil
        }
        // Mention read-chip navigation (B4). Memories instance only —
        // pop any pushed detail, set the mention filter (shows the banner).
        .onChange(of: mentionFilter.pendingMention) { _, pending in
            guard let pending, viewMode == .memories else { return }
            selectedEntryId = nil
            viewModel.selectedMention = pending
            mentionFilter.pendingMention = nil
        }
        } // NavigationStack
    }

    /// The mention-filter banner — visible indicator + clear for a
    /// mention-chip-driven Memories filter (B4). Per-type glyph + name.
    private func mentionFilterBanner(_ mention: MentionChip) -> some View {
        HStack(spacing: 8) {
            Image(systemName: mention.type.sfSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
            Text("Mentions of \(mention.name)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Crucible.Color.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                viewModel.selectedMention = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear mention filter")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Crucible.Color.wash1, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// Routes a Siri / shortcut action to the right capture surface.
    /// Extracted from `body`'s `.onChange(of: quickAction.pendingAction)`
    /// — keeps the body free of the inline switch and the early-return
    /// guard. Returns immediately for unrecognized actions.
    private func handleQuickAction(_ action: String) {
        quickAction.pendingAction = nil
        // Route shortcut modalities through the shared bus so the
        // tab-level HiMemTabView captureFlowHost presents them — that
        // way a shortcut invoked from any tab honors the "capture
        // returns to Clips" rule uniformly.
        switch action {
        case "com.himem.app.voice-capture":
            CaptureRequestBus.shared.pendingModality = .voice
        case "com.himem.app.new-entry":
            CaptureRequestBus.shared.pendingModality = .note
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
                }
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
    // handlePendingVoiceRecordRequest retired 2026-07-10 — HiMemTabView
    // owns the Siri drain (tab-level capture flow).

    // MARK: - Memories list

    /// The List of grouped memory entries. Mirrors the original inline
    /// layout: empty-state placeholder, grouped Sections, and a summary
    /// footer with the Recently-Deleted count. (Swipe actions retired —
    /// see the per-row comment below; the card is a tap target and
    /// destruction lives inside the opened memory.)
    private var memoriesList: some View {
        List {
            emptyMemoriesState

            if viewMode == .memories {
                ForEach(viewModel.groupedEntries) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            EntryCardView(entry: entry)
                            // F16 · she reached the list rather than the View
                            // toast. Swap step 3's anchor from the toast to her
                            // row. Per-row `onAppear` rather than a list-level
                            // one because a PreferenceKey does not propagate out
                            // of a `List` (device-only bug, 2026-07) — the row
                            // appearing IS the signal that it is on screen.
                            // F20b · `onAppear` fires when the row mounts. If the
                            // Memories list was already rendered behind the flow
                            // — the normal case — it fired long before the beat
                            // armed and never fires again, so the list-side
                            // anchor could not engage. Watch the beat as well:
                            // whichever happens second is the one that matters.
                            // `memoriesListDidShowWalkthroughMemory` no-ops
                            // unless step 3 is open, so both calls are safe.
                            .onAppear { announceIfWalkthroughRow(entry) }
                            .onChange(of: walkthrough.activeBeat) { _, _ in
                                announceIfWalkthroughRow(entry)
                            }
                            // F16 · the target identifies itself. The walkthrough
                            // overlay has no anchoring primitive (no
                            // anchorPreference / GeometryReader / spotlight), so
                            // rather than have a floating banner claim "your
                            // memory is in the list" and leave her guessing which
                            // row, the row she just made wears a ring while the
                            // walkthrough is pointing at it. Reuses the locked
                            // "selection = ring" affordance (`Crucible`
                            // accessibility rules) — no new vocabulary, no new UI.
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        Crucible.Color.accent,
                                        lineWidth: walkthroughTargetId == entry.id ? 2 : 0
                                    )
                                    .allowsHitTesting(false)
                            )
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
        // Clear the floating capture FAB so the last row (Memories and Projects
        // tab lists) doesn't run under it (device pass 2026-07-27). Matches the
        // 108pt FAB footprint clearance used on the Clips scroll + Memory Detail.
        .contentMargins(.bottom, 108, for: .scrollContent)
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

    /// F22 · one of the three surfaces that speak while the first import is
    /// running. A count of zero here is produced identically by "she has none"
    /// and "we haven't looked yet"; `FirstImportState` is the only thing that
    /// can tell them apart, and on a fresh install the wrong reading says
    /// *your memories are gone*.
    @ViewBuilder
    private var emptyMemoriesState: some View {
        if viewModel.filteredEntries.isEmpty {
            if !firstImport.mayAssertEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(FirstImportState.Copy.memoriesTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(FirstImportState.Copy.memoriesDetail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
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
        // Per `HiMem · evidence and context.md:143` (July 10 2026):
        // "capture returns to Clips … never to Memories and never
        // into a forced memory." So we do NOT navigate to the new
        // memory's detail; we surface the Clips tab so the user
        // sees where their thought landed.
        if newId != nil {
            CaptureLandingBus.shared.pendingReturnToClips = true
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

    /// Siri capture tutorial (#6) — discovery-triggered per
    /// `Tutorials · triggers spec.md` (July 5 2026): fires once on
    /// Today, after `memoryCount >= 3`, so the faster path only
    /// surfaces after the capture habit is established. Firing on
    /// day zero wastes the one-time fire. If both this and Watch
    /// discovery (#5) would collide, the orchestrator's
    /// one-per-session flag defers whichever loses to the next
    /// natural trigger.
    private func attemptSiriTutorial() {
        guard viewModel.entries.count >= 3 else { return }
        TutorialOrchestrator.shared.tryFire(.siri)
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
    var hidesModeToggle: Bool = false
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
            // Center: segmented toggle. Retired in HiMemTabView (Phase 5)
            // where the OS tab bar is the mode switcher; the segmented
            // control lives on for any legacy embed of JournalView.
            if !hidesModeToggle {
                Picker("", selection: $viewMode) {
                    ForEach(JournalView.ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

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

                // The `?` opens the Learn hub. Warm-ink, never blue
                // — per spec, status/info glyphs in the toolbar share
                // the same quiet ink as search and settings; AI blue is
                // reserved for actions that invoke AI. "Learn, not Help"
                // per Kingfisher · North Star — the label reads
                // "want to understand this?" not "something's wrong."
                if let onHelpTap {
                    Button(action: onHelpTap) {
                        Image(systemName: "questionmark.circle")
                            .font(.body)
                            .foregroundStyle(Crucible.Color.ink)
                    }
                    .accessibilityLabel("Learn")
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

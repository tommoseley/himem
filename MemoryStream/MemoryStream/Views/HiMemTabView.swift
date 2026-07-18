import SwiftUI
import CoreData

/// The three-tab root shell. Cold launch lands on Memories; the last-
/// used tab is remembered only while the app stays alive (`@State`,
/// not `@AppStorage`).
///
/// Per `HiMem · evidence and context.md:143` (locked 2026-07-10):
///
/// > "The three tabs share one chrome, and capture is on every one.
/// > The capture FAB floats on every tab, in the same position —
/// > capture is one tap from anywhere, per the perishability first
/// > principle; a tab where capture isn't one tap away fails the
/// > core promise. Capture returns to Clips (record → the thought
/// > lands as a new clip on the Clips bench), never to Memories and
/// > never into a forced memory."
///
/// So the FAB and capture-flow host live at THIS level, not inside
/// any one tab. Tapping the FAB from any tab presents the composer
/// sheet (no tab switch mid-record); on successful commit we route
/// through `CaptureLandingBus.pendingReturnToClips = true` so the
/// user lands on Clips.
struct HiMemTabView: View {

    enum Tab: Hashable {
        case clips
        case memories
        case projects
    }

    @State private var selection: Tab = .memories
    @State private var activeCaptureModality: CaptureModality? = nil
    /// Non-nil while the Clips status sheet is presented (Active
    /// Navigation Tap → sheet per `CLAUDE.md` §Phone, locked July 10
    /// 2026). Snapshot fields carried by the enum so the sheet reads
    /// the counts that were live the moment the user tapped, rather
    /// than a re-fetch after the sheet animation.
    @State private var clipsStatusSheet: ClipsStatusData? = nil
    @StateObject private var speechService = SpeechService()
    @ObservedObject private var captureLanding = CaptureLandingBus.shared
    @ObservedObject private var captureRequests = CaptureRequestBus.shared
    @ObservedObject private var coachmarks = CoachmarkOrchestrator.shared
    @ObservedObject private var inbox = InboxManifest.shared
    /// Reads which project (if any) the user is currently viewing —
    /// routes the Projects tab FAB per the July 10 context-aware
    /// lock (`CaptureLandingRouter`).
    @ObservedObject private var projectsNav = ProjectsNavigationContext.shared
    /// Non-nil while a Memory Detail (`EntryExpandedView`) is on
    /// screen. Suppresses the tab-shell FAB so it doesn't stack
    /// above the Memory Detail's own append FAB — the "two RABs"
    /// bug Tom hit July 11 2026.
    @ObservedObject private var memoryDetailPresence = MemoryDetailPresentationContext.shared
    /// Non-nil while a Clip Detail (`ClipDetailView`) is on screen.
    /// Suppresses the tab-shell FAB per `Clip model · spec.md`
    /// §Clip triage (July 12 2026): "No FAB on an opened clip —
    /// it's an opened item, not a capture surface."
    @ObservedObject private var clipDetailPresence = ClipDetailPresentationContext.shared
    /// Signals "open Memory Detail for this id" — the Create-one-
    /// memory flow (`CreateMemoryFromClipsSheet`) sets it after a
    /// successful save so the user lands on the freshly-created
    /// memory instead of the calm Clips list.
    @ObservedObject private var memoryNavigation = MemoryNavigationBus.shared
    /// Routes a topic read-chip tap (from any tab's Memory Detail) to the
    /// Memories tab's topic filter (unified associations read model).
    @ObservedObject private var topicFilter = TopicFilterBus.shared
    /// Routes a project read-chip tap to the Projects tab (opens the
    /// project detail there).
    @ObservedObject private var projectOpen = ProjectOpenBus.shared
    /// Set true when `pendingReturnToClips` fires; consumed by the
    /// next Clips coachmark evaluation so guardrail #3 ("suppress the
    /// Clips coachmark when arriving from a capture") holds. Cleared
    /// once the coachmark decision is made — subsequent neutral
    /// arrivals at Clips are eligible.
    @State private var justArrivedFromCapture = false

    /// Custom binding that intercepts every tab tap — including taps
    /// on the already-active tab, which SwiftUI's `$selection` handles
    /// by simply re-setting the same value. Repeat taps on the Clips
    /// tab fire the Active Navigation Tap behavior (status sheet); on
    /// other tabs today they're a no-op (spec allows their own status
    /// sheets later).
    private var selectionBinding: Binding<Tab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection && newValue == .clips {
                    clipsStatusSheet = ClipsStatusDataSource.snapshot()
                }
                selection = newValue
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: selectionBinding) {
                ClipsTabView()
                    .tabItem { Label("Clips", systemImage: "waveform") }
                    .tag(Tab.clips)
                // No native `.badge()` — SwiftUI TabView badges are red
                // (semantic danger in Crucible), and a red dot reads as
                // "something is wrong," not "something arrived." Per
                // `CLAUDE.md` §Phone (July 10 2026), the dot must sit
                // in ochre as presence-not-alert. The dot is drawn as
                // an overlay below.

                JournalView(initialMode: .memories, hidesModeToggle: true)
                    .tabItem { Label("Memories", systemImage: "book.closed") }
                    .tag(Tab.memories)

                JournalView(initialMode: .projects, hidesModeToggle: true)
                    .tabItem { Label("Projects", systemImage: "folder") }
                    .tag(Tab.projects)
            }
            // Nav selection is a user action → ochre. Blue is reserved
            // for AI moments (Kingfisher · North Star + crucible.css).
            .tint(Crucible.Color.accent)

            // FAB overlay — floats on every tab in the same position
            // per the July 10 lock, EXCEPT when a Memory Detail is
            // on screen (that view owns its own append FAB — see
            // `MemoryDetailPresentationContext`). The exact
            // affordance is chosen by `CaptureLandingRouter`: on
            // Projects at the list level + opens the New Project
            // sheet (no modality picker), on every other case +
            // opens the ad-hoc modality stack.
            if memoryDetailPresence.currentMemoryId == nil && clipDetailPresence.currentClipId == nil {
                switch currentIntent {
                case .openNewProjectSheet:
                    NewProjectFAB(onTap: {
                        NewProjectRequestBus.shared.request()
                    })
                case .createMemoryInProject:
                    // In-project FAB offers TWO paths (Projects · MVP spec
                    // §Surfaces): capture a new memory in this project (the
                    // modality stack) + "Add existing memory" (the leading
                    // pill → the search-to-add sheet, via the request bus).
                    AppendFAB(
                        onSelect: { modality in
                            activeCaptureModality = modality
                        },
                        accessibilityLabel: currentFabAccessibilityLabel,
                        leadingAction: AppendFABLeadingAction(
                            label: "Add existing memory",
                            systemImage: "folder.badge.plus",
                            onTap: { AddExistingMemoryRequestBus.shared.request() }
                        )
                    )
                case .dropOnBench, .createMemory:
                    AppendFAB(
                        onSelect: { modality in
                            activeCaptureModality = modality
                        },
                        accessibilityLabel: currentFabAccessibilityLabel
                    )
                }
            }

            // Ochre presence dot on the Clips tab item. Drawn as an
            // overlay so we avoid TabView's red native badge, which
            // reads as danger in Crucible. Positioned relative to the
            // Clips tab center (index 0 of 3, so `width/6`) and just
            // above the tab bar. Hit-testing off so it never blocks a
            // tap on the tab. Removed entirely when there are no
            // unseen arrivals.
            if inbox.hasUnseenArrivals {
                ClipsTabPresenceDot()
                    .allowsHitTesting(false)
            }
        }
        .captureFlowHost(
            activeModality: $activeCaptureModality,
            speechService: speechService,
            onCaptured: handleCapturedItem
        )
        .fullScreenCover(item: Binding(
            get: { coachmarks.visible },
            set: { newValue in
                if newValue == nil, let current = coachmarks.visible {
                    coachmarks.dismiss(current)
                }
            }
        )) { kind in
            CoachmarkView(kind: kind) {
                coachmarks.dismiss(kind)
            }
            .presentationBackground(.clear)
        }
        .sheet(isPresented: Binding(
            get: { clipsStatusSheet != nil },
            set: { presented in if !presented { clipsStatusSheet = nil } }
        )) {
            if let data = clipsStatusSheet {
                ClipsStatusSheet(data: data) {
                    clipsStatusSheet = nil
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Crucible.Color.paper)
            }
        }
        .onChange(of: captureLanding.pendingReturnToClips) { _, pending in
            if pending {
                justArrivedFromCapture = true
                selection = .clips
                captureLanding.pendingReturnToClips = false
            }
        }
        // Create-one-memory landing (`Himem · Memory Detail.html`
        // §Just created, July 12 2026): after
        // `CreateMemoryFromClipsSheet` saves, jump to the Memories
        // tab so `JournalView(initialMode: .memories)` can consume
        // the same signal and push into `EntryExpandedView`. The
        // bus id is deliberately NOT cleared here — the memories
        // `JournalView` clears it after routing so the tab switch
        // and the push don't race on nil.
        .onChange(of: memoryNavigation.pendingOpenMemoryId) { _, pending in
            if pending != nil {
                selection = .memories
            }
        }
        // Topic read-chip tapped on an opened memory → route to the
        // Memories tab so its JournalView can apply the topic filter
        // (unified associations read model). The id is NOT cleared here;
        // the memories JournalView clears it after applying the filter.
        .onChange(of: topicFilter.pendingTopicFilter) { _, pending in
            if pending != nil {
                selection = .memories
            }
        }
        // Project read-chip tapped on an opened memory → route to the
        // Projects tab so ProjectListView can push the project detail.
        // Id NOT cleared here; ProjectListView clears it after pushing.
        .onChange(of: projectOpen.pendingProjectId) { _, pending in
            if pending != nil {
                selection = .projects
            }
        }
        .onChange(of: selection) { _, newTab in
            evaluateCoachmark(for: newTab)
            // Clear the arrival dot on Clips per `CLAUDE.md` §Phone —
            // "the dot represents new, unseen arrivals and clears when
            // the user opens Clips."
            if newTab == .clips {
                InboxManifest.shared.markAllSeen()
            }
        }
        // Cold-launch onto Clips + arrivals while Clips is already
        // visible (July 12 2026 stuck-dot fix). The `.onChange(of:
        // selection)` above only fires on tab CHANGE — if the app
        // boots straight onto Clips or the user records via the
        // phone FAB while already on Clips (the July 10 lock:
        // "capture returns to Clips"), the selection doesn't
        // change and the dot never cleared. Observing the manifest
        // flag lets us clear the moment it flips true while the
        // user is looking at the bench.
        .onChange(of: inbox.hasUnseenArrivals) { _, hasUnseen in
            if hasUnseen && selection == .clips {
                InboxManifest.shared.markAllSeen()
            }
        }
        // Siri backward-compat: `StartVoiceRecordingIntent` still sets
        // `pendingVoiceRecord`. Route it through the shared modality
        // pipeline. Cold-launch case (Siri set the flag before the view
        // existed) is handled by the `.onAppear` drain below.
        .onChange(of: captureRequests.pendingVoiceRecord) { _, pending in
            if pending {
                captureRequests.pendingVoiceRecord = false
                activeCaptureModality = .voice
            }
        }
        .onAppear {
            // Cold-launch onto Clips: the `.onChange(of: selection)`
            // above only fires on a change, and cold-launch may init
            // `selection` straight to `.clips` (last-used tab). Clear
            // the arrival dot here so a boot straight into Clips
            // doesn't leave it stuck.
            if selection == .clips && inbox.hasUnseenArrivals {
                InboxManifest.shared.markAllSeen()
            }
            // Cold-launch session bump for the coachmark's "never on
            // first launch" guardrail (spec guardrail #4). Runs once
            // per cold launch — SwiftUI calls `onAppear` on the root
            // tab shell as the app boots.
            coachmarks.armSession()
            if captureRequests.pendingVoiceRecord {
                captureRequests.pendingVoiceRecord = false
                DispatchQueue.main.async { activeCaptureModality = .voice }
            }
            if let modality = captureRequests.pendingModality {
                captureRequests.pendingModality = nil
                DispatchQueue.main.async { activeCaptureModality = modality }
            }
            // Evaluate the coachmark for the cold-launch landing tab
            // (Memories by default). No-op on session 1 with no
            // content per the gate.
            evaluateCoachmark(for: selection)
        }
        // Any surface (App Shortcuts, other in-app triggers) can request
        // capture by setting `pendingModality`.
        .onChange(of: captureRequests.pendingModality) { _, modality in
            if let modality {
                captureRequests.pendingModality = nil
                activeCaptureModality = modality
            }
        }
    }

    /// Coachmark trigger dispatch per `Tutorials · triggers spec.md`
    /// §"Per-tab coachmark on first arrival." Applies the four
    /// guardrails via `CoachmarkOrchestrator.tryFire`.
    private func evaluateCoachmark(for tab: Tab) {
        let kind: CoachmarkOrchestrator.Kind
        switch tab {
        case .clips:    kind = .clips
        case .memories: kind = .memories
        case .projects: kind = .projects
        }
        let suppressed = (tab == .clips) && justArrivedFromCapture
        coachmarks.tryFire(
            kind,
            tabHasContent: tabHasContent(for: tab),
            suppressedByCaptureArrival: suppressed
        )
        // Consume the "just arrived from capture" flag after this
        // evaluation — the next arrival at Clips is neutral.
        if suppressed {
            justArrivedFromCapture = false
        }
    }

    /// Rough "is there anything to anchor to" check per guardrail #4.
    /// Returns true when the tab has enough content that a tour is
    /// meaningful. Doesn't need to be perfect — an over-shown
    /// coachmark is only shown once ever, and Skip is instant.
    private func tabHasContent(for tab: Tab) -> Bool {
        switch tab {
        case .clips:
            return !inbox.isEmpty
        case .memories:
            return coreDataCount(entityName: "JournalEntry") > 0
        case .projects:
            return coreDataCount(entityName: "Project") > 0
        }
    }

    private func coreDataCount(entityName: String) -> Int {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        req.resultType = .countResultType
        return (try? ctx.count(for: req)) ?? 0
    }

    /// Current FAB routing intent per `CaptureLandingRouter`. Reactive
    /// — recomputed on every render because both `selection` and
    /// `projectsNav.currentProjectId` are observed.
    private var currentIntent: CaptureLandingIntent {
        CaptureLandingRouter.route(
            tab: routerTab(for: selection),
            projectContext: projectsNav.currentProjectId
        )
    }

    /// Bridge `HiMemTabView.Tab` (SwiftUI-facing) to the router's
    /// tab identifiers.
    private func routerTab(for tab: Tab) -> CaptureLandingRouter.Tab {
        switch tab {
        case .clips:    return .clips
        case .memories: return .memories
        case .projects: return .projects
        }
    }

    /// Accessibility label for the ad-hoc-modality FAB. Distinct
    /// between Clips ("Add clip") and Memories ("Add memory") so
    /// VoiceOver users hear the actual outcome, not a generic +.
    private var currentFabAccessibilityLabel: String {
        switch currentIntent {
        case .dropOnBench:              return "Add clip"
        case .createMemory:             return "Add memory"
        case .createMemoryInProject:    return "Add memory to this project"
        case .openNewProjectSheet:      return "New project"
        }
    }

    /// Applies the routing intent to a completed `CapturedItem`. Per
    /// `CaptureLandingRouter` (July 10 lock) the destination depends
    /// on the tab the user was on when they tapped +. Photo/video/
    /// note/attach items on Clips land as unplaced `MediaReference`s;
    /// voice items land as `InboxClip`s. On Memories, the composer's
    /// output turns into a `JournalEntry`. On Projects (inside a
    /// project), same but with a project association.
    private func handleCapturedItem(_ item: CapturedItem) {
        switch currentIntent {
        case .dropOnBench:
            PhoneCaptureBenchDispatcher.dispatch(item)
            // "The new clip drops into the list already in view
            // (recognition, no navigation)" — no tab switch needed;
            // we're already on Clips. The manifest publish will
            // trigger `SessionListView` to re-render with the new
            // card in place.
            CaptureLandingBus.shared.pendingReturnToClips = true

        case .createMemory:
            let coordinator = JournalCaptureCoordinator()
            let lifecycle = EntryLifecycleService(
                storage: .shared,
                processingEngine: .shared
            )
            _ = coordinator.createNewMemory(
                from: item,
                lifecycle: lifecycle,
                seedNote: nil
            )
            // Stay on Memories — the user came here to build a memory,
            // not to be teleported to Clips.

        case .createMemoryInProject(let projectId):
            let coordinator = JournalCaptureCoordinator()
            let lifecycle = EntryLifecycleService(
                storage: .shared,
                processingEngine: .shared
            )
            let newEntryId = coordinator.createNewMemory(
                from: item,
                lifecycle: lifecycle,
                seedNote: nil
            )
            if let entryId = newEntryId {
                associate(entryId: entryId, withProject: projectId)
            }
            // Stay on the current project — the project was the
            // trigger, so keep the associative context in view.

        case .openNewProjectSheet:
            // Unreachable: FAB variant for this intent never emits a
            // CapturedItem; it opens the New Project sheet directly.
            break
        }
    }

    /// Attach a freshly-created memory to a project. Mirrors the
    /// `ProjectViewModel.addMemory` write pattern (`project.addToEntries`
    /// + `project.updatedAt = Date()`) so the two paths behave the
    /// same downstream (list ordering, assist re-eligibility).
    private func associate(entryId: UUID, withProject projectId: UUID) {
        let storage = StorageService.shared
        let ctx = storage.viewContext
        let entryReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        entryReq.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        entryReq.fetchLimit = 1
        let projectReq = NSFetchRequest<Project>(entityName: "Project")
        projectReq.predicate = NSPredicate(format: "id == %@", projectId as CVarArg)
        projectReq.fetchLimit = 1
        guard let entry = try? ctx.fetch(entryReq).first,
              let project = try? ctx.fetch(projectReq).first else { return }
        project.addToEntries(entry)
        project.updatedAt = Date()
        try? storage.save(context: ctx)
    }
}

/// 8pt ochre circle drawn above the Clips tab item — the presence-only
/// arrival dot per `CLAUDE.md` §Phone (July 10 2026): "the dot answers
/// 'should I look?' — presence, not a count." The `card`-colored ring
/// around it prevents the ochre from smearing into the tab-bar
/// background at small sizes.
///
/// Positioned with `GeometryReader` because `TabView.tabItem` gives us
/// no way to place chrome inside a specific item. Numbers below match
/// the iOS-26 system tab bar layout: three tabs of equal width, icon
/// centered above label, tab-bar height ~49pt content + safe-area
/// bottom inset.
private struct ClipsTabPresenceDot: View {
    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(Crucible.Color.accent)
                .overlay(
                    Circle().stroke(Crucible.Color.card, lineWidth: 1.5)
                )
                .frame(width: 8, height: 8)
                .position(
                    // Clips is index 0 of 3 → horizontal center at
                    // width/6. Offset ~10pt right so the dot sits at
                    // the top-right of the tab icon rather than dead
                    // center on it.
                    x: geo.size.width / 6 + 10,
                    // Vertical: the tab bar content area sits above
                    // the safe-area bottom inset by roughly 45pt.
                    // Placing the dot ~45pt above the safe-area bottom
                    // lines it up with the top edge of the tab icon.
                    y: geo.size.height - geo.safeAreaInsets.bottom - 45
                )
        }
        .accessibilityLabel("New arrivals in Clips")
    }
}

/// Session-scoped signal used by any capture surface (arrival banner,
/// notification tap, tab-level FAB) to request "return to Clips" per
/// `HiMem · evidence and context.md:143`. Not persisted; a fresh cold
/// launch always lands on Memories.
@MainActor
final class CaptureLandingBus: ObservableObject {
    static let shared = CaptureLandingBus()
    @Published var pendingReturnToClips: Bool = false
    private init() {}
}

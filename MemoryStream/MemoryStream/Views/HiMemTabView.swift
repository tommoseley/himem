import SwiftUI
import CoreData

/// The **two-tab** root shell — Memories · Projects. Cold launch lands on
/// Memories; the last-used tab is remembered only while the app stays alive
/// (`@State`, not `@AppStorage`).
///
/// **I1a (2026-09-17).** Clips retired as a user-facing surface, so the July 10
/// lock's second half — *"Capture returns to Clips (record → the thought lands
/// as a new clip on the Clips bench), never to Memories"* — is superseded: a
/// capture now lands in a memory. **Its first half survives untouched and is
/// why this file exists:**
///
/// > "The tabs share one chrome, and capture is on every one. The capture FAB
/// > floats on every tab, in the same position — capture is one tap from
/// > anywhere, per the perishability first principle; a tab where capture
/// > isn't one tap away fails the core promise."
///
/// So the FAB and capture-flow host still live at THIS level, not inside any
/// one tab. Tapping the FAB from any tab presents the composer sheet (no tab
/// switch mid-record), and the completed capture is routed by
/// `CaptureLandingRouter` without moving her anywhere.
struct HiMemTabView: View {

    /// **Two tabs (I1a, 2026-09-17).** `clips` retired with the surface it
    /// named. `ClipsTabView` and `SessionListView` remain ON DISK but
    /// UNREACHABLE — deliberately, and TEMPORARILY: a two-tab shell that can be
    /// reviewed on device and reverted in one commit is worth a short-lived
    /// decoy, before ~21,000 lines are deleted in I2. They go in that slice.
    enum Tab: Hashable {
        case memories
        case projects
    }

    @State private var selection: Tab = .memories
    @AppStorage("fabHandednessLeft") private var fabHandednessLeft = false
    @State private var activeCaptureModality: CaptureModality? = nil
    /// How the in-flight capture was initiated. `.handsFree` (Siri) lands the
    /// completed capture in a memory from every screen (F3). Set at each
    /// capture-initiation point; reset after the capture is handled.
    @State private var captureSource: CaptureSource = .manual
    @StateObject private var speechService = SpeechService()
    @ObservedObject private var captureLanding = CaptureLandingBus.shared
    @ObservedObject private var captureRequests = CaptureRequestBus.shared
    /// The landing intent decided when the user TAPPED the FAB, held
    /// across the capture flow. Nil for captures that never touched the
    /// FAB (Siri / hands-free), which fall back to a live route. See
    /// `beginCapture` for why completion-time routing was wrong (F25).
    @State private var pendingLanding: CaptureLandingIntent? = nil

    /// **The `in_peak == 0` capture gate's message**, non-nil while it is on
    /// screen (ruled 2026-08-02).
    ///
    /// Owned by the shell, deliberately. The gate has to be consulted for
    /// every landing — bench, new memory, and memory-in-project — and only
    /// this level sees all three. Wiring it into the Clips bench alone
    /// (where the saved-clip confirmation slot lives) would be an owner on
    /// one path and nothing on the other two: the `.measurement`-on-the-
    /// watch / literal-on-the-phone shape, and the memory landings are the
    /// more expensive loss precisely because they have no slot of their own.
    @State private var silentCaptureMessage: String? = nil

    /// **F28 · which tab, if any, currently has the Learn hub pushed.**
    ///
    /// Learn pushes onto each tab's own `NavigationStack` and a `TabView`
    /// keeps every tab alive, so a tab-local flag left the hub pushed
    /// while the user was on another tab and re-presented it on return —
    /// "out of context", because she had mentally left it. A tab cannot
    /// observe that the tab changed; this shell can, and clears it below.
    ///
    /// Deliberately a `Tab?` rather than one shared Bool: a single flag
    /// would push Learn onto every stack at once. Deliberately NOT a new
    /// ambient singleton either — that accumulation is exactly what F6
    /// names as the cost of "each locally reasonable call".
    @State private var learnOpenOn: Tab? = nil
    // F8 · guided walkthrough (do-it-with-me first run). Replaced the per-tab
    // coachmark cards, retired 2026-07-27 (F8 + F7c section-? cover the ground).
    @ObservedObject private var walkthrough = WalkthroughOrchestrator.shared
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
    @ObservedObject private var projectSummaryActions = ProjectSummaryActionsPresence.shared
    /// Signals "open Memory Detail for this id".
    @ObservedObject private var memoryNavigation = MemoryNavigationBus.shared
    /// Routes a topic read-chip tap (from any tab's Memory Detail) to the
    /// Memories tab's topic filter (unified associations read model).
    @ObservedObject private var topicFilter = TopicFilterBus.shared
    /// Routes a project read-chip tap to the Projects tab (opens the
    /// project detail there).
    @ObservedObject private var projectOpen = ProjectOpenBus.shared
    /// Routes a mention read-chip tap to the Memories tab's mention filter.
    @ObservedObject private var mentionFilter = MentionFilterBus.shared

    // The custom `selectionBinding` is GONE with the Clips status sheet.
    // It existed to intercept a repeat tap on the ACTIVE tab — which SwiftUI's
    // `$selection` treats as a no-op — so Clips could present its Active
    // Navigation Tap sheet. Memories and Projects keep their own sheets as a
    // decision (`CLAUDE.md` §Phone); neither has one built, so an interception
    // point with nothing to intercept is a speculative abstraction. `$selection`
    // is used directly; restore the wrapper when a surface actually needs it.

    var body: some View {
        // CRAP 2026-07-26: the observer cluster + presentation modifiers are
        // split off `body` — it was sitting exactly on the CC-30 critical line
        // (a tab shell hanging ~13 `.onChange` bus observers off one body; F2b's
        // `restorePending` observer was the latest nudge). Body is now the
        // layout + presentation; routing observers live in `tabRoutingObservers`.
        tabRoutingObservers(
            tabRootLayout
                .captureFlowHost(
                    activeModality: $activeCaptureModality,
                    speechService: speechService,
                    captureSource: captureSource,
                    onCaptured: handleCapturedItem
                )
        )
        // F8 · the guided walkthrough renders above the live tab content. Modal
        // beats block; action beats are a non-blocking banner so the real
        // control the user must tap stays live underneath.
        .overlay { WalkthroughOverlay() }
    }

    /// The tab shell's layout — TabView + context-aware FAB + presence dot.
    private var tabRootLayout: some View {
        // FAB anchor edge follows the Left-Handed FAB preference. The presence
        // dot self-positions (GeometryReader + `.position`) so it's unaffected;
        // the TabView fills. Only the FAB moves. See `FABHandedness`.
        ZStack(alignment: FABHandedness.containerAlignment(leftHanded: fabHandednessLeft)) {
            TabView(selection: $selection) {
                JournalView(initialMode: .memories, hidesModeToggle: true,
                            learnPresented: Binding(get: { learnOpenOn == .memories }, set: { learnOpenOn = $0 ? .memories : nil }))
                    .tabItem { Label("Memories", systemImage: "book.closed") }
                    .tag(Tab.memories)

                JournalView(initialMode: .projects, hidesModeToggle: true,
                            learnPresented: Binding(get: { learnOpenOn == .projects }, set: { learnOpenOn = $0 ? .projects : nil }))
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
            // The bench's multi-select suppression is gone with the bench:
            // `ClipsSelection` only ever reported selecting on Clips.
            if memoryDetailPresence.currentMemoryId == nil && clipDetailPresence.currentClipId == nil
                && !projectSummaryActions.actionsOnScreen {
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
                        onSelect: { modality in beginCapture(modality) },
                        accessibilityLabel: currentFabAccessibilityLabel,
                        leadingAction: AppendFABLeadingAction(
                            label: "Add existing memory",
                            systemImage: "folder.badge.plus",
                            onTap: { AddExistingMemoryRequestBus.shared.request() }
                        )
                    )
                case .dropOnBench, .createMemory:
                    AppendFAB(
                        onSelect: { modality in beginCapture(modality) },
                        accessibilityLabel: currentFabAccessibilityLabel
                    )
                }
            }

            // The capture gate's message, drawn at the shell so it reaches
            // whichever surface the capture landed on. Ruled placement:
            // where the saved-clip confirmation would have been — the same
            // bottom slot `CreationToast` occupies on the bench.
            //
            // 108pt is not a fresh guess: it is the clearance `ClipsTabView`
            // already reserves for "the FAB + tab pill" on its own content,
            // so this sits on the line the bench already treats as clear.
            // DEVICE-UNVERIFIED — the same class of constant as F26's 88pt
            // `bottomPinClearance`, and wrong either way is visible.
            if let message = silentCaptureMessage {
                SilentCaptureBanner(message: message) {
                    silentCaptureMessage = nil
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 108)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: silentCaptureMessage)
    }

    /// The cross-tab event-bus routing observers (+ the cold-launch `onAppear`),
    /// split off `body` in the 2026-07-26 CRAP pass — ~13 `.onChange` handlers,
    /// each individually trivial (route a bus signal to a tab selection or a
    /// capture modality) but collectively at the CC-30 line when inline.
    private func tabRoutingObservers(_ content: some View) -> some View {
        content
        // I3 · F26's Clips tab switch is GONE, and I1a removed the
        // `pendingReturnToClips` switch that followed it. Capture lands in a
        // memory from wherever she is, and the flow moves her nowhere.
        // F8 · the capture produced a memory — advance to step 2 and track the
        // memory so we can watch it organize below. I3: this one signal now
        // does what `clipDidLand()` + the `makeMemory` step used to.
        .onChange(of: memoryNavigation.justCreatedMemoryId) { _, newId in
            if let newId { walkthrough.memoryDidStart(id: newId) }
        }
        // F8 · watch the walkthrough's memory for organize completion (its
        // title + summary appearing). `lastOrganizedAt` isn't broadcast, so we
        // check on Core Data change. On Plus this fires ~at once; on Free after
        // the user taps Organize.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in
            // Free only: detect the organize pass finishing → advance to done. On
            // Plus the organize beat is a *confirmation* (organizeAlreadyDone) the
            // user taps through, so auto-advancing would skip step 4 — the exact
            // "I didn't see it happen" miss F10 exists to fix (Tom 2026-07-28).
            guard walkthrough.activeBeat == .organize, !walkthrough.organizeAlreadyDone,
                  let id = walkthrough.walkthroughMemoryId else { return }
            if walkthroughMemoryIsOrganized(id) { walkthrough.organizeDidComplete() }
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
        // **The arrival notification lands on Memories** (Tom, 2026-09-16).
        //
        // It used to deep-link to Clips, set from inside `JournalView` — tab
        // content reaching sideways to choose a tab. Which tab a tap lands on
        // is a shell concern, so it is owned here now, and Memories is the
        // only home left.
        //
        // **Deliberately NOT a memory.** She tapped a notification saying her
        // recording arrived; she did not ask to be put inside anything. The
        // July 10 no-teleport rationale — that moving her after a capture is
        // the magic, not reading the tab — applies equally to moving her after
        // a tap.
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.openInboxNotification)) { _ in
            selection = .memories
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
        // Mention read-chip tapped → route to Memories so its JournalView
        // applies the mention filter. Not cleared here; the memories
        // JournalView clears it after applying.
        .onChange(of: mentionFilter.pendingMention) { _, pending in
            if pending != nil {
                selection = .memories
            }
        }
        .onChange(of: selection) { _, newTab in
            // F28 · Learn does not survive a tab change. It is a reference
            // surface reached from a `?`, not a place the user was working;
            // leaving the tab is leaving it.
            learnOpenOn = nil
        }
        // Siri backward-compat: `StartVoiceRecordingIntent` still sets
        // `pendingVoiceRecord`. Route it through the shared modality
        // pipeline. Cold-launch case (Siri set the flag before the view
        // existed) is handled by the `.onAppear` drain below.
        .onChange(of: captureRequests.pendingVoiceRecord) { _, pending in
            if pending {
                captureRequests.pendingVoiceRecord = false
                captureSource = .handsFree // Siri → a memory of one part (F3)
                activeCaptureModality = .voice
            }
        }
        .onAppear {
            // F8's first-run offer was RETIRED 2026-08-23. This `.onAppear`
            // fires when the tab shell mounts — which on a fresh install is
            // BEHIND the intro tour, before it has been seen. Arming `.offer`
            // there put the walkthrough's invitation underneath a tour that
            // was still asking the same question. The tour is the invitation;
            // page 7 enters at beat 1 via `startAtFirstBeat()`.
            if captureRequests.pendingVoiceRecord {
                captureRequests.pendingVoiceRecord = false
                captureSource = .handsFree // Siri cold-launch → a memory of one part (F3)
                DispatchQueue.main.async { activeCaptureModality = .voice }
            }
            if let modality = captureRequests.pendingModality {
                captureRequests.pendingModality = nil
                // Same decision point as a FAB tap: pin the landing now,
                // while the navigation context is still whole (F25).
                DispatchQueue.main.async { beginCapture(modality) }
            }
        }
        // Any surface (App Shortcuts, other in-app triggers) can request
        // capture by setting `pendingModality`.
        .onChange(of: captureRequests.pendingModality) { _, modality in
            if let modality {
                captureRequests.pendingModality = nil
                beginCapture(modality)
            }
        }
    }

    /// True once the walkthrough's memory has an organize pass — its title +
    /// summary now exist. Drives the F8 `organize` → `done` advance (checked on
    /// Core Data change since `lastOrganizedAt` isn't broadcast).
    private func walkthroughMemoryIsOrganized(_ id: UUID) -> Bool {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let entry = try? StorageService.shared.viewContext.fetch(req).first else { return false }
        return entry.inferenceSummary != nil || entry.lastOrganizedAt != nil
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
        case .memories: return .memories
        case .projects: return .projects
        }
    }

    /// Accessibility label for the ad-hoc-modality FAB. Distinct
    /// between Clips ("Add clip") and Memories ("Add memory") so
    /// VoiceOver users hear the actual outcome, not a generic +.
    private var currentFabAccessibilityLabel: String {
        switch currentIntent {
        case .dropOnBench:
            // Unproducible: no tab routes here (I1a). Kept so the switch stays
            // exhaustive until I2 removes the case from `CaptureLandingIntent`.
            return "Add memory"
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
    /// Begin a FAB-initiated capture. **The landing intent is decided
    /// HERE, at tap time — not at completion.**
    ///
    /// F25: `handleCapturedItem` used to re-derive the destination from
    /// `projectsNav.currentProjectId` when the capture finished, and the
    /// capture flow itself destroys that value. The composer is hosted at
    /// the tab shell, above the Projects `NavigationStack`, and photo and
    /// video present as `fullScreenCover` — which removes the covered
    /// `ProjectDetailView` and fires its `.onDisappear`, calling
    /// `ProjectsNavigationContext.exit`. (That method's guard only
    /// protects against a *different* project's late disappear; when the
    /// same view is covered and uncovered the id matches and it clears.)
    /// So by completion the context was nil, the route fell to
    /// `.openNewProjectSheet`, and the item was dropped on the floor.
    ///
    /// Deciding at tap time is also what makes the fix cover attach,
    /// photo and video together: it does not depend on which
    /// presentation style clears what, only on reading the context while
    /// the user is demonstrably still inside the project.
    private func beginCapture(_ modality: CaptureModality) {
        captureSource = .manual // FAB = user-initiated
        pendingLanding = CaptureLandingRouter.route(
            tab: routerTab(for: selection),
            projectContext: projectsNav.currentProjectId,
            source: .manual
        )
        activeCaptureModality = modality
    }

    private func handleCapturedItem(_ item: CapturedItem) {
        // Prefer the intent captured when the user tapped the FAB (F25).
        // Fall back to a live route for captures that never touched the
        // FAB — Siri / hands-free — where `source == .handsFree` already
        // short-circuits to the bench regardless of the visible tab.
        let landing = pendingLanding ?? CaptureLandingRouter.route(
            tab: routerTab(for: selection),
            projectContext: projectsNav.currentProjectId,
            source: captureSource
        )
        defer {
            captureSource = .manual // reset for the next capture
            pendingLanding = nil
        }

        // **The `in_peak == 0` capture gate, consulted BEFORE the switch —
        // once, for every landing** (ruled 2026-08-02).
        //
        // Deliberately outside `switch landing`: a recording that heard
        // nothing is the same failure whether it lands on the bench or
        // becomes a memory, and the memory landings are where it costs
        // more. A reference inside one case would cover one path and
        // silently drop two, which is the shape `SilentCaptureGateTests`
        // exists to fail on.
        //
        // Only a voice session can be silent; a photo, video, note or
        // attach has no amplitude to judge — those leave any standing
        // message alone, because it is still true of the last recording.
        //
        // Assigned UNCONDITIONALLY for a voice session, `nil` included: a
        // message set on a silent capture and cleared only by hand would
        // still be standing after a later recording that worked. That is
        // the frozen-snapshot class (F24 D2, F25) — a correct value
        // rendered after it stopped being true.
        if case .voiceSession = item {
            silentCaptureMessage = SilentCaptureDecision.bannerMessage(for: speechService.lastCaptureSilence)
        }

        switch landing {
        case .dropOnBench:
            // **UNPRODUCIBLE AFTER I1a, AND MADE LOUD RATHER THAN TRUSTED.**
            // `.dropOnBench` came from one place — `tab == .clips` — and that
            // tab is gone; `.handsFree` stopped routing here at F3. So nothing
            // can reach this.
            //
            // "Unreachable" is precisely the claim that cost this project a P0
            // (F25, at `.openNewProjectSheet` below, where a `break` under a
            // FALSE unreachability comment silently destroyed captures). Same
            // treatment, same reason: DEBUG fails at the moment and place it
            // happens; Release falls back to the safest real landing rather
            // than dropping her recording.
            //
            // The fallback is `createMemory`, NOT the bench: the bench is
            // unreachable, so dispatching there would hide the capture instead
            // of losing it — which is worse, because it looks like success.
            assertionFailure(
                "CapturedItem reached .dropOnBench — no tab produces it after I1a."
            )
            createMemory(from: item)

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
            // Stay put. Moving her after a capture is the magic, not reading
            // the tab (July 10, and it survives the retirement intact).

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
            // This case previously read `break` under the comment
            // "Unreachable: FAB variant for this intent never emits a
            // CapturedItem." The comment was FALSE, and it is what made a
            // silent drop look safe — F25's whole defect arrived through
            // here. With the intent now captured at tap time it should
            // genuinely be unreachable, but "unreachable" is precisely the
            // claim that just cost us a P0, so it is made LOUD rather than
            // trusted.
            //
            // DEBUG: fail the assertion, at the moment and place it happens.
            // Release: land the capture in a memory rather than destroy it.
            // The bench was the escape hatch when this was written; with it
            // gone, a memory is the only place a capture can land and still
            // be found.
            assertionFailure(
                "CapturedItem reached .openNewProjectSheet — the landing intent was not captured at tap time (F25)."
            )
            createMemory(from: item)
        }
    }

    /// The safe landing every fallback uses. Extracted so the two
    /// "this should be unreachable" branches cannot drift apart from the real
    /// one — near-duplicate recovery procedures are how a fallback quietly
    /// stops matching what it is recovering to.
    private func createMemory(from item: CapturedItem) {
        let coordinator = JournalCaptureCoordinator()
        let lifecycle = EntryLifecycleService(storage: .shared, processingEngine: .shared)
        _ = coordinator.createNewMemory(from: item, lifecycle: lifecycle, seedNote: nil)
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


/// Session-scoped signal used by any capture surface (arrival banner,
/// notification tap, tab-level FAB) to request "return to Clips" per
/// `HiMem · evidence and context.md:143`. Not persisted; a fresh cold
/// launch always lands on Memories.
@MainActor
final class CaptureLandingBus: ObservableObject {
    static let shared = CaptureLandingBus()
    // `pendingReturnToClips` RETIRED with the tab it named (I1a). Its last
    // writer was `JournalView`'s post-create path, which set it under the July
    // 10 clause "capture returns to Clips … never to Memories" — a clause F3
    // had already contradicted by routing captures into memories. So this is a
    // CONTRADICTION RESOLVING, not a behaviour lost.
    private init() {}
}

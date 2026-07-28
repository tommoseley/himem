import SwiftUI
import CoreData
import UIKit

struct EntryExpandedView: View {
    let entry: EntryDisplayModel
    var backLabel: String = "Today"
    let allTopics: [String]
    let cameraService: CameraService
    @ObservedObject var speechService: SpeechService
    /// `(entryId, newContent, newTitle)`. Title-only path that the
    /// inline title tap-to-edit (`commitTitleEdit`) routes through.
    /// `newTitle == nil` means "leave the title alone"; an empty
    /// string clears it so `displayTitle` falls back to the
    /// AI/derived ladder. Tags / topics / media edits each have
    /// their own dedicated lifecycle paths now — they don't ride
    /// `onSave` anymore (the legacy 7-arg shape was retired with the
    /// pen-mode cleanup, June 11 2026).
    let onSave: (UUID, String, String?) -> Void
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var onAdjust: ((UUID, String) -> Void)? = nil
    /// One-shot commit of a batch of appends. Fires at most once per session.
    /// additionalContent: typed text + concatenated transcripts.
    /// mediaCaptures: staged photo/video/voice assets.
    var onCommit: ((UUID, String, [(localIdentifier: String, mediaType: MediaReference.MediaType)]) -> Void)? = nil
    var onRecycle: ((UUID) -> Void)? = nil
    /// Set when this Memory Detail was opened from inside a project.
    /// When non-nil, the bottom destruction button swaps from
    /// `Delete memory` to `Remove from project` per `Memory Detail ·
    /// unified editing model.md` line 109: "member memory → bottom
    /// **Remove from project** (memory survives)". The callback
    /// receives the entry id; the host wires the project context.
    var onRemoveFromProject: ((UUID) -> Void)? = nil
    /// Names the project for the "Remove from [project]" button (F2/F3).
    var projectContextName: String? = nil

    @Environment(\.dismiss) private var dismiss

    // Per-fragment editing state. The legacy global-edit-mode flip
    // (`mode: EntryViewMode = .reading/.editing`, `enterEditing`,
    // `cancelEditing`, `commitEdits`, staged `addedTopics`/
    // `removedTagIds`) was retired in the unified-editing pass per
    // `docs/design/Memory Detail · unified editing model.md`. Every
    // field now commits inline through its own dedicated tap-to-edit
    // path; this state cluster only retains things still consumed by
    // the live code (inline title draft, staged media deletes routed
    // through `applyEditsImmediately`, and the per-sheet target ids).
    @State private var editedTitle = ""
    @State private var removedMediaIds: Set<UUID> = []
    /// Memory Detail FAB · path 2: presents `AddExistingClipsSheet` to
    /// attach loose bench clips to this memory
    /// (`Memory Detail · unified editing model.md` §"Adding clips to a
    /// memory").
    @State private var showAddExistingClips = false
    /// True while the bottom "Let Go of this Memory" button is on screen.
    /// The append FAB hides so the full-width Delete owns the bottom-right
    /// — the same suppression rule the Clips multi-select FAB follows.
    /// Driven by the button's own `onAppear`/`onDisappear` (List calls
    /// these as rows enter/leave the viewport) — reliable, unlike
    /// `PreferenceKey`s emitted from inside a `List`, which don't
    /// propagate to ancestor `onPreferenceChange`.
    @State private var letGoOnScreen = false
    /// D5 · true while the Organize card is on screen. The append FAB steps
    /// aside for it exactly as it does for Let Go, so a scrolled-to Organize
    /// button isn't covered by the floating FAB (device pass 2026-07-27). Gated
    /// by `topAnchorVisible` too — a short memory keeps the FAB (see below).
    @State private var organizeOnScreen = false
    /// True while the zero-height top anchor is on screen — i.e. the body
    /// is at its resting top, not scrolled. Paired with `letGoOnScreen` /
    /// `organizeOnScreen` so the FAB only hides after a deliberate scroll.
    ///
    /// **Deliberate tradeoff — do NOT "fix" this into a hidden FAB (ruling
    /// 2026-07-27).** On a memory too short to scroll, the top anchor stays
    /// visible, so the FAB is KEPT even while Let Go / Organize are on screen.
    /// That accepts a corner overlap of the floating FAB over the bottom card
    /// on a tiny (one-short-clip) memory — the strictly lesser evil, because
    /// the FAB is the only add-clips affordance and hiding it here would strand
    /// it. The section reorder (clips above Organize) makes any memory with a
    /// real transcript scrollable, shrinking this to almost nothing. A future
    /// pass that hides the FAB on short memories to kill the overlap would
    /// re-strand the append path — that's a regression, not a fix.
    @State private var topAnchorVisible = true
    /// P8 Let Go split disclosure, computed once on appear (nil → the static
    /// footnote shows until it's ready).
    @State private var letGoSplitFootnote: String? = nil
    /// Non-nil while `PlaceClipSheet` is presented on top of this
    /// memory. Carries the clip id being relocated so the sheet can
    /// resolve the ref + wire "Remove from this memory" against this
    /// memory's edge. Per `Memory Detail · unified editing model.md:66`
    /// (July 5 2026): "Where does this belong?" from a clip's edit
    /// state opens the placement sheet with three destinations.
    @State private var relocatingClipId: UUID? = nil
    /// Slice 9 (Memory Detail Full stream convergence): the
    /// retired `PhotoDescriptionEditSheet` used to host the
    /// QuickLook viewer inside its own sheet. With inline
    /// description edit in `MediaCard`, the viewer moves up to
    /// this container. Non-nil while the QuickLook is presented
    /// over a photo tap. Video keeps its own `videoPlayerForItem`
    /// full-screen cover.
    @State private var photoViewerItem: MediaDisplayItem? = nil
    /// Non-nil while the full-screen video player is presented.
    /// Set when the user taps a video's play badge in the
    /// chronological capture stream. Pre-launch addition (Tom
    /// 2026-06-09): videos in the ubiquity container had a play-
    /// overlay glyph but tapping only opened the description
    /// sheet — no playback path existed.
    @State private var videoPlayerForItem: MediaDisplayItem? = nil
    @State private var showShareSheet = false
    @ObservedObject private var entitlement = Entitlement.shared

    // MARK: - Long-memory transcript mode (Tom 2026-06-09)
    // Source of truth: `docs/design/screens-memory-detail.jsx`
    // §"Long memory · Full ⇄ Compact". Mode + anchor are session-scoped
    // (process-lifetime), kept in `TranscriptModeSessionStore`. Short
    // memories pin to .full and never see the toggle.

    /// View mode for the transcript section. Synced to the session
    /// store on every change so a navigate-back-and-forth in the same
    /// session preserves the user's choice. Initialized to a safe `.full`;
    /// the threshold-driven default is applied in `.onAppear` so we have
    /// access to entry data without recomputing in init.
    @State private var transcriptMode: TranscriptMode = .full

    /// In Compact mode, the id of the one row currently expanded as a
    /// single-open accordion. Tapping a closed row sets this to its id;
    /// tapping the open row sets it back to nil. Photos/notes/voice
    /// rows all live in the same id space (the MediaReference id).
    @State private var transcriptOpenRowId: UUID? = nil

    // MARK: - Unified editing (Tom 2026-06-09)
    // Per `docs/design/Memory Detail · unified editing model.md`:
    // tap text → edit in place → save on commit. No global edit
    // mode — each text field manages its own focused state.

    /// True while the user is editing the summary in place. The
    /// section flips from a Text display to a TextEditor for the
    /// duration; commit writes through `EntryLifecycleService.updateSummary`
    /// which sets `JournalEntry.summaryUserEdited = true`.
    @State private var summaryIsEditing: Bool = false
    /// Draft buffer for the in-place summary edit. Initialized from
    /// `entry.renderedSummary` when editing begins; written to
    /// `JournalEntry.summary` on commit.
    @State private var summaryDraft: String = ""
    @FocusState private var summaryFieldFocused: Bool

    /// True while the user is editing the title in place. Tap text →
    /// `titleIsEditing = true` + focus the field; commit via Done in
    /// the inline `EditCommitBar` (tap-away is NOT an implicit commit
    /// per `Memory Detail · unified editing model.md` §"Committing an
    /// edit by weight").
    @State private var titleIsEditing: Bool = false
    @FocusState private var titleFieldFocused: Bool

    /// Drives the FAB-hide rule + "one edit at a time" rule from the
    /// unified editing spec. EntryExpandedView observes
    /// `editCoordinator.isAnyEditing` to hide the FAB; per-clip rows
    /// observe `editCoordinator.activeEditId` to commit-and-close
    /// when a different editor takes focus.
    @StateObject private var editCoordinator = TextEditCoordinator.shared

    /// True once `onAppear` has resolved `transcriptMode` from the
    /// session store / threshold default. Prevents the brief flash
    /// where a long memory would render Full for one frame before
    /// `onAppear` flips it to Compact.
    @State private var transcriptModeResolved = false

    private var transcriptClipCount: Int {
        TranscriptWordCount.clipCount(transcriptsAndNotes: entry.mediaItems)
    }
    private var transcriptWordCount: Int {
        TranscriptWordCount.count(transcriptsAndNotes: entry.mediaItems)
    }
    private var transcriptHeaderShown: Bool {
        TranscriptModeThreshold.headerShown(clipCount: transcriptClipCount)
    }

    /// Direct lifecycle reference for per-panel edit/delete operations on the
    /// chronological capture stream and for the Append spec's per-modality
    /// capture flows (which call lifecycle.append directly when the user
    /// finishes a pill capture).
    private let lifecycle = EntryLifecycleService()
    /// Owns activeCaptureModality + the per-modality dispatch that
    /// routes captured items to `lifecycle.append`. Extracted from
    /// this view in the CRAP audit 2026-05-28 (Batch 2) so the
    /// append-spec dispatch is unit-testable. The view still drives
    /// the modality binding (passed to AppendFAB) but the dispatch
    /// logic lives on the coordinator.
    @StateObject private var appendCoordinator = EntryAppendCoordinator()
    /// Drives the ManageTopicsSheet — the sole sheet still presented
    /// from this view. Was previously an enum with `.newTopic` and
    /// `.manageTopics` cases; the `.newTopic` case rode the dead
    /// `addTopicMenu` and went out with the cleanup.
    @State private var showManageTopics: Bool = false
    /// Drives the ManageProjectsSheet — the projects sibling of the topic
    /// manage sheet (unified associations, 2026-07-17), opened from the
    /// dashed Edit in the Projects read section.
    @State private var showManageProjects: Bool = false
    /// Drives the ManageMentionsSheet — the mentions sibling (B4 Phase 2),
    /// opened from the dashed Edit in the Mentions read section.
    @State private var showManageMentions: Bool = false
    // Memory Detail → unified Clip Editor modal (2026-07-16 cycle). The ✎ Edit
    // control in an expanded clip row opens the modal for that clip; the
    // long-memory read accordion (transcriptOpenRowId) is untouched. Editing
    // routes here, superseding the bespoke inline editors + AudioPlayerSheet.
    @State private var editingClip: ClipEditorModal.Source? = nil
    /// Drives in-place voice playback + the row's play/stop glyph (cycle 2/3).
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true
    @AppStorage("fabHandednessLeft") private var fabHandednessLeft = false
    /// The tab bar's contribution to this pushed page's bottom safe area.
    /// The tab-shell FABs (Clips/Memories/Projects) are `TabView` siblings, so
    /// SwiftUI never insets them for the tab bar — they anchor to the window's
    /// safe area and float over the bar. This page is `List` content inside the
    /// nav stack, so it DOES inherit the tab-bar inset and its append FAB sits
    /// one tab-bar-height too high. We subtract that inset from the FAB's anchor
    /// so it lands on the same edge as the tab-shell FABs. Measured (window
    /// bottom subtracted from this page's bottom inset) so it holds across
    /// devices/orientations rather than hardcoding a tab-bar height.
    @State private var tabBarInset: CGFloat = 0

    /// Topic names assigned to this memory. Was previously composed
    /// from `entry.topicNames` minus `removedTopics` plus `addedTopics` —
    /// that staging set rode the legacy global edit mode, which is gone.
    /// Topic changes now write straight through `ManageTopicsSheet`.
    private var currentTopics: [String] { entry.topicNames }

    /// Tab-bar height = this page's bottom inset minus the window's (home
    /// indicator). Zero if the window can't be read or there's no tab bar.
    private static func tabBarInset(pageBottom: CGFloat) -> CGFloat {
        let windowBottom = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
        return max(0, pageBottom - windowBottom)
    }

    var body: some View {
        // Append-FAB anchor edge follows the Left-Handed FAB preference. The
        // `List` fills; the FAB is the only bottom-anchored child, so only it
        // moves. See `FABHandedness`.
        ZStack(alignment: FABHandedness.containerAlignment(leftHanded: fabHandednessLeft)) {
        // Measure this page's bottom safe-area inset (includes the tab bar) and
        // subtract the window's (home-indicator only) to recover the tab-bar
        // height, so the append FAB can drop to the tab-shell FABs' edge. Read
        // off a stable full-bleed layer (not the FAB, which the offset moves)
        // to avoid a measure→offset feedback loop.
        Color.clear
            .allowsHitTesting(false)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { tabBarInset = Self.tabBarInset(pageBottom: proxy.safeAreaInsets.bottom) }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, v in
                        tabBarInset = Self.tabBarInset(pageBottom: v)
                    }
            })
        // Detail screen renders as a `List` (not a `ScrollView + VStack`)
        // so the chronological capture stream rows can use Apple's native
        // `.swipeActions`. List + native swipe is the only configuration
        // that coordinates scroll and swipe correctly — a `simultaneousGesture`
        // over a custom swipe modifier traps vertical drags before the
        // parent `ScrollView` can claim them.
        List {
            // Zero-height top anchor: its visibility is the "scrolled?"
            // signal for the append FAB's Let-Go suppression. On screen ⇒
            // body is at rest (short memory / top); off screen ⇒ scrolled
            // down. Invisible, no row chrome — purely a measurement seam.
            Color.clear
                .frame(height: 1)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .onAppear { topAnchorVisible = true }
                .onDisappear { topAnchorVisible = false }
            // Header rhythm per `AI Organize · spec.md §2c` and
            // `screens-topics.jsx` `ScrMemoryWithTopics`: title →
            // timestamp → summary → topic chip row. The topics row
            // sits *under* the summary — that's the spec's
            // "persistent home" for topics. Reorganize never touches
            // it; the chip row Edit affordance opens the dedicated
            // ManageTopicsSheet.
            headerRow { titleSection }
            headerRow {
                Text(fullTimestamp)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
            }
            headerRow { summarySection }
            headerRow(top: -3) { topicChipsRow }
            // Project-context row (F2/F3): "In [project]" membership chips
            // + a dashed "Edit" affordance. Always shown (like the topic
            // row) so a memory can always be filed; unified associations
            // read model (2026-07-17).
            headerRow(top: -3) { projectSection }
            // Section order (ruling 2026-07-27): title → summary → TOPICS →
            // PROJECTS → MENTIONS → PARTS (clips) → Organize → Let Go. The
            // spec's summary→topics adjacency (`AI Organize · spec.md` §"A
            // persistent home" — the derived layer reads as one block) is
            // preserved; the clip body sits AFTER the metadata sections, before
            // Organize. Supersedes the earlier clips-between-PROJECTS-and-
            // MENTIONS placement; the "content-first / clips-before-topics"
            // idea was withdrawn because it would split summary from topics.
            sectionRow { mentionsSection }
            // Transcript Full ⇄ Compact toggle heads the clip body (PARTS).
            // Hidden for short memories — the header disappears, the body still
            // renders fine without any eyebrow. D1: the clip body carries no
            // eyebrow and no `?` — it's the memory's content, self-evident, and
            // clip help lives one ✎-tap away in Edit Clip.
            if transcriptHeaderShown {
                sectionRow {
                    TranscriptHeaderControl(
                        clipCount: transcriptClipCount,
                        wordCount: transcriptWordCount,
                        mode: Binding(
                            get: { transcriptMode },
                            set: { newMode in
                                transcriptMode = newMode
                                TranscriptModeSessionStore.shared.set(newMode, for: entry.id)
                                // Switching modes collapses any open
                                // Compact row so the next entry into
                                // Compact starts clean.
                                if newMode == .full { transcriptOpenRowId = nil }
                            }
                        )
                    )
                }
            }
            bodyContent
            sectionRow {
                // Memory Detail AI zone — routes to Idle (no pass yet)
                // / Draft (unreviewed pass, B1 review sheet on tap) /
                // Organized (chip + body, optional stale banner).
                OrganizeMemorySection(
                    entryID: entry.id,
                    onOrganize: { triggerManualAIOrganize() }
                )
                // Pin SwiftUI identity to the entry id. Without an
                // explicit `.id`, the List's cell housing this view
                // can recycle across body re-evals (especially when
                // the parent's other rows update from the new
                // `OrganizePass`), which un-mounts and re-mounts
                // `OrganizeMemorySection`. Each re-mount destroys
                // the `@State activeSheet` AND orphans the
                // `.sheet(item:)`'s SwiftUI `PresentationHostingController`
                // in UIKit's tracking — that orphaned controller is
                // the "already presenting Z" UIKit reports on the
                // next presentation attempt. Pinning identity makes
                // SwiftUI preserve the view across body re-evals.
                .id(entry.id)
                // D5 · tell the FAB to step aside for the Organize card.
                .onAppear { organizeOnScreen = true }
                .onDisappear { organizeOnScreen = false }
            }
            sectionRow { inferenceCardSection }
            // Bottom Delete memory — the sole memory-delete path per
            // `HiMem · Buttons & Actions.html` §3 and `Memory Detail ·
            // unified editing model.md` (June 12 2026). Full-width red
            // button at the very end of the opened item; the scroll to
            // reach it *is* the deliberation, so no confirm. Recently
            // Deleted (30 days) is the safety net.
            sectionRow {
                // Per `screens-projects-views.jsx` §ScrProjectMemberOpen
                // (2026-07-09 update), a memory opened from within a
                // project surfaces BOTH fate actions at the bottom: the
                // recycle "Remove from [project]" (memory survives)
                // above the red "Delete memory" (destroys → Recently
                // Deleted). Memory opened outside a project shows only
                // Delete.
                VStack(spacing: 10) {
                    if let onRemoveFromProject {
                        BottomDeleteButton(kind: .removeFromProject(name: projectContextName)) {
                            onRemoveFromProject(entry.id)
                            dismiss()
                        }
                    }
                    BottomDeleteButton(
                        kind: .delete(noun: "memory"),
                        footnoteOverride: letGoSplitFootnote
                    ) {
                        onRecycle?(entry.id)
                        dismiss()
                    }
                    .onAppear {
                        letGoSplitFootnote = computeLetGoSplit()
                        // The Delete footer scrolled into view — yield the
                        // FAB's corner (gated by the scroll guard, so a
                        // short memory that shows Delete at rest keeps it).
                        letGoOnScreen = true
                    }
                    .onDisappear { letGoOnScreen = false }
                }
                .padding(.top, 24)
            }
            // Bottom inset so neither the floating append FAB NOR the tab bar
            // covers the last row (the Let Go footer). Two obstructions:
            //   • FAB — 60pt circle + 28pt bottom padding = 88pt, +20pt gap
            //     = 108pt (device pass 2026-07-26).
            //   • Tab bar — the append FAB is dropped onto the tab-bar edge via
            //     `-tabBarInset`, so the same measured height must be added or
            //     the footer clips under the tab pill (device pass 2026-07-27).
            Color.clear
                .frame(height: 108 + tabBarInset)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Crucible.Color.paper)
        // D4 · the one-time section-`?` coachmark, pinned below the nav bar;
        // non-blocking so the `?` glyphs underneath stay tappable.
        .overlay(alignment: .top) { CoachmarkBanner(coachmark: .sectionHelp) }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { leadingToolbar }
            ToolbarItem(placement: .navigationBarTrailing) { trailingToolbar }
        }
        .onAppear {
            editedTitle = entry.displayTitle
            migrateOrphanedContentIfNeeded()
            resolveTranscriptModeIfNeeded()
            // Signal that a Memory Detail is on screen so
            // `HiMemTabView` hides its tab-shell FAB. Without this
            // the shell FAB stacks above Memory Detail's own append
            // FAB — the "two RABs" bug (July 11 2026).
            MemoryDetailPresentationContext.shared.enter(memoryId: entry.id)
            // F8 · if this is the walkthrough's memory, arm the organize/done
            // beats now that Organize + the title/summary are on screen. On
            // Plus the auto-organize (processEntry) has usually already run, so
            // pass whether it's organized — the orchestrator skips straight to
            // the "that's a memory" beat rather than pointing at an Organize
            // control that isn't there.
            if WalkthroughOrchestrator.shared.walkthroughMemoryId == entry.id {
                // `inferenceSummary` is the display model's organized signal —
                // the AI-written title/summary. Non-nil ⇒ Plus already
                // auto-organized ⇒ skip the organize beat.
                WalkthroughOrchestrator.shared.memoryDidOpen(alreadyOrganized: entry.inferenceSummary != nil)
            }
            // D4 · introduce the section-`?` affordance once, after the
            // walkthrough (the guard no-ops during it and on later visits).
            OneShotCoachmark.sectionHelp.armIfEligible()
        }
        .onDisappear {
            MemoryDetailPresentationContext.shared.exit(memoryId: entry.id)
        }
        // Rule #6 — one edit at a time. When the coordinator's
        // `activeEditId` changes to something other than the title or
        // summary id while one of them is open, commit it. Mirrors
        // the same observer pattern used in VoiceClipPanel and
        // CompactClipRow so cross-editor jumps always commit, never
        // discard.
        .onChange(of: editCoordinator.activeEditId) { _, newId in
            if titleIsEditing && newId != "title" {
                commitTitleEdit()
            }
            if summaryIsEditing && newId != "summary" {
                commitSummaryEdit()
            }
        }
        .modifier(MediaFragmentEditorStack(
            photoViewerItem: $photoViewerItem,
            videoPlayerForItem: $videoPlayerForItem
        ))
        .sheet(item: $editingClip) { source in
            ClipEditorModal(source: source)
        }
        .sheet(isPresented: $showShareSheet) {
            let composed = "\(entry.displayTitle)\n\n\(entry.content)"
            ShareSheet(items: [composed])
        }
        .sheet(isPresented: $showManageTopics) {
            ManageTopicsSheet(entryID: entry.id, onDismiss: {
                showManageTopics = false
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showManageProjects) {
            ManageProjectsSheet(entryID: entry.id, onDismiss: {
                showManageProjects = false
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showManageMentions) {
            ManageMentionsSheet(entryID: entry.id, onDismiss: {
                showManageMentions = false
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: Binding(
            get: { relocatingClipId != nil },
            set: { presented in if !presented { relocatingClipId = nil } }
        )) {
            if let id = relocatingClipId,
               let ref = fetchRefForRelocate(id: id) {
                PlaceClipSheet(
                    ref: ref,
                    sourceMemoryId: entry.id,
                    onPlaced: {
                        // A relocate action ran — regenerate the memory's
                        // content since its clip set changed.
                        lifecycle.regenerateContent(forEntryId: entry.id)
                    }
                )
            }
        }
        // Memory Detail FAB · path 2 — add existing loose clips. The
        // sheet is pure selection; the attach runs here (host owns
        // `lifecycle`) via `attachExistingClips` — new edges in append
        // order, content regenerated, memory marked stale (offers
        // Reorganize), never auto-organized.
        .sheet(isPresented: $showAddExistingClips) {
            AddExistingClipsSheet { clipIds in
                let added = lifecycle.attachExistingClips(entryId: entry.id, clipIds: clipIds)
                if added > 0 {
                    // The clip set changed — refresh the Let Go split
                    // disclosure (some added clips may be used elsewhere).
                    letGoSplitFootnote = computeLetGoSplit()
                }
            }
        }
        // Capture-flow host attached to the List (NavigationStack-level
        // hosting controller), NOT the outer ZStack (`UIHostingController
        // <RootModifier>`). On iOS 26 the `UIPresentationController`-based
        // animator coordination adds a runloop tick after `viewDidDisappear`
        // before `_presentedViewController` clears. When `.captureFlowHost`
        // was on the ZStack, its sheets anchored to the same root UIKit
        // slot as `OrganizeMemorySection`'s `.sheet(item:)` — leftover
        // captures from a memory-creation voice flow would block the next
        // Review-draft presentation in that one-tick window (the
        // rise-and-fall bug the troika diagnosed June 13 2026). Moving
        // it inside the List re-routes capture-flow presentations to the
        // NavigationStack's hosting controller, eliminating the slot
        // collision.
        .captureFlowHost(
            activeModality: $appendCoordinator.activeCaptureModality,
            speechService: speechService,
            appendingTo: entry.displayTitle,
            onCaptured: { item in
                appendCoordinator.apply(
                    item,
                    to: entry.id,
                    using: lifecycle,
                    context: StorageService.shared.viewContext
                )
            }
        )

            // Append-spec FAB — pick a modality, capture, append to
            // this memory. Hidden during any active text edit per
            // `Memory Detail · unified editing model.md` §"Editing a
            // clip transcript — exact layout behavior" rule 3: the
            // FAB must never sit over the caret line. The
            // `editCoordinator` flips on any title/summary/transcript
            // edit; the FAB disappears until the edit commits or
            // cancels.
            if !editCoordinator.isAnyEditing && !((letGoOnScreen || organizeOnScreen) && !topAnchorVisible) {
                AppendFAB(
                    onSelect: { modality in
                        appendCoordinator.activeCaptureModality = modality
                    },
                    accessibilityLabel: "Add to memory",
                    // Path 2 (`Memory Detail · unified editing model.md`
                    // §"Adding clips to a memory"): the leading pill adds
                    // existing loose clips from the bench — the same
                    // stack shape the in-project FAB uses ("make new here,
                    // or add one you already have"). The capture modality
                    // stack below is path 1 (capture new into this memory).
                    leadingAction: AppendFABLeadingAction(
                        label: "Add existing clips",
                        systemImage: "tray.and.arrow.down",
                        onTap: { showAddExistingClips = true }
                    )
                )
                // Drop the FAB by the tab-bar inset so it lands on the same
                // edge as the tab-shell FABs (see `tabBarInset`).
                .padding(.bottom, -tabBarInset)
            }
        }
        // Overlap fix (`Memory Detail · unified editing model.md` §"Adding
        // clips to a memory"): the append FAB yields the bottom-right
        // corner to the full-width "Let Go of this Memory" button once the
        // user has scrolled to the destructive footer — the same
        // suppression rule the Clips multi-select FAB follows. Driven by
        // the Let Go button's and top anchor's `onAppear`/`onDisappear`
        // (see `letGoOnScreen` / `topAnchorVisible`), which List fires
        // reliably; the FAB `if` above drops it from the hierarchy.
        .animation(.easeInOut(duration: 0.18), value: letGoOnScreen)
        .animation(.easeInOut(duration: 0.18), value: organizeOnScreen)
        .animation(.easeInOut(duration: 0.18), value: topAnchorVisible)
    }

    // MARK: - Body sections (decomposed from var body)

    /// The persistent topic chip row — the "visible home" for topics
    /// per `AI Organize · spec.md §2c` and `screens-topics.jsx`
    /// `TopicRow`. Lives directly under the summary on every memory.
    ///
    /// Shape:
    /// - TOPICS eyebrow (small caps, ink3)
    /// - Inline ochre-dot chips on `wash1` background (`TopicChip(.set)`)
    /// - Persistent dashed-ochre **Edit** affordance — opens
    ///   `ManageTopicsSheet`. Always visible (not gated on edit mode)
    ///   so the user can manage topics deliberately, never as an AI
    ///   side effect.
    ///
    /// Status badge (for inferring/failed/etc.) moves below the chips
    /// — it's orthogonal to topics and shouldn't squat the topic row.
    private var topicChipsRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("TOPICS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Crucible.Color.ink3)
                SectionHelpButton(topic: .memoryTopics, size: 13)  // F7c
                Spacer(minLength: 0)
            }

            // Chips size to their content (no text wrapping) and
            // flow-wrap to a new row when the available width runs
            // out. `LazyVGrid(.adaptive)` was wrong here — it pinned
            // a fixed column width and the chip text wrapped inside.
            FlowLayout(spacing: 10) {
                ForEach(currentTopics, id: \.self) { topic in
                    // Unified associations read model (locked 2026-07-17):
                    // a read chip NAVIGATES to where the association lives
                    // — a topic → the Memories-list filter for that topic.
                    // Management moved to the one dashed **Edit** below (no
                    // longer tap-the-chip). Routing goes through the tab
                    // shell so it works from a member memory opened inside
                    // a Project too.
                    Button {
                        TopicFilterBus.shared.request(topic)
                    } label: {
                        TopicChip(label: topic, state: .set)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter memories by topic: \(topic)")
                }
                // "+ Add" affordance — dashed border = add/provisional
                // per the affordance vocabulary lock. Same sheet as
                // tapping a chip; the dashed border still signals
                // "add a new one" specifically (vs. "manage existing").
                addTopicAffordance
            }

            if let status = entry.displayStatus, entry.inferenceSummary == nil {
                HStack {
                    StatusBadge(text: status.text, style: status.style)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        // Hairline separator between Summary and TOPICS. 4pt
        // breathing room above the line (the summary sits closer
        // than the clips do above the mentions row, so it needs an
        // explicit buffer), then 8pt below before the eyebrow text.
        // Per Tom 2026-06-08.
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Crucible.Color.hairline)
                .frame(height: 0.5)
                .padding(.top, 4)
        }
    }

    /// Dashed-ochre **Edit** affordance — the ONE way into topic
    /// management (unified associations read model, 2026-07-17). Read
    /// chips now navigate (tap a topic → its filter), so add/remove is
    /// no longer tap-the-chip; this dashed Edit is the single entry to
    /// the manage sheet. The dashed border keeps its "add / manage"
    /// meaning per the affordance vocabulary lock.
    private var addTopicAffordance: some View {
        Button {
            showManageTopics = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Edit")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Crucible.Color.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle()) // edge-to-edge tap (dashed pill interior is transparent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit topics")
    }

    /// Projects read section (unified associations, 2026-07-17) — the
    /// sibling of the topic row. Navigable folder chips (tap → open the
    /// project) plus one dashed **Edit** that opens `ManageProjectsSheet`.
    /// Replaces the F2/F3 "In [project]" static chips + add-menu. Always
    /// shown so a memory can always be filed. The bottom "Remove from
    /// [project]" fate button (member-through-project) is unchanged — the
    /// one contextual exception to routing through the sheet.
    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("PROJECTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Crucible.Color.ink3)
                SectionHelpButton(topic: .memoryProjects, size: 13)  // F7c
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 10) {
                ForEach(entry.projectMemberships) { membership in
                    Button {
                        ProjectOpenBus.shared.request(membership.id)
                    } label: {
                        projectReadChip(membership.name)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open project: \(membership.name)")
                }
                editProjectsAffordance
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Crucible.Color.hairline)
                .frame(height: 0.5)
                .padding(.top, 4)
        }
    }

    /// A navigable project chip — folder glyph + name (glyph rule: dot =
    /// topic, folder = project). Tapping opens the project.
    private func projectReadChip(_ name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .semibold))
            Text(name)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Crucible.Color.ink2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(Crucible.Color.wash1, in: Capsule())
    }

    /// Dashed **Edit** — the one way into project management, matching the
    /// topic row's dashed Edit. Opens `ManageProjectsSheet` (on this
    /// memory / new project / from your library).
    private var editProjectsAffordance: some View {
        Button {
            showManageProjects = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Edit")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Crucible.Color.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle()) // edge-to-edge tap (dashed pill interior is transparent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit projects")
    }

    /// Title field swaps between an editable `TextField` and a read-mode
    /// `Text` that taps into editing. Unified editing model (Tom
    /// 2026-06-09): tap-to-edit fires a per-field `titleIsEditing`
    /// state instead of the legacy global `mode == .editing` flip, so
    /// the rest of the screen stays in "reading" while just the title
    /// is hot. Commit on focus loss or Return — no dismiss.
    @ViewBuilder
    private var titleSection: some View {
        if titleIsEditing {
            // Title editor in flow: TextField + inline Cancel/Done bar
            // directly beneath. Per `Memory Detail · unified editing
            // model.md` §"Committing an edit (accept / cancel) — by
            // weight": **anything that opens a full editing context
            // gets an explicit Cancel/Done anchored on the control**,
            // never a floating keyboard toolbar (that bug was called
            // out in the June-9 spec update). Tap-away is NOT an
            // implicit commit — user must hit Cancel or Done.
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $editedTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.ink)
                    .padding(10)
                    .background(Crucible.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1.5))
                    .focused($titleFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTitleEdit() }
                EditCommitBar(
                    onCancel: { cancelTitleEdit() },
                    onDone:   { commitTitleEdit() }
                )
            }
        } else {
            // Provenance lives in the Organized chip below — once a
            // suggestion is accepted, the field is the memory's, not
            // the AI's. No `✦ AI` tag here.
            Text(entry.displayTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Crucible.Color.ink)
                .contentShape(Rectangle())
                .onTapGesture { beginEditingTitle() }
        }
    }

    /// Accepted AI summary, rendered as a labelled block above the
    /// chronological capture stream. Honest Label principle: the
    /// `✦ AI` glyph + caption make the origin visible at a glance.
    /// Empty when the summary isn't accepted (or doesn't exist) —
    /// view collapses without taking layout space.
    ///
    /// Unified editing model (Tom 2026-06-09): tap the summary text →
    /// it flips to a TextEditor focused inline. Tap-away commits via
    /// `EntryLifecycleService.updateSummary` which writes the new
    /// text to `JournalEntry.summary` and flips
    /// `summaryUserEdited` to true. Empty content on commit clears
    /// the summary back to nil; the section then renders an empty
    /// placeholder until the next organize pass or another edit.
    @ViewBuilder
    private var summarySection: some View {
        if summaryIsEditing {
            summaryEditor
        } else if let summary = entry.renderedSummary {
            summaryReadable(summary)
        }
    }

    private var summaryEyebrow: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text("SUMMARY")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
        }
        .foregroundStyle(Crucible.Color.aiBlue)
    }

    @ViewBuilder
    private func summaryReadable(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            summaryEyebrow
            Text(summary)
                .font(.body)
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture { beginEditingSummary() }
    }

    @ViewBuilder
    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryEyebrow
            // `TextField(axis: .vertical)` matches the read view's
            // metrics 1:1 and auto-grows to fit the entire content —
            // a 6-line summary edits in a 6-line field, no internal
            // scrolling, no fixed-height clipping. Per the new spec
            // rule #7: edit field must mirror the read view's font,
            // line-height, weight, and width.
            TextField("", text: $summaryDraft, axis: .vertical)
                .font(.body)
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(3)
                .focused($summaryFieldFocused)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Crucible.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Crucible.Color.accent, lineWidth: 1)
                )
            EditCommitBar(
                onCancel: { cancelSummaryEdit() },
                onDone:   { commitSummaryEdit() }
            )
        }
        .padding(.top, 4)
    }

    private func beginEditingSummary() {
        summaryDraft = entry.renderedSummary ?? ""
        summaryIsEditing = true
        editCoordinator.begin(id: "summary")
        // Defer focus to the next runloop so the field is in the
        // hierarchy before the focus state asks for it.
        DispatchQueue.main.async {
            summaryFieldFocused = true
        }
    }

    private func commitSummaryEdit() {
        // Only persist if the text actually changed. Avoids writing
        // an identical value and (more importantly) avoids flipping
        // the `summaryUserEdited` marker when the user opens the
        // editor and immediately taps Done without typing.
        let trimmed = summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = entry.renderedSummary ?? ""
        if trimmed != current {
            lifecycle.updateSummary(entryId: entry.id, summary: trimmed)
        }
        summaryFieldFocused = false
        summaryIsEditing = false
        editCoordinator.end(id: "summary")
    }

    private func cancelSummaryEdit() {
        summaryDraft = ""
        summaryFieldFocused = false
        summaryIsEditing = false
        editCoordinator.end(id: "summary")
    }

    /// Toggles the title-edit layout WITHOUT the `List`'s implicit
    /// cell-resize animation. The title row changes height (read `Text`
    /// ⇄ `TextField` + commit bar); `List` animates that resize by
    /// default, and the adjacent topic-chip row reflows *through* the
    /// animation — its ochre dot renders at intermediate positions, the
    /// "floating dot" bug (Tom, 2026-07-18). Making the swap instant
    /// means no subview is ever caught in motion.
    private func setTitleEditing(_ editing: Bool) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { titleIsEditing = editing }
    }

    private func beginEditingTitle() {
        editedTitle = entry.displayTitle
        setTitleEditing(true)
        editCoordinator.begin(id: "title")
        DispatchQueue.main.async {
            titleFieldFocused = true
        }
    }

    private func commitTitleEdit() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleToSave: String? = (trimmed == entry.displayTitle) ? nil : trimmed
        if titleToSave != nil {
            onSave(entry.id, entry.content, titleToSave)
        }
        titleFieldFocused = false
        setTitleEditing(false)
        editCoordinator.end(id: "title")
    }

    private func cancelTitleEdit() {
        editedTitle = entry.displayTitle
        titleFieldFocused = false
        setTitleEditing(false)
        editCoordinator.end(id: "title")
    }

    /// Tappable location chip — variant E (Himem · Location.html). Pin
    /// glyph in accent, place name in ink, chevron implies tap. Tap opens
    /// Apple Maps centered on the entry's coordinates.
    @ViewBuilder
    private var locationChip: some View {
        if let name = entry.locationName, let lat = entry.latitude, let lon = entry.longitude {
            Button {
                openInMaps(name: name, latitude: lat, longitude: lon)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "mappin")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Crucible.Color.accent)
                    // Detail shows the full string — let it wrap to
                    // a second line rather than truncate.
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Crucible.Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Crucible.Color.ink3)
                        .padding(.leading, 2)
                }
                .padding(.leading, 10)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    /// Wraps a non-row view in a list row with the standard chrome — no
    /// separator, no row background, the same horizontal margin
    /// `ScrollView`-era used. Keeps the per-section view code identical
    /// to its pre-List form while letting the parent List context manage
    /// scrolling.
    @ViewBuilder
    private func sectionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    /// Tight variant of `sectionRow` for the v3 header block — title,
    /// topic chip, date line, and summary card. 1pt top/bottom by
    /// default so those four rows read as one continuous heading
    /// block while the rest of the page (clip stream, mentions,
    /// organize card, inference card) keeps the normal 8pt rhythm.
    ///
    /// `top` / `bottom` overridable so individual header rows can
    /// tighten further (e.g. the topic chip sits right under the
    /// title with a -3pt top to compensate for `Text`'s own descender
    /// padding).
    @ViewBuilder
    private func headerRow<Content: View>(
        top: CGFloat = 1,
        bottom: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }

    /// Body — every entry renders through ChronologicalCaptureStream
    /// post-FragmentMigration v2. Voice / note / image / video are all
    /// MediaReferences interleaved in createdAt order.
    ///
    /// Render paths:
    ///   1. No media fragments at all → plain `entry.content` text, as a
    ///      single list row. Covers pure-content entries the migration
    ///      didn't convert.
    ///   2. Has fragments → ChronologicalCaptureStream emits one List row
    ///      per fragment, each with its own native `.swipeActions`
    ///      (NotePanel for notes, VoiceClipPanel for voice, photo grid
    ///      for image/video clusters).
    ///
    /// Orphaned `entry.content` (text exists but no `.note` fragment
    /// covers it — left over from earlier code paths that wrote
    /// `entry.content` directly) gets auto-migrated into a real `.note`
    /// MediaReference in `.onAppear` via `migrateOrphanedContentIfNeeded`,
    /// so the user gets the full NotePanel UX without a separate
    /// inline-Text affordance.
    @ViewBuilder
    private var bodyContent: some View {
        if entry.mediaItems.isEmpty {
            sectionRow {
                Text(entry.content.attributedWithLinks())
                    .font(.body)
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(4)
            }
        } else {
            ChronologicalCaptureStream(
                entry: entry,
                onDeleteVoice: { id in
                    removedMediaIds.insert(id)
                    applyEditsImmediately()
                },
                onDeleteNote: { id in
                    deleteNoteFragment(id: id)
                },
                onDeleteMedia: { id in
                    removedMediaIds.insert(id)
                    applyEditsImmediately()
                },
                onRelocateClip: { id in
                    relocatingClipId = id
                },
                onOpenVoice: { item in
                    // Play IN PLACE (2026-07-16 cycle 2/3): the row's ▶ toggles
                    // playback through the audio session — no sheet. The modal
                    // (opened via ✎ Edit) is the full listen surface with the
                    // progress timeline; the row is quick sample-in-place.
                    let file = item.localIdentifier
                    if audioPlayer.isPlaying && audioPlayer.currentFile == file {
                        audioPlayer.stop()
                    } else {
                        audioPlayer.play(filename: file)
                    }
                },
                onCommitVoiceTranscript: { mediaId, newText in
                    lifecycle.updateMediaTranscript(
                        mediaId: mediaId,
                        transcript: newText,
                        entryId: entry.id
                    )
                },
                onCommitNoteText: { mediaId, newText in
                    lifecycle.updateNoteFragment(
                        id: mediaId,
                        text: newText,
                        entryId: entry.id
                    )
                },
                onPlayVideo: { item in
                    videoPlayerForItem = item
                },
                onViewPhoto: { item in
                    // Slice 9 (Memory Detail Full stream
                    // convergence): photo thumbnail tap opens the
                    // full-screen photo viewer over the memory. The
                    // description edit path is now inline inside
                    // `MediaCard` via `ClipEditor(field: .description)`
                    // — this callback owns consume only, matching Q3's
                    // edit-vs-consume separation. `PhotoViewerSheet`
                    // resolves the bytes itself (ubiquity or legacy
                    // PhotoKit), so this just hands off the item.
                    photoViewerItem = item
                },
                onCommitMediaDescription: { mediaId, newText in
                    updateMediaDescription(id: mediaId, text: newText)
                },
                onEditClip: { id in openClipEditor(id: id) },
                playingFilename: audioPlayer.isPlaying ? audioPlayer.currentFile : nil,
                mode: transcriptMode,
                openCompactRowId: transcriptOpenRowId,
                onToggleCompactRow: { rowId in
                    // Single-open accordion: tapping the open row closes
                    // it, tapping a different row replaces it.
                    transcriptOpenRowId = transcriptOpenRowId == rowId ? nil : rowId
                }
            )
        }
    }

    /// Resolves the transcript mode for this entry's first appearance
    /// inside this app session: prior session-store choice wins; falls
    /// back to the threshold-driven default. Idempotent — the
    /// `transcriptModeResolved` flag prevents re-applying the default
    /// after the user has manually toggled.
    fileprivate func resolveTranscriptModeIfNeeded() {
        guard !transcriptModeResolved else { return }
        transcriptModeResolved = true
        if let stored = TranscriptModeSessionStore.shared.mode(for: entry.id) {
            transcriptMode = stored
            return
        }
        transcriptMode = TranscriptModeThreshold.defaultMode(
            clipCount: transcriptClipCount,
            wordCount: transcriptWordCount
        )
    }

    /// On first detail view, mint a `.note` fragment for orphaned
    /// `entry.content` text so it renders through `NotePanel` with the
    /// same swipe-edit/delete affordances as every other fragment.
    /// Delegates to `EntryLifecycleService` so the guard logic is
    /// unit-tested — see `migrateOrphanedContentIfNeeded_*` tests for the
    /// "any `.note` fragment present → skip" rule that prevents
    /// duplicate-mint compounding on every open.
    private func migrateOrphanedContentIfNeeded() {
        lifecycle.migrateOrphanedContentIfNeeded(entryId: entry.id)
    }

    /// Fires AI processing for THIS entry on user tap. Assist
    /// consumption has already happened inside `OrganizeAIPanel` via
    /// `EntitlementService.tryConsumeAssist()` — this method only
    /// dispatches the actual processing pipeline. We look up the entry
    /// fresh from the view context so the background task gets a stable
    /// managed object reference.
    private func triggerManualAIOrganize() {
        let entryId = entry.id
        Task.detached {
            let ctx = await StorageService.shared.viewContext
            let request = JournalEntry.fetchOne(id: entryId)
            guard let journalEntry = try? await ctx.perform({ try ctx.fetch(request).first }) else {
                return
            }
            await ProcessingEngine.shared.processEntry(journalEntry)
        }
    }

    /// AI inference card — legacy display surface for entries that
    /// were processed before the `OrganizePass` schema existed.
    ///
    /// New passes write into `OrganizePass`, which the
    /// `OrganizeDoneSections(entryID:)` view above renders. To avoid
    /// duplicating output for entries that have both records, this
    /// card is wrapped in a `@FetchRequest` view that suppresses
    /// itself when a modern pass exists for the entry. Kept around
    /// only for entries created before the v2 pricing-design rebuild.
    @ViewBuilder
    private var inferenceCardSection: some View {
        if let inference = entry.inferenceSummary, entry.feedbackState == nil {
            LegacyInferenceCardSlot(entryID: entry.id) {
                InferenceCard(
                    summary: inference,
                    feedbackState: entry.feedbackState,
                    onFeedback: { state in onFeedback?(entry.id, state) },
                    onAdjust: { correction in onAdjust?(entry.id, correction) }
                )
            }
        }
    }

    /// Mentions section — the unified associations read model (B4 Phase 2,
    /// July 18 2026), the mentions sibling of the topic + project rows.
    /// Per-type-glyph navigable chips (tap → filter Memories by that
    /// mention) + one dashed **Edit** → `ManageMentionsSheet`. Replaces the
    /// retired inline `ManagedChipEdit` (✕-pill + free-text add). Always
    /// mounted so a memory can always gain mentions.
    @ViewBuilder
    private var mentionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("MENTIONS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(1.6)
                    .foregroundStyle(Crucible.Color.ink3)
                SectionHelpButton(topic: .memoryMentions, size: 13)  // F7c
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 10) {
                ForEach(entry.mentions) { mention in
                    Button {
                        MentionFilterBus.shared.request(mention)
                    } label: {
                        mentionReadChip(mention)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter memories by \(mention.type.label.lowercased()): \(mention.name)")
                }
                editMentionsAffordance
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Crucible.Color.hairline).frame(height: 0.5)
        }
    }

    /// A navigable mention chip — per-type line glyph + name (glyph rule:
    /// dot = topic, folder = project, per-type glyph = mention).
    private func mentionReadChip(_ mention: MentionChip) -> some View {
        HStack(spacing: 5) {
            Image(systemName: mention.type.sfSymbol)
                .font(.system(size: 11, weight: .semibold))
            Text(mention.name)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Crucible.Color.ink2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(Crucible.Color.wash1, in: Capsule())
    }

    /// Dashed **Edit** — the one way into mention management, matching the
    /// topic + project rows. Opens `ManageMentionsSheet`.
    private var editMentionsAffordance: some View {
        Button {
            showManageMentions = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Edit")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Crucible.Color.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle()) // edge-to-edge tap (dashed pill interior is transparent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit mentions")
    }

    // MARK: - Toolbar items (decomposed from var body)

    @ViewBuilder
    private var leadingToolbar: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                Text(backLabel)
            }
            .foregroundStyle(Crucible.Color.accent)
        }
        .accessibilityLabel("Back to \(backLabel)")
    }

    /// Trailing toolbar — Folder · Share. Per the unified editing model
    /// (June 12 2026 supersession): destruction is no longer a toolbar
    /// affordance. The bottom Delete memory button at the very end of
    /// the body is the sole memory-delete path.
    @ViewBuilder
    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            // The toolbar folder-plus is retired (unified associations,
            // 2026-07-17) — project add/remove now lives on the Projects
            // read section's dashed Edit → ManageProjectsSheet, the one
            // management path. Share only.
            Button { showShareSheet = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(Crucible.Color.ink2)
            }
            .accessibilityLabel("Share memory")
        }
    }

    // Append-spec dispatch moved to `EntryAppendCoordinator.apply`
    // in the CRAP audit 2026-05-28 (Batch 2). See
    // `Views/Journal/EntryAppendCoordinator.swift`.

    // MARK: - Attachment styling

    private func attachmentColor(for type: MediaReference.MediaType) -> Color {
        switch type {
        case .image: return Crucible.Color.Media.photo
        case .video: return Crucible.Color.Media.video
        case .voice: return Crucible.Color.Media.audio
        case .note:  return Crucible.Color.Media.text
        }
    }

    private func attachmentIcon(for type: MediaReference.MediaType) -> String {
        switch type {
        case .image: return "camera"
        case .video: return "video"
        case .voice: return "mic"
        case .note:  return "text.alignleft"
        }
    }

    private func attachmentLabel(for type: MediaReference.MediaType) -> String {
        switch type {
        case .image: return "Photo"
        case .video: return "Video"
        case .voice: return "Audio"
        case .note:  return "Note"
        }
    }

    /// T4 (checklist): memory meta shares the atom's reflective
    /// date shape — `Sun Jul 5 · 3:44 PM` (or `Sun Jul 5, 2025 ·
    /// 3:44 PM` when the date isn't the current year). Was
    /// `July 5 · 3:44 PM`, which collided with the clip header's
    /// `EEE MMM d` format on the same screen. Format string
    /// matches `ClipAtomProjections.formatDateTimePlace` so a
    /// spec change in one place is a spec change in both.
    private var fullTimestamp: String {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let entryYear = cal.component(.year, from: entry.createdAt)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = (entryYear == currentYear) ? "EEE MMM d" : "EEE MMM d, yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let dateStr = dateFormatter.string(from: entry.createdAt)
        let timeStr = timeFormatter.string(from: entry.createdAt)
        return "\(dateStr) · \(timeStr)"
    }

    private func openInMaps(name: String, latitude: Double, longitude: Double) {
        let coords = "\(latitude),\(longitude)"
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?q=\(encoded)&ll=\(coords)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Chronological capture stream helpers

    /// P8 last-reference disclosure (July 19 2026) — computed at open time
    /// (`onAppear`, into `letGoSplitFootnote`), splits this memory's *live*
    /// clips into "used elsewhere → stay" vs "only here → move to Recently
    /// Deleted." Fetches the managed entry (the view holds a value
    /// `EntryDisplayModel`) and mirrors the rule `EntryLifecycleService.recycle`
    /// applies (same `referencingMemoryCount`), so the footnote can't drift
    /// from what Let Go actually does. Discloses, never asks.
    private func computeLetGoSplit() -> String {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
        req.fetchLimit = 1
        guard let managed = try? ctx.fetch(req).first else {
            return BottomDeleteButton.letGoFootnote(stayCount: 0, moveCount: 0)
        }
        let clips = managed.mediaReferencesArray // excludes already-recycled
        let move = clips.filter { $0.referencingMemoryCount == 1 }.count
        let stay = clips.count - move
        return BottomDeleteButton.letGoFootnote(stayCount: stay, moveCount: move)
    }

    /// Removes a media reference immediately rather than batching it with
    /// title/content edits via the existing onSave path. Used by the
    /// chronological capture stream's per-panel delete.
    private func applyEditsImmediately() {
        let ids = removedMediaIds
        guard !ids.isEmpty else { return }
        // Delete always destroys per `Memory Detail · unified editing
        // model.md:66` — P8: soft to Recently Deleted (30-day net), not a
        // hard destroy. Remove-from-memory is a separate placement action
        // reached via "Where does this belong?".
        for id in ids {
            lifecycle.recycleClip(refId: id)
        }
        lifecycle.regenerateContent(forEntryId: entry.id)
        removedMediaIds = []
    }

    private func deleteNoteFragment(id: UUID) {
        lifecycle.recycleClip(refId: id)
        lifecycle.regenerateContent(forEntryId: entry.id)
    }

    /// Fetches the MediaReference by id for the placement sheet.
    /// PlaceClipSheet needs a concrete ref (not just an id) so its
    /// title branches on `referencingMemoryCount`.
    private func fetchRefForRelocate(id: UUID) -> MediaReference? {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? ctx.fetch(req).first
    }

    /// Opens the unified Clip Editor modal for the clip `id`, from the ✎ Edit
    /// affordance in an expanded row. Memory Detail clips are all placed
    /// (`.managed`); fetch the live `MediaReference` so the modal's Zone 2
    /// edges + delete branch on the real object.
    private func openClipEditor(id: UUID) {
        guard let ref = fetchRefForRelocate(id: id) else { return }
        editingClip = .managed(ref)
    }

    private func updateMediaDescription(id: UUID, text: String) {
        lifecycle.updateMediaDescription(mediaId: id, description: text, entryId: entry.id)
    }

    private func updateMediaTranscript(id: UUID, text: String) {
        lifecycle.updateMediaTranscript(mediaId: id, transcript: text, entryId: entry.id)
    }
}

// MARK: - Inline Add Toolbar

private struct InlineAddToolbar: View {
    let isRecording: Bool
    let onPhotoTap: () -> Void
    let onVideoTap: () -> Void
    let onAudioTap: () -> Void
    let onTextTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ToolbarIcon(
                kind: .audio,
                icon: isRecording ? "stop.fill" : "mic",
                label: isRecording ? "Stop" : "Audio",
                isActive: isRecording,
                action: onAudioTap
            )
            ToolbarIcon(kind: .text, icon: "pencil", label: "Text", isActive: false, action: onTextTap)
            ToolbarIcon(kind: .photo, icon: "camera", label: "Photo", isActive: false, action: onPhotoTap)
            ToolbarIcon(kind: .video, icon: "video", label: "Video", isActive: false, action: onVideoTap)
        }
        .padding(4)
        .background(Crucible.Color.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }
}

private enum InlineToolbarKind {
    case photo, video, audio, text

    var color: Color {
        switch self {
        case .photo: return Crucible.Color.Media.photo
        case .video: return Crucible.Color.Media.video
        case .audio: return Crucible.Color.Media.audio
        case .text: return Crucible.Color.Media.text
        }
    }
}

private struct ToolbarIcon: View {
    let kind: InlineToolbarKind
    let icon: String
    let label: String
    let isActive: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? .white : (disabled ? Crucible.Color.ink4 : kind.color))
                    .frame(width: 28, height: 28)
                    .background(isActive ? kind.color : Crucible.Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.clear : Crucible.Color.hairline, lineWidth: 1)
                    )

                Text(label)
                    .font(.caption2)
                    .fontWeight(isActive ? .bold : .medium)
                    .foregroundStyle(isActive ? kind.color : (disabled ? Crucible.Color.ink4 : Crucible.Color.ink2))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(isActive ? kind.color.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Inline Text Appender

private struct InlineTextAppender: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(Crucible.Color.ink)
                .frame(minHeight: 80)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Crucible.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1))
                .focused($focused)

            HStack {
                Button("Cancel", action: onCancel)
                    .font(.footnote)
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
                Button("Done", action: onCommit)
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(Crucible.Color.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 4)
        .onAppear { focused = true }
    }
}

// MARK: - Pending Staging Section

private struct PendingStagingSection: View {
    let typedText: String
    let transcripts: [String]
    let media: [(localIdentifier: String, mediaType: MediaReference.MediaType)]
    let isRecording: Bool
    let onRemoveMedia: (Int) -> Void
    let onRemoveTranscript: (Int) -> Void
    let onClearTypedText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PENDING")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(Crucible.Color.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Crucible.Color.Media.audio)
                        .frame(width: 8, height: 8)
                    Text("Recording...")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Crucible.Color.Media.audio)
                }
            }

            // Transcripts (body text, not tiles)
            ForEach(Array(transcripts.enumerated()), id: \.offset) { index, transcript in
                HStack(alignment: .top) {
                    Text(transcript)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(3)
                    Spacer()
                    Button { onRemoveTranscript(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove transcript")
                }
            }

            let trimmedTyped = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTyped.isEmpty {
                HStack(alignment: .top) {
                    Text(trimmedTyped)
                        .font(.footnote)
                        .foregroundStyle(Crucible.Color.ink)
                        .lineSpacing(3)
                    Spacer()
                    Button(action: onClearTypedText) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Crucible.Color.ink4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear typed text")
                }
            }

            // Media tile grid
            if !media.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                        MediaTile(
                            localIdentifier: item.localIdentifier,
                            mediaType: item.mediaType,
                            onRemove: { onRemoveMedia(index) }
                        )
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

// PendingMediaRow and PendingMediaThumbnail retired — replaced by MediaTile grid

// MARK: - Commit Footer

private struct CommitFooter: View {
    let pendingItemCount: Int
    let onCommit: () -> Void

    var body: some View {
        Button(action: onCommit) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.subheadline.bold())
                Text("Attach \(pendingItemCount) item\(pendingItemCount == 1 ? "" : "s")")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Crucible.Color.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

// MARK: - Body sub-modifiers

/// Media-fragment edit sheets that ride on top of every
/// EntryExpandedView. Audio → transcript editor; photo/video →
/// description editor; video → full-screen player. Note-fragment
/// edits are inline now (NotePanel tap-to-edit); the legacy
/// `NoteEditorSheet.swift` was deleted 2026-06-11 once its last
/// caller went away. Follows the unified edit-sheet template
/// (`docs/design/HiMem · Edit Sheet.html` June 2026). Extracted from
/// `EntryExpandedView.body` so the body stops owning their wiring
/// directly — CRAP audit 2026-06-07.
private struct MediaFragmentEditorStack: ViewModifier {
    /// Slice 9 (Memory Detail Full stream convergence):
    /// `PhotoDescriptionEditSheet` retired. Photo + video consume both
    /// present a full-screen viewer on black with a standard dismiss
    /// (tap · swipe-down · ✕) — `PhotoViewerSheet` replaces the bare
    /// `QuickLookViewer`, which showed no dismiss chrome in a SwiftUI
    /// sheet (device bug, 2026-07-21). (Voice playback + transcript edit
    /// moved to the unified modal / inline row play — AudioPlayerSheet
    /// retired 2026-07-17.)
    @Binding var photoViewerItem: MediaDisplayItem?
    @Binding var videoPlayerForItem: MediaDisplayItem?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $photoViewerItem) { item in
                PhotoViewerSheet(item: item)
            }
            .fullScreenCover(item: $videoPlayerForItem) { item in
                VideoPlayerSheet(item: item)
            }
    }
}


import SwiftUI

/// Identifies the voice tile a user tapped, so the AudioPlayerSheet can be
/// presented via SwiftUI's `sheet(item:)` API. `mediaId` is the
/// MediaReference id (so the sheet's transcript edit can save back to the
/// right ref); `filename` is the audio file path; `recordedAt` is shown as
/// a header timestamp; `transcript` is the per-clip transcript (nil for
/// legacy voice refs from before the schema gained the field, in which
/// case the sheet falls back to entry.content).
struct AudioPlayerTarget: Identifiable {
    let mediaId: UUID?
    let filename: String
    let recordedAt: Date?
    let transcript: String?
    var id: String { filename }
}

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
    var onAddToProject: ((UUID, UUID) -> Void)? = nil  // entryId, projectId
    /// Set when this Memory Detail was opened from inside a project.
    /// When non-nil, the bottom destruction button swaps from
    /// `Delete memory` to `Remove from project` per `Memory Detail ·
    /// unified editing model.md` line 109: "member memory → bottom
    /// **Remove from project** (memory survives)". The callback
    /// receives the entry id; the host wires the project context.
    var onRemoveFromProject: ((UUID) -> Void)? = nil
    var availableProjects: [ProjectDisplayModel] = []

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
    @State private var selectedMedia: MediaDisplayItem? = nil
    /// Non-nil while the full-screen video player is presented. Set
    /// when the user taps a video in the chronological capture stream
    /// (photos still open `PhotoDescriptionEditSheet` via
    /// `selectedMedia`). Pre-launch addition (Tom 2026-06-09): videos
    /// in the ubiquity container had a play-overlay glyph but tapping
    /// only opened the description sheet — no playback path existed.
    @State private var videoPlayerForItem: MediaDisplayItem? = nil
    @State private var audioPlayerForFile: AudioPlayerTarget? = nil
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
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true

    /// Topic names assigned to this memory. Was previously composed
    /// from `entry.topicNames` minus `removedTopics` plus `addedTopics` —
    /// that staging set rode the legacy global edit mode, which is gone.
    /// Topic changes now write straight through `ManageTopicsSheet`.
    private var currentTopics: [String] { entry.topicNames }

    /// Mentions to render in the always-visible mentions row. Used to
    /// filter out staged `removedTagIds`; deletion now writes directly
    /// to Core Data through `ManagedChipEdit`'s ✕ → `lifecycle.removeMention`,
    /// so the list is just the entry's tags.
    private var visibleTags: [TagDisplayModel] { entry.tags }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        // Detail screen renders as a `List` (not a `ScrollView + VStack`)
        // so the chronological capture stream rows can use Apple's native
        // `.swipeActions`. List + native swipe is the only configuration
        // that coordinates scroll and swipe correctly — a `simultaneousGesture`
        // over a custom swipe modifier traps vertical drags before the
        // parent `ScrollView` can claim them.
        List {
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
            // Transcript Full ⇄ Compact toggle sits between the topic
            // chips row and the chronological body. Hidden for short
            // memories — the section header itself disappears, the
            // body still renders fine without any eyebrow.
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
            // Mentions promoted out of the previous bottom expander
            // (was after OrganizeMemorySection / inferenceCardSection)
            // and rendered as an always-visible row between the
            // chronological capture stream and the Organized · review
            // card. Spec: `docs/Memory Detail/screens-memory-detail.jsx`.
            sectionRow { mentionsSection }
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
            }
            sectionRow { inferenceCardSection }
            // Bottom Delete memory — the sole memory-delete path per
            // `HiMem · Buttons & Actions.html` §3 and `Memory Detail ·
            // unified editing model.md` (June 12 2026). Full-width red
            // button at the very end of the opened item; the scroll to
            // reach it *is* the deliberation, so no confirm. Recently
            // Deleted (30 days) is the safety net.
            sectionRow {
                if let onRemoveFromProject {
                    BottomDeleteButton(kind: .removeFromProject) {
                        onRemoveFromProject(entry.id)
                        dismiss()
                    }
                    .padding(.top, 24)
                } else {
                    BottomDeleteButton(kind: .delete(noun: "memory")) {
                        onRecycle?(entry.id)
                        dismiss()
                    }
                    .padding(.top, 24)
                }
            }
            // Bottom inset so the floating Contribute FAB doesn't cover the
            // last row.
            Color.clear
                .frame(height: 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Crucible.Color.paper)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { leadingToolbar }
            ToolbarItem(placement: .navigationBarTrailing) { trailingToolbar }
        }
        .onAppear {
            editedTitle = entry.displayTitle
            migrateOrphanedContentIfNeeded()
            resolveTranscriptModeIfNeeded()
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
            audioPlayerForFile: $audioPlayerForFile,
            selectedMedia: $selectedMedia,
            videoPlayerForItem: $videoPlayerForItem,
            legacyTranscriptFallback: entry.content,
            onSaveAudioTranscript: { mediaId, newText in
                if let mediaId {
                    updateMediaTranscript(id: mediaId, text: newText)
                } else {
                    // Legacy voice entry — transcript IS entry.content.
                    // Persist through lifecycle.edit so search +
                    // inference re-derive from the new text.
                    lifecycle.edit(entryId: entry.id, newContent: newText)
                }
            },
            onSaveMediaDescription: { mediaId, newText in
                updateMediaDescription(id: mediaId, text: newText)
            },
            onDeleteMedia: { mediaId in
                lifecycle.deleteMediaReferences(ids: [mediaId])
                lifecycle.regenerateContent(forEntryId: entry.id)
            }
        ))
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
            if !editCoordinator.isAnyEditing {
                AppendFAB(
                    onSelect: { modality in
                        appendCoordinator.activeCaptureModality = modality
                    },
                    accessibilityLabel: "Add to memory"
                )
            }
        }
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
            Text("TOPICS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Crucible.Color.ink3)

            // Chips size to their content (no text wrapping) and
            // flow-wrap to a new row when the available width runs
            // out. `LazyVGrid(.adaptive)` was wrong here — it pinned
            // a fixed column width and the chip text wrapped inside.
            FlowLayout(spacing: 10) {
                ForEach(currentTopics, id: \.self) { topic in
                    // Per the unified-editing model (Tom 2026-06-09),
                    // tap any topic chip → ManageTopicsSheet. The
                    // dedicated "+ Edit" pill is retired; the entry
                    // gesture is now tap-on-chip itself, exactly the
                    // same gesture that's now used everywhere else in
                    // the app for metadata management.
                    Button {
                        showManageTopics = true
                    } label: {
                        TopicChip(label: topic, state: .set)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manage topic: \(topic)")
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

    /// Dashed-ochre **+ Add** affordance — opens the topic management
    /// sheet for adding a new topic. Per the unified-editing model
    /// (Tom 2026-06-09), the dashed border still means
    /// "add / provisional" per the affordance vocabulary lock; what
    /// changed is the label from "+ Edit" to "+ Add" — tapping any
    /// existing chip handles editing now, so the dedicated pill no
    /// longer needs to overload that role.
    private var addTopicAffordance: some View {
        Button {
            showManageTopics = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add")
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit topics")
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

    private func beginEditingTitle() {
        editedTitle = entry.displayTitle
        titleIsEditing = true
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
        titleIsEditing = false
        editCoordinator.end(id: "title")
    }

    private func cancelTitleEdit() {
        editedTitle = entry.displayTitle
        titleFieldFocused = false
        titleIsEditing = false
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
                onOpenVoice: { item in
                    audioPlayerForFile = AudioPlayerTarget(
                        mediaId: item.id,
                        filename: item.localIdentifier,
                        recordedAt: item.createdAt,
                        transcript: item.transcript
                    )
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
                onEditMediaDescription: { item in
                    // Whole-card tap on a photo or video routes here.
                    // Opens the description editor — the editor itself
                    // hosts a tap-to-open larger viewer for the image
                    // / video. Putting the description on the primary
                    // gesture keeps it reachable; the prior whole-card
                    // → QuickLook/player routing left it hidden behind
                    // a swipe most users never tried.
                    selectedMedia = item
                },
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

    /// Mentions section — always-visible row of extracted entity
    /// tags per Memory Detail v3. Now uses the **managed chip · edit
    /// state** Crucible pattern: each chip is tap-to-edit in place
    /// (rename or remove via ✕). A trailing dashed **+ Add** chip
    /// matches the unified-editing model's "lightweight inline" rule
    /// for mentions. The section sits between the chronological
    /// capture stream and the Organized · review card; the section
    /// stays mounted even when empty so the + Add affordance is always
    /// reachable.
    @ViewBuilder
    private var mentionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MENTIONS")
                .font(.caption2)
                .fontWeight(.bold)
                .tracking(1.6)
                .foregroundStyle(Crucible.Color.ink3)

            FlowLayout(spacing: 6) {
                ForEach(visibleTags) { tag in
                    ManagedChipEdit(
                        id: "mention-\(tag.id.uuidString)",
                        value: tag.value,
                        dotTint: tag.entityType.mentionTint,
                        onCommitRename: { newValue in
                            lifecycle.renameMention(
                                entityId: tag.id,
                                newValue: newValue,
                                entryId: entry.id
                            )
                        },
                        onRemove: {
                            lifecycle.removeMention(entityId: tag.id, entryId: entry.id)
                        }
                    )
                }
                ManagedChipAddAffordance(
                    id: "mention-add",
                    onCommit: { newValue in
                        lifecycle.addMention(value: newValue, entryId: entry.id)
                    }
                )
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Crucible.Color.hairline).frame(height: 0.5)
        }
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
            if !availableProjects.isEmpty {
                Menu {
                    ForEach(availableProjects) { project in
                        Button {
                            onAddToProject?(entry.id, project.id)
                        } label: {
                            Label(project.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                }
                .accessibilityLabel("Add to project")
            }
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

    private var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d · h:mm a"
        return formatter.string(from: entry.createdAt)
    }

    private func openInMaps(name: String, latitude: Double, longitude: Double) {
        let coords = "\(latitude),\(longitude)"
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?q=\(encoded)&ll=\(coords)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Chronological capture stream helpers

    /// Removes a media reference immediately rather than batching it with
    /// title/content edits via the existing onSave path. Used by the
    /// chronological capture stream's per-panel delete.
    private func applyEditsImmediately() {
        let ids = removedMediaIds
        guard !ids.isEmpty else { return }
        lifecycle.deleteMediaReferences(ids: ids)
        lifecycle.regenerateContent(forEntryId: entry.id)
        removedMediaIds = []
    }

    private func deleteNoteFragment(id: UUID) {
        lifecycle.deleteMediaReferences(ids: [id])
        lifecycle.regenerateContent(forEntryId: entry.id)
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
    @Binding var audioPlayerForFile: AudioPlayerTarget?
    @Binding var selectedMedia: MediaDisplayItem?
    @Binding var videoPlayerForItem: MediaDisplayItem?
    /// Used when a voice clip predates the per-clip transcript
    /// schema — the joined entry content is the only transcript
    /// available. Passed through to AudioPlayerSheet's
    /// `initialTranscript`.
    let legacyTranscriptFallback: String
    /// (mediaId?, newText) — `nil` mediaId means a legacy voice
    /// entry whose transcript IS the entry content.
    let onSaveAudioTranscript: (UUID?, String) -> Void
    let onSaveMediaDescription: (UUID, String) -> Void
    /// Deletes the photo/video clip from inside the description editor's
    /// bottom Delete button. Wired to the same `EntryLifecycleService`
    /// delete path the Full/Compact rows use.
    let onDeleteMedia: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $audioPlayerForFile) { target in
                AudioPlayerSheet(
                    filename: target.filename,
                    recordedAt: target.recordedAt,
                    initialTranscript: target.transcript ?? legacyTranscriptFallback,
                    onSaveTranscript: { newText in
                        onSaveAudioTranscript(target.mediaId, newText)
                    }
                )
                .presentationDetents([.large])
            }
            .sheet(item: $selectedMedia) { item in
                PhotoDescriptionEditSheet(
                    item: item,
                    onSaveDescription: { newDescription in
                        onSaveMediaDescription(item.id, newDescription)
                    },
                    onDelete: {
                        onDeleteMedia(item.id)
                    }
                )
                .presentationDetents([.large])
            }
            .fullScreenCover(item: $videoPlayerForItem) { item in
                VideoPlayerSheet(item: item)
            }
    }
}


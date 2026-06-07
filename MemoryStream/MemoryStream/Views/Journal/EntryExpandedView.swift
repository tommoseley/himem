import SwiftUI

enum EntryViewMode {
    case reading, editing
}

private enum ExpandedSheet: Identifiable {
    case newTopic

    var id: String {
        switch self {
        case .newTopic: return "newTopic"
        }
    }
}

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

/// Identifies the note fragment a user tapped, so `NoteEditorSheet` can be
/// presented via SwiftUI's `sheet(item:)` API. `mediaId` is the
/// MediaReference id so the sheet's save callback can persist back to the
/// right `.note` fragment; `text` seeds the editor; `createdAt` is shown as
/// a header timestamp.
struct NoteEditorTarget: Identifiable {
    let mediaId: UUID
    let text: String
    let createdAt: Date
    var id: UUID { mediaId }
}

struct EntryExpandedView: View {
    let entry: EntryDisplayModel
    var backLabel: String = "Today"
    let allTopics: [String]
    let cameraService: CameraService
    @ObservedObject var speechService: SpeechService
    /// (entryId, newContent, newTitle, removedTagIds, removedMediaIds, addedTopics, removedTopics).
    /// `newTitle == nil` means "leave the title alone"; an empty string clears it
    /// so `displayTitle` falls back to the AI/derived ladder.
    let onSave: (UUID, String, String?, Set<UUID>, Set<UUID>, Set<String>, Set<String>) -> Void
    var onFeedback: ((UUID, InferenceSummary.FeedbackState) -> Void)? = nil
    var onAdjust: ((UUID, String) -> Void)? = nil
    /// One-shot commit of a batch of appends. Fires at most once per session.
    /// additionalContent: typed text + concatenated transcripts.
    /// mediaCaptures: staged photo/video/voice assets.
    var onCommit: ((UUID, String, [(localIdentifier: String, mediaType: MediaReference.MediaType)]) -> Void)? = nil
    var onRecycle: ((UUID) -> Void)? = nil
    var onAddToProject: ((UUID, UUID) -> Void)? = nil  // entryId, projectId
    var availableProjects: [ProjectDisplayModel] = []

    @Environment(\.dismiss) private var dismiss
    @State private var mode: EntryViewMode = .reading

    // Editing state
    @State private var editedTitle = ""
    @State private var removedTagIds: Set<UUID> = []
    @State private var removedMediaIds: Set<UUID> = []
    @State private var addedTopics: Set<String> = []
    @State private var removedTopics: Set<String> = []
    @State private var selectedMedia: MediaDisplayItem? = nil
    @State private var audioPlayerForFile: AudioPlayerTarget? = nil
    @State private var noteEditorTarget: NoteEditorTarget? = nil
    @State private var showDeleteConfirmation = false
    @State private var showEmptyMemoryDeletePrompt = false
    @State private var showShareSheet = false
    @State private var newTopicName = ""
    @State private var newTopicColorKey = Crucible.Color.topicPalette[0].key
    @State private var aiCardUnfolded = false
    @ObservedObject private var entitlement = Entitlement.shared

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
    @State private var activeSheet: ExpandedSheet?
    @AppStorage("saveVoiceEntries") private var saveVoiceEntries = true

    private var currentTopics: [String] {
        entry.topicNames.filter { !removedTopics.contains($0) } + addedTopics.sorted()
    }

    private var availableToAdd: [String] {
        allTopics.filter { topic in
            !entry.topicNames.contains(topic) && !addedTopics.contains(topic)
            || removedTopics.contains(topic)
        }
    }

    private var visibleTags: [TagDisplayModel] {
        entry.tags.filter { !removedTagIds.contains($0.id) }
    }

    private var hasChanges: Bool {
        editedTitle != entry.displayTitle
            || !removedTagIds.isEmpty
            || !removedMediaIds.isEmpty
            || !addedTopics.isEmpty
            || !removedTopics.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        // Detail screen renders as a `List` (not a `ScrollView + VStack`)
        // so the chronological capture stream rows can use Apple's native
        // `.swipeActions`. List + native swipe is the only configuration
        // that coordinates scroll and swipe correctly — a `simultaneousGesture`
        // over a custom swipe modifier traps vertical drags before the
        // parent `ScrollView` can claim them.
        List {
            // Per Memory Detail v3 spec: title is the hero (serif),
            // topic chip sits *below* it and above the meta line, not
            // above. The four header rows (title, chip, date, summary)
            // use `headerRow` for a tight rhythm; the rest of the
            // page keeps `sectionRow`'s normal 8pt gap.
            headerRow { titleSection }
            headerRow(top: -3) { topicChipsRow }
            headerRow {
                Text(fullTimestamp)
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
            }
            // Memory Detail v3: the memory-level location pill is
            // retired. Per-clip headers in the chronological capture
            // stream carry their own date + time + place name now,
            // making the page-level pill redundant. `locationChip`
            // remains defined below for the share/export composer
            // until that path migrates to per-clip place names.
            headerRow { summarySection }
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
                    unfolded: $aiCardUnfolded,
                    onOrganize: { triggerManualAIOrganize() }
                )
            }
            sectionRow { inferenceCardSection }
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
            ToolbarItem(placement: .principal) { principalToolbar }
            ToolbarItem(placement: .navigationBarTrailing) { trailingToolbar }
        }
        .onAppear {
            editedTitle = entry.displayTitle
            migrateOrphanedContentIfNeeded()
        }
        .sheet(item: $audioPlayerForFile) { target in
            // Prefer the per-clip transcript captured at recording time;
            // fall back to entry.content (the joined-transcript blob) for
            // legacy voice refs from before the schema gained the field.
            AudioPlayerSheet(
                filename: target.filename,
                recordedAt: target.recordedAt,
                initialTranscript: target.transcript ?? entry.content,
                onSaveTranscript: { newText in
                    if let mediaId = target.mediaId {
                        updateMediaTranscript(id: mediaId, text: newText)
                    } else {
                        // Legacy voice entry — transcript IS entry.content.
                        // Persist through lifecycle.edit so search +
                        // inference re-derive from the new text.
                        lifecycle.edit(entryId: entry.id, newContent: newText)
                    }
                }
            )
            // Match the note editor's `.large` detent so the voice
            // editor and note editor open at the same height — Tom's
            // edit surfaces should feel the same regardless of clip
            // type.
            .presentationDetents([.large])
        }
        .sheet(item: $noteEditorTarget) { target in
            NoteEditorSheet(
                recordedAt: target.createdAt,
                initialText: target.text,
                onSave: { newText in
                    updateNoteFragment(id: target.mediaId, text: newText)
                }
            )
            .presentationDetents([.large])
        }
        // Photo / video tap → directly into the description editor.
        // The voice clip path opens AudioPlayerSheet directly too
        // (also a `.sheet`), so the two media editors land on parallel
        // surfaces with no intermediate viewer step. Per
        // `docs/design/HiMem · Edit Sheet.html` June 2026.
        .sheet(item: $selectedMedia) { item in
            PhotoDescriptionEditSheet(item: item) { newDescription in
                updateMediaDescription(id: item.id, text: newDescription)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showShareSheet) {
            let composed = "\(entry.displayTitle)\n\n\(entry.content)"
            ShareSheet(items: [composed])
        }
        .alert("Move to Recently Deleted?", isPresented: $showDeleteConfirmation) {
            Button("Move to Recently Deleted", role: .destructive) {
                onRecycle?(entry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This memory will be moved to the Recently Deleted. You can restore it from Settings.")
        }
        .alert("Delete this memory?", isPresented: $showEmptyMemoryDeletePrompt) {
            Button("Delete", role: .destructive) {
                lifecycle.delete(entryId: entry.id)
                dismiss()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("All content has been removed. This will permanently delete the memory — it won't go to Recently Deleted.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newTopic:
                NewTopicSheet(
                    name: $newTopicName,
                    colorKey: $newTopicColorKey,
                    onAdd: { name, colorKey in
                        addedTopics.insert(name)
                        TopicPaletteStore.shared.set(key: colorKey, for: name)
                    }
                )
            }
        }

            // Append-spec FAB — pick a modality, capture, append to
            // this memory. After the assist-quota retirement (PR 8d.2b)
            // there's no inline always-visible review card to suppress
            // the FAB against; the B1 review sheet is modal and
            // doesn't share screen real estate with the FAB.
            if mode == .reading {
                AppendFAB(
                    onSelect: { modality in
                        appendCoordinator.activeCaptureModality = modality
                    },
                    accessibilityLabel: "Add to memory"
                )
            }
        }
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
    }

    // MARK: - Body sections (decomposed from var body)

    /// Topic chips + (edit-mode) Add menu + (read-mode) status badge.
    /// Per Memory Detail v3 spec (`MDTopicChip`): full-width chip,
    /// neutral subtle dark background, `ink2` label, 11.5pt — the
    /// dot picks up the topic's pip color while the chip body stays
    /// muted. Spec's `inline-flex` child of a flex-column parent
    /// stretches to the column width via CSS's default
    /// `align-items: stretch`; SwiftUI parallel is
    /// `.frame(maxWidth: .infinity, alignment: .leading)` per chip.
    /// Vertical padding is 2pt — the v2 4pt was reading ~50% too
    /// tall against the spec.
    ///
    /// Multi-topic memories stack chips vertically; each chip still
    /// spans the full width. Status badge moves to its own row
    /// (rendered below) so it doesn't compete with the chip's
    /// full-width band.
    private var topicChipsRow: some View {
        VStack(spacing: 6) {
            ForEach(currentTopics, id: \.self) { topic in
                let hue = Crucible.Color.topicHue(for: topic)
                HStack(spacing: 6) {
                    Circle().fill(hue.fg).frame(width: 7, height: 7)
                    Text(topic)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink2)
                    if mode == .editing {
                        Button {
                            if addedTopics.contains(topic) {
                                addedTopics.remove(topic)
                            } else {
                                removedTopics.insert(topic)
                            }
                        } label: {
                            Text("×")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Crucible.Color.ink.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }

            if mode == .editing {
                HStack {
                    addTopicMenu
                    Spacer()
                }
            }

            if let status = entry.displayStatus, entry.inferenceSummary == nil {
                HStack {
                    StatusBadge(text: status.text, style: status.style)
                    Spacer()
                }
            }
        }
    }

    /// Edit-mode menu for toggling existing topics or creating a new one.
    private var addTopicMenu: some View {
        Menu {
            // Show every topic. Currently-applied ones are marked with a
            // checkmark; tapping toggles membership so the user can switch
            // topics in a single gesture without first having to × the
            // existing chip.
            ForEach(allTopics, id: \.self) { topic in
                let isSelected = currentTopics.contains(topic)
                Button {
                    toggleTopic(topic, currentlySelected: isSelected)
                } label: {
                    if isSelected {
                        Label(topic, systemImage: "checkmark")
                    } else {
                        Text(topic)
                    }
                }
            }
            if !allTopics.isEmpty { Divider() }
            Button {
                newTopicName = ""
                newTopicColorKey = Crucible.Color.topicPalette[0].key
                activeSheet = .newTopic
            } label: {
                Label("New Topic…", systemImage: "plus.circle")
            }
        } label: {
            Text("+ Add")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Crucible.Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Crucible.Color.sunk)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Crucible.Color.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    /// Title field swaps between an editable `TextField` and a read-mode
    /// `Text` that taps into editing.
    @ViewBuilder
    private var titleSection: some View {
        if mode == .editing {
            TextField("Title", text: $editedTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Crucible.Color.ink)
                .padding(10)
                .background(Crucible.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.accent, lineWidth: 1.5))
        } else {
            // Provenance lives in the Organized chip below — once a
            // suggestion is accepted, the field is the memory's, not
            // the AI's. No `✦ AI` tag here.
            Text(entry.displayTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Crucible.Color.ink)
                .contentShape(Rectangle())
                .onTapGesture { enterEditing() }
        }
    }

    /// Accepted AI summary, rendered as a labelled block above the
    /// chronological capture stream. Honest Label principle: the
    /// `✦ AI` glyph + caption make the origin visible at a glance.
    /// Empty when the summary isn't accepted (or doesn't exist) —
    /// view collapses without taking layout space.
    @ViewBuilder
    private var summarySection: some View {
        if let summary = entry.renderedSummary {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                    Text("SUMMARY")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(0.5)
                }
                .foregroundStyle(Crucible.Color.aiBlue)
                Text(summary)
                    .font(.body)
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
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
                onOpenNote: { item in
                    noteEditorTarget = NoteEditorTarget(
                        mediaId: item.id,
                        text: item.text ?? "",
                        createdAt: item.createdAt
                    )
                },
                onTapPhoto: { item in
                    selectedMedia = item
                }
            )
        }
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
    /// tags per Memory Detail v3. Previously a bottom-of-page
    /// collapsed `MENTIONS ⌄` expander; the chevron + count are
    /// retired and all chips render in a single FlowLayout. The
    /// section sits between the chronological capture stream and the
    /// Organized · review card. Person-typed mentions and others
    /// flow together — no internal split.
    @ViewBuilder
    private var mentionsSection: some View {
        if !entry.tags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("MENTIONS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundStyle(Crucible.Color.ink3)

                FlowLayout(spacing: 6) {
                    ForEach(visibleTags) { mentionChip($0) }
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(Crucible.Color.hairline).frame(height: 0.5)
            }
        }
    }

    /// One standalone-mentions chip. Persons get a `person.fill`
    /// glyph; other types get a colored dot. Tint comes from
    /// `ExtractedEntity.EntityType.mentionTint` so any mention
    /// surface reads from one palette.
    @ViewBuilder
    private func mentionChip(_ tag: TagDisplayModel) -> some View {
        HStack(spacing: 4) {
            if tag.entityType == .person {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tag.entityType.mentionTint)
            } else {
                Circle()
                    .fill(tag.entityType.mentionTint)
                    .frame(width: 5, height: 5)
            }
            Text(tag.value)
            if mode == .editing {
                Button {
                    removedTagIds.insert(tag.id)
                } label: {
                    Text("×")
                        .fontWeight(.bold)
                        .foregroundStyle(Crucible.Color.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(Crucible.Color.ink2)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Crucible.Color.sunk)
        .clipShape(Capsule())
    }

    // MARK: - Toolbar items (decomposed from var body)

    @ViewBuilder
    private var leadingToolbar: some View {
        if mode == .editing {
            Button("Cancel") { cancelEditing() }
                .foregroundStyle(Crucible.Color.accent)
        } else {
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
    }

    @ViewBuilder
    private var principalToolbar: some View {
        if mode == .editing {
            Text("Editing")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Crucible.Color.ink)
        }
    }

    @ViewBuilder
    private var trailingToolbar: some View {
        if mode == .editing {
            Button("Done") {
                if hasChanges {
                    commitEdits()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = .reading }
                }
            }
            .fontWeight(.bold)
            .foregroundStyle(Crucible.Color.accent)
        } else {
            HStack(spacing: 16) {
                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink3)
                }
                .accessibilityLabel("Delete memory")
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
                Button { enterEditing() } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink2)
                }
                .accessibilityLabel("Edit memory")
            }
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

    // MARK: - Mode transitions

    private func enterEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .editing
        }
    }

    private func cancelEditing() {
        editedTitle = entry.displayTitle
        removedTagIds = []
        removedMediaIds = []
        addedTopics = []
        removedTopics = []
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .reading
        }
    }

    private func commitEdits() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pass nil when the title field wasn't touched so we don't overwrite
        // the entry's actual title with the displayTitle fallback that
        // `enterEditing` seeded into editedTitle.
        let titleToSave: String? = (trimmedTitle == entry.displayTitle) ? nil : trimmedTitle
        // Body editing happens per-fragment now (NotePanel inline edit,
        // AudioPlayerSheet transcript edit). Pass entry.content unchanged so
        // the save round-trip touches only title/tags/media/topics.
        onSave(entry.id, entry.content, titleToSave, removedTagIds, removedMediaIds, addedTopics, removedTopics)
        dismiss()
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

    // MARK: - Topic toggle (edit mode)

    /// Flips a topic's membership on the current entry. Maintains the
    /// staged `addedTopics` / `removedTopics` sets so the change can be
    /// committed atomically by Done or rolled back by Cancel.
    private func toggleTopic(_ topic: String, currentlySelected: Bool) {
        if currentlySelected {
            // Currently selected → remove it.
            if entry.topicNames.contains(topic) {
                // Was on the entry originally; stage a removal.
                removedTopics.insert(topic)
            } else {
                // Was just added in this edit session; un-stage.
                addedTopics.remove(topic)
            }
        } else {
            // Not currently selected → add it.
            if removedTopics.contains(topic) {
                // Was originally on the entry, then staged for removal —
                // un-stage the removal.
                removedTopics.remove(topic)
            } else {
                addedTopics.insert(topic)
            }
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
        promptForPermanentDeleteIfEmpty()
    }

    private func deleteNoteFragment(id: UUID) {
        lifecycle.deleteMediaReferences(ids: [id])
        lifecycle.regenerateContent(forEntryId: entry.id)
        promptForPermanentDeleteIfEmpty()
    }

    /// Surfaces the "delete this empty memory?" prompt when the just-deleted
    /// fragment was the entry's last one. A memory that has lost every
    /// fragment renders as a blank shell — recycle would just defer the
    /// problem to the bin, so we offer a permanent delete instead.
    private func promptForPermanentDeleteIfEmpty() {
        if lifecycle.isEntryEmpty(entryId: entry.id) {
            showEmptyMemoryDeletePrompt = true
        }
    }

    private func updateNoteFragment(id: UUID, text: String) {
        lifecycle.updateNoteFragment(id: id, text: text, entryId: entry.id)
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

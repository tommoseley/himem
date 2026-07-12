import SwiftUI
import CoreData

/// Clip as primary object — the "opened item" view for any clip
/// on any surface. Shows the transcript / media, timestamp, the
/// memories that reference this clip ("Referenced in", empty
/// when the clip is still loose on the bench), and a bottom
/// Delete.
///
/// Chunk B (July 12 2026) — `ClipDetailView` now accepts either
/// a `MediaReference` (a clip that's been bundled and lives in
/// Core Data) OR an `InboxClip` (a bench voice clip that's still
/// on the manifest, waiting to be bundled). A loose bench clip
/// is legitimately referenced in nothing yet — the referenced-in
/// section renders its empty state rather than routing to a
/// separate view. Both paths render the same chrome; only the
/// data source and the save/delete plumbing differ.
///
/// See `docs/design/HiMem · evidence and context.md` (edge
/// ontology), `docs/design/Clip model · spec.md` §"Clip triage"
/// (July 12 2026 fate-actions lock), and
/// `docs/architecture/2026-07-08-evidence-context-ontology-plan.md`
/// § Phase 7.
struct ClipDetailView: View {

    /// The clip being rendered. Managed = live Core Data
    /// `MediaReference` (observed for updates). Inbox = a
    /// snapshot of an on-manifest voice clip that hasn't been
    /// bundled into a memory yet; the body observes
    /// `InboxManifest.shared` and looks up the live row by id.
    enum Source {
        case managed(MediaReference)
        case inbox(InboxClip)
    }

    let source: Source

    /// Managed-source init — matches the old signature so every
    /// pre-Chunk-B callsite (`ClipDetailView(ref:)`) keeps working.
    init(ref: MediaReference) {
        self.source = .managed(ref)
    }

    /// Inbox-source init — used by the bench when a loose voice
    /// clip is tapped. Delete routes through `InboxManifest.remove`;
    /// save routes through `InboxManifest.recordTranscriptionAttempt`.
    init(inboxClip: InboxClip) {
        self.source = .inbox(inboxClip)
    }

    var body: some View {
        switch source {
        case .managed(let ref):
            MediaReferenceClipDetail(ref: ref)
        case .inbox(let clip):
            InboxClipDetail(clipId: clip.clipId)
        }
    }
}

/// The Core-Data-backed detail — the existing chrome, unchanged.
/// Rendered when `ClipDetailView.source == .managed`.
private struct MediaReferenceClipDetail: View {
    @ObservedObject var ref: MediaReference
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var showingPlacement = false
    /// Slice 7 (Clip Model convergence): inline description editor
    /// state for photo/video clips. Nil = read state (invite or
    /// filled description); non-nil = editing (inline
    /// `ClipEditor(field: .description)`).
    @State private var descriptionDraft: String? = nil

    private let storage = StorageService.shared

    /// True while the description editor is on-screen. `Clip model ·
    /// spec.md` §Clip triage (July 12 2026): "Edit mode — words only:
    /// the transcript field + Play + Cancel/Done. No fate actions,
    /// no Referenced-in, no FAB." Everything below the editor hides
    /// while editing so Delete clip never renders twice.
    private var editing: Bool { descriptionDraft != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if editing {
                    header
                    if isMediaClip {
                        descriptionSection
                    }
                } else {
                    // Tap-anywhere-to-edit (Tom, 2026-07-12): only
                    // meaningful when the clip has a description slot
                    // (photo/video); voice/note refs display their
                    // transcript read-only here — editing lives in
                    // the Memory Detail path. `contentShape` covers
                    // the empty padding between subviews so the
                    // whole viewing region is one hit target for the
                    // description editor when applicable.
                    let viewingBody = VStack(alignment: .leading, spacing: 20) {
                        header
                        if ref.mediaTypeEnum == .voice, let transcript = ref.transcript, !transcript.isEmpty {
                            transcriptSection(transcript)
                        } else if ref.mediaTypeEnum == .note, let text = ref.text, !text.isEmpty {
                            transcriptSection(text)
                        }
                        if isMediaClip {
                            descriptionSection
                        }
                        referencedInSection
                        placementAffordance
                    }
                    if isMediaClip {
                        viewingBody
                            .contentShape(Rectangle())
                            .onTapGesture {
                                descriptionDraft = ref.mediaDescription ?? ""
                            }
                    } else {
                        viewingBody
                    }
                    Spacer(minLength: 40)
                    deleteSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Crucible.Color.paper.ignoresSafeArea())
        .navigationTitle("Clip")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPlacement) {
            PlaceClipSheet(ref: ref)
        }
    }

    private var isMediaClip: Bool {
        ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video
    }

    // MARK: - Description section (photo/video — Slice 7)

    /// Description slot for photo/video clips per `Clip model ·
    /// spec.md` §Content ("the description is the media clip's
    /// words") and Q2's answer: **Clip Detail is an opened
    /// context**, so the ochre invite lights up when empty. Tap
    /// the invite (or the existing description body) → inline
    /// `ClipEditor(field: .description)`. No sheet.
    @ViewBuilder
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            if descriptionDraft != nil {
                // *Words only.* `showFates: false` drops the editor's
                // internal Delete tier (`Clip model · spec.md` §Clip
                // triage July 12 2026: "editing words is not a moment
                // to delete or eject — Delete clip must never render
                // twice"). `showLabel: false` avoids repeating the
                // "DESCRIPTION" eyebrow the section already renders.
                ClipEditor(
                    field: .description,
                    draft: Binding(
                        get: { descriptionDraft ?? "" },
                        set: { descriptionDraft = $0 }
                    ),
                    initialValue: ref.mediaDescription ?? "",
                    editId: "description-\(ref.id.uuidString)",
                    evidence: nil,
                    fateActions: ClipEditorFateActions(
                        onDelete: { },
                        onRelocate: nil
                    ),
                    showLabel: false,
                    showFates: false,
                    onCancel: { descriptionDraft = nil },
                    onDone: { newValue in
                        ref.mediaDescription = newValue.isEmpty ? nil : newValue
                        ref.lastEditedAt = Date()
                        try? storage.save(context: context)
                        descriptionDraft = nil
                    }
                )
            } else if let description = ref.mediaDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        descriptionDraft = description
                    }
            } else {
                emptyDescriptionInvite
            }
        }
    }

    private var emptyDescriptionInvite: some View {
        Button {
            descriptionDraft = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add a description")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Crucible.Color.accent,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a description")
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
            if let place = ref.placeName, !place.isEmpty {
                Text(place)
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var dateLine: String {
        guard let date = ref.createdAt else { return "" }
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d · h:mm a"
        return df.string(from: date)
    }

    @ViewBuilder
    private func transcriptSection(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, design: .serif))
            .foregroundStyle(Crucible.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var referencedInSection: some View {
        let memories = ref.referencingMemoriesSortedByLinkedAtDesc
        VStack(alignment: .leading, spacing: 10) {
            Text("Referenced in")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Crucible.Color.ink3)
            if memories.isEmpty {
                Text("Not attached to a memory yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
            } else {
                ForEach(memories, id: \.id) { mem in
                    referencedInRow(mem)
                }
            }
        }
    }

    @ViewBuilder
    private func referencedInRow(_ memory: JournalEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Crucible.Color.aiBlue)
                .frame(width: 5, height: 5)
                .offset(y: -3)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title ?? "Untitled memory")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text(memoryDateLine(memory))
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func memoryDateLine(_ memory: JournalEntry) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: memory.createdAt)
    }

    // MARK: - Placement

    /// Dashed ochre "+ Where (else) does this belong?" affordance per
    /// `docs/design/screens-clips-page.jsx` `ScrClipDetail`. Label
    /// branches on placement state — an unplaced clip asks "Where does
    /// this belong?"; a placed clip asks "where **else**" (placement
    /// stops being terminal, per `HiMem · evidence and context.md`).
    @ViewBuilder
    private var placementAffordance: some View {
        Button {
            showingPlacement = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(placementLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Crucible.Color.accent,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(placementLabel)
    }

    private var placementLabel: String {
        ref.referencingMemoryCount > 0
            ? "Where else does this belong?"
            : "Where does this belong?"
    }

    // MARK: - Delete

    @ViewBuilder
    private var deleteSection: some View {
        let attachedCount = ref.referencingMemoryCount
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                if attachedCount > 0 {
                    confirmingDelete = true
                } else {
                    performDelete()
                }
            } label: {
                Text("Delete clip")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Crucible.Color.danger)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Crucible.Color.danger, lineWidth: 1)
                    )
            }
            if attachedCount > 0 {
                Text("This is attached to \(attachedCount) \(attachedCount == 1 ? "memory" : "memories").")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
        .alert("Delete clip?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clip is attached to \(attachedCount) \(attachedCount == 1 ? "memory" : "memories"). Deleting it will remove it from all of them.")
        }
    }

    private func performDelete() {
        let service = EntryLifecycleService(storage: storage, processingEngine: ProcessingEngine.shared)
        service.deleteMediaReference(refId: ref.id)
        dismiss()
    }
}

/// The bench-clip detail — rendered for a voice `InboxClip`
/// that's still on the manifest, waiting to be bundled. Chrome
/// mirrors `MediaReferenceClipDetail`: header, transcript with
/// tap-to-edit via the shared `ClipEditor`, empty Referenced-in
/// section ("Not attached to a memory yet"), bottom Delete.
/// Save goes through `InboxManifest.recordTranscriptionAttempt`;
/// delete through `InboxManifest.remove`. Move-to-memory and
/// Remove-from-session are Chunk C wire-ups.
private struct InboxClipDetail: View {

    /// Stable identity — the view looks the clip up on the
    /// manifest each render. If the clip is removed elsewhere
    /// (Delete session, bundled into a memory), the view detects
    /// its absence and dismisses.
    let clipId: UUID

    @ObservedObject private var inbox: InboxManifest = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var transcriptDraft: String? = nil
    @State private var confirmingDelete = false

    /// Live lookup. Nil = the clip has left the manifest (deleted
    /// or promoted into a memory); the body dismisses.
    private var clip: InboxClip? {
        inbox.clips.first { $0.clipId == clipId }
    }

    /// True while the transcript editor is on-screen. `Clip model ·
    /// spec.md` §Clip triage (July 12 2026): "Edit mode — **words
    /// only**: the transcript field + Play + Cancel/Done. No fate
    /// actions, no Referenced-in, no FAB." Everything below the
    /// editor hides while editing so Delete clip never renders twice.
    private var editing: Bool { transcriptDraft != nil }

    var body: some View {
        Group {
            if let clip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if editing {
                            header(clip: clip)
                            transcriptSection(clip: clip)
                        } else {
                            // Tap-anywhere-to-edit (Tom, 2026-07-12):
                            // hunting for the transcript row to open
                            // the editor read as friction — the whole
                            // viewing region above the fate stack is
                            // now one hit target. `contentShape`
                            // includes the empty padding between
                            // subviews. Individual `Text.onTapGesture`
                            // affordances inside still fire (Buttons
                            // and Text-taps take precedence over the
                            // outer gesture) but tapping the header
                            // meta, Referenced-in list, or any empty
                            // vertical space also opens the editor.
                            VStack(alignment: .leading, spacing: 20) {
                                header(clip: clip)
                                transcriptSection(clip: clip)
                                referencedInSection
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                transcriptDraft = clip.transcript
                            }
                            Spacer(minLength: 40)
                            bottomFateStack
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .background(Crucible.Color.paper.ignoresSafeArea())
                .navigationTitle("Clip")
                .navigationBarTitleDisplayMode(.inline)
                .alert("Delete clip?", isPresented: $confirmingDelete) {
                    Button("Delete", role: .destructive) { performDelete() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This clip goes to Recently Deleted for 30 days.")
                }
            } else {
                // Clip vanished from the manifest while this view
                // was open. Dismiss immediately.
                Color.clear
                    .onAppear { dismiss() }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(clip: InboxClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLine(clip.capturedAt))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
            // Bench InboxClips don't carry a resolved place name
            // yet (that happens at bundle time via
            // `ClipLocationResolver`). No place line here.
        }
    }

    private func dateLine(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d · h:mm a"
        return df.string(from: date)
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptSection(clip: InboxClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSCRIPT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            if transcriptDraft != nil {
                // *Words only.* `showFates: false` drops the editor's
                // internal Remove/Move/Delete tier — those live in the
                // view-mode `bottomFateStack` (below), hidden while
                // editing. `showLabel: false` avoids repeating the
                // "TRANSCRIPT" eyebrow the section already renders.
                ClipEditor(
                    field: .transcript,
                    draft: Binding(
                        get: { transcriptDraft ?? "" },
                        set: { transcriptDraft = $0 }
                    ),
                    initialValue: clip.transcript,
                    editId: "inbox-transcript-\(clip.clipId.uuidString)",
                    evidence: .audio(duration: clip.duration),
                    fateActions: ClipEditorFateActions(
                        onDelete: { },
                        onRelocate: nil
                    ),
                    showLabel: false,
                    showFates: false,
                    onCancel: { transcriptDraft = nil },
                    onDone: { newValue in
                        InboxManifest.shared.recordTranscriptionAttempt(
                            clipId: clip.clipId,
                            transcript: newValue
                        )
                        transcriptDraft = nil
                    }
                )
            } else if !clip.transcript.isEmpty {
                Text("\u{201C}\(clip.transcript)\u{201D}")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transcriptDraft = clip.transcript
                    }
            } else {
                // Empty transcript — same tap-to-edit affordance so
                // the user can add words to a clip that didn't
                // transcribe.
                Text("(no transcript)")
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { transcriptDraft = "" }
            }
        }
    }

    // MARK: - Referenced in (always empty for a bench clip)

    @ViewBuilder
    private var referencedInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Referenced in")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Crucible.Color.ink3)
            Text("Not attached to a memory yet.")
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    // MARK: - Bottom fate stack (view mode only)

    /// The opened-item bottom fate stack per `Clip model · spec.md`
    /// §Clip triage July 12 2026:
    /// > View mode — meta · transcript · Play · Referenced in, then
    /// > a single bottom fate stack: Remove from session (neutral
    /// > hairline) above Delete clip (danger red), one of each.
    ///
    /// Remove-from-session only renders when the clip is currently
    /// grouped with siblings (i.e., not already solo). Both hide
    /// during edit mode via the `!editing` gate up in `body`, so
    /// Delete clip never renders twice.
    @ViewBuilder
    private var bottomFateStack: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !inbox.soloClipIds.contains(clipId) {
                removeFromSessionButton
            }
            deleteClipButton
        }
    }

    private var removeFromSessionButton: some View {
        Button {
            InboxManifest.shared.markSolo(clipId: clipId)
            dismiss()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("Remove from session")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Crucible.Color.ink2)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Crucible.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var deleteClipButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Text("Delete clip")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Crucible.Color.danger)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Crucible.Color.danger, lineWidth: 1)
                )
        }
    }

    private func performDelete() {
        InboxManifest.shared.remove(clipId: clipId)
        dismiss()
    }
}

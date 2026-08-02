import SwiftUI
import AVFoundation

/// The **unified Clip Editor modal** — spec: `Clip Editor · unified modal ·
/// spec.md` (locked July 16 2026). ONE editor, invoked on tap/edit from every
/// surface (Clips bench · session · memory detail · search · cluster editor).
/// It retires the bespoke clip-edit paths (AudioPlayerSheet, the inline
/// transcript editors) into one sheet with one commit gate
/// (`ClipEditorCommitDecision`) — the invariant that makes the transcript-wipe
/// class *structurally* impossible: there is no second edit path to drift.
///
/// Three zones:
/// - **1 · the clip atom** — media + timing + transcript/description. Seeded
///   synchronously before render; edited once → true in every memory.
/// - **2 · memory edges** — single-open accordion (managed clips only), one
///   row per memory: annotation ("why this matters here") + Remove-from-this-
///   memory + Open ›. A loose clip shows "Not in any memory yet".
/// - **3 · Delete this Clip** — atom-level destruction, live-count warning.
///
/// Dual source (mirrors `ClipDetailView.Source`): a never-placed bench clip is
/// an `InboxClip` (voice-only, no edges, inbox-store audio); a placed/unlinked
/// clip is a `MediaReference` (edges, memory-store audio). All InboxClip-only
/// branching is confined to the pre-first-placement state (Tom, July 16).
struct ClipEditorModal: View {

    enum Source: Identifiable {
        case managed(MediaReference)
        case inbox(InboxClip)
        var id: UUID {
            switch self {
            case .managed(let ref): return ref.id
            case .inbox(let clip):  return clip.clipId
            }
        }
    }

    let source: Source
    /// "Open ›" on an edge — hand the memory id back to the presenter to
    /// navigate. Nil = the row's Open link is hidden.
    var onOpenMemory: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = AudioPlayerService.shared
    private let lifecycle = EntryLifecycleService()

    // Zone 1 — atom edit. `nil` = read; non-nil = editing (seeded SYNCHRONOUSLY
    // from the current content the instant edit begins — never blank-then-fill).
    @State private var contentDraft: String? = nil
    @State private var audioDuration: TimeInterval? = nil
    // Live playback position for the Zone 1 progress bar (Memory Detail cycle
    // 2/3 — the modal is the full listen surface; AudioPlayerService has no
    // seek, so this is a progress indicator + timeline, not a scrub control).
    @State private var playbackTime: TimeInterval = 0
    @State private var isRetranscribing = false
    @State private var retryStatus: String? = nil
    /// Set when a Zone-1 commit reached no store. Drawn in the content
    /// block, where the transcript would be — NOT reported to
    /// `ErrorState` alone: `JournalErrorBanner` is absent from Clips and
    /// renders beneath every sheet (F23 C1), so a banner from a modal
    /// presented over the bench is a message nobody reads. F18's ruled
    /// honest-failure placement: put it where the dead interface was.
    @State private var saveError: String? = nil
    /// The last value this modal committed AND confirmed stored. Set
    /// only from a write that reported success, so it can never assert
    /// an edit that did not land. See `backingContent` for why a bench
    /// clip cannot simply be re-read.
    @State private var committedContent: String? = nil
    /// This session's re-transcription returned `.transcribed` with no
    /// text — the run succeeded and there was nothing to hear. Distinct
    /// from "not yet transcribed" (see `EmptyContentState`) and from a
    /// deferral, which is what `retryStatus` carries.
    @State private var heardNothing = false

    // Zone 2 — single-open edge accordion + inline annotation edit.
    @State private var openEdgeId: UUID? = nil
    @State private var annotationDraft: String? = nil
    @State private var placing = false

    // Zone 1 photo/video hero — the thumbnail + full-screen consume.
    // Resolved the same way `MediaClipRow` does (ThumbnailService), and
    // "Tap to view full size" routes to the full-screen viewer. This
    // wiring was lost when `ClipEditorModal` replaced
    // `PhotoDescriptionEditSheet` (device bug, 2026-07-21).
    @State private var heroThumbnail: UIImage? = nil
    @State private var photoConsumeItem: MediaDisplayItem? = nil
    @State private var videoConsumeItem: MediaDisplayItem? = nil

    /// Title of the clip EDIT surface — distinct from the read-only
    /// `ClipDetailView` ("Clip") so the two surfaces never read the same.
    static let editorTitle = "Edit Clip"

    /// Shown when an edit reached no store. Parallel construction with
    /// the approved family ("Couldn't remove this clip. Try again." /
    /// "Couldn't create this memory. Try again." / "Couldn't add these
    /// clips. Try again."), approved 2026-07-31. Crucible voice: names
    /// the state, never blames the user, offers the one useful action.
    static let saveFailedMessage = "Couldn't save your edit. Try again."

    /// The AI action's label. **"again" is a claim about history and
    /// must be true**: with no transcript nothing is being repeated, and
    /// her model is "please transcribe this," not "retry" (F21).
    ///
    /// Offering it on an empty transcript is not a re-roll. F21 reasoned
    /// that re-transcribe is a *retry* — same audio, same model, same
    /// output — and the one thing that legitimately justifies a re-run
    /// is a genuine condition change. There is one: `4a08423` fixed the
    /// `.measurement` gain suppression, so every clip recorded before it
    /// was captured under-gained, and a re-run on those can now succeed
    /// where it previously heard nothing. That is exactly the population
    /// this state describes.
    ///
    /// Crucible: blue AI buttons name the AI with a trailing sparkle
    /// (the glyph is applied in `retranscribeAction`).
    static func transcribeActionLabel(hasTranscript: Bool) -> String {
        hasTranscript ? "Transcribe again with AI" : "Transcribe with AI"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    zone1
                    zone2
                }
                .padding(16)
            }
            deleteFooter
        }
        .background(Crucible.Color.paper.ignoresSafeArea())
        .task(id: source.id) {
            await loadDurationIfNeeded()
            await loadHeroThumbnailIfNeeded()
        }
        // "Opened by you" — the single point where a clip becomes Reviewed
        // (P7-2). Covers every open path (bench, session, cluster, Memory
        // Detail) since they all present this modal. Per-device, idempotent.
        .onAppear {
            switch source {
            case .inbox(let clip):
                // P0-3: a bench clip may already be materialized (a ref). Mark
                // BOTH stores — the manifest flag for the still-in-flight case,
                // the ref-keyed store (clipId == ref.id) for the materialized
                // case — so "seen" sticks regardless of backing. Both idempotent.
                InboxManifest.shared.markReviewed(clipId: clip.clipId)
                BenchClipReviewStore.markReviewed(clip.clipId)
            case .managed(let ref): BenchClipReviewStore.markReviewed(ref.id)
            }
        }
        // Drive the Zone 1 progress bar while this clip plays. 4 Hz is smooth
        // enough for a progress indicator and cheap; it idles to 0 otherwise.
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            if isPlayingThis {
                playbackTime = player.currentAVPlayer?.currentTime ?? 0
            } else if playbackTime != 0 {
                playbackTime = 0
            }
        }
        .onDisappear { if player.isPlaying { player.stop() } }
        .sheet(isPresented: $placing) { placementSheet }
        // Full-screen consume (Q3 "tap to view full size"). Both viewers
        // carry a standard dismiss (tap · swipe-down · ✕).
        .fullScreenCover(item: $photoConsumeItem) { PhotoViewerSheet(item: $0) }
        .fullScreenCover(item: $videoConsumeItem) { VideoPlayerSheet(item: $0) }
    }

    // MARK: - Top bar (bare-text exception place: Cancel · Edit Clip · Done)

    private var topBar: some View {
        HStack {
            Button("Cancel") { player.stop(); dismiss() }
                .font(.system(size: 15.5))
                .foregroundStyle(Crucible.Color.ink2)
            Spacer()
            // This is the *edit* surface for a clip; the title says so.
            // The read-only "opened clip" view (`ClipDetailView`) titles
            // itself "Clip" — the two surfaces stay distinct.
            Text(Self.editorTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Spacer()
            SectionHelpButton(topic: .editClip, size: 17)  // F7c — one ? for the sheet
            Button("Done") { commitOpenEdits(); player.stop(); dismiss() }
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(Crucible.Color.accent)
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Crucible.Color.divider).frame(height: 1)
        }
    }

    // MARK: - Zone 1 · the clip atom

    @ViewBuilder
    private var zone1: some View {
        clipHero
        contentBlock
    }

    @ViewBuilder
    private var clipHero: some View {
        switch media {
        case .voice, .note:
            HStack(spacing: 12) {
                Button { togglePlay() } label: {
                    Circle()
                        .fill(Crucible.Color.accentTint)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: isPlayingThis ? "stop.fill" : "play.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Crucible.Color.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(media == .note)
                .opacity(media == .note ? 0 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    metadataLine
                    if media == .voice {
                        Text("Original recording\(durationSuffix)")
                            .font(.system(size: 13))
                            .foregroundStyle(Crucible.Color.ink2)
                        if isPlayingThis {
                            playbackProgressRow
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        case .photo, .video:
            Button { openConsume() } label: {
                HStack(spacing: 13) {
                    heroThumbnailTile
                    VStack(alignment: .leading, spacing: 4) {
                        metadataLine
                        Text("Tap to view full size")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.aiBlue)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 68×68 hero tile — the real thumbnail (resolved via
    /// `ThumbnailService`, same source `MediaClipRow` uses) with a media
    /// glyph as the placeholder until it loads, and a play badge on video.
    @ViewBuilder
    private var heroThumbnailTile: some View {
        ZStack {
            if let heroThumbnail {
                Image(uiImage: heroThumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                RoundedRectangle(cornerRadius: 13)
                    .fill(Crucible.Color.sunk)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Image(systemName: media == .video ? "video.fill" : "photo.fill")
                            .foregroundStyle(Crucible.Color.ink3)
                    )
            }
            if media == .video {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.black)
                    )
            }
        }
    }

    @ViewBuilder
    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contentLabel)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            if let _ = contentDraft {
                // Editing — seeded synchronously (see beginContentEdit).
                ClipEditor(
                    field: contentField,
                    draft: Binding(get: { contentDraft ?? "" }, set: { contentDraft = $0 }),
                    initialValue: currentContent,
                    editId: "clip-atom-\(source.id.uuidString)",
                    // Device pass 2026-08-01: "Original recording · 0:14"
                    // rendered TWICE — once in this modal's own Zone-1 header
                    // (`Text("Original recording\(durationSuffix)")`) and again
                    // in the editor's evidence row. Suppressed HERE rather than
                    // removed from `ClipEditor`, because the other call sites
                    // (`CompactTranscriptViews`, `ChronologicalCaptureStream`)
                    // have no such header and the evidence row is their only
                    // render of it.
                    evidence: nil,
                    fateActions: ClipEditorFateActions(onDelete: {}, onRelocate: nil),
                    showLabel: false,
                    showFates: false,
                    onCancel: { contentDraft = nil },
                    onDone: { newValue in commitContent(newValue); contentDraft = nil }
                )
                // F21/B4 · the blue sparkle consequence line is DELETED, and
                // replaced with nothing. Three faults: it dressed STATUS as an
                // AI action (AI-blue + sparkle is reserved for *invoking* AI —
                // Buttons & Actions); it taught the many-to-many model unasked
                // (F13 curriculum); and it read as actively confusing on
                // device. The information already appears in context below —
                // "Not in any memory yet" / "In N memories" / the delete
                // warning — which is the correct place: shown where it is
                // true, not asserted as a preamble.
            } else {
                Text(displayContent)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(currentContent.isEmpty ? Crucible.Color.ink3 : Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginContentEdit() }
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 13))
                        .foregroundStyle(Crucible.Color.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                if canRetranscribe {
                    retranscribeAction
                }
            }
        }
        .padding(.top, 16)
    }

    private var retranscribeAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { retranscribe() } label: {
                HStack(spacing: 7) {
                    if isRetranscribing {
                        ProgressView().controlSize(.small)
                    }
                    Text(isRetranscribing ? "Transcribing…" : Self.transcribeActionLabel(hasTranscript: !currentContent.isEmpty))
                    if !isRetranscribing { Image(systemName: "sparkles").font(.system(size: 12)) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Crucible.Color.aiBlue)
                .frame(minHeight: 38)
                .padding(.horizontal, 15)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Crucible.Color.aiBlue, lineWidth: 1))
                // F17 · the pill is stroked, not filled — without this the tap
                // region is only the drawn text. Guarded by ButtonHitRegionTests.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRetranscribing)
            if let retryStatus {
                Text(retryStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Zone 2 · memory edges (managed only)

    @ViewBuilder
    private var zone2: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(edges.isEmpty ? "Not in any memory yet"
                               : "In \(referencingCount) \(referencingCount == 1 ? "memory" : "memories")")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Crucible.Color.ink3)
            ForEach(edges, id: \.id) { edge in
                edgeRow(edge)
            }
            addToMemoryButton
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private func edgeRow(_ edge: MemoryClipEdge) -> some View {
        let isOpen = openEdgeId == edge.id
        let annotation = edge.annotation ?? ""
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleEdge(edge)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(edge.memory?.displayTitle ?? "")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundStyle(Crucible.Color.ink)
                        Text(edgeDateText(edge))
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.ink3)
                        if !isOpen {
                            // F22 EXEMPT: `annotation` is the edit field's own
                            // draft text — what the user has typed, never loaded
                            // from an unimported store.
                            if annotation.isEmpty {
                                Text("Add a note")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Crucible.Color.aiBlue)
                                    .padding(.top, 5)
                            } else {
                                Text(annotation)
                                    .font(.system(size: 13, design: .serif))
                                    .italic()
                                    .foregroundStyle(Crucible.Color.ink3)
                                    .lineLimit(1)
                                    .padding(.top, 5)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Crucible.Color.aiBlue)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider().padding(.vertical, 11)
                Text("WHY THIS MATTERS HERE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Crucible.Color.ink4)
                    .padding(.bottom, 6)
                annotationEditor(edge, current: annotation)
                HStack {
                    Button { removeFromMemory(edge) } label: {
                        Label("Remove from this memory", systemImage: "eject")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink2)
                            .frame(minHeight: 34)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if onOpenMemory != nil {
                        Button { onOpenMemory?(edge.memoryId) } label: {
                            Text("Open ›").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Crucible.Color.aiBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Crucible.Color.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Crucible.Color.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func annotationEditor(_ edge: MemoryClipEdge, current: String) -> some View {
        if annotationDraft != nil {
            ClipEditor(
                field: .description,
                draft: Binding(get: { annotationDraft ?? "" }, set: { annotationDraft = $0 }),
                initialValue: current,
                editId: "edge-annotation-\(edge.id.uuidString)",
                evidence: nil,
                fateActions: ClipEditorFateActions(onDelete: {}, onRelocate: nil),
                showLabel: false,
                showFates: false,
                onCancel: { annotationDraft = nil },
                onDone: { newValue in
                    lifecycle.updateEdgeAnnotation(edgeId: edge.id, annotation: newValue)
                    annotationDraft = nil
                }
            )
        // F22 EXEMPT: `current` is this edge's annotation text on a clip the
        // user has open — edit-field contents, not a store collection.
        } else if current.isEmpty {
            Text("Add a note")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Crucible.Color.aiBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { annotationDraft = current }
        } else {
            Text(current)
                .font(.system(size: 14, design: .serif))
                .italic()
                .lineSpacing(2)
                .foregroundStyle(Crucible.Color.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { annotationDraft = current }
        }
    }

    private var addToMemoryButton: some View {
        Button { placing = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add to a memory")
            }
            .font(.system(size: 14.5, weight: .semibold))
            .foregroundStyle(Crucible.Color.accent)
            .frame(maxWidth: .infinity, minHeight: 46)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Crucible.Color.accent, style: StrokeStyle(lineWidth: 1, dash: [5])))
            .contentShape(Rectangle()) // edge-to-edge tap (dashed pill interior is transparent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Zone 3 · Delete this Clip

    private var deleteFooter: some View {
        VStack(spacing: 10) {
            Text(deleteWarning)
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink3)
                .multilineTextAlignment(.center)
            Button { deleteClip() } label: {
                Label("Delete this Clip", systemImage: "trash")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.danger)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Crucible.Color.danger, lineWidth: 1))
                    .contentShape(Rectangle()) // edge-to-edge tap (stroke pill interior is transparent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(Crucible.Color.paper)
        .overlay(alignment: .top) { Rectangle().fill(Crucible.Color.divider).frame(height: 1) }
    }

    // MARK: - Placement sheet

    @ViewBuilder
    private var placementSheet: some View {
        switch source {
        case .managed(let ref):
            PlaceClipSheet(ref: ref)
        case .inbox(let clip):
            // Promote-then-place (Tom, July 16; wired 2026-07-25): materialize
            // the InboxClip → MediaReference + edge ON CONFIRM (see
            // `PlaceInboxClipSheet` / `EntryLifecycleService.placeInboxClip`).
            // Cancel leaves the bench clip untouched. On success the clip is
            // promoted off the bench, so this editor (which was editing the
            // now-gone inbox clip) dismisses.
            PlaceInboxClipSheet(clip: clip, onPlaced: { dismiss() })
        }
    }

    // MARK: - Derived source properties

    private var media: ClipDisplayModel.Media {
        switch source {
        case .inbox: return .voice
        case .managed(let ref):
            switch ref.mediaTypeEnum {
            case .voice: return .voice
            case .note:  return .note
            case .image: return .photo
            case .video: return .video
            }
        }
    }

    /// What Zone 1 must display: the value we last committed **and
    /// confirmed stored**, else the backing's own value.
    ///
    /// `nil` committed → read the backing. Pure + static so the
    /// invariant is red-able without a SwiftUI runtime.
    static func resolvedContent(committed: String?, backing: String) -> String {
        committed ?? backing
    }

    private var currentContent: String {
        Self.resolvedContent(committed: committedContent, backing: backingContent)
    }

    /// The backing store's own value. For `.managed` this is a live
    /// `NSManagedObject` read. For `.inbox` it is a **frozen snapshot**:
    /// `InboxClip` is a struct, captured when `.sheet(item:)` presented
    /// this modal, and nothing here ever re-reads the manifest. So a
    /// successful bench edit displayed the PRE-EDIT text — the save had
    /// worked and the screen said otherwise (F24 Defect 2).
    /// `committedContent` is what closes that, and it is only ever set
    /// from a write that reported success (Defect 3), so the display
    /// cannot claim an edit that did not land.
    private var backingContent: String {
        switch source {
        case .inbox(let clip): return clip.transcript
        case .managed(let ref):
            switch ref.mediaTypeEnum {
            case .voice: return ref.transcript ?? ""
            case .note:  return ref.text ?? ""
            case .image, .video: return ref.mediaDescription ?? ""
            }
        }
    }

    /// Why an empty Zone 1 is three facts, not one.
    ///
    /// "We haven't transcribed this yet" and "we transcribed it and
    /// there were no words" are **different facts and must never share
    /// a string** (ruled 2026-07-31). Before F24 Defect 4 they shared
    /// `"(no transcript)"`, and the transcribed-to-silence case had no
    /// voice at all: `retranscribe` set `retryStatus` from
    /// `userFacingDeferralMessage`, which returns nil for `.transcribed`
    /// — so a run that succeeded and heard nothing showed a spinner
    /// that returned to idle and said nothing. Indistinguishable from a
    /// dead button.
    ///
    /// "No words in this recording." is the honest state: the
    /// transcription ran and heard nothing. Not a failure, not a
    /// deferral, no blame, and it promises no retry that won't help.
    enum EmptyContentState: Equatable {
        /// Photo/video with no description — an invitation, not a report.
        case needsDescription
        /// Never transcribed, or the attempt failed and will be retried.
        case notYetTranscribed
        /// Transcribed successfully; the recording contained no speech.
        case transcribedToSilence

        var message: String {
            switch self {
            case .needsDescription:     return "Add a description"
            case .notYetTranscribed:    return "(no transcript)"
            case .transcribedToSilence: return "No words in this recording."
            }
        }
    }

    /// Pure resolution of the three empty states, so each fact is
    /// red-able independently of the SwiftUI runtime.
    ///
    /// - Parameter heardNothing: this session's re-transcription
    ///   returned `.transcribed` with empty text.
    /// - Parameter attemptedAndEmpty: the *stored* signal — the clip
    ///   records a completed transcription attempt and has no text.
    static func emptyContentState(isDescriptionField: Bool,
                                  heardNothing: Bool,
                                  attemptedAndEmpty: Bool) -> EmptyContentState {
        if isDescriptionField { return .needsDescription }
        return (heardNothing || attemptedAndEmpty) ? .transcribedToSilence : .notYetTranscribed
    }

    /// The stored "we transcribed it and it was empty" signal. Only
    /// `.inbox` carries it (`InboxClip.transcriptionAttempted`);
    /// `MediaReference` has no equivalent field, so a *managed* clip
    /// that transcribed to silence reads as `.notYetTranscribed` until
    /// she re-runs it in this session. Stated rather than papered over:
    /// closing it needs a schema attribute and a CloudKit deploy
    /// (the F6i option-C trade), which is not a nine-days-out change.
    private var attemptedAndEmpty: Bool {
        guard currentContent.isEmpty else { return false }
        if case .inbox(let clip) = source { return clip.transcriptionAttempted }
        return false
    }

    private var displayContent: String {
        guard currentContent.isEmpty else { return currentContent }
        return Self.emptyContentState(
            isDescriptionField: media == .photo || media == .video,
            heardNothing: heardNothing,
            attemptedAndEmpty: attemptedAndEmpty
        ).message
    }

    private var contentLabel: String { (media == .photo || media == .video) ? "Description" : "Transcript" }
    private var contentField: ClipEditorField { (media == .photo || media == .video) ? .description : .transcript }
    /// **F21 state 2, finally built (2026-08-02).** The AI action renders
    /// ONLY when there is no transcript.
    ///
    /// F21 ruled three states: *no transcript / failed* → offer
    /// **Transcribe**; *transcript exists* → edit + "Add to a memory",
    /// **no AI button competing** with the action she almost always wants
    /// next; *no third affordance*. F24 only changed the LABEL and left the
    /// button rendering in every state, so on device Tom tapped a control
    /// that F21 says should not be there — and it no-opped, because
    /// re-transcribing the same audio yields the same nothing.
    ///
    /// Re-transcribe is a **retry**, not an improve: same audio, same model,
    /// same output. Offering it against existing text is a promise we cannot
    /// keep.
    ///
    /// **This is also what makes the heard-nothing message reachable.**
    /// `displayContent` only surfaces "No words in this recording." while
    /// `currentContent.isEmpty`. Gating the button on the SAME condition
    /// means every state that can set `heardNothing` is a state that can
    /// show it — the two are pinned together by
    /// `ClipEditorHeardNothingTests.theHeardNothingStateIsAlwaysReachable`.
    /// Before this, `heardNothing` could be set and never rendered: the
    /// silent no-op class reintroduced one state over from where F24
    /// removed it.
    private var canRetranscribe: Bool {
        contentDraft == nil && (media == .voice || media == .video) && currentContent.isEmpty
    }

    private var edges: [MemoryClipEdge] {
        if case .managed(let ref) = source { return ref.edgesArray }
        return []
    }
    private var referencingCount: Int { edges.count }

    private var deleteWarning: String {
        referencingCount == 0
            ? "This clip isn't in any memory yet."
            : "This clip is part of \(referencingCount) \(referencingCount == 1 ? "memory" : "memories"). Deleting it removes it from \(referencingCount == 1 ? "that memory" : "all of them")."
    }

    private var audioFilename: String? {
        switch source {
        case .inbox(let clip): return clip.audioFilename
        case .managed(let ref): return ref.mediaTypeEnum == .voice ? ref.osIdentifier : nil
        }
    }
    private var isPlayingThis: Bool { player.isPlaying && player.currentFile == audioFilename }
    private var durationSuffix: String {
        guard let d = audioDuration else { return "" }
        return " · \(Int(d) / 60):\(String(format: "%02d", Int(d) % 60))"
    }

    /// Zone 1 playback progress — a non-interactive progress bar + elapsed /
    /// total timeline (AudioPlayerService has no seek, so this reports
    /// position; it doesn't scrub). Shown only while this clip is playing.
    private var playbackProgressRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: playbackProgress)
                .tint(Crucible.Color.accent)
            HStack(spacing: 0) {
                Text(Self.formatPlaybackTime(playbackTime))
                Spacer(minLength: 8)
                Text(Self.formatPlaybackTime(audioDuration ?? 0))
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(Crucible.Color.ink3)
        }
        .frame(maxWidth: 220, alignment: .leading)
        .padding(.top, 3)
    }

    private var playbackProgress: Double {
        guard let d = audioDuration, d > 0 else { return 0 }
        return min(1, max(0, playbackTime / d))
    }

    static func formatPlaybackTime(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var timingText: String {
        let date: Date
        switch source {
        case .inbox(let clip): date = clip.capturedAt
        case .managed(let ref): date = ref.createdAt ?? .distantPast
        }
        let place: String?
        if case .managed(let ref) = source { place = ref.placeName } else { place = nil }
        let f = DateFormatter(); f.dateFormat = "EEE MMM d · h:mm a"
        var s = f.string(from: date)
        if let place, !place.isEmpty { s += " · \(place)" }
        return s
    }

    private func edgeDateText(_ edge: MemoryClipEdge) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"
        return f.string(from: edge.linkedAt ?? .distantPast)
    }

    /// Capture-source glyph name for a per-clip `source` string (Finding 2,
    /// 2026-07-16). Source is per-clip metadata — a small watch/phone glyph,
    /// never a headline (source-agnostic rule, `CLAUDE.md` §Phone). Unknown /
    /// absent source → no glyph. Siri capture doesn't produce clips yet; its
    /// glyph is added when that source ships. Pure + static so the mapping is
    /// unit-tested without Core Data (`ClipEditorModalSourceTests`).
    static func sourceGlyphName(for sourceString: String?) -> String? {
        switch sourceString {
        case "watch": return "applewatch"
        case "phone": return "iphone"
        default:       return nil
        }
    }

    /// The glyph for THIS clip. `.inbox` clips carry `source`; `.managed`
    /// clips now read `MediaReference.sourceDevice` (shipped in the B4
    /// schema batch, July 18 2026). Nil (no glyph) when the source is
    /// unknown — legacy clips captured before the field, which we never
    /// backfill with a guess.
    private var sourceGlyph: String? {
        switch source {
        case .inbox(let clip):  return Self.sourceGlyphName(for: clip.source)
        case .managed(let ref): return Self.sourceGlyphName(for: ref.sourceDevice)
        }
    }

    /// Zone 1 metadata line — source glyph (when known) + reflective timing.
    private var metadataLine: some View {
        HStack(spacing: 5) {
            if let sourceGlyph {
                Image(systemName: sourceGlyph)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .accessibilityLabel(sourceGlyph == "applewatch" ? "Captured on Apple Watch" : "Captured on iPhone")
            }
            Text(timingText)
                .font(.system(size: 12))
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    // MARK: - Actions

    private func beginContentEdit() {
        // SEED SYNCHRONOUSLY — the draft holds the real content before the
        // editor renders. A no-op Done can never write empty over real text.
        contentDraft = currentContent
    }

    /// Commit Zone 1, and **check that it landed.** The writers return the
    /// text actually stored, or nil when the edit reached no store at all
    /// — a clip that is neither a live `MediaReference` nor a manifest row
    /// used to lose the edit through two stacked bare `return`s, while
    /// this modal closed as if it had saved (F24 Defect 3). A silent
    /// failed save is worse than a wipe: the user believes it took.
    private func commitContent(_ newValue: String) {
        let stored: String?
        switch source {
        case .inbox(let clip):
            // P0-3: a materialized bench clip is a ref — route through the
            // backing-aware writer so the edit lands (never a silent no-op).
            stored = lifecycle.writeBenchClipTranscript(clipId: clip.clipId, transcript: newValue)
        case .managed(let ref):
            if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
                stored = lifecycle.updateClipDescription(refId: ref.id, description: newValue)
            } else {
                stored = lifecycle.updateClipTranscript(refId: ref.id, transcript: newValue)
            }
        }
        saveError = (stored == nil) ? Self.saveFailedMessage : nil
        // Only on a confirmed write — never display what we could not store.
        if let stored { committedContent = stored }
    }

    /// What the top-bar **Done** must do with an open draft. `nil` = no
    /// draft is open. Otherwise the same gate every other commit path
    /// uses, so there is still exactly one decision and no second path
    /// to drift.
    ///
    /// Pure + static deliberately: the defect this closes (F24 Defect 1)
    /// was invisible at the owner level. `ClipEditorCommitDecision` was
    /// correct and simply **was not called** — `commitOpenEdits` nil'd
    /// the drafts under a comment asserting "the ClipEditor coordinator
    /// commits." It does not: closing the editor fires only
    /// `coordinator.end(id:)`, which sets `activeEditId = nil`, so
    /// `ClipEditorSwitchOutcome.decide` sees `switchedToOtherEditor ==
    /// false` and returns `.stayEditing`. Typing and then tapping the
    /// top-bar Done — the natural gesture — discarded the edit in
    /// silence. A correct owner nobody consults is the class named in
    /// CLAUDE.md § "Guard the Caller, Not Just the Owner"; the caller is
    /// guarded by `ClipEditorTopBarDoneTests`.
    static func openDraftDecision(draft: String?, current: String,
                                  field: ClipEditorField) -> ClipEditorCommitDecision? {
        guard let draft else { return nil }
        return ClipEditorCommitDecision.decide(initial: current, draft: draft, field: field)
    }

    private func commitOpenEdits() {
        // Done from the top bar while a field is open COMMITS it (never lose
        // work) — routed through the same decision the editors' own Done
        // uses, then the drafts close.
        if case .commit(let trimmed)? = Self.openDraftDecision(
            draft: contentDraft, current: currentContent, field: contentField
        ) {
            commitContent(trimmed)
        }
        if let edgeId = openEdgeId,
           let edge = edges.first(where: { $0.id == edgeId }),
           case .commit(let trimmed)? = Self.openDraftDecision(
               draft: annotationDraft, current: edge.annotation ?? "", field: .description
           ) {
            lifecycle.updateEdgeAnnotation(edgeId: edgeId, annotation: trimmed)
        }
        contentDraft = nil
        annotationDraft = nil
    }

    private func togglePlay() {
        guard let filename = audioFilename else { return }
        if isPlayingThis { player.stop() } else { player.play(filename: filename) }
    }

    private func toggleEdge(_ edge: MemoryClipEdge) {
        annotationDraft = nil
        openEdgeId = (openEdgeId == edge.id) ? nil : edge.id
    }

    private func removeFromMemory(_ edge: MemoryClipEdge) {
        guard case .managed(let ref) = source else { return }
        lifecycle.removeClipFromMemory(memoryId: edge.memoryId, refId: ref.id)
        openEdgeId = nil
    }

    private func deleteClip() {
        switch source {
        // P8/P8b: soft-delete to Recently Deleted on BOTH backings — a
        // promoted clip via MediaReference.recycledAt, an unpromoted bench
        // clip via the per-device manifest recycledAt (uniform bin).
        case .managed(let ref): lifecycle.recycleClip(refId: ref.id)
        // P0-3: a materialized bench clip is a ref — route through the
        // backing-aware recycle so the delete lands (never a silent no-op).
        case .inbox(let clip):  lifecycle.recycleBenchClip(clipId: clip.clipId)
        }
        player.stop()
        dismiss()
    }

    /// The on-disk audio URL to re-transcribe, resolved per backing. Managed
    /// refs live in the memory store; inbox clips live in the inbox store —
    /// EXCEPT a phone-captured inbox clip whose audio already sits in the memory
    /// store (same dual-store logic as `appendToExistingMemory`). Static + pure
    /// (injectable `fileExists`) so the both-backing behavior is money-tested
    /// and can't silently diverge again. Wiring the inbox branch closes the
    /// "Transcribe again does nothing on bench clips" bug.
    static func retranscribeAudioURL(isInbox: Bool, filename: String,
                                     fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let voiceURL = SpeechService.audioURL(for: filename)
        guard isInbox else { return voiceURL }
        return fileExists(voiceURL) ? voiceURL : InboxManifest.audioURL(for: filename)
    }

    private func retranscribe() {
        guard #available(iOS 26.0, *), let filename = audioFilename else { return }
        let isInbox: Bool = { if case .inbox = source { return true }; return false }()
        let url = Self.retranscribeAudioURL(isInbox: isInbox, filename: filename)
        isRetranscribing = true
        retryStatus = nil
        Task {
            let outcome = await TranscriptionService.shared.transcribe(audioURL: url)
            await MainActor.run {
                isRetranscribing = false
                let text = outcome.textOrEmpty.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    // Two very different empty results, and conflating them is
                    // what made this button read as dead (F24 Defect 4).
                    // `.transcribed` with no text means the run SUCCEEDED and
                    // heard nothing — `userFacingDeferralMessage` is nil for
                    // that case by design, so the old code showed nothing at
                    // all. Say the honest thing instead, in the transcript's
                    // own slot. Everything else is a genuine deferral.
                    if case .transcribed = outcome {
                        heardNothing = true
                        retryStatus = nil
                    } else {
                        heardNothing = false
                        retryStatus = outcome.userFacingDeferralMessage
                    }
                } else {
                    // Reseed the edit field with the fresh transcript; the user
                    // still commits via Done (one commit path).
                    heardNothing = false
                    contentDraft = text
                }
            }
        }
    }

    /// The `MediaDisplayItem` for this clip's photo/video hero. Only
    /// managed refs carry photo/video (inbox clips are voice-only).
    private var heroDisplayItem: MediaDisplayItem? {
        guard case .managed(let ref) = source else { return nil }
        return MediaDisplayItem(
            id: ref.id,
            localIdentifier: ref.osIdentifier,
            mediaType: ref.mediaTypeEnum,
            thumbnailCacheFilename: ref.thumbnailCacheFilename,
            isAccessible: ref.isAccessible
        )
    }

    /// Tap on the hero / "Tap to view full size" → full-screen consume.
    private func openConsume() {
        guard let item = heroDisplayItem else { return }
        switch item.mediaType {
        case .image: photoConsumeItem = item
        case .video: videoConsumeItem = item
        default:     break
        }
    }

    /// Resolve the 68×68 hero thumbnail the same way `MediaClipRow` does
    /// (`ThumbnailService.cacheThumbnail → cachedThumbnail`). No-op for
    /// voice/note and for inbox clips.
    private func loadHeroThumbnailIfNeeded() async {
        guard heroThumbnail == nil,
              case .managed(let ref) = source,
              ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video else { return }
        if let name = await ThumbnailService.shared.cacheThumbnail(
            for: ref.osIdentifier,
            mediaType: ref.mediaTypeEnum
        ) {
            heroThumbnail = ThumbnailService.shared.cachedThumbnail(filename: name)
        }
    }

    private func loadDurationIfNeeded() async {
        guard media == .voice, audioDuration == nil else { return }
        if case .inbox(let clip) = source, clip.duration > 0 {
            await MainActor.run { audioDuration = clip.duration }
            return
        }
        guard let filename = audioFilename else { return }
        let url = SpeechService.audioURL(for: filename)
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration), cm.seconds.isFinite {
            await MainActor.run { audioDuration = cm.seconds }
        }
    }
}

/// Seam for the bench-clip promote-then-place flow (wiring cycle). Shows the
/// intended affordance so the additive build reviews end-to-end without
/// materializing a MediaReference on open.

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
            case .inbox(let clip):  InboxManifest.shared.markReviewed(clipId: clip.clipId)
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
                    evidence: media == .voice ? .audio(duration: audioDuration) : nil,
                    fateActions: ClipEditorFateActions(onDelete: {}, onRelocate: nil),
                    showLabel: false,
                    showFates: false,
                    onCancel: { contentDraft = nil },
                    onDone: { newValue in commitContent(newValue); contentDraft = nil }
                )
                // Blue AI consequence line — the edit is true everywhere.
                Label("This is the clip itself — your edit shows in every memory that uses it.",
                      systemImage: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.aiBlue)
                    .padding(.top, 2)
            } else {
                Text(displayContent)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(currentContent.isEmpty ? Crucible.Color.ink3 : Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginContentEdit() }
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
                    Text(isRetranscribing ? "Transcribing…" : "Transcribe again with AI")
                    if !isRetranscribing { Image(systemName: "sparkles").font(.system(size: 12)) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Crucible.Color.aiBlue)
                .frame(minHeight: 38)
                .padding(.horizontal, 15)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Crucible.Color.aiBlue, lineWidth: 1))
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
                               : "Evidence in \(referencingCount) \(referencingCount == 1 ? "memory" : "memories")")
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
                        Text(edge.memory?.title ?? "Untitled memory")
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundStyle(Crucible.Color.ink)
                        Text(edgeDateText(edge))
                            .font(.system(size: 12))
                            .foregroundStyle(Crucible.Color.ink3)
                        if !isOpen {
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

    private var currentContent: String {
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

    private var displayContent: String {
        currentContent.isEmpty
            ? (media == .photo || media == .video ? "Add a description" : "(no transcript)")
            : currentContent
    }

    private var contentLabel: String { (media == .photo || media == .video) ? "Description" : "Transcript" }
    private var contentField: ClipEditorField { (media == .photo || media == .video) ? .description : .transcript }
    private var canRetranscribe: Bool { contentDraft == nil && (media == .voice || media == .video) }

    private var edges: [MemoryClipEdge] {
        if case .managed(let ref) = source { return ref.edgesArray }
        return []
    }
    private var referencingCount: Int { edges.count }

    private var deleteWarning: String {
        referencingCount == 0
            ? "This clip isn't in any memory yet."
            : "This clip is evidence in \(referencingCount) \(referencingCount == 1 ? "memory" : "memories"). Deleting it removes it from \(referencingCount == 1 ? "that memory" : "all of them")."
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

    private func commitContent(_ newValue: String) {
        switch source {
        case .inbox(let clip):
            InboxManifest.shared.recordTranscriptionAttempt(clipId: clip.clipId, transcript: newValue)
        case .managed(let ref):
            if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
                lifecycle.updateClipDescription(refId: ref.id, description: newValue)
            } else {
                lifecycle.updateClipTranscript(refId: ref.id, transcript: newValue)
            }
        }
    }

    private func commitOpenEdits() {
        // Done from the top bar while a field is open commits it (never lose
        // work), routed through the same gate via each editor's own onDone —
        // here we simply close drafts; the ClipEditor coordinator commits.
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
        case .inbox(let clip):  InboxManifest.shared.recycleClip(clipId: clip.clipId)
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
                    retryStatus = outcome.userFacingDeferralMessage
                } else {
                    // Reseed the edit field with the fresh transcript; the user
                    // still commits via Done (one commit path).
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

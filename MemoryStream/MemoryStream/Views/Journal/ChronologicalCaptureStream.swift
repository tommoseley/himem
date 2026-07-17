import SwiftUI
import UIKit
import AVFoundation

/// Chronological capture stream: emits one List row per capture in
/// `createdAt` order. The parent view embeds this inside a `List`, which
/// is why each row carries `.listRowSeparator`, `.listRowBackground`, and
/// `.listRowInsets` modifiers — List owns the scrolling. Row deletion is
/// the fate row's Delete; swipe-to-delete was retired June 12 2026
/// (`HiMem · Buttons & Actions §3`), so there are no swipe pills here.
///
/// Three panel kinds:
///   - **Voice clip**: timestamp + transcript text. Tap the transcript to
///     edit in place; "Original recording · Play" footer plays back the
///     audio. Delete via the fate row.
///   - **Note** (typed): timestamp + text. Tap the body to edit in place;
///     delete via the fate row.
///   - **Photo / video card**: thumbnail + optional description. Photo
///     tap consumes (opens description sheet); video play-overlay plays.
///     Delete via the fate row (no tap-to-consume path on video yet).
///
/// Photo grouping rule: walk captures sorted by createdAt, accumulate
/// consecutive image/video items into the current strip; flush the strip
/// whenever a voice or note breaks the run.
struct ChronologicalCaptureStream: View {
    let entry: EntryDisplayModel
    let onDeleteVoice: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void
    let onDeleteMedia: (UUID) -> Void
    /// Called when the user taps `Where does this belong?` on a
    /// clip's fate row. Parent presents `PlaceClipSheet`.
    let onRelocateClip: (UUID) -> Void
    /// Opens the AudioPlayerSheet for a voice clip — fires when the
    /// user taps the quiet "Original recording · Play" footer in the
    /// transcript-first VoiceClipPanel.
    let onOpenVoice: (MediaDisplayItem) -> Void
    /// Commits an inline transcript edit on a voice clip — fires when
    /// the user taps the transcript body, types, then taps away. The
    /// parent routes to `EntryLifecycleService.updateMediaTranscript`.
    let onCommitVoiceTranscript: (UUID, String) -> Void
    /// Commits an inline note edit — fires when the user taps a note
    /// body, types, then taps Done in the EditCommitBar (or another
    /// editor takes the active edit id). Parent routes to
    /// `EntryLifecycleService.updateNoteFragment`. Mirrors the
    /// `onCommitVoiceTranscript` shape.
    let onCommitNoteText: (UUID, String) -> Void
    /// Fires when the user taps the play-overlay circle on a video
    /// card — the quick-play shortcut that skips the description
    /// editor and goes straight to playback.
    let onPlayVideo: (MediaDisplayItem) -> Void
    /// Fires when the user taps a photo thumbnail on a Full-mode
    /// `MediaCard`. Container opens `QuickLookViewer` for the
    /// underlying file. Slice 9 (Memory Detail Full stream
    /// convergence): replaces the retired
    /// `onEditMediaDescription` whole-card route — thumbnail =
    /// consume; description slot = inline edit (Q3 separation).
    let onViewPhoto: (MediaDisplayItem) -> Void
    /// Commits an inline description edit on a photo/video from
    /// `MediaCard`'s embedded `ClipEditor(field: .description)`.
    /// Parent routes to `EntryLifecycleService.updateMediaDescription`.
    /// Slice 9 successor to `onEditMediaDescription` — no more
    /// sheet round-trip; the trimmed value lands here directly.
    let onCommitMediaDescription: (UUID, String) -> Void

    /// Opens the unified Clip Editor modal for a clip id — fired by the ✎ Edit
    /// affordance in an expanded row (2026-07-16 Memory Detail cycle). Editing
    /// routes here; the inline editors (`onCommit*`) are the retiring path,
    /// kept reachable-in-code but no longer entered on tap.
    let onEditClip: (UUID) -> Void

    /// View mode for long memories. `.full` is the historical behavior
    /// (one rich row per clip); `.compact` renders a scannable index of
    /// voice + note clips and skips photos/videos entirely. Short
    /// memories pin to `.full` — the toggle that produces `.compact`
    /// isn't even shown until the threshold is earned. Default keeps
    /// every existing call site unchanged.
    var mode: TranscriptMode = .full

    /// When non-nil and `mode == .compact`, the matching row renders in
    /// its open (expanded) state — header in accent + full transcript
    /// body below. Single-open accordion semantics: the parent makes
    /// sure only one row's id is here at a time, so opening one row
    /// closes any other.
    var openCompactRowId: UUID? = nil

    /// Fires when the user taps a Compact row's header — the parent
    /// toggles `openCompactRowId` (same id = close; different id = open
    /// that row instead).
    var onToggleCompactRow: ((UUID) -> Void)? = nil

    var body: some View {
        switch mode {
        case .full:    fullBody
        case .compact: compactBody
        }
    }

    /// Original chronological stream — one rich row per fragment, full
    /// swipe affordances. Identical to the pre-Compact-toggle behavior.
    @ViewBuilder
    private var fullBody: some View {
        ForEach(panels) { panel in
            switch panel.kind {
            case .voice(let item):
                TranscriptClipController(
                    item: item,
                    onPlay: { onOpenVoice(item) },
                    onCommit: { newText in
                        onCommitVoiceTranscript(item.id, newText)
                    },
                    onDelete: { onDeleteVoice(item.id) },
                    onRelocate: { onRelocateClip(item.id) },
                    onEdit: { onEditClip(item.id) }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            case .note(let item):
                TranscriptClipController(
                    item: item,
                    onPlay: nil,
                    onCommit: { newText in
                        onCommitNoteText(item.id, newText)
                    },
                    onDelete: { onDeleteNote(item.id) },
                    onRelocate: { onRelocateClip(item.id) },
                    onEdit: { onEditClip(item.id) }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            case .media(let item):
                // Slice 9 (Memory Detail Full stream convergence):
                // description edit lives inline in `MediaCard` via
                // `ClipEditor(field: .description)`. Whole-card tap
                // is retired — thumbnail = consume (viewer / player);
                // description slot = edit (Q3 separation).
                MediaCard(
                    item: item,
                    onPlayVideo: item.mediaType == .video ? { onPlayVideo(item) } : nil,
                    onViewPhoto: item.mediaType == .image ? { onViewPhoto(item) } : nil,
                    onSaveDescription: { newText in
                        onCommitMediaDescription(item.id, newText)
                    },
                    onDelete: { onDeleteMedia(item.id) },
                    onRelocate: { onRelocateClip(item.id) },
                    onEdit: { onEditClip(item.id) }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
    }

    /// Compact index — one slim List row per clip. Each row is a
    /// single-open expander (tap header → reveal the full transcript
    /// in place). Swipe-to-delete is retired (June 12 2026); a `Delete
    /// clip` button sits at the bottom of the expanded body — same
    /// bottom-Delete rule as everywhere else.
    @ViewBuilder
    private var compactBody: some View {
        ForEach(compactItems) { item in
            CompactClipRow(
                item: item,
                isOpen: openCompactRowId == item.id,
                // Voice/note tap = toggle the single-open accordion.
                // Photo/video tap = open the description editor
                // (matches Full-mode card-tap behavior). Media items
                // never expand-in-place because they have no
                // transcript to drop in — the chevron stays pointing
                // right (rotation only triggers on `isOpen`, which
                // the parent never sets for media).
                onTap: {
                    // Slice 9: Compact media rows route consume
                    // to the parent viewer path — description edit
                    // is a Full-mode concern (media rows are
                    // hidden in Compact per the collapsed accordion
                    // spec). Photo → QuickLook via onViewPhoto;
                    // video → AVPlayer via onPlayVideo. Voice/note
                    // still toggle the single-open accordion.
                    switch item.mediaType {
                    case .image:  onViewPhoto(item)
                    case .video:  onPlayVideo(item)
                    default:      onToggleCompactRow?(item.id)
                    }
                },
                // Voice clips edit inline through the lifecycle service;
                // notes will get their own path in a later slice (Phase
                // 3 of the unified-editing surgery).
                onCommitTranscript: item.mediaType == .voice
                    ? { newText in onCommitVoiceTranscript(item.id, newText) }
                    : nil,
                // Play control on voice rows in both read and edit
                // (spec rule #8). Same target as Full mode — opens
                // the AudioPlayerSheet via the parent.
                onPlay: item.mediaType == .voice
                    ? { onOpenVoice(item) }
                    : nil,
                // Bottom `Delete clip` button rendered inside the
                // expanded body. Image/video can't be expanded in
                // Compact, so the callback is unused for those —
                // tapping a media row opens the description editor,
                // which carries its own bottom Delete clip button.
                onDelete: { compactDeleteAction(item) },
                onRelocate: item.mediaType == .voice || item.mediaType == .note
                    ? { onRelocateClip(item.id) }
                    : nil,
                onEdit: item.mediaType == .voice || item.mediaType == .note
                    ? { onEditClip(item.id) }
                    : nil
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    /// Routes a Compact row's bottom `Delete clip` button to the same
    /// delete callback the Full row would invoke for that media type.
    private func compactDeleteAction(_ item: MediaDisplayItem) {
        switch item.mediaType {
        case .voice: onDeleteVoice(item.id)
        case .note:  onDeleteNote(item.id)
        case .image, .video: onDeleteMedia(item.id)
        }
    }

    /// All media items in createdAt order — the eligible set for the
    /// Compact index. Photos and videos render as tap-to-consume
    /// rows (no expand-in-place since there's no transcript to drop);
    /// voice and note rows keep the single-open-accordion behavior.
    /// Spec: `Memory Detail · long-memory navigation.md` — "one row
    /// per clip" extends to every capture in the memory; the index
    /// is the memory's table of contents, not a transcript-only
    /// scan. Earlier behavior filtered to voice + note and left
    /// photos/videos unreachable from Compact (bug fix 2026-06-11).
    private var compactItems: [MediaDisplayItem] {
        Self.compactItems(from: entry.mediaItems)
    }

    /// Pure helper — sorts the media items by createdAt and includes
    /// every type. Static + Sendable so `CompactItemsTests` can
    /// exercise the filter without building a SwiftUI environment.
    static func compactItems(from items: [MediaDisplayItem]) -> [MediaDisplayItem] {
        items.sorted { $0.createdAt < $1.createdAt }
    }

    /// Walks the entry's fragments in `createdAt` order, grouping contiguous
    /// image/video MediaReferences into a single grid panel and emitting
    /// voice/note as their own panels. Every fragment kind is now a
    /// `MediaDisplayItem`; the legacy `TextSegment`-flavored note path is
    /// gone.
    private var panels: [Panel] {
        var result: [Panel] = []
        let sorted = entry.mediaItems.sorted { $0.createdAt < $1.createdAt }
        for media in sorted {
            switch media.mediaType {
            case .voice: result.append(Panel(kind: .voice(media)))
            case .note:  result.append(Panel(kind: .note(media)))
            case .image, .video: result.append(Panel(kind: .media(media)))
            }
        }
        return result
    }

    struct Panel: Identifiable {
        enum Kind {
            case voice(MediaDisplayItem)
            case note(MediaDisplayItem)
            /// Photo or video as a full-width per-item card with a
            /// description. Replaces the prior `photoStrip` grouping
            /// — per `docs/design/HiMem · Photo Descriptions.html`,
            /// each photo/video is its own card so the empty-state
            /// description prompt or filled description has room to
            /// render alongside the media.
            case media(MediaDisplayItem)
        }
        let kind: Kind
        var id: String {
            switch kind {
            case .voice(let item): return "voice-\(item.id.uuidString)"
            case .note(let item): return "note-\(item.id.uuidString)"
            case .media(let item): return "media-\(item.id.uuidString)"
            }
        }
    }
}


// MARK: - Media card (photo / video with description)

/// Full-width per-item card for a photo or video in the chronological
/// stream. Per `docs/design/HiMem · Photo Descriptions.html`: the
/// description sits below the thumbnail as derived content; the photo
/// or video stays first-class. Tap the card to open the full-frame
/// viewer where the user can read or edit the description.
struct MediaCard: View {
    let item: MediaDisplayItem
    /// Fires when the user taps the play-overlay circle on a video
    /// thumbnail. Nil for photo items (the overlay isn't drawn) and
    /// for callers that haven't yet wired playback.
    var onPlayVideo: (() -> Void)? = nil
    /// Fires when the user taps the thumbnail on a photo item.
    /// Container opens `QuickLookViewer`. Nil = photo thumbnail is
    /// inert (video uses `onPlayVideo` for the play badge; photos
    /// only get a viewer when this is wired).
    var onViewPhoto: (() -> Void)? = nil
    /// Commits an edited description. Called by the inline
    /// `ClipEditor` on Done when the trimmed value differs from
    /// `item.mediaDescription`. Nil = description slot is read-only.
    var onSaveDescription: ((String) -> Void)? = nil
    /// Deletes the photo/video clip. Fires from the fate row inside
    /// the inline description editor (matches
    /// `VoiceClipPanel.onDelete` shape). Nil = fate row is hidden
    /// from the editor.
    var onDelete: (() -> Void)? = nil
    /// Relocates the photo/video clip to another memory / into a
    /// new memory. Fires from the fate row inside the inline
    /// description editor. Nil = the relocate half of the fate row
    /// is hidden.
    var onRelocate: (() -> Void)? = nil

    /// Opens the unified Clip Editor modal for the description (2026-07-16
    /// cycle). When non-nil, the ✎ Edit control (filled) / invite tap (empty)
    /// open the modal instead of the inline editor, which is retired but kept
    /// reachable-in-code.
    var onEdit: (() -> Void)? = nil

    /// Slice 9 (Memory Detail Full stream convergence): inline
    /// description edit state, replacing the retired
    /// `PhotoDescriptionEditSheet`. Nil = read state (invite or
    /// filled description); non-nil = editing (inline
    /// `ClipEditor(field: .description)`). Same pattern as
    /// `ClipDetailView`'s Slice 7 description slot — one editor,
    /// consistent across surfaces.
    @State private var editingDescription: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptureTimestampLabel(date: item.createdAt, placeName: item.placeName)
            MediaCardThumbnail(
                item: item,
                onPlayVideo: onPlayVideo,
                onTapPhoto: onViewPhoto
            )
            descriptionSlot
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crucible.Color.hairline, lineWidth: 1))
    }

    /// Description edit surface — tap-to-edit invite / filled body
    /// in read state, inline `ClipEditor` in edit state. Nil
    /// `onSaveDescription` collapses this to read-only.
    @ViewBuilder
    private var descriptionSlot: some View {
        if editingDescription != nil, let onSaveDescription, let onDelete {
            ClipEditor(
                field: .description,
                draft: Binding(
                    get: { editingDescription ?? "" },
                    set: { editingDescription = $0 }
                ),
                initialValue: item.mediaDescription ?? "",
                editId: "description-\(item.id.uuidString)",
                evidence: nil,
                fateActions: ClipEditorFateActions(
                    onDelete: onDelete,
                    onRelocate: onRelocate
                ),
                onCancel: { editingDescription = nil },
                onDone: { newValue in
                    onSaveDescription(newValue)
                    editingDescription = nil
                }
            )
        } else if let desc = item.mediaDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            // Filled description: the text stays selectable/non-tappable; a
            // quiet blue ✎ Edit control opens the modal (2026-07-16). Legacy
            // inline tap-to-edit only when no modal host is wired.
            if let onEdit {
                HStack(alignment: .top, spacing: 8) {
                    MediaDescriptionFilled(text: desc)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    descriptionEditButton(onEdit: onEdit)
                }
            } else {
                MediaDescriptionFilled(text: desc)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if onSaveDescription != nil { editingDescription = desc }
                    }
            }
        } else {
            // Empty invite — a distinct "add a description" affordance (dashed,
            // not content text), so tapping it to open the modal is honest.
            MediaDescriptionEmpty()
                .contentShape(Rectangle())
                .onTapGesture {
                    if let onEdit { onEdit() }
                    else if onSaveDescription != nil { editingDescription = "" }
                }
        }
    }

    /// Quiet blue **✎ Edit** control (≥44px) that opens the modal to the
    /// clip's description field — the photo/video counterpart to the
    /// transcript row's Edit affordance.
    private func descriptionEditButton(onEdit: @escaping () -> Void) -> some View {
        Button(action: onEdit) {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                Text("Edit")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Crucible.Color.aiBlue)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Thumbnail tile that drives the visual presence inside `MediaCard`.
/// Loads the photo via `ThumbnailService` and overlays a small
/// type/duration chip plus a play badge for video. Mirrors the design's
/// `MediaThumb` component.
private struct MediaCardThumbnail: View {
    let item: MediaDisplayItem
    let onPlayVideo: (() -> Void)?
    /// Slice 9: photo thumbnail tap → `QuickLookViewer` for the
    /// original file. Video keeps its own play-badge callback for
    /// the AVPlayer; the surrounding thumbnail area is inert on
    /// video so a stray tap doesn't compete with the badge.
    let onTapPhoto: (() -> Void)?

    @State private var thumbnail: UIImage?

    private let height: CGFloat = 168

    var body: some View {
        ZStack(alignment: .center) {
            thumbnailContent
            if item.mediaType == .video {
                Button {
                    onPlayVideo?()
                } label: {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Play video")
                .disabled(onPlayVideo == nil)
            }
        }
        .overlay(alignment: .bottomLeading) {
            typeChip
                .padding(9)
        }
        .frame(height: height)
        .task(id: item.id) {
            guard thumbnail == nil else { return }
            if let cached = await ThumbnailService.shared.cacheThumbnail(for: item.localIdentifier, mediaType: item.mediaType) {
                thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
            }
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        let tile = Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Crucible.Color.sunk)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        Image(systemName: item.mediaType == .video ? "video" : "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(Crucible.Color.ink4)
                    }
            }
        }
        if item.mediaType == .image, let onTapPhoto {
            Button(action: onTapPhoto) { tile }
                .buttonStyle(.plain)
                .accessibilityLabel("View photo")
        } else {
            tile
        }
    }

    @ViewBuilder
    private var typeChip: some View {
        HStack(spacing: 4) {
            if item.mediaType == .video {
                Image(systemName: "play.fill").font(.system(size: 9))
            }
            Text(item.mediaType == .video ? "Video" : "Photo")
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .textCase(.uppercase)
    }
}

/// Empty-state description prompt. Ochre invitation card — per the
/// design's color discipline, descriptions are HUMAN-written so the
/// affordance is the user-action color, never AI blue.
struct MediaDescriptionEmpty: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Crucible.Color.accent)
                    .frame(width: 26, height: 26)
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Add a description")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
                Text("A few words make this searchable and help HiMem organize the memory.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Crucible.Color.accentTint)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Filled-state description. The description becomes the card's body
/// text — parallel to a voice clip's transcript. No inline Edit
/// affordance: the whole card is tappable to edit. That matches the
/// voice clip panel (which also has no inline Edit affordance) and the
/// unified edit-sheet contract.
struct MediaDescriptionFilled: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DESCRIPTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink3)
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(3)
        }
    }
}

// MARK: - Capture timestamp label

/// Clip-row header per Memory Detail v3:
///   "Sun May 17 · 6:12 PM · Bishop St, Bluffton"
/// Year appears only when the capture isn't in the current calendar
/// year (e.g. "Sun May 17, 2025 · …"). The trailing place segment is
/// omitted when `placeName` is nil — legacy clips without location,
/// or clips whose reverse-geocode is still in flight.
struct CaptureTimestampLabel: View {
    let date: Date
    var placeName: String? = nil

    var body: some View {
        Text(formatted)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Crucible.Color.ink3)
            .accessibilityLabel(accessibilityLabel)
    }

    private var formatted: String {
        let dateStr = Self.dateFormatter(for: date).string(from: date)
        let timeStr = Self.timeFormatter.string(from: date)
        if let placeName, !placeName.isEmpty {
            return "\(dateStr) · \(timeStr) · \(placeName)"
        }
        return "\(dateStr) · \(timeStr)"
    }

    private var accessibilityLabel: String {
        "Captured \(formatted)"
    }

    /// Suppresses the year for the current calendar year so the
    /// header doesn't get noisy with current-year stamps. Older
    /// captures gain a year segment (`Sun May 17, 2025`) so the
    /// user isn't ambiguous about whether a memory is recent.
    private static func dateFormatter(for date: Date) -> DateFormatter {
        let cal = Calendar.current
        let captureYear = cal.component(.year, from: date)
        let currentYear = cal.component(.year, from: Date())
        return captureYear == currentYear ? currentYearDateFormatter : olderYearDateFormatter
    }

    private static let currentYearDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private static let olderYearDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

// MARK: - Photo grid layout (retained as a pure helper)

/// Pure column-count rule used by `PhotoGridLayoutTests`. The runtime
/// view that used to consume this (`PhotoFilmstripPanel`) was retired
/// 2026-06-12 when photos/videos moved to per-card `MediaCard` rows
/// in the chronological stream; the enum stays because the tests do.
enum PhotoGridLayout {
    static func columnCount(isPad: Bool, isLandscape: Bool) -> Int {
        if isPad {
            return isLandscape ? 6 : 4
        } else {
            return isLandscape ? 5 : 3
        }
    }
}

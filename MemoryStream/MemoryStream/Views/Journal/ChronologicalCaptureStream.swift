import SwiftUI
import UIKit

/// Chronological capture stream: emits one List row per capture in
/// `createdAt` order. The parent view embeds this inside a `List`, which
/// is why each row carries `.listRowSeparator`, `.listRowBackground`, and
/// `.listRowInsets` modifiers — List is responsible for both scrolling
/// and swipe-action coordination, so vertical drags scroll while
/// horizontal drags reveal the swipe pills.
///
/// Three panel kinds:
///   - **Voice clip**: timestamp + transcript text. Leading swipe opens the
///     AudioPlayerSheet (play + transcript editor); trailing swipe deletes.
///   - **Note** (typed): timestamp + text. Leading swipe opens the
///     NoteEditorSheet; trailing swipe deletes.
///   - **Photo grid**: contiguous image/video MediaReferences group into
///     one row rendered as a 3-wide `LazyVGrid`. Per-tile X buttons handle
///     delete; the row itself doesn't have swipe actions.
///
/// Photo grouping rule: walk captures sorted by createdAt, accumulate
/// consecutive image/video items into the current strip; flush the strip
/// whenever a voice or note breaks the run.
struct ChronologicalCaptureStream: View {
    let entry: EntryDisplayModel
    let onDeleteVoice: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void
    let onDeleteMedia: (UUID) -> Void
    /// Opens the AudioPlayerSheet for a voice clip — fires on leading swipe.
    let onOpenVoice: (MediaDisplayItem) -> Void
    /// Opens the NoteEditorSheet for a note fragment — fires on leading swipe.
    let onOpenNote: (MediaDisplayItem) -> Void
    /// Opens the full-frame photo / video viewer for a photo or video
    /// item. The viewer hosts read + edit of the
    /// `MediaDisplayItem.mediaDescription` per
    /// `docs/design/HiMem · Photo Descriptions.html`.
    let onTapPhoto: (MediaDisplayItem) -> Void

    var body: some View {
        ForEach(panels) { panel in
            switch panel.kind {
            case .voice(let item):
                VoiceClipPanel(item: item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { onOpenVoice(item) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Crucible.Color.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { onDeleteVoice(item.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            case .note(let item):
                NotePanel(item: item)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { onOpenNote(item) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Crucible.Color.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { onDeleteNote(item.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            case .media(let item):
                MediaCard(item: item, onTap: { onTapPhoto(item) })
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { onTapPhoto(item) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Crucible.Color.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { onDeleteMedia(item.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
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

// MARK: - Voice clip panel

/// Renders one `.voice` MediaReference as the visual content of a List row.
/// Swipe actions are configured by the parent List context — this view
/// just owns the timestamp + transcript layout.
struct VoiceClipPanel: View {
    let item: MediaDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptureTimestampLabel(date: item.createdAt, placeName: item.placeName)
            Text(displayText.attributedWithLinks())
                .font(.callout)
                .foregroundStyle(item.transcript == nil || item.transcript?.isEmpty == true
                                 ? Crucible.Color.ink4 : Crucible.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
    }

    private var displayText: String {
        if let t = item.transcript, !t.isEmpty { return t }
        return "(no transcript)"
    }
}

// MARK: - Note panel

private struct NotePanel: View {
    /// Backed by a `.note` MediaReference — `text` carries the body.
    let item: MediaDisplayItem

    private var bodyText: String { item.text ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptureTimestampLabel(date: item.createdAt, placeName: item.placeName)
            Text(bodyText.attributedWithLinks())
                .font(.callout)
                .foregroundStyle(Crucible.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                CaptureTimestampLabel(date: item.createdAt, placeName: item.placeName)
                MediaCardThumbnail(item: item)
                if let desc = item.mediaDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    MediaDescriptionFilled(text: desc)
                } else {
                    MediaDescriptionEmpty()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Crucible.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Crucible.Color.hairline, lineWidth: 1))
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
    @State private var thumbnail: UIImage?

    private let height: CGFloat = 168

    var body: some View {
        ZStack(alignment: .center) {
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
            if item.mediaType == .video {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
            }
        }
        .overlay(alignment: .bottomLeading) {
            typeChip
                .padding(9)
        }
        .frame(height: height)
        .task(id: item.id) {
            guard thumbnail == nil else { return }
            if let cached = await ThumbnailService.shared.cacheThumbnail(for: item.localIdentifier) {
                thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
            }
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
/// affordance: the whole card is tappable, and the swipe action says
/// Edit. That matches the voice clip panel (which also has no inline
/// Edit affordance) and the unified edit-sheet contract.
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

// MARK: - Photo grid panel

/// Pure column-count rule for the chronological capture stream's photo
/// grid. Exposed for unit tests — runtime callers go through
/// `PhotoFilmstripPanel`, which reads device + scene orientation.
///
/// Column counts pinned 2026-05-11 per Tom: iPhone tilesy stay smaller
/// for thumb scanning (3 portrait / 5 landscape); iPad tiles are larger
/// because the tablet is for review, not capture (4 portrait / 6 landscape).
enum PhotoGridLayout {
    static func columnCount(isPad: Bool, isLandscape: Bool) -> Int {
        if isPad {
            return isLandscape ? 6 : 4
        } else {
            return isLandscape ? 5 : 3
        }
    }
}

/// Renders one chronological cluster of `.image` / `.video` MediaReferences
/// (i.e. captures taken within ~10 minutes of each other) as a responsive
/// grid: 3 cols on iPhone portrait, 5 on iPhone landscape, 4 on iPad
/// portrait, 6 on iPad landscape. Each cluster is its own grid; multiple
/// clusters in an entry stack vertically with the chronological capture
/// stream's other panels in between, preserving capture-time ordering.
///
/// Reactivity: SwiftUI's `horizontalSizeClass` / `verticalSizeClass` don't
/// distinguish iPad portrait from landscape (both `.regular`), so we read
/// the active scene's `interfaceOrientation` and refresh on
/// `UIDevice.orientationDidChangeNotification`.
private struct PhotoFilmstripPanel: View {
    let items: [MediaDisplayItem]
    let onDelete: (UUID) -> Void
    let onTap: (MediaDisplayItem) -> Void

    @State private var isLandscape: Bool = PhotoFilmstripPanel.currentSceneIsLandscape()

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(items) { item in
                MediaTile(
                    localIdentifier: item.localIdentifier,
                    mediaType: item.mediaType,
                    createdAt: item.createdAt,
                    onRemove: { onDelete(item.id) },
                    onTap: { onTap(item) }
                )
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            isLandscape = PhotoFilmstripPanel.currentSceneIsLandscape()
        }
    }

    private var gridColumns: [GridItem] {
        let cols = PhotoGridLayout.columnCount(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            isLandscape: isLandscape
        )
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: cols)
    }

    private static func currentSceneIsLandscape() -> Bool {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        return scene?.interfaceOrientation.isLandscape ?? false
    }
}

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
            case .photoStrip(let items):
                PhotoFilmstripPanel(
                    items: items,
                    onDelete: onDeleteMedia,
                    onTap: onTapPhoto
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
    }

    /// Walks the entry's fragments in `createdAt` order, grouping contiguous
    /// image/video MediaReferences into a single grid panel and emitting
    /// voice/note as their own panels. Every fragment kind is now a
    /// `MediaDisplayItem`; the legacy `TextSegment`-flavored note path is
    /// gone.
    private var panels: [Panel] {
        struct Item { let createdAt: Date; let kind: ItemKind }
        enum ItemKind {
            case voice(MediaDisplayItem)
            case note(MediaDisplayItem)
            case photoOrVideo(MediaDisplayItem)
        }

        var items: [Item] = []
        for media in entry.mediaItems {
            switch media.mediaType {
            case .voice: items.append(Item(createdAt: media.createdAt, kind: .voice(media)))
            case .note:  items.append(Item(createdAt: media.createdAt, kind: .note(media)))
            case .image, .video: items.append(Item(createdAt: media.createdAt, kind: .photoOrVideo(media)))
            }
        }
        items.sort { $0.createdAt < $1.createdAt }

        var result: [Panel] = []
        var currentStrip: [MediaDisplayItem] = []

        func flushStrip() {
            if !currentStrip.isEmpty {
                result.append(Panel(kind: .photoStrip(currentStrip)))
                currentStrip = []
            }
        }

        for item in items {
            switch item.kind {
            case .voice(let media):
                flushStrip()
                result.append(Panel(kind: .voice(media)))
            case .note(let media):
                flushStrip()
                result.append(Panel(kind: .note(media)))
            case .photoOrVideo(let media):
                currentStrip.append(media)
            }
        }
        flushStrip()
        return result
    }

    struct Panel: Identifiable {
        enum Kind {
            case voice(MediaDisplayItem)
            case note(MediaDisplayItem)
            case photoStrip([MediaDisplayItem])
        }
        let kind: Kind
        var id: String {
            switch kind {
            case .voice(let item): return "voice-\(item.id.uuidString)"
            case .note(let item): return "note-\(item.id.uuidString)"
            case .photoStrip(let items): return "strip-" + items.map(\.id.uuidString).joined(separator: ",")
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
            CaptureTimestampLabel(date: item.createdAt)
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
            CaptureTimestampLabel(date: item.createdAt)
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

// MARK: - Capture timestamp label

/// Small h:mm a label rendered above each chronological capture panel.
/// Keeps a consistent style across voice / note panels and matches the
/// timestamp overlay rendered by MediaTile on photo/video tiles.
private struct CaptureTimestampLabel: View {
    let date: Date

    var body: some View {
        Text(Self.formatter.string(from: date))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Crucible.Color.ink3)
            .accessibilityLabel("Captured at \(Self.formatter.string(from: date))")
    }

    private static let formatter: DateFormatter = {
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

import SwiftUI

/// Chronological capture stream: replaces the entry-detail "content text +
/// media grid" block with per-capture panels rendered in `createdAt` order.
///
/// Three panel kinds:
///   - **Voice clip**: × delete + ▶︎ play + transcript text. Tap to open the
///     full audio player. Edit-tap on the transcript edits in place.
///   - **Note** (typed): × delete + text. Edit-tap edits in place.
///   - **Photo filmstrip**: contiguous image/video MediaReferences (no
///     voice/note between them) group into one panel; horizontal scroll if
///     it overflows.
///
/// Photo grouping rule: walk captures sorted by createdAt, accumulate
/// consecutive image/video items into the current filmstrip; flush the
/// filmstrip whenever a voice or note breaks the run.
struct ChronologicalCaptureStream: View {
    let entry: EntryDisplayModel
    let onDeleteVoice: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void
    let onDeleteMedia: (UUID) -> Void
    let onEditNote: (UUID, String) -> Void
    let onEditTranscript: (UUID, String) -> Void
    let onPlayVoice: (MediaDisplayItem) -> Void
    let onTapPhoto: (MediaDisplayItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(panels) { panel in
                switch panel.kind {
                case .voice(let item):
                    VoiceClipPanel(
                        item: item,
                        onDelete: { onDeleteVoice(item.id) },
                        onPlay: { onPlayVoice(item) },
                        onEditTranscript: { newText in onEditTranscript(item.id, newText) }
                    )
                case .note(let segment):
                    NotePanel(
                        segment: segment,
                        onDelete: { onDeleteNote(segment.id) },
                        onEdit: { newText in onEditNote(segment.id, newText) }
                    )
                case .photoStrip(let items):
                    PhotoFilmstripPanel(
                        items: items,
                        onDelete: onDeleteMedia,
                        onTap: onTapPhoto
                    )
                }
            }
        }
    }

    /// Walks the entry's captures in `createdAt` order, grouping contiguous
    /// image/video MediaReferences into a single filmstrip panel and
    /// emitting voice/note as their own panels.
    private var panels: [Panel] {
        struct Item { let createdAt: Date; let kind: ItemKind }
        enum ItemKind {
            case voice(MediaDisplayItem)
            case note(TextSegmentDisplayItem)
            case photoOrVideo(MediaDisplayItem)
        }

        var items: [Item] = []
        for media in entry.mediaItems {
            switch media.mediaType {
            case .voice: items.append(Item(createdAt: media.createdAt, kind: .voice(media)))
            case .image, .video: items.append(Item(createdAt: media.createdAt, kind: .photoOrVideo(media)))
            }
        }
        for segment in entry.textSegments {
            items.append(Item(createdAt: segment.createdAt, kind: .note(segment)))
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
            case .note(let segment):
                flushStrip()
                result.append(Panel(kind: .note(segment)))
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
            case note(TextSegmentDisplayItem)
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

private struct VoiceClipPanel: View {
    let item: MediaDisplayItem
    let onDelete: () -> Void
    let onPlay: () -> Void
    let onEditTranscript: (String) -> Void

    @StateObject private var player = AudioPlayerService.shared
    @State private var editing = false
    @State private var draftText = ""

    private var isPlayingThis: Bool {
        player.isPlaying && player.currentFile == item.localIdentifier
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onPlay) {
                Image(systemName: isPlayingThis ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.system(size: 18))
                    .foregroundStyle(Crucible.Color.Media.audio)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play voice clip")

            if editing {
                TextEditor(text: $draftText)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Crucible.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Crucible.Color.hairline))
                    .onAppear { draftText = item.transcript ?? "" }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                onEditTranscript(draftText.trimmingCharacters(in: .whitespacesAndNewlines))
                                editing = false
                            }
                        }
                    }
            } else {
                Text(displayText)
                    .font(.callout)
                    .foregroundStyle(item.transcript == nil || item.transcript?.isEmpty == true
                                     ? Crucible.Color.ink4 : Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .onTapGesture(count: 2) { editing = true }
            }
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
        .swipeToDelete(onDelete: onDelete, accessibilityLabel: "Delete voice clip")
    }

    private var displayText: String {
        if let t = item.transcript, !t.isEmpty { return t }
        return "(no transcript)"
    }
}

// MARK: - Note panel

private struct NotePanel: View {
    let segment: TextSegmentDisplayItem
    let onDelete: () -> Void
    let onEdit: (String) -> Void

    @State private var editing = false
    @State private var draftText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Spacer where the speaker icon lives on voice panels — keeps
            // text alignment consistent across panel types.
            Color.clear.frame(width: 18, height: 18)

            if editing {
                TextEditor(text: $draftText)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Crucible.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Crucible.Color.hairline))
                    .onAppear { draftText = segment.text }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                onEdit(draftText.trimmingCharacters(in: .whitespacesAndNewlines))
                                editing = false
                            }
                        }
                    }
            } else {
                Text(segment.text)
                    .font(.callout)
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .onTapGesture(count: 2) { editing = true }
            }
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
        .swipeToDelete(onDelete: onDelete, accessibilityLabel: "Delete note")
    }
}

// MARK: - Swipe-to-delete modifier

extension View {
    /// Wraps the view with a swipe-right-to-delete affordance: drag the
    /// content rightward to reveal a red Delete button on the leading edge,
    /// tap it to fire `onDelete`. Drag past `commitThreshold` and release
    /// to delete in one motion.
    ///
    /// Used on voice and note panels in the chronological capture stream.
    /// Photo filmstrip tiles keep their inline × because the horizontal
    /// scroll inside the filmstrip would compete with this gesture.
    func swipeToDelete(onDelete: @escaping () -> Void, accessibilityLabel: String = "Delete") -> some View {
        modifier(SwipeToDeleteModifier(onDelete: onDelete, accessibilityLabel: accessibilityLabel))
    }
}

private struct SwipeToDeleteModifier: ViewModifier {
    let onDelete: () -> Void
    let accessibilityLabel: String

    @State private var offset: CGFloat = 0
    @State private var revealed: Bool = false
    /// Once the drag is dominantly horizontal, we lock into swipe mode for
    /// the rest of the drag — otherwise the parent ScrollView's gesture can
    /// re-claim the touch when the user's finger wobbles vertically.
    @State private var engagedHorizontal: Bool = false

    private let revealWidth: CGFloat = 88
    private let commitThreshold: CGFloat = 200

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            // Delete affordance behind the content — reveals as the user
            // drags right. Tap fires the delete; the row otherwise snaps
            // back when released below the reveal threshold.
            Button(role: .destructive) {
                onDelete()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    if offset > revealWidth * 0.6 {
                        Text("Delete")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: max(0, offset))
                .frame(maxHeight: .infinity)
                .background(Crucible.Color.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .opacity(offset > 4 ? 1 : 0)

            content
                .offset(x: offset)
                // simultaneousGesture lets the parent ScrollView keep its
                // vertical scroll while we still claim horizontal drags.
                // Without this, the ScrollView's pan recognizer eats the
                // touch and our DragGesture's onChanged never fires.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            // First-pass direction lock: once we see a
                            // dominantly-horizontal drag, stay in swipe mode
                            // for the rest of this gesture so vertical
                            // wobbles don't release us back to the ScrollView.
                            if !engagedHorizontal {
                                let dx = value.translation.width
                                let dy = value.translation.height
                                if dx > 4, abs(dx) > abs(dy) * 1.4 {
                                    engagedHorizontal = true
                                } else if abs(dy) > abs(dx) {
                                    return
                                }
                            }
                            guard engagedHorizontal else { return }
                            let proposed = value.translation.width + (revealed ? revealWidth : 0)
                            offset = max(0, min(proposed, commitThreshold))
                        }
                        .onEnded { _ in
                            defer { engagedHorizontal = false }
                            if offset >= commitThreshold {
                                withAnimation(.easeOut(duration: 0.18)) { offset = commitThreshold }
                                onDelete()
                            } else if offset > revealWidth * 0.6 {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    offset = revealWidth
                                    revealed = true
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    offset = 0
                                    revealed = false
                                }
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Photo filmstrip panel

private struct PhotoFilmstripPanel: View {
    let items: [MediaDisplayItem]
    let onDelete: (UUID) -> Void
    let onTap: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    MediaTile(
                        localIdentifier: item.localIdentifier,
                        mediaType: item.mediaType,
                        onRemove: { onDelete(item.id) },
                        onTap: { onTap(item) }
                    )
                    .frame(width: 110, height: 110)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

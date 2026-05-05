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
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Crucible.Color.ink4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete voice clip")

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
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Crucible.Color.ink4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete note")

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

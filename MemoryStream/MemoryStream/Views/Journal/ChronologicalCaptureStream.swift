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
        .swipeActions(
            onDelete: onDelete,
            onEdit: { editing = true },
            deleteAccessibilityLabel: "Delete voice clip",
            editAccessibilityLabel: "Edit transcript"
        )
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
        .swipeActions(
            onDelete: onDelete,
            onEdit: { editing = true },
            deleteAccessibilityLabel: "Delete note",
            editAccessibilityLabel: "Edit note"
        )
    }
}

// MARK: - Swipe actions modifier (pill-style)

extension View {
    /// Outlook-style swipe action pills.
    ///
    /// Right-to-left swipe → trailing red Delete pill.
    /// Left-to-right swipe → leading accent Edit pill (only if `onEdit` is
    /// non-nil — pure delete-only panels just don't reveal anything on the
    /// rightward drag).
    ///
    /// Tap the pill to fire its action; drag past `commitThreshold` and
    /// release to fire in one motion.
    func swipeActions(
        onDelete: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        deleteAccessibilityLabel: String = "Delete",
        editAccessibilityLabel: String = "Edit"
    ) -> some View {
        modifier(SwipeActionsModifier(
            onDelete: onDelete,
            onEdit: onEdit,
            deleteAccessibilityLabel: deleteAccessibilityLabel,
            editAccessibilityLabel: editAccessibilityLabel
        ))
    }
}

private struct SwipeActionsModifier: ViewModifier {
    let onDelete: () -> Void
    let onEdit: (() -> Void)?
    let deleteAccessibilityLabel: String
    let editAccessibilityLabel: String

    /// Signed offset: negative = revealing trailing Delete, positive =
    /// revealing leading Edit. Magnitude clamped to `commitThreshold`.
    @State private var offset: CGFloat = 0
    @State private var revealed: RevealedSide? = nil
    /// Once the drag is dominantly horizontal, lock for the rest of the
    /// gesture so vertical wobbles don't yield to the parent ScrollView.
    @State private var engagedHorizontal: Bool = false

    private enum RevealedSide { case leading, trailing }

    private let revealWidth: CGFloat = 84
    private let commitThreshold: CGFloat = 200

    func body(content: Content) -> some View {
        ZStack {
            // Leading Edit pill — visible only on positive offset.
            if let onEdit, offset > 4 {
                HStack(spacing: 0) {
                    SwipeActionPill(
                        icon: "pencil",
                        label: "Edit",
                        color: .blue,
                        action: onEdit
                    )
                    .frame(width: offset)
                    .accessibilityLabel(editAccessibilityLabel)
                    Spacer(minLength: 0)
                }
            }

            // Trailing Delete pill — visible only on negative offset.
            if offset < -4 {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SwipeActionPill(
                        icon: "trash",
                        label: "Delete",
                        color: Crucible.Color.danger,
                        action: onDelete
                    )
                    .frame(width: -offset)
                    .accessibilityLabel(deleteAccessibilityLabel)
                }
            }

            content
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if !engagedHorizontal {
                                let dx = value.translation.width
                                let dy = value.translation.height
                                if abs(dx) > 4, abs(dx) > abs(dy) * 1.4 {
                                    engagedHorizontal = true
                                } else if abs(dy) > abs(dx) {
                                    return
                                }
                            }
                            guard engagedHorizontal else { return }

                            let base: CGFloat = {
                                switch revealed {
                                case .leading: return revealWidth
                                case .trailing: return -revealWidth
                                case .none: return 0
                                }
                            }()
                            var proposed = value.translation.width + base
                            // If no Edit handler, can't drag rightward.
                            if onEdit == nil { proposed = min(0, proposed) }
                            offset = max(-commitThreshold, min(proposed, commitThreshold))
                        }
                        .onEnded { _ in
                            defer { engagedHorizontal = false }
                            // Negative = trailing/Delete.
                            if offset <= -commitThreshold {
                                withAnimation(.easeOut(duration: 0.18)) { offset = -commitThreshold }
                                onDelete()
                            } else if offset < -revealWidth * 0.6 {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    offset = -revealWidth
                                    revealed = .trailing
                                }
                            }
                            // Positive = leading/Edit.
                            else if offset >= commitThreshold, onEdit != nil {
                                withAnimation(.easeOut(duration: 0.18)) { offset = commitThreshold }
                                onEdit?()
                                // Snap back so pill doesn't linger.
                                withAnimation(.easeOut(duration: 0.18).delay(0.05)) {
                                    offset = 0
                                    revealed = nil
                                }
                            } else if offset > revealWidth * 0.6, onEdit != nil {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    offset = revealWidth
                                    revealed = .leading
                                }
                            }
                            // Snap closed.
                            else {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    offset = 0
                                    revealed = nil
                                }
                            }
                        }
                )
        }
    }
}

/// Outlook-style swipe action pill — vertically stacked icon over label,
/// inset from the row edges so it reads as a separate button rather than
/// a flush stripe.
private struct SwipeActionPill: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
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

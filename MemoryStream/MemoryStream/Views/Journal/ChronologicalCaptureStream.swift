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
    /// Opens the AudioPlayerSheet for a voice clip — fires on swipe-edit.
    /// Sheet is the canonical surface for playing AND editing the
    /// transcript; the panel itself doesn't have a tap-to-play affordance.
    let onOpenVoice: (MediaDisplayItem) -> Void
    let onTapPhoto: (MediaDisplayItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(panels) { panel in
                switch panel.kind {
                case .voice(let item):
                    VoiceClipPanel(
                        item: item,
                        onDelete: { onDeleteVoice(item.id) },
                        onOpenSheet: { onOpenVoice(item) }
                    )
                case .note(let item):
                    NotePanel(
                        item: item,
                        onDelete: { onDeleteNote(item.id) },
                        onEdit: { newText in onEditNote(item.id, newText) }
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

    /// Walks the entry's fragments in `createdAt` order, grouping contiguous
    /// image/video MediaReferences into a single filmstrip panel and
    /// emitting voice/note as their own panels. Every fragment kind is now
    /// a `MediaDisplayItem`; the legacy `TextSegment`-flavored note path is
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

/// Renders one `.voice` MediaReference — used wherever voice fragments
/// appear in the chronological capture stream. Single shape regardless of
/// how the clip was captured (FAB recorder, watch promotion, Contribute).
struct VoiceClipPanel: View {
    let item: MediaDisplayItem
    let onDelete: () -> Void
    /// Opens the AudioPlayerSheet — the canonical play + edit-transcript
    /// surface for a voice clip. Tap on the panel and swipe-right both
    /// route here; the sheet's transcript editor is the only way to edit
    /// the clip's transcript now.
    let onOpenSheet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptureTimestampLabel(date: item.createdAt)
            Text(displayText)
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
        .swipeActions(
            onDelete: onDelete,
            onEdit: onOpenSheet,
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
    /// Backed by a `.note` MediaReference — `text` carries the body.
    let item: MediaDisplayItem
    let onDelete: () -> Void
    let onEdit: (String) -> Void

    @State private var editing = false
    @State private var draftText = ""

    private var bodyText: String { item.text ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptureTimestampLabel(date: item.createdAt)
            if editing {
                TextEditor(text: $draftText)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Crucible.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Crucible.Color.hairline))
                    .onAppear { draftText = bodyText }
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
                Text(bodyText)
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
                        action: {
                            // Snap closed before firing — the panel may swap
                            // to a taller editing layout, and a lingering
                            // pill stretches with it.
                            withAnimation(.easeOut(duration: 0.18)) {
                                offset = 0
                                revealed = nil
                            }
                            onEdit()
                        }
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
                        action: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                offset = 0
                                revealed = nil
                            }
                            onDelete()
                        }
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

// MARK: - Photo grid panel

/// Renders one chronological cluster of `.image` / `.video` MediaReferences
/// (i.e. captures taken within ~10 minutes of each other) as a 3-column
/// grid. Each cluster is its own grid; multiple clusters in an entry stack
/// vertically with the chronological capture stream's other panels in
/// between, preserving capture-time ordering.
///
/// Initially this was a horizontal-scrolling filmstrip — the
/// "infinite-width row" was confusing and lost the at-a-glance overview
/// the prior 3-wide grid layout provided. Switched back 2026-05-10.
private struct PhotoFilmstripPanel: View {
    let items: [MediaDisplayItem]
    let onDelete: (UUID) -> Void
    let onTap: (MediaDisplayItem) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
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
    }
}

import SwiftUI
import AVFoundation

/// Two view components shipped together because they only exist for each
/// other: the section header that owns the Full ⇄ Compact toggle, and the
/// row that renders one clip in Compact mode. Design source of truth:
/// `docs/design/screens-memory-detail.jsx` §"Long memory · Full ⇄ Compact"
/// (Tom 2026-06-09).

// MARK: - Transcript section header

/// Eyebrow above the transcript section: `Transcript · N clips · N words`
/// on the left, a two-segment Full/Compact toggle on the right. Only
/// rendered when `TranscriptModeThreshold.toggleEarned(...)` returns true
/// — short memories never see the control. The eyebrow's count text is
/// authoritative; callers pass the same numbers they fed the threshold
/// check so the display can never drift.
struct TranscriptHeaderControl: View {
    let clipCount: Int
    let wordCount: Int
    @Binding var mode: TranscriptMode

    var body: some View {
        HStack(alignment: .center) {
            Text(eyebrowText)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Crucible.Color.ink3)
            Spacer(minLength: 12)
            toggle
        }
    }

    private var eyebrowText: String {
        // `formatted()` on Int respects the user's locale for grouping —
        // 3,581 in en-US, 3.581 in de-DE, etc. The design eyebrow is
        // information density, not a brand mark, so locale-correctness
        // matters more than visual rigidity.
        "Transcript · \(clipCount) clips · \(wordCount.formatted()) words"
    }

    private var toggle: some View {
        HStack(spacing: 2) {
            segmentButton(
                target: .full,
                systemImage: "text.alignleft",
                a11yLabel: "Full transcript view"
            )
            segmentButton(
                target: .compact,
                systemImage: "list.bullet",
                a11yLabel: "Compact index view"
            )
        }
        .padding(3)
        .background(Crucible.Color.sunk, in: RoundedRectangle(cornerRadius: 11))
    }

    private func segmentButton(target: TranscriptMode, systemImage: String, a11yLabel: String) -> some View {
        let active = mode == target
        return Button {
            // 44pt hit floor (Crucible rule). The visible chrome is 34pt
            // but the tap zone is generous via `.frame` + `contentShape`.
            mode = target
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Crucible.Color.ink : Crucible.Color.ink3)
                .frame(width: 42, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(active ? Crucible.Color.card : Color.clear)
                        .shadow(color: active ? Color.black.opacity(0.08) : .clear, radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - Compact clip row

/// One row in the Compact transcript index — a single-open expander.
/// Collapsed: a `HH:MM` stamp, a single-line preview, a chevron, ~52pt
/// tall. Open: chevron rotates 90°, time + chevron switch to the accent
/// colour, the preview turns semibold, and the full transcript drops in
/// below the header in place. Tapping toggles open/closed; the parent
/// enforces the single-open accordion by only allowing one row's id to
/// be `isOpen` at a time.
///
/// A Compact row is still a clip — the parent attaches the same swipe
/// actions a Full clip card has (leading ochre Edit, trailing red Trash).
/// We don't put .swipeActions here because they only work on List rows,
/// and Compact rows ARE List rows when used in the chronological stream.
///
/// Renders every capture as a single row in the Compact index. Voice
/// and note rows expand in place to reveal the transcript; photo and
/// video rows are tap-to-consume — they have no transcript to drop in,
/// so the tap fires the parent's viewer / player callback instead.
/// Photos and videos earned a row in 2026-06-11 — the prior behavior
/// hid them from Compact entirely, leaving users unable to reach their
/// own captures without flipping to Full.
struct CompactClipRow: View {
    let item: MediaDisplayItem
    let isOpen: Bool
    let onTap: () -> Void
    /// Fires when the user taps the expanded transcript body to edit
    /// it in place. Nil callers render the expanded body as static
    /// text — used by items without an edit path (media, legacy notes).
    let onCommitTranscript: ((String) -> Void)?
    /// Fires when the user taps the quiet "Original recording · Play"
    /// footer beneath the expanded transcript. Per spec rule #8
    /// (June 10 2026): the play control is present in **both** read
    /// AND edit states for every voice clip — replaying audio is
    /// precisely what users do while fixing a transcript. Nil for
    /// non-voice items (the footer isn't drawn).
    let onPlay: (() -> Void)?
    /// Delete clip on the fate row — always destroys. Image/video
    /// rows tap into the description editor; this callback is unused
    /// for those.
    let onDelete: () -> Void
    /// Where does this belong? on the fate row — opens the placement
    /// sheet. Nil for image/video (they use the description editor's
    /// own delete affordance).
    let onRelocate: (() -> Void)?

    /// Slice 10b (Clip Model convergence): inline edit state.
    /// Nil = read; non-nil = editing (renders `ClipEditor(field:
    /// .transcript)` in the expanded body). Replaces the retired
    /// `isEditingTranscript` / `transcriptDraft` / `FocusState`
    /// / `TextEditCoordinator` observer trio — `ClipEditor` owns
    /// coordinator participation and focus internally.
    @State private var editingDraft: String? = nil

    /// Audio duration in seconds, resolved lazily so the play footer
    /// reads "Original recording · 0:48".
    @State private var audioDuration: TimeInterval? = nil

    init(
        item: MediaDisplayItem,
        isOpen: Bool,
        onTap: @escaping () -> Void,
        onCommitTranscript: ((String) -> Void)? = nil,
        onPlay: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        onRelocate: (() -> Void)? = nil
    ) {
        self.item = item
        self.isOpen = isOpen
        self.onTap = onTap
        self.onCommitTranscript = onCommitTranscript
        self.onPlay = onPlay
        self.onDelete = onDelete
        self.onRelocate = onRelocate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen, let fullBody = Self.expandedBody(for: item) {
                expandedTranscriptArea(fallback: fullBody)
                if let onPlay, item.mediaType == .voice {
                    // Play footer present in read AND edit (spec
                    // rule #8). Tap fires the parent's audio-player
                    // sheet — same callback as
                    // `TranscriptClipController`.
                    // E3 alignment: same glyph shape as the atom's
                    // reflective namedPlay (`play`, not
                    // `play.circle`), same tint discipline (accent
                    // for the triangle, ink3 for the label) so the
                    // compact expanded body's play affordance
                    // reads as the same primitive.
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: "play")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Crucible.Color.accent)
                            Text(TranscriptClipController.playFooterLabel(duration: audioDuration))
                                .font(.system(size: 13))
                                .foregroundStyle(Crucible.Color.ink3)
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 32)
                    .accessibilityLabel(TranscriptClipController.playFooterAccessibilityLabel(duration: audioDuration))
                    .task(id: item.id) { await loadAudioDurationIfNeeded() }
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.timeLabel(for: item.createdAt)), \(Self.previewLine(for: item))")
        .accessibilityHint(isOpen
                           ? "Closes this clip"
                           : "Expands this clip's transcript in place")
        .accessibilityAddTraits(isOpen ? [.isSelected] : [])
        // Rule #5 (June 10 2026): when another row opens, this row
        // closes via the single-open accordion. If we're currently
        // editing, commit the edit (Done semantics) before letting
        // the close happen — never discard.
        .onChange(of: isOpen) { _, newValue in
            if !newValue && editingDraft != nil {
                commitDraft()
            }
        }
    }

    /// Header — atom's `.reflectiveCompact` row + chevron. Slice 10b
    /// convergence: the media glyph / time / preview projections all
    /// come from `ClipAtomView`; the chevron and accordion animation
    /// stay container-owned per `Memory Detail · long-memory
    /// navigation.md` §Compact ("expanding it swaps in the clip's
    /// reflective body"). `isEmphasized: isOpen` drives the ochre
    /// time + semibold preview weight the row inherits from the
    /// prior JSX spec.
    private var header: some View {
        Button(action: {
            if editingDraft != nil { commitDraft() }
            onTap()
        }) {
            HStack(spacing: 6) {
                // C1: when the row is expanded, hide the header's
                // preview line so it doesn't double-print above
                // the full transcript in the body below. T5: time
                // stays one color — the chevron rotation is the
                // open-state cue, no ochre time swap.
                ClipAtomView(
                    model: ClipDisplayModel(mediaDisplayItem: item, duration: audioDuration, sessionStart: nil),
                    register: .reflectiveCompact,
                    isEmphasized: isOpen,
                    hidePreview: isOpen
                )
                .frame(maxWidth: .infinity)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOpen ? Crucible.Color.accent : Crucible.Color.ink3)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isOpen)
                    .padding(.trailing, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 52)
    }

    /// Either the read-mode transcript body (tap-to-edit when a
    /// commit callback is wired) or the inline `ClipEditor`. Slice
    /// 10b: retired the bespoke `TextField(axis: .vertical)` +
    /// `ClipFateRow` + `EditCommitBar` triple in favor of `ClipEditor`,
    /// which encodes the same shape once. Read-mode retains
    /// `simultaneousGesture` because a plain `onTapGesture` gets
    /// eaten by List-row gesture machinery.
    @ViewBuilder
    private func expandedTranscriptArea(fallback: String) -> some View {
        if editingDraft != nil, let onCommitTranscript {
            ClipEditor(
                field: .transcript,
                draft: Binding(
                    get: { editingDraft ?? "" },
                    set: { editingDraft = $0 }
                ),
                initialValue: currentText,
                editId: "compact-transcript-\(item.id.uuidString)",
                evidence: audioEvidence,
                fateActions: ClipEditorFateActions(
                    onDelete: onDelete,
                    onRelocate: onRelocate
                ),
                onCancel: { editingDraft = nil },
                onDone: { newValue in
                    onCommitTranscript(newValue)
                    editingDraft = nil
                }
            )
            .padding(.top, 2)
            .padding(.bottom, 12)
            .padding(.horizontal, 4)
        } else {
            // C2: quote the transcript in the expanded body so it
            // reads as spoken words — matches the atom's
            // reflective / operational transcript render. Media
            // clips (no transcript) fall to `fallback = nil`
            // upstream so this branch never renders for them.
            Text("\u{201C}\(fallback)\u{201D}")
                .font(.system(size: 14.5))
                .lineSpacing(2)
                .foregroundStyle(Crucible.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .padding(.bottom, 12)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if onCommitTranscript != nil { editingDraft = currentText }
                    }
                )
        }
    }

    /// Voice: `.audio(duration:)`. Note: nil (no evidence). Feeds the
    /// `ClipEditor`'s evidence row — kept visible during edit per
    /// spec § "media evidence kept visible."
    private var audioEvidence: ClipDisplayModel.Evidence? {
        item.mediaType == .voice ? .audio(duration: audioDuration) : nil
    }

    private var currentText: String {
        item.transcript ?? item.text ?? ""
    }

    private func commitDraft() {
        guard let draft = editingDraft, let onCommitTranscript else {
            editingDraft = nil
            return
        }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != current {
            onCommitTranscript(trimmed)
        }
        editingDraft = nil
    }

    /// Loads the clip's duration via `AVURLAsset.load` if local. Same
    /// pattern as `VoiceClipPanel.loadAudioDurationIfNeeded`; lives
    /// here too because the compact row is its own SwiftUI view and
    /// needs its own state.
    private func loadAudioDurationIfNeeded() async {
        guard audioDuration == nil, item.mediaType == .voice else { return }
        let url = UbiquityStore.shared.audioURL(for: item.localIdentifier)
        guard UbiquityStore.shared.downloadStatus(at: url) == .downloaded else { return }
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration), cm.seconds.isFinite {
            await MainActor.run { audioDuration = cm.seconds }
        }
    }

    /// The body text shown inside the open expander. `nil` falls back to
    /// the preview line — the only case it returns nil is when both
    /// transcript and note text are empty, in which case the header
    /// itself already shows "(no transcript)" and no expander body is
    /// useful.
    static func expandedBody(for item: MediaDisplayItem) -> String? {
        let source = (item.transcript ?? item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? nil : source
    }

    // MARK: - Pure formatting helpers

    /// 12-hour `HH:MM AM/PM` matching the design comp (e.g. "6:22 PM").
    /// Cached formatter — DateFormatter init is expensive enough that a
    /// long memory's worth of rows can add measurable overhead without it.
    static func timeLabel(for date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Single-line preview drawn from voice transcript or note body.
    /// Falls back to `"(no transcript)"` when both are empty — matches
    /// `VoiceClipPanel.displayText` shape so users see a consistent
    /// language across views. We do NOT consult the audio-download
    /// status here: the Compact index is a *transcript scan*, not a
    /// playback-readiness UI; rich audio state belongs to Full.
    ///
    /// Preview rule: take everything before the first sentence
    /// terminator (`.`, `!`, `?`, `\n`). If none, cap at 80 characters
    /// with an ellipsis. Result is trimmed of leading whitespace.
    static func previewLine(for item: MediaDisplayItem) -> String {
        // Photo / video rows lean on the user-written description if
        // there is one, falling back to the bare type label otherwise.
        // Neither has a transcript to scan from; the description is
        // the only words that belong to this capture.
        switch item.mediaType {
        case .image:
            if let d = item.mediaDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !d.isEmpty { return d }
            return "Photo"
        case .video:
            if let d = item.mediaDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !d.isEmpty { return d }
            return "Video"
        case .voice, .note:
            break
        @unknown default:
            break
        }
        let source = (item.transcript ?? item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "(no transcript)" }
        if let terminator = source.firstIndex(where: { ".!?\n".contains($0) }) {
            // Include the terminator itself if it's a punctuation
            // mark — reads more naturally than a sentence cut short.
            let endIndex = source.index(after: terminator)
            let sentence = String(source[..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Newline-terminated previews drop the trailing newline;
            // strip any stray period left behind if the source was a
            // single fragment.
            return sentence.isEmpty ? source : sentence
        }
        if source.count <= 80 { return source }
        let cutoff = source.index(source.startIndex, offsetBy: 80)
        return String(source[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

// MARK: - Back-to-index link


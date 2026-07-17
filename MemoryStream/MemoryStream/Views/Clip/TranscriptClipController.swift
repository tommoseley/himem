import SwiftUI
import AVFoundation

/// Wraps `ClipAtomView(register: .reflective)` with the async +
/// stateful concerns a Memory Detail Full-mode voice or note clip
/// carries — audio download-status probing, duration probing,
/// inline transcript editing, and `TextEditCoordinator`
/// participation. Slice 9b of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
///
/// The atom stays pure. This controller is the "voice clip
/// controller" the plan names — extended to also handle notes,
/// since the panels shared their entire tap-to-edit / commit-on-
/// switch shape and duplicating a `NoteClipController` would just
/// re-encode the same wiring.
///
/// Media-kind branching lives in three narrow, well-named
/// helpers (`currentText`, `audioEvidence`, `emptyCaption`) so a
/// future third transcript-bearing kind (whatever it turns out
/// to be) has one place to slot in.
struct TranscriptClipController: View {

    /// The clip being rendered. Voice: `transcript`. Note: `text`.
    /// Photo/video callers must use `MediaCard` — this controller
    /// only handles `.voice` and `.note`.
    let item: MediaDisplayItem

    /// Voice-only play callback — parent routes to
    /// `AudioPlayerSheet`. Nil for notes, and voice callers who
    /// leave it nil get the atom's evidence label without an
    /// active tap target.
    let onPlay: (() -> Void)?

    /// Commits an inline transcript / note edit. Trimmed value
    /// arrives via `ClipEditor`'s Done path. Nil = read-only
    /// (matches `VoiceClipPanel`'s prior semantics).
    let onCommit: ((String) -> Void)?

    /// Delete clip — routed to the retired panel's identical
    /// path. Nil hides the fate row from the inline editor.
    let onDelete: (() -> Void)?

    /// Where does this belong? — placement sheet trigger. Nil
    /// hides the relocate half of the fate row.
    let onRelocate: (() -> Void)?

    /// Opens the unified Clip Editor modal (2026-07-16 cycle). When
    /// non-nil, the ✎ Edit control shows and inline edit-on-tap is
    /// retired — editing happens in the modal, not in place. The inline
    /// `editor(...)` below is kept reachable-in-code but no longer entered.
    var onEdit: (() -> Void)? = nil

    /// True when this clip's audio is playing in place — drives the atom's
    /// play/stop evidence glyph (2026-07-16 cycle 2/3).
    var isPlaying: Bool = false

    /// `nil` = read state; non-nil = the in-flight
    /// `ClipEditor(field: .transcript)` draft. Matches Slice 7's
    /// `descriptionDraft` idiom in `ClipDetailView`.
    @State private var editingDraft: String? = nil

    /// Voice-only. Read lazily via `UbiquityStore` on first
    /// appearance when the transcript is empty (so we can
    /// disambiguate "iCloud in flight" from "recognizer heard
    /// nothing"). Ignored for notes.
    @State private var audioDownloadStatus: UbiquityStore.DownloadStatus? = nil

    /// Voice-only. Loaded lazily via `AVURLAsset.load(.duration)`
    /// once the file is local. Feeds the atom's evidence label
    /// (`"Original recording · 0:48"`). Nil for notes and for
    /// voice while the download is pending.
    @State private var audioDuration: TimeInterval? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editingDraft != nil, let onCommit, let onDelete {
                editor(onCommit: onCommit, onDelete: onDelete)
            } else {
                readState
            }
        }
        .padding(12)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1))
        .task(id: item.id) {
            await refreshAudioStatusIfNeeded()
            await loadAudioDurationIfNeeded()
        }
    }

    // MARK: - Read state (atom)

    private var readState: some View {
        let model = ClipDisplayModel(
            mediaDisplayItem: item,
            duration: audioDuration,
            sessionStart: nil
        )
        return VStack(alignment: .leading, spacing: 8) {
            ClipAtomView(
                model: model,
                register: .reflective,
                // Inline edit-on-tap retired (2026-07-16): the transcript
                // text stays selectable and non-tappable; the ✎ Edit control
                // below opens the modal. When `onEdit` is nil (no modal host),
                // fall back to the legacy inline entry so nothing regresses.
                onTapContent: onEdit == nil && onCommit != nil ? { editingDraft = currentText } : nil,
                onPlayEvidence: onPlay,
                isPlayingEvidence: isPlaying,
                emptyTranscriptCaption: emptyCaption
            )
            if let onEdit {
                editControlLane(onEdit: onEdit)
            }
        }
    }

    /// The row's control lane — a quiet blue **✎ Edit** affordance
    /// (≥44px) that opens the modal. Trailing-aligned; sits with the
    /// atom's play evidence as the row's actions.
    private func editControlLane(onEdit: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 0)
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

    // MARK: - Edit state (ClipEditor)

    private func editor(onCommit: @escaping (String) -> Void, onDelete: @escaping () -> Void) -> some View {
        ClipEditor(
            field: .transcript,
            draft: Binding(
                get: { editingDraft ?? "" },
                set: { editingDraft = $0 }
            ),
            initialValue: currentText,
            editId: editId,
            evidence: audioEvidence,
            fateActions: ClipEditorFateActions(
                onDelete: onDelete,
                onRelocate: onRelocate
            ),
            onCancel: { editingDraft = nil },
            onDone: { newValue in
                onCommit(newValue)
                editingDraft = nil
            }
        )
    }

    // MARK: - Media-kind projections

    /// Current words for this clip — the same content the atom's
    /// reflective register reads. Voice: transcript. Note: text.
    private var currentText: String {
        switch item.mediaType {
        case .voice: return item.transcript ?? ""
        case .note:  return item.text ?? ""
        case .image, .video: return "" // controller shouldn't be used for media
        @unknown default: return ""
        }
    }

    /// Evidence the atom keeps visible during edit per
    /// `Clip model · spec.md` §"media evidence kept visible."
    /// Voice: `.audio(duration:)`. Note: `nil` (no evidence).
    private var audioEvidence: ClipDisplayModel.Evidence? {
        item.mediaType == .voice ? .audio(duration: audioDuration) : nil
    }

    /// Italic caption for the empty-transcript case. Voice
    /// disambiguates the iCloud audio state; notes stay silent
    /// (empty notes fall to the atom's default "(no transcript)").
    private var emptyCaption: String? {
        guard item.mediaType == .voice,
              (item.transcript ?? "").isEmpty else { return nil }
        switch audioDownloadStatus {
        case .downloading, .notDownloaded:
            return "Audio downloading from iCloud…"
        case .missing:
            return "Audio no longer in iCloud."
        case .downloaded, .none:
            return nil
        }
    }

    /// Stable id for `TextEditCoordinator` — matches the retired
    /// panels' ids so any external state consulting the
    /// coordinator (currently none, but the invariant is worth
    /// preserving) sees the same edit surface.
    private var editId: String {
        item.mediaType == .voice
            ? "transcript-\(item.id.uuidString)"
            : "note-\(item.id.uuidString)"
    }

    // MARK: - Voice-only async probes

    /// Asks `UbiquityStore` for the audio's download status when
    /// the transcript is empty — otherwise we don't need the
    /// disambiguation caption and the file-system read is
    /// wasteful. Matches the retired `VoiceClipPanel` pattern
    /// exactly.
    private func refreshAudioStatusIfNeeded() async {
        guard item.mediaType == .voice,
              (item.transcript ?? "").isEmpty else { return }
        let url = UbiquityStore.shared.audioURL(for: item.localIdentifier)
        let status = UbiquityStore.shared.downloadStatus(at: url)
        await MainActor.run { audioDownloadStatus = status }
    }

    /// Loads the audio duration once the file is local so the
    /// atom's evidence renders `"Original recording · 0:48"`
    /// instead of just `"Original recording"`. Skipped for notes
    /// and for voice while the download is pending — the atom
    /// falls back to the label-only render.
    private func loadAudioDurationIfNeeded() async {
        guard item.mediaType == .voice, audioDuration == nil else { return }
        let url = UbiquityStore.shared.audioURL(for: item.localIdentifier)
        guard UbiquityStore.shared.downloadStatus(at: url) == .downloaded else { return }
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration), cm.seconds.isFinite {
            await MainActor.run { audioDuration = cm.seconds }
        }
    }

    // MARK: - Static play-footer formatters (used by CompactClipRow)

    /// Play-footer label. Loaded: `"Original recording · 0:48"`.
    /// Not loaded yet (file still in iCloud, or duration probe
    /// pending): `"Original recording"`. Moved here from the
    /// retired `VoiceClipPanel` for parity with the compact
    /// index — the Compact row still renders its own play footer
    /// pending Slice 10b's atom substitution.
    static func playFooterLabel(duration: TimeInterval?) -> String {
        guard let duration else { return "Original recording" }
        return "Original recording · \(formatDuration(duration))"
    }

    static func playFooterAccessibilityLabel(duration: TimeInterval?) -> String {
        guard let duration else { return "Play original recording" }
        return "Play original recording, \(formatDuration(duration)) long"
    }

    /// `m:ss` — shared with the atom's evidence label projection
    /// (`ClipTimingProjection` and `ClipEvidenceProjection`) so
    /// duration formatting stays lockstep across surfaces.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Pure decision function moved from the retired `VoiceClipPanel`
    /// — money-tested (see `VoiceClipPanelDisplayTextTests`, since
    /// renamed to point at this call). Picks the right full-body
    /// label for a voice clip given the transcript and the audio
    /// file's download status:
    ///   - Non-empty transcript → transcript itself
    ///   - Empty + downloading/notDownloaded → "Audio downloading
    ///     from iCloud…"
    ///   - Empty + missing → "Audio no longer in iCloud."
    ///   - Empty + downloaded/none → "(no transcript)"
    ///
    /// This is the same contract the atom's `emptyTranscriptCaption`
    /// param + default "(no transcript)" express — kept as a static
    /// for the tests and any legacy callers that need the fully-
    /// resolved string (rather than the atom's split render).
    static func displayText(
        transcript: String?,
        audioStatus: UbiquityStore.DownloadStatus?
    ) -> String {
        if let t = transcript, !t.isEmpty { return t }
        switch audioStatus {
        case .downloading, .notDownloaded:
            return "Audio downloading from iCloud…"
        case .missing:
            return "Audio no longer in iCloud."
        case .downloaded, .none:
            return "(no transcript)"
        }
    }
}

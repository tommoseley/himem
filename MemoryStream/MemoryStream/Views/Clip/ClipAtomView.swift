import SwiftUI
import UIKit

/// The one clip view. Every clip on every surface — Clips tab
/// session card, Clip Detail, Sessions bench, Memory Detail Full,
/// Memory Detail Compact — renders through this component.
///
/// Slice 3 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`,
/// `docs/design/Clip model · spec.md` §1). Three ordered parts,
/// same structure everywhere: **timing header · content · evidence
/// control**. Register (`.operational` / `.reflective` /
/// `.reflectiveCompact`) is the only skin switch — no per-callsite
/// hand-rolling.
///
/// The atom is deliberately pure: no `.task` loads of audio
/// duration, no `TextEditCoordinator` involvement, no CoreData
/// access. Playback controllers and edit-state wrappers live one
/// level up (Slice 9's `VoiceClipController`). This keeps the atom
/// trivially testable via projections (`ClipAtomProjectionTests`,
/// 30 money tests locking the 12-cell matrix + the anti-double-
/// print).
struct ClipAtomView: View {

    let model: ClipDisplayModel
    let register: ClipRegister

    /// Opt-in pre-fetched thumbnail (Slice 3 primitive contract per
    /// Tightening 1). Container batch-fetches strip images once
    /// (e.g. `BurstRow` — Slice 6 wraps N atoms with pre-loaded
    /// images through a bounded-concurrency queue). Nil = the atom
    /// self-fetches via `ThumbnailService.cacheThumbnail`; non-nil
    /// = render directly, skip the disk hit.
    var providedThumbnail: UIImage? = nil

    /// Operational inclusion ring state. Nil in `.reflective` /
    /// `.reflectiveCompact` (no ring on the reflective surface per
    /// spec §Chrome table). Non-nil in `.operational` — tapping the
    /// ring toggles the binding.
    var ring: Binding<Bool>? = nil

    /// Tap on the content area (transcript body, thumbnail, or
    /// preview row). Callers use this for tap-to-edit or
    /// tap-to-expand. Nil = the content is inert.
    var onTapContent: (() -> Void)? = nil

    /// Tap on the evidence control (play button / named-play row).
    /// Container wires up audio/video playback. Nil = no
    /// interaction.
    var onPlayEvidence: (() -> Void)? = nil

    /// Tap on the operational `Retry transcription` link (rendered
    /// only when `register == .operational && model.failed`). Nil
    /// = don't render the link.
    var onRetryTranscription: (() -> Void)? = nil

    /// `true` = evidence control renders the stop glyph (◼);
    /// `false` = play glyph (▶). Session-scoped audio controllers
    /// (e.g. `SessionListView`'s single-player) drive this via a
    /// `playingClipId == model.id` comparison. Slice 8 (Sessions
    /// bench convergence) hook — no visual effect on `.reflective`
    /// or `.reflectiveCompact`, where evidence renders as the
    /// named-play row and the transient stop state isn't part of
    /// the reflective vocabulary.
    var isPlayingEvidence: Bool = false

    /// `true` = the voice/note transcript is empty because
    /// transcription hasn't been attempted yet — atom shows
    /// `"Transcribing…"` italic instead of a blank line. Meaningful
    /// only in `.operational` where the bench distinguishes pending
    /// vs empty vs failed; ignored in `.reflective` /
    /// `.reflectiveCompact` (a memory doesn't linger in
    /// "transcribing" state — it's either done or the retry link
    /// is showing).
    var pendingTranscript: Bool = false

    /// `true` = the voice/note transcript is empty *after* a
    /// transcription attempt (accidental capture). Atom shows
    /// `"No speech detected · likely accidental"` italic. Distinct
    /// from `pendingTranscript`. Consumer sets this alongside
    /// `model.failed = true`; the retry link renders in parallel.
    var accidentalTranscript: Bool = false

    /// Slice 9b (Memory Detail Full stream): caller-supplied
    /// italic caption for the empty-transcript case that neither
    /// `pendingTranscript` nor `accidentalTranscript` covers.
    /// `TranscriptClipController` uses this to disambiguate the
    /// iCloud audio state: `"Audio downloading from iCloud…"` /
    /// `"Audio no longer in iCloud."` when the transcript is
    /// empty because the source file isn't local yet — vs the
    /// operational bench's pending/accidental cases. Ignored when
    /// transcript is non-empty. Precedence order in the content
    /// slot: pendingTranscript > accidentalTranscript >
    /// emptyTranscriptCaption > default "(no transcript)".
    var emptyTranscriptCaption: String? = nil

    /// Slice 10b (Compact row convergence): container-driven
    /// "active row" hint for `.reflectiveCompact`. When true, the
    /// preview line goes semibold — the chevron rotation is the
    /// primary open-state cue. Ignored in `.operational` and
    /// `.reflective`. Time color stays ink3 either way per
    /// checklist T5 ("Compact row time is one treatment. …Same
    /// element, one color.").
    var isEmphasized: Bool = false

    /// Compact row spec (checklist C1 — "no double-printed lead
    /// line"). When the container expands the row into its
    /// reflective body, it also passes `hidePreview: true` so the
    /// collapsed preview sentence stops printing above the same
    /// sentence in the transcript body. Header collapses to time-
    /// only + media glyph (matching the long-memory nav spec:
    /// "expanded, the header collapses to time-only and the body
    /// carries the full transcript"). Ignored in `.operational`
    /// and `.reflective`.
    var hidePreview: Bool = false

    /// Media clip content-invite in an opened context (checklist
    /// C3). When true and the media clip's description is empty,
    /// the atom renders the ochre dashed "Add a description"
    /// affordance under the thumbnail — the description is the
    /// media clip's *words* and the opened row invites the user
    /// to write them. Session-expanded body sets true (Q2 opened-
    /// context branch); dense flat-list rows and reflective
    /// memory cards leave it false so the empty state stays
    /// silent.
    var showDescriptionInvite: Bool = false

    /// Optional tap target for the C3 invite. Nil = invite is
    /// visible but inert — some containers rely on an outer
    /// `NavigationLink` to route the whole tap (session-expanded
    /// media row is one such case). Non-nil intercepts the tap
    /// and fires the closure instead.
    var onTapDescriptionInvite: (() -> Void)? = nil

    /// Density hint for the operational register — the flat Clips
    /// tab (browse-a-single-clip context) leaves this false and
    /// gets the full-bleed thumbnail + billboard media render.
    /// The session-expanded card (triage-many-clips context) sets
    /// true and gets a scan-friendly skin: leading media glyph,
    /// small horizontal thumbnail (~52pt) for media, offset stamp
    /// demoted to 10pt subordinate weight, transcripts capped to
    /// three lines. Same operational register, two densities —
    /// the axis is intent (operational), the flag is scale.
    /// Ignored in `.reflective` and `.reflectiveCompact` (those
    /// registers already carry their own density).
    var isDenseContainer: Bool = false

    /// Inline status text appended after the retry link
    /// (e.g. `"· Retrying…"` while a retry is in flight,
    /// `"· Retry failed"` after an error). Owned by the container
    /// because the state lives outside the clip (per-user, per-tap
    /// transient). Nil = no suffix. Only rendered when the retry
    /// link is visible (`.operational && model.failed`).
    var retryStatus: String? = nil

    var body: some View {
        switch register {
        case .operational:
            operationalRow
        case .reflective:
            reflectiveCard
        case .reflectiveCompact:
            reflectiveCompactRow
        }
    }

    // MARK: - Operational row

    private var operationalRow: some View {
        let timing = ClipTimingProjection.project(model: model, register: .operational)
        let content = ClipContentProjection.project(content: model.content, register: .operational)
        let evidence = ClipEvidenceProjection.project(model: model, register: .operational)
        return HStack(alignment: .top, spacing: 12) {
            ClipRing(binding: ring)
            // Dense operational (session-expanded triage): leading
            // media glyph — voice/note read too similarly without
            // one, per CD 2026-07-12. Matches the glyph
            // `reflectiveCompact` already ships. Not drawn on the
            // flat Clips tab (`isDenseContainer: false`) because a
            // browse row is showing one clip at a time — the media
            // is its own type signal.
            if isDenseContainer {
                Image(systemName: mediaSFSymbol(model.media))
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                ClipTimingHeader(timing: timing, register: .operational, isDense: isDenseContainer)
                ClipContentSlot(
                    content: content,
                    media: model.media,
                    thumbnailKey: model.thumbnailKey,
                    providedThumbnail: providedThumbnail,
                    onTap: onTapContent,
                    pendingTranscript: pendingTranscript,
                    accidentalTranscript: accidentalTranscript,
                    emptyTranscriptCaption: emptyTranscriptCaption,
                    showDescriptionInvite: showDescriptionInvite,
                    onTapDescriptionInvite: onTapDescriptionInvite,
                    isDenseContainer: isDenseContainer
                )
                if model.failed, let onRetry = onRetryTranscription {
                    ClipRetry(onTap: onRetry, status: retryStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ClipEvidenceControl(projection: evidence, onTap: onPlayEvidence, isPlaying: isPlayingEvidence)
        }
        .padding(.vertical, isDenseContainer ? 8 : 12)
    }

    // MARK: - Reflective card

    private var reflectiveCard: some View {
        let timing = ClipTimingProjection.project(model: model, register: .reflective)
        let content = ClipContentProjection.project(content: model.content, register: .reflective)
        let evidence = ClipEvidenceProjection.project(model: model, register: .reflective)
        return VStack(alignment: .leading, spacing: 10) {
            ClipTimingHeader(timing: timing, register: .reflective)
            ClipContentSlot(
                content: content,
                media: model.media,
                thumbnailKey: model.thumbnailKey,
                providedThumbnail: providedThumbnail,
                onTap: onTapContent
            )
            if evidence != .none {
                ClipEvidenceControl(projection: evidence, onTap: onPlayEvidence)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - Reflective Compact row (collapsed index row)

    private var reflectiveCompactRow: some View {
        let timing = ClipTimingProjection.project(model: model, register: .reflectiveCompact)
        let content = ClipContentProjection.project(content: model.content, register: .reflectiveCompact)
        return HStack(spacing: 10) {
            if let glyph = timing.mediaGlyph {
                Image(systemName: mediaSFSymbol(glyph))
                    .font(.system(size: 12))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(width: 16, alignment: .center)
            }
            if let time = timing.timeOnly {
                // T5: time is one color regardless of open state.
                // The chevron rotation is the accordion cue.
                Text(time)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink3)
                    .monospacedDigit()
            }
            // C1: when the container hides the preview (expanded
            // row), pad with an empty flexible spacer so the row
            // height stays consistent while the chevron sits on
            // the trailing edge.
            if hidePreview {
                Spacer(minLength: 0)
            } else {
                previewLine(from: content)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTapContent?() }
    }

    @ViewBuilder
    private func previewLine(from content: ClipContentProjection) -> some View {
        switch content {
        case .transcriptPreview(let text):
            Text(text.isEmpty ? "(no transcript)" : text)
                .font(.system(size: 13, weight: isEmphasized ? .semibold : .regular))
                .foregroundStyle(Crucible.Color.ink2)
        case .media(let description):
            Text(description ?? mediaLabel(model.media))
                .font(.system(size: 13, weight: description == nil || isEmphasized ? .semibold : .regular))
                .foregroundStyle(Crucible.Color.ink2)
        case .transcriptFull:
            // Unreachable in .reflectiveCompact (project returns
            // .transcriptPreview here) — but exhaustively handled
            // so the switch stays sound if a future register
            // wants full text with a different chrome.
            EmptyView()
        }
    }

    private func mediaLabel(_ media: ClipDisplayModel.Media) -> String {
        switch media {
        case .voice: return "Voice"
        case .photo: return "Photo"
        case .video: return "Video"
        case .note:  return "Note"
        }
    }

    /// Canonical media glyphs — matches
    /// `EntryCardView.MediaGlyphRow` on the memory-card side and
    /// `MediaRow.sfSymbol(for:)` in `ClipComposition.swift`.
    /// Sync 2026-07-11 per Tom's ask.
    private func mediaSFSymbol(_ media: ClipDisplayModel.Media) -> String {
        switch media {
        case .voice: return "waveform"
        case .photo: return "camera"
        case .video: return "video"
        case .note:  return "text.alignleft"
        }
    }
}

// MARK: - Sub-views

/// The operational inclusion ring — ochre when selected (filled +
/// paper inner dot per Crucible §Selection rules), hollow when
/// excluded. Nil binding = no ring rendered (`.reflective` /
/// `.reflectiveCompact`).
struct ClipRing: View {
    let binding: Binding<Bool>?

    var body: some View {
        if let binding {
            Button {
                binding.wrappedValue.toggle()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            binding.wrappedValue ? Crucible.Color.accent : Crucible.Color.ink4,
                            lineWidth: 1.5
                        )
                        .background(Circle().fill(binding.wrappedValue ? Crucible.Color.accent : Color.clear))
                        .frame(width: 20, height: 20)
                    if binding.wrappedValue {
                        Circle()
                            .fill(Crucible.Color.accentInk)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 1)
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }
}

/// Header line above the content — offset/duration for operational,
/// full date+time+place for reflective, time-only (rendered by the
/// atom's compact row inline, not here).
struct ClipTimingHeader: View {
    let timing: ClipTimingProjection
    let register: ClipRegister
    /// Density hint from the atom (CD 2026-07-12). When true in
    /// `.operational`, the offset demotes to a 10pt ink4
    /// subordinate stamp — CD's diagnosis was that session-
    /// triage rows shouldn't compete for the eye with the glyph
    /// and transcript preview. Offset stays (still useful for
    /// reconstructing "the first clip was quiet, then this one
    /// 129s later") but stops being primary.
    var isDense: Bool = false

    var body: some View {
        switch register {
        case .operational:
            HStack(spacing: 12) {
                // T2: duration lives in the Play control only.
                // Previously the row printed `+128s · 0:03` AND
                // `▶ 0:03` on the same line — same value twice.
                // The offset is the only per-row datum here now;
                // duration attaches to the play affordance to
                // preserve the "duration always names playback"
                // discipline the reflective register also follows.
                if let offset = timing.offsetString {
                    Text(offset)
                        .monospacedDigit()
                        .frame(width: isDense ? 36 : 44, alignment: .leading)
                }
            }
            .font(.system(size: isDense ? 10 : 11, weight: isDense ? .regular : .medium))
            .foregroundStyle(isDense ? Crucible.Color.ink4 : Crucible.Color.ink3)
        case .reflective:
            // T3: mixed-case with location. Previously we
            // uppercased + letter-spaced this line, which
            // stripped the "Sun May 17 · 6:12 PM · Bishop St,
            // Bluffton" cadence into a shout ("SAT JUL 4 · 9:37
            // PM"). The projection already returns the canonical
            // form — the view was the drift.
            if let full = timing.dateTimePlace {
                Text(full)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        case .reflectiveCompact:
            // The atom's compact row draws its own header inline
            // (glyph + time + preview) — no separate header sub-view.
            EmptyView()
        }
    }
}

/// The content slot — transcript body (voice/note), thumbnail
/// (photo/video with optional description body/invite), or preview
/// line (compact — rendered by the atom's compact row inline).
struct ClipContentSlot: View {
    let content: ClipContentProjection
    let media: ClipDisplayModel.Media
    let thumbnailKey: ClipDisplayModel.ThumbnailKey?
    let providedThumbnail: UIImage?
    let onTap: (() -> Void)?
    /// Slice 8 (Sessions bench): renders `"Transcribing…"` italic
    /// for empty `.transcriptFull` when transcription hasn't been
    /// attempted yet. Distinguishes the pending state from the
    /// attempted-and-empty state (which shows the retry link at
    /// atom level instead).
    var pendingTranscript: Bool = false
    /// Slice 8 (Sessions bench): renders `"No speech detected ·
    /// likely accidental"` italic for empty `.transcriptFull` when
    /// transcription was attempted (i.e. `model.failed = true`) —
    /// the accidental-capture state. Distinct from `pendingTranscript`
    /// (not-yet-attempted) and from generic "(no transcript)".
    /// Consumer sets this alongside `model.failed`; the retry link
    /// renders in parallel at atom level.
    var accidentalTranscript: Bool = false
    /// Slice 9b (Memory Detail Full stream): caller-supplied italic
    /// caption for the empty-transcript case that neither
    /// `pendingTranscript` nor `accidentalTranscript` covers.
    /// Precedence: pending > accidental > caption > default
    /// "(no transcript)".
    var emptyTranscriptCaption: String? = nil
    /// Media invite (checklist C3). When true and the media
    /// clip's description is empty, the atom renders the ochre
    /// dashed "Add a description" affordance under the
    /// thumbnail. Tapping fires `onTapDescriptionInvite`.
    var showDescriptionInvite: Bool = false
    /// Fires when the user taps the ochre "Add a description"
    /// invite. Nil = the invite renders as a static prompt (still
    /// visible per spec, but inert).
    var onTapDescriptionInvite: (() -> Void)? = nil
    /// Density hint from `ClipAtomView` (CD 2026-07-12). When
    /// true, `.transcriptFull` caps to three lines and `.media`
    /// swaps from the full-bleed 168pt billboard to a leading
    /// 52pt horizontal thumbnail — the session-triage skin.
    var isDenseContainer: Bool = false

    var body: some View {
        switch content {
        case .transcriptFull(let text):
            if text.isEmpty && pendingTranscript {
                Text("Transcribing…")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if text.isEmpty && accidentalTranscript {
                Text("No speech detected · likely accidental")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if text.isEmpty, let caption = emptyTranscriptCaption {
                Text(caption)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let body = Text(text.isEmpty ? "(no transcript)" : "\u{201C}\(text)\u{201D}")
                    .font(.system(size: isDenseContainer ? 13 : 13.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                if isDenseContainer {
                    // Dense triage: cap transcripts so a long clip
                    // doesn't push the row height past a scannable
                    // line count. Full transcript still opens via
                    // tap-to-edit / navigation, same as non-dense.
                    body
                        .lineLimit(3)
                        .onTapGesture { onTap?() }
                } else {
                    body
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { onTap?() }
                }
            }
        case .transcriptPreview:
            // Consumed by the atom's reflectiveCompact row inline —
            // this slot isn't invoked in that register.
            EmptyView()
        case .media(let description):
            mediaBody(description: description)
        }
    }

    @ViewBuilder
    private func mediaBody(description: String?) -> some View {
        if isDenseContainer {
            denseMediaBody(description: description)
        } else {
            billboardMediaBody(description: description)
        }
    }

    /// Full-bleed media body — the flat Clips tab render. Thumbnail
    /// is the primary object (168pt block); the description hangs
    /// underneath as its own row. Correct for a browse-single-clip
    /// surface where the media *is* what's being consumed.
    @ViewBuilder
    private func billboardMediaBody(description: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnailKey {
                ClipThumbnailView(
                    key: thumbnailKey,
                    provided: providedThumbnail,
                    kind: media
                )
                .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { onTap?() }
            }
            let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                Text(trimmed)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
            } else if showDescriptionInvite {
                inviteButton(compact: false)
            }
        }
    }

    /// Dense media body — the session-triage render (CD 2026-07-12).
    /// Small (52pt) horizontal thumbnail on the leading edge; the
    /// description or invite reads inline to the right. The row now
    /// scans at "one card of a triage list" instead of "a photo I'm
    /// looking at." Same content, different scale.
    @ViewBuilder
    private func denseMediaBody(description: String?) -> some View {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        HStack(alignment: .top, spacing: 10) {
            if let thumbnailKey {
                ClipThumbnailView(
                    key: thumbnailKey,
                    provided: providedThumbnail,
                    kind: media
                )
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { onTap?() }
            }
            if !trimmed.isEmpty {
                Text(trimmed)
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
            } else if showDescriptionInvite {
                inviteButton(compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(kindLabel(for: media))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// C3 ochre-dashed "Add a description" — one call site, two
    /// scales. `compact` sizes down for the dense triage row so it
    /// nests inside the 52pt thumbnail's HStack without pushing the
    /// row height.
    @ViewBuilder
    private func inviteButton(compact: Bool) -> some View {
        Button {
            onTapDescriptionInvite?()
        } label: {
            HStack(spacing: compact ? 4 : 6) {
                Image(systemName: "plus")
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                Text("Add a description")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
            }
            .foregroundStyle(Crucible.Color.accent)
            .frame(maxWidth: .infinity, minHeight: compact ? 32 : 40)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 10)
                    .strokeBorder(
                        Crucible.Color.accent,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(onTapDescriptionInvite == nil)
        .accessibilityLabel("Add a description")
    }

    private func kindLabel(for media: ClipDisplayModel.Media) -> String {
        switch media {
        case .voice: return "Voice"
        case .photo: return "Photo"
        case .video: return "Video"
        case .note:  return "Note"
        }
    }
}

/// Photo/video thumbnail — uses `providedThumbnail` when non-nil
/// (Slice 6's `BurstRow` batch-fetches and hands it in), or self-
/// fetches via `ThumbnailService.cacheThumbnail` otherwise. Video
/// carries a leading play badge; photo doesn't.
private struct ClipThumbnailView: View {
    let key: ClipDisplayModel.ThumbnailKey
    let provided: UIImage?
    let kind: ClipDisplayModel.Media

    @State private var loaded: UIImage?

    var body: some View {
        ZStack {
            if let img = provided ?? loaded {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Crucible.Color.hairline.opacity(0.3))
                    .overlay {
                        Image(systemName: kind == .video ? "video" : "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(Crucible.Color.ink4)
                    }
            }
            if kind == .video {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.black)
                    }
            }
        }
        .task(id: key.osIdentifier) {
            // Skip self-fetch if a thumbnail was provided.
            guard provided == nil, loaded == nil else { return }
            if let name = await ThumbnailService.shared.cacheThumbnail(
                for: key.osIdentifier,
                mediaType: key.mediaType
            ) {
                loaded = ThumbnailService.shared.cachedThumbnail(filename: name)
            }
        }
    }
}

/// Play affordance — compact (`▶ 0:03`) for operational, named
/// (`▶ Original recording · 0:42`) for reflective, hidden for
/// reflectiveCompact + photo + note.
struct ClipEvidenceControl: View {
    let projection: ClipEvidenceProjection
    let onTap: (() -> Void)?
    /// Slice 8 (Sessions bench): flips the operational glyph
    /// (`▶ → ◼`) so a single session-scoped player can drive N
    /// atoms visually. Ignored on `.namedPlay` (reflective) —
    /// the transient stop state isn't part of that vocabulary.
    var isPlaying: Bool = false

    var body: some View {
        switch projection {
        case .none:
            EmptyView()
        case .compactPlay(let durationString):
            Button {
                onTap?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isPlaying ? "stop" : "play")
                        .font(.system(size: 12, weight: .regular))
                    if let durationString {
                        Text(durationString)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Crucible.Color.ink3)
                .frame(minWidth: 26, minHeight: 26, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .namedPlay(let label, let durationString):
            // E1: same glyph as `.compactPlay`, register-styled.
            // Previously used `play.circle.fill` — filled ochre
            // disc — which read as a different affordance from
            // the operational hairline play triangle. Same
            // symbol, larger + accent-tinted for reflective
            // presence.
            Button {
                onTap?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Crucible.Color.accent)
                    Text(evidenceLabel(label: label, durationString: durationString))
                        .font(.system(size: 13))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func evidenceLabel(label: String, durationString: String?) -> String {
        guard let durationString else { return label }
        return "\(label) · \(durationString)"
    }
}

/// Operational `Retry transcription` link — AI-blue text link, shown
/// only when the transcription failed. See
/// `docs/design/HiMem · Buttons & Actions.html` §F: retry is an AI
/// action → AI-blue link (not ochre).
struct ClipRetry: View {
    let onTap: () -> Void
    /// Slice 8 (Sessions bench): optional inline status appended
    /// after the link (`"· Retrying…"`, `"· Retry failed"`). Owned
    /// by the container because it's transient per-user state, not
    /// a property of the clip.
    var status: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Retry transcription")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Crucible.Color.aiBlue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let status {
                Text("· \(status)")
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }
}

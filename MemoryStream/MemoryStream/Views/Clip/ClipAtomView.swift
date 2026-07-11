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
            VStack(alignment: .leading, spacing: 4) {
                ClipTimingHeader(timing: timing, register: .operational)
                ClipContentSlot(
                    content: content,
                    media: model.media,
                    thumbnailKey: model.thumbnailKey,
                    providedThumbnail: providedThumbnail,
                    onTap: onTapContent
                )
                if model.failed, let onRetry = onRetryTranscription {
                    ClipRetry(onTap: onRetry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ClipEvidenceControl(projection: evidence, onTap: onPlayEvidence)
        }
        .padding(.vertical, 12)
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
                Text(time)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Crucible.Color.ink3)
                    .monospacedDigit()
            }
            previewLine(from: content)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.system(size: 13))
                .foregroundStyle(Crucible.Color.ink2)
        case .media(let description):
            Text(description ?? mediaLabel(model.media))
                .font(.system(size: 13, weight: description == nil ? .semibold : .regular))
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

    private func mediaSFSymbol(_ media: ClipDisplayModel.Media) -> String {
        switch media {
        case .voice: return "mic.fill"
        case .photo: return "camera.fill"
        case .video: return "video.fill"
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

    var body: some View {
        switch register {
        case .operational:
            HStack(spacing: 12) {
                if let offset = timing.offsetString {
                    Text(offset)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .leading)
                }
                if let duration = timing.durationString {
                    Text(duration).monospacedDigit()
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Crucible.Color.ink3)
        case .reflective:
            if let full = timing.dateTimePlace {
                Text(full.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
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

    var body: some View {
        switch content {
        case .transcriptFull(let text):
            Text(text.isEmpty ? "(no transcript)" : "\u{201C}\(text)\u{201D}")
                .font(.system(size: 13.5))
                .foregroundStyle(Crucible.Color.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }
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
            if let description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
            }
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

    var body: some View {
        switch projection {
        case .none:
            EmptyView()
        case .compactPlay(let durationString):
            Button {
                onTap?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play")
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
            Button {
                onTap?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
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

    var body: some View {
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
    }
}

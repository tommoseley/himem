import Foundation

/// The value-typed snapshot every `ClipAtomView` renders from.
///
/// Slice 1 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// This is the load-bearing type the whole convergence rests on:
/// every clip on every surface (Clips tab, Memory Detail Full,
/// Memory Detail Compact, Clip Detail, Sessions bench,
/// Create-Memory chip) renders through
/// `ClipAtomView(model: ClipDisplayModel, register:)` in later
/// slices. Adapters project it from three sources without leaking
/// Core Data managed-object lifetimes into leaf views:
///
///   - `InboxClip` (bench voice clip, Codable struct).
///   - `MediaReference` (Core Data managed object).
///   - `MediaDisplayItem` (Swift-value snapshot of `MediaReference`).
///
/// **Register-agnostic by design** (`Clip model · spec.md` §1 —
/// July 11 2026 lock): the register is a sibling parameter on the
/// view, never part of the model. `reflectiveCompact` is a
/// *density* of reflective, not a new axis — its `time`-only
/// header and first-line preview are projections of the same
/// `capturedAt` + `content.transcript` fields the other registers
/// consume. If a consumer needs a field only Compact uses, that's
/// a **fork signal** — stop and flag it, do not add a compact-only
/// field to this struct.
struct ClipDisplayModel: Equatable, Identifiable {

    /// Stable identity — matches the source's UUID (`InboxClip.clipId`
    /// or `MediaReference.id` / `MediaDisplayItem.id`). SwiftUI
    /// `ForEach` keys on this.
    let id: UUID

    let media: Media

    /// When the clip was captured. Consumed by all three registers:
    ///   - operational → `+Ns` offset from `sessionStart`.
    ///   - reflective → `Sun May 17 · 6:12 PM` (via
    ///     `CaptureTimestampLabel`'s format).
    ///   - reflectiveCompact → `6:12 PM` — a projection of the same
    ///     `capturedAt` (no new field).
    let capturedAt: Date

    /// Non-nil for session-scoped renders (a session card, a Sort
    /// cluster). Operational's offset (`+128s`) computes against
    /// this. Reflective and reflectiveCompact ignore it.
    let sessionStart: Date?

    /// Reverse-geocoded place (e.g. `"Bishop St, Bluffton"`).
    /// Rendered by the reflective register only, per
    /// `Memory Detail · long-memory navigation.md` §Compact.
    /// Operational and reflectiveCompact omit it — Compact's
    /// header is time-only, and the bench doesn't render place on
    /// its dense rows.
    let placeName: String?

    let content: Content

    /// The play/evidence control. `nil` for photo (thumbnail IS the
    /// evidence) and note (text IS the clip) — spec § "Evidence
    /// control." Encoded as `Optional` so the atom's exhaustive
    /// switch on kind doesn't have to invent a bogus placeholder
    /// case for "no evidence."
    let evidence: Evidence?

    /// Photo/video thumbnail source. Consumed by
    /// `ClipContentSlot`'s image path (Slice 3). Nil for voice/note.
    let thumbnailKey: ThumbnailKey?

    /// Failed-transcription flag — drives the operational register's
    /// Retry link. Bench-specific concept
    /// (`transcriptionAttempted && transcript.isEmpty`); always
    /// `false` for memory-side clips (they're assumed complete).
    /// The atom in `.reflective` / `.reflectiveCompact` never
    /// renders Retry per the spec — exceptions are handled on the
    /// workbench, not the reflective surface.
    let failed: Bool

    /// Capture source — "watch" / "phone" (nil = unknown). Drives the
    /// per-clip source glyph on the operational/bench row (B4, July 18
    /// 2026 — "a small Watch/phone glyph on the card"). From
    /// `InboxClip.source` (bench) or `MediaReference.sourceDevice`
    /// (managed). Reflective registers ignore it.
    var sourceDevice: String? = nil

    /// The four media kinds. Explicit + exhaustive — the spec
    /// (`Clip model · spec.md` §1 · Content, Evidence control) is
    /// written against these four; adding a fifth would ripple
    /// through every downstream switch.
    enum Media: Equatable, Hashable {
        case voice
        case photo
        case video
        case note
    }

    /// What the atom's content slot renders. Two cases only —
    /// voice/note fill `.transcript`; photo/video fill `.media`.
    /// **Do not add a `.compactPreview` case** — Compact's preview
    /// line is a projection over `transcript`, computed at the view
    /// layer. See guardrail in `Clip model · spec.md` §1.
    enum Content: Equatable {
        /// The words are the content. May be empty (`""`) while
        /// transcription is pending or after a failed pass; the
        /// `failed` flag disambiguates.
        case transcript(String)
        /// The thumbnail is the content. `description` is the
        /// user-written words (the media clip's stand-in for a
        /// voice transcript, editable via `ClipEditor` with
        /// `field="description"` per `Captured Clips ·
        /// session-first · spec.md` July 11 bullet).
        case media(description: String?)
    }

    /// The play/evidence affordance the atom renders alongside
    /// content. Duration is optional because `MediaReference`
    /// doesn't persist it — `AVURLAsset.load(.duration)` resolves
    /// it async, and the caller passes it in when known. The atom
    /// renders label-only when nil (`"▶"` operational,
    /// `"Original recording"` reflective).
    enum Evidence: Equatable {
        case audio(duration: TimeInterval?)
        case video(duration: TimeInterval?)
    }

    /// Address for `ThumbnailService.cacheThumbnail(for:mediaType:)`
    /// lookups. The atom passes it into `.task(id:)` to load the
    /// image, or receives a pre-fetched `UIImage` via the
    /// `providedThumbnail` param (Slice 3) when the container has
    /// already batch-loaded the strip (e.g. a burst).
    struct ThumbnailKey: Equatable, Hashable {
        let osIdentifier: String
        let mediaType: MediaReference.MediaType
    }
}

// MARK: - Adapters

extension ClipDisplayModel {

    /// From an `InboxClip` (bench voice clip). Always `.voice`;
    /// `.audio` evidence with the clip's persisted duration; no
    /// thumbnail; `failed` derived from
    /// `transcriptionAttempted && transcript.isEmpty`.
    /// `placeName` is `nil` — bench clips aren't reverse-geocoded.
    init(inboxClip clip: InboxClip, sessionStart: Date?) {
        self.init(
            id: clip.clipId,
            media: .voice,
            capturedAt: clip.capturedAt,
            sessionStart: sessionStart,
            placeName: nil,
            content: .transcript(clip.transcript),
            // A duration of 0 means "not known here", never "zero seconds".
            // `MediaReference` carries no duration attribute, so a clip
            // captured on another device has no entry in the per-device
            // `BenchClipDurationStore` and `syntheticClip` supplies 0. Passing
            // that through rendered a confident "0:00" — a duration the app
            // states and that is false (Honest-Label class, money-tested by
            // `ClipDisplayModelTests.voice_bench_unknownDuration_*`).
            // Absence is the honest state and needs no announcement: the
            // projection simply omits the time. `BenchClipDurationStore.record`
            // already refuses non-positive values for the same reason.
            evidence: .audio(duration: clip.duration > 0 ? clip.duration : nil),
            thumbnailKey: nil,
            failed: clip.transcriptionAttempted && clip.transcript.isEmpty,
            sourceDevice: clip.source
        )
    }

    /// From a `MediaReference` (Core Data managed object).
    ///
    /// - Parameter duration: audio/video duration — pass when
    ///   known (from `AVURLAsset.load(.duration)`). `nil` renders
    ///   the atom's evidence label without the `· 0:MM` suffix.
    /// - Parameter sessionStart: when non-nil, the operational
    ///   register renders offset (`+Ns`); nil for reflective /
    ///   Compact renders where the clip stands alone.
    ///
    /// Reads managed-object fields synchronously — call from a
    /// context-owning surface (viewContext) and don't retain the
    /// model past that context's lifetime.
    init(mediaReference ref: MediaReference, duration: TimeInterval? = nil, sessionStart: Date? = nil) {
        let media = Self.media(from: ref.mediaTypeEnum)
        let content = Self.content(
            for: ref.mediaTypeEnum,
            transcript: ref.transcript,
            text: ref.text,
            mediaDescription: ref.mediaDescription
        )
        let evidence = Self.evidence(for: ref.mediaTypeEnum, duration: duration)
        let thumbnailKey = Self.thumbnailKey(
            for: ref.mediaTypeEnum,
            osIdentifier: ref.osIdentifier
        )
        self.init(
            id: ref.id,
            media: media,
            capturedAt: ref.createdAt ?? .distantPast,
            sessionStart: sessionStart,
            placeName: ref.placeName,
            content: content,
            evidence: evidence,
            thumbnailKey: thumbnailKey,
            failed: false,
            sourceDevice: ref.sourceDevice
        )
    }

    /// From a `MediaDisplayItem` — the value-typed snapshot of a
    /// `MediaReference` used by `EntryMapper` / Memory Detail's
    /// display path. Same projection as
    /// `init(mediaReference:duration:sessionStart:)`; kept as a
    /// separate initializer so callers don't need a live managed
    /// object to construct a model.
    init(mediaDisplayItem item: MediaDisplayItem, duration: TimeInterval? = nil, sessionStart: Date? = nil) {
        let media = Self.media(from: item.mediaType)
        let content = Self.content(
            for: item.mediaType,
            transcript: item.transcript,
            text: item.text,
            mediaDescription: item.mediaDescription
        )
        let evidence = Self.evidence(for: item.mediaType, duration: duration)
        let thumbnailKey = Self.thumbnailKey(
            for: item.mediaType,
            osIdentifier: item.localIdentifier
        )
        self.init(
            id: item.id,
            media: media,
            capturedAt: item.createdAt,
            sessionStart: sessionStart,
            placeName: item.placeName,
            content: content,
            evidence: evidence,
            thumbnailKey: thumbnailKey,
            failed: false
        )
    }

    // MARK: Shared projections

    private static func media(from mediaType: MediaReference.MediaType) -> Media {
        switch mediaType {
        case .voice: return .voice
        case .image: return .photo
        case .video: return .video
        case .note:  return .note
        }
    }

    /// Content projection — voice/note fill `.transcript` (from
    /// `transcript` or `text`); photo/video fill `.media` (with
    /// optional description). Note's transcript source is `text`,
    /// not `transcript` — `MediaReference` stores note bodies in
    /// `text` and voice transcripts in `transcript`; this switch
    /// dispatches so the caller doesn't have to remember which.
    private static func content(
        for mediaType: MediaReference.MediaType,
        transcript: String?,
        text: String?,
        mediaDescription: String?
    ) -> Content {
        switch mediaType {
        case .voice: return .transcript(transcript ?? "")
        case .note:  return .transcript(text ?? "")
        case .image, .video: return .media(description: mediaDescription)
        }
    }

    /// Evidence projection per the spec's evidence-control table:
    /// audio/video → Play; photo/note → nil.
    private static func evidence(
        for mediaType: MediaReference.MediaType,
        duration: TimeInterval?
    ) -> Evidence? {
        switch mediaType {
        case .voice: return .audio(duration: duration)
        case .video: return .video(duration: duration)
        case .image, .note: return nil
        }
    }

    private static func thumbnailKey(
        for mediaType: MediaReference.MediaType,
        osIdentifier: String
    ) -> ThumbnailKey? {
        switch mediaType {
        case .image, .video: return ThumbnailKey(osIdentifier: osIdentifier, mediaType: mediaType)
        case .voice, .note: return nil
        }
    }
}

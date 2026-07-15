import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `ClipDisplayModel` and its three adapters
/// (`InboxClip`, `MediaReference`, `MediaDisplayItem`).
///
/// Slice 1 of the Clip Model convergence
/// (`docs/architecture/2026-07-11-clip-model-convergence-plan.md`).
/// The model is the load-bearing value type the whole convergence
/// depends on: every clip in every register renders through
/// `ClipAtomView(model: ClipDisplayModel, register:)` in later
/// slices. Fork here and the whole slice pack collapses.
///
/// Three money tests locked by CD + Tom:
///   (i)   adapter round-trip parity across bench vs memory —
///         the same voice clip via `InboxClip` and via
///         `MediaReference` produces the same `media`, `content`,
///         and `evidence`. Only source-specific fields differ.
///   (ii)  `reflectiveCompact` needs no field the other two
///         registers don't — the compact preview line is a
///         projection from `transcript`, not a new `Content` case.
///         If Compact ever needs its own case, the switch
///         exhaustiveness will force this test to change; that's
///         the fork signal.
///   (iii) Note's evidence-slot semantics pinned — `evidence == nil`
///         is an explicit spec decision (the text IS the clip),
///         not an accident. Same for photo.
@MainActor
@Suite(.serialized)
struct ClipDisplayModelTests {

    // MARK: - Money test (i) · adapter round-trip parity

    /// Voice clip via bench (`InboxClip`) vs via memory
    /// (`MediaReference`) yields the same `media`, `content`, and
    /// `evidence`. Timing/context legitimately differ (bench carries
    /// `sessionStart`; memory carries `placeName`).
    @Test func voice_adapter_round_trip_parity_across_bench_and_memory() throws {
        let ctx = try makeInMemoryContext()
        let capturedAt = Date()

        // Bench side
        let inboxClip = InboxClip(
            clipId: UUID(),
            capturedAt: capturedAt,
            duration: 3.0,
            transcript: "Ben said the Basque cheesecake",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "clip.m4a",
            transcriptionAttempted: true
        )
        let benchModel = ClipDisplayModel(inboxClip: inboxClip, sessionStart: capturedAt)

        // Memory side
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.osIdentifier = "shared.m4a"
        ref.createdAt = capturedAt
        ref.transcript = "Ben said the Basque cheesecake"
        let memoryModel = ClipDisplayModel(mediaReference: ref, duration: 3.0)

        #expect(benchModel.media == memoryModel.media, "media kind must match across sources")
        #expect(benchModel.content == memoryModel.content, "content must project identically from either source")
        #expect(benchModel.evidence == memoryModel.evidence, "evidence must project identically from either source")
    }

    /// `MediaDisplayItem` (a Swift-value snapshot of `MediaReference`)
    /// produces the same model as the `MediaReference` it was
    /// snapshotted from. Guards the "value snapshot is a pure
    /// projection" invariant so the two adapters never drift.
    @Test func mediaDisplayItem_adapter_parity_with_mediaReference() throws {
        let ctx = try makeInMemoryContext()
        let capturedAt = Date()

        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.osIdentifier = "photo.jpg"
        ref.createdAt = capturedAt
        ref.mediaDescription = "my new camera"
        ref.placeName = "Bishop St, Bluffton"

        let item = MediaDisplayItem(
            id: ref.id,
            localIdentifier: ref.osIdentifier,
            mediaType: ref.mediaTypeEnum,
            thumbnailCacheFilename: nil,
            isAccessible: true,
            mediaDescription: ref.mediaDescription,
            createdAt: capturedAt,
            placeName: ref.placeName
        )

        let refModel = ClipDisplayModel(mediaReference: ref)
        let itemModel = ClipDisplayModel(mediaDisplayItem: item)

        #expect(refModel.media == itemModel.media)
        #expect(refModel.content == itemModel.content)
        #expect(refModel.evidence == itemModel.evidence)
        #expect(refModel.placeName == itemModel.placeName)
        #expect(refModel.thumbnailKey == itemModel.thumbnailKey)
    }

    // MARK: - Money test (ii) · anti-fork content shape

    /// `Content` has exactly two cases — `.transcript(String)` for
    /// voice/note; `.media(description: String?)` for photo/video.
    /// If Compact ever needs a `.compactPreview` case, the exhaustive
    /// switch below stops compiling. That's the fork signal the
    /// guardrail promises to catch.
    @Test func content_shape_survives_compact_pressure() throws {
        let ctx = try makeInMemoryContext()

        let voiceRef = MediaReference(context: ctx)
        voiceRef.id = UUID()
        voiceRef.mediaType = MediaReference.MediaType.voice.rawValue
        voiceRef.osIdentifier = "v.m4a"
        voiceRef.createdAt = Date()
        voiceRef.transcript = "hi"
        let voiceModel = ClipDisplayModel(mediaReference: voiceRef)

        switch voiceModel.content {
        case .transcript(let t):
            #expect(t == "hi")
        case .media:
            Issue.record("voice content must be .transcript, got .media")
        }

        let photoRef = MediaReference(context: ctx)
        photoRef.id = UUID()
        photoRef.mediaType = MediaReference.MediaType.image.rawValue
        photoRef.osIdentifier = "p.jpg"
        photoRef.createdAt = Date()
        let photoModel = ClipDisplayModel(mediaReference: photoRef)

        switch photoModel.content {
        case .media:
            break
        case .transcript:
            Issue.record("photo content must be .media, got .transcript")
        }
    }

    // MARK: - Money test (iii) · note + photo evidence pinned

    /// Note's evidence slot is nil — the text IS the clip; there
    /// is no play affordance to render.
    @Test func note_has_nil_evidence_and_transcript_content() throws {
        let ctx = try makeInMemoryContext()
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.note.rawValue
        ref.osIdentifier = ""
        ref.createdAt = Date()
        ref.text = "Sourdough starter needs feeding"

        let model = ClipDisplayModel(mediaReference: ref)

        #expect(model.media == .note)
        #expect(model.evidence == nil, "note evidence slot must be nil — the text is the clip")
        if case .transcript(let text) = model.content {
            #expect(text == "Sourdough starter needs feeding")
        } else {
            Issue.record("note content should be .transcript, got \(model.content)")
        }
        #expect(model.thumbnailKey == nil, "note has no thumbnail")
    }

    /// Photo's evidence slot is nil — the thumbnail IS the evidence.
    @Test func photo_has_nil_evidence_and_thumbnailKey() throws {
        let ctx = try makeInMemoryContext()
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.osIdentifier = "photo.jpg"
        ref.createdAt = Date()

        let model = ClipDisplayModel(mediaReference: ref)

        #expect(model.media == .photo)
        #expect(model.evidence == nil, "photo evidence slot must be nil — the thumbnail is the evidence")
        #expect(model.thumbnailKey != nil, "photo must carry a thumbnail key")
        #expect(model.thumbnailKey?.osIdentifier == "photo.jpg")
    }

    /// Video carries evidence (`.video`) AND a thumbnail key —
    /// unique among the four media types. The video badge on the
    /// thumbnail lives in the atom's view; the model carries both.
    @Test func video_has_both_evidence_and_thumbnailKey() throws {
        let ctx = try makeInMemoryContext()
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.video.rawValue
        ref.osIdentifier = "vid.mov"
        ref.createdAt = Date()

        let model = ClipDisplayModel(mediaReference: ref, duration: 8.0)

        #expect(model.media == .video)
        #expect(model.evidence == .video(duration: 8.0))
        #expect(model.thumbnailKey?.osIdentifier == "vid.mov")
    }

    // MARK: - Photo description survives as optional (Q2 anchor)

    /// Photo description is optional in the model. Nil is a valid
    /// state — the atom decides how to render it (silent on
    /// operational scan rows, ochre invite on opened detail) per
    /// Q2's answer in the convergence plan.
    @Test func photo_description_nil_carries_through() throws {
        let ctx = try makeInMemoryContext()
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.osIdentifier = "p.jpg"
        ref.createdAt = Date()
        ref.mediaDescription = nil

        let model = ClipDisplayModel(mediaReference: ref)
        if case .media(let description) = model.content {
            #expect(description == nil)
        } else {
            Issue.record("photo content must be .media")
        }
    }

    @Test func photo_description_text_carries_through() throws {
        let ctx = try makeInMemoryContext()
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.osIdentifier = "p.jpg"
        ref.createdAt = Date()
        ref.mediaDescription = "my new camera"

        let model = ClipDisplayModel(mediaReference: ref)
        if case .media(let description) = model.content {
            #expect(description == "my new camera")
        } else {
            Issue.record("photo content must be .media")
        }
    }

    // MARK: - Failed transcript flag (operational only)

    /// A bench voice clip with `transcriptionAttempted == true` and
    /// an empty transcript sets `failed = true`. The atom's Retry
    /// affordance (operational register only) hangs off this flag.
    @Test func voice_bench_failed_transcript_sets_failed_flag() {
        let capturedAt = Date()
        let inboxClip = InboxClip(
            clipId: UUID(),
            capturedAt: capturedAt,
            duration: 2.0,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "silent.m4a",
            transcriptionAttempted: true
        )
        let model = ClipDisplayModel(inboxClip: inboxClip, sessionStart: capturedAt)
        #expect(model.failed == true, "attempted + empty transcript is the failed signal")
    }

    /// A bench voice clip that hasn't been transcribed yet
    /// (`transcriptionAttempted == false`) is NOT failed — it's
    /// still in flight. The atom shows "Transcribing…" upstream,
    /// never Retry.
    @Test func voice_bench_pending_transcription_is_not_failed() {
        let capturedAt = Date()
        let inboxClip = InboxClip(
            clipId: UUID(),
            capturedAt: capturedAt,
            duration: 2.0,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "pending.m4a",
            transcriptionAttempted: false
        )
        let model = ClipDisplayModel(inboxClip: inboxClip, sessionStart: capturedAt)
        #expect(model.failed == false)
    }

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        // Test-isolation fix (2026-07-15): share the ONE production
        // `cachedModel` via StorageService(inMemory:) instead of a fresh
        // `mergedModel(from:)` — multiple live models for the same entity
        // classes race in Core Data's global registry under parallel @Suite
        // runs. Stores stay per-test isolated; the MODEL shares one instance.
        return StorageService(inMemory: true).viewContext
    }
}

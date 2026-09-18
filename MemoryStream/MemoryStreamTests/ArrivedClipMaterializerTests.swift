import Testing
import Foundation
import CoreData
@testable import HiMem

/// **The DRAIN's contract — what `materializeAll` sweeps, and that it
/// converges.** Originally the P0-3 money tests for materialize-on-arrival
/// (`docs/architecture/2026-07-25-clip-sync-single-source-of-truth.md`), where
/// a transcribed clip became a zero-edge `MediaReference` so it followed the
/// person rather than the device.
///
/// **§1 (2026-09-18) changed what it materialises INTO** — a memory whose
/// writing is the transcript, no part — so the assertions about ref minting
/// are retired by supersession and live in
/// `ArrivedRecordingBecomesMemoryTests`. What survives here is the half that
/// is about the SWEEP rather than its product: only finished work is drained,
/// and running it repeatedly converges. Both are properties of a migration
/// that runs on every launch, and neither depends on what it produces.
///
/// `.serialized` — every test mutates the `InboxManifest.shared` singleton;
/// parallel runs would cross-talk. The audio discard is injected
/// (`{ _ in true }`) so these stay filesystem-free.
@MainActor
@Suite(.serialized)
struct ArrivedClipMaterializerTests {

    /// Seed a manifest clip at a given status, snapshot/restore the singleton.
    private func withSeededClip(
        status: InboxClip.Status = .transcribed,
        transcript: String = "hello there",
        reviewed: Bool = false,
        rollGroupId: UUID? = UUID(),
        _ body: (InboxClip, NSManagedObjectContext) throws -> Void
    ) rethrows {
        let manifest = InboxManifest.shared
        let snapshot = manifest.clips
        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 4.0,
            transcript: transcript,
            latitude: 37.5,
            longitude: -122.3,
            source: "watch",
            audioFilename: "clip-\(UUID().uuidString).m4a",
            transcriptionAttempted: status == .transcribed,
            rollGroupId: rollGroupId,
            status: status,
            reviewed: reviewed
        )
        manifest.acceptClip(clip)
        let storage = StorageService(inMemory: true)
        defer {
            for c in manifest.clips where !snapshot.contains(where: { $0.clipId == c.clipId }) {
                manifest.remove(clipId: c.clipId)
            }
        }
        try body(clip, storage.viewContext)
    }

    private func fetchEntry(id: UUID, in context: NSManagedObjectContext) -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(req).first
    }

    // RETIRED BY SUPERSESSION (§1, 2026-09-18) — each guarded ref minting, a
    // MECHANISM the ruling removes, not a promise it preserves:
    //
    //   materialize_createsZeroEdgeVoiceRef_withClipIdAsId
    //   materialize_removesManifestActiveRow
    //   materialize_isIdempotent_noDuplicateRef
    //   materialize_clipAppearsExactlyOnce_acrossBothStores
    //   materialize_carriesReviewedFlag
    //   materialize_emptyTranscript_stillMaterializes_asAccidentalSignal
    //
    // An arrival no longer produces a `MediaReference`: the audio is discarded
    // after transcription, so a media-shaped object would reference bytes that
    // cannot exist. Every promise underneath them is re-asserted against the
    // new product in `ArrivedRecordingBecomesMemoryTests` — the clip's id
    // carried onto the durable object, the manifest tombstone, idempotency,
    // and a silent recording still becoming something. `carriesReviewedFlag`
    // is the one with no successor: review state was a bench concept and
    // retires with the bench.
    //
    // `composeBenchClips_dedupsManifestAndRef_refWins` went with them — it
    // guarded the two-store read, and there is one store now.

    // MARK: - materializeAll drains only what's done

    @Test func materializeAll_drainsTranscribed_leavesInFlight() throws {
        let manifest = InboxManifest.shared
        let snapshot = manifest.clips
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        defer {
            for c in manifest.clips where !snapshot.contains(where: { $0.clipId == c.clipId }) {
                manifest.remove(clipId: c.clipId)
            }
        }
        func makeClip(_ status: InboxClip.Status) -> InboxClip {
            InboxClip(
                clipId: UUID(), capturedAt: Date(), duration: 3, transcript: "x",
                latitude: nil, longitude: nil, source: "watch",
                audioFilename: "a-\(UUID().uuidString).m4a",
                transcriptionAttempted: status == .transcribed,
                rollGroupId: nil, status: status)
        }
        let done = makeClip(.transcribed)
        let inFlight = makeClip(.transcribing)
        manifest.acceptClip(done)
        manifest.acceptClip(inFlight)

        let n = ArrivedClipMaterializer.materializeAll(in: ctx, deleteAudio: { _ in true })
        #expect(n == 1, "only the transcribed clip materialized")
        #expect(fetchEntry(id: done.clipId, in: ctx) != nil, "transcribed → a memory")
        #expect(fetchEntry(id: inFlight.clipId, in: ctx) == nil,
                "in-flight → NOT a memory yet. Draining a clip mid-transcription would publish an EMPTY memory and then have nowhere to put the words when they arrive.")
        #expect(!manifest.clips.contains { $0.clipId == done.clipId }, "transcribed left the manifest")
        #expect(manifest.clips.contains { $0.clipId == inFlight.clipId }, "in-flight stays in the manifest")
    }

    // MARK: - Migration = materializeAll runs on every bench appear (idempotent)

    /// The launch-migration contract: `materializeAll` runs on EVERY launch and
    /// on every paperclip open (F1 gave it a bench-independent owner), so it
    /// must converge. A first pass migrates the pre-existing transcribed clips;
    /// a second mints nothing — which is what makes it safe to call from more
    /// than one place. **Duplicating here would duplicate MEMORIES**, which is
    /// a louder failure than the duplicate refs it used to risk.
    @Test func materializeAll_isIdempotentAcrossAppears() throws {
        let manifest = InboxManifest.shared
        let snapshot = manifest.clips
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        defer {
            for c in manifest.clips where !snapshot.contains(where: { $0.clipId == c.clipId }) {
                manifest.remove(clipId: c.clipId)
            }
        }
        let ids = (0..<3).map { _ in UUID() }
        for id in ids {
            manifest.acceptClip(InboxClip(
                clipId: id, capturedAt: Date(), duration: 2, transcript: "t",
                latitude: nil, longitude: nil, source: "watch",
                audioFilename: "m-\(id.uuidString).m4a",
                transcriptionAttempted: true, rollGroupId: nil, status: .transcribed))
        }

        let first = ArrivedClipMaterializer.materializeAll(in: ctx, deleteAudio: { _ in true })
        #expect(first == 3, "first pass migrates all pre-existing transcribed clips")
        let second = ArrivedClipMaterializer.materializeAll(in: ctx, deleteAudio: { _ in true })
        #expect(second == 0, "second pass is a no-op — nothing left to migrate")

        let total = try ctx.count(for: NSFetchRequest<JournalEntry>(entityName: "JournalEntry"))
        #expect(total == 3, "exactly 3 memories — no duplicates across two passes")
    }
}

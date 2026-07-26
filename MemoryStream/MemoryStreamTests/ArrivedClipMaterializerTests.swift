import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for P0-3 piece A — materialize-on-arrival
/// (`docs/architecture/2026-07-25-clip-sync-single-source-of-truth.md`). A
/// fully-transcribed bench clip becomes a CloudKit-synced **zero-edge
/// `MediaReference`** so it follows the person, not the device (the
/// iPad-invisible-bench bug). The manifest active row is demoted to a tombstone.
///
/// `.serialized` — every test mutates the `InboxManifest.shared` singleton and
/// the `BenchClipReviewStore` UserDefaults; parallel runs would cross-talk.
/// The audio move is injected (`{ _ in true }`) so these stay filesystem-free.
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

    private func fetchRef(id: UUID, in context: NSManagedObjectContext) -> MediaReference? {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(req).first
    }

    // MARK: - The ref is minted with the clip's identity + metadata

    @Test func materialize_createsZeroEdgeVoiceRef_withClipIdAsId() throws {
        try withSeededClip(rollGroupId: UUID()) { clip, ctx in
            let id = ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            #expect(id == clip.clipId, "the ref's id IS the clipId — the dedup + convergence key")

            let ref = try #require(fetchRef(id: clip.clipId, in: ctx))
            #expect(ref.mediaType == MediaReference.MediaType.voice.rawValue)
            #expect(ref.osIdentifier == clip.audioFilename)
            #expect(ref.transcript == clip.transcript)
            #expect(ref.createdAt == clip.capturedAt)
            #expect(ref.rollGroupId == clip.rollGroupId)
            #expect(ref.sourceDevice == clip.source)
            #expect(ref.referencingMemoryCount == 0, "materializes UNPLACED — a zero-edge ref")
        }
    }

    // MARK: - The manifest active row is demoted (risk-3 tombstone survives)

    @Test func materialize_removesManifestActiveRow() throws {
        try withSeededClip { clip, ctx in
            #expect(InboxManifest.shared.clips.contains { $0.clipId == clip.clipId })
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            #expect(!InboxManifest.shared.clips.contains { $0.clipId == clip.clipId },
                    "the active row is gone — the ref is now the source of truth")
        }
    }

    // MARK: - Idempotency + the double-render guard (risk-1, P0)

    @Test func materialize_isIdempotent_noDuplicateRef() throws {
        try withSeededClip { clip, ctx in
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            // Re-seed the active row to simulate a redelivery racing the ref.
            InboxManifest.shared.acceptClip(clip)
            let second = ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            #expect(second == clip.clipId, "second pass converges via refExists, no throw")

            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "id == %@", clip.clipId as CVarArg)
            #expect((try? ctx.count(for: req)) == 1, "exactly ONE ref — no double-materialize")
        }
    }

    /// The compose-layer contract: after materialize, the union the bench reads —
    /// {active manifest rows} ∪ {zero-edge refs}, deduped by id — contains the
    /// clip EXACTLY once. This is the structural guarantee behind risk-1.
    @Test func materialize_clipAppearsExactlyOnce_acrossBothStores() throws {
        try withSeededClip { clip, ctx in
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })

            let manifestIds = Set(InboxManifest.shared.clips.map(\.clipId))
            let refReq = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            refReq.predicate = NSPredicate(format: "edges.@count == 0 AND recycledAt == nil AND mediaType == %@",
                                           MediaReference.MediaType.voice.rawValue)
            let refIds = Set((try ctx.fetch(refReq)).compactMap(\.id))

            #expect(!manifestIds.contains(clip.clipId), "not in the manifest store")
            #expect(refIds.contains(clip.clipId), "in the ref store")
            let union = manifestIds.union(refIds)
            #expect(union.filter { $0 == clip.clipId }.count == 1, "exactly once across the union")
        }
    }

    // MARK: - Reviewed carries (risk-2, per-device)

    @Test func materialize_carriesReviewedFlag() throws {
        try withSeededClip(reviewed: true) { clip, ctx in
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            #expect(BenchClipReviewStore.isReviewed(clip.clipId), "reviewed rides into the ref-keyed store")
        }
        try withSeededClip(reviewed: false) { clip, ctx in
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            #expect(!BenchClipReviewStore.isReviewed(clip.clipId), "unreviewed stays unreviewed")
        }
    }

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

        let n = ArrivedClipMaterializer.materializeAll(in: ctx, moveAudio: { _ in true })
        #expect(n == 1, "only the transcribed clip materialized")
        #expect(fetchRef(id: done.clipId, in: ctx) != nil, "transcribed → ref")
        #expect(fetchRef(id: inFlight.clipId, in: ctx) == nil, "in-flight → NOT a ref yet")
        #expect(!manifest.clips.contains { $0.clipId == done.clipId }, "transcribed left the manifest")
        #expect(manifest.clips.contains { $0.clipId == inFlight.clipId }, "in-flight stays in the manifest")
    }

    // MARK: - Compose-layer dedup (risk-1, P0) — the bench-read guard

    /// The migration-window double-render: a clip present as BOTH a stale
    /// manifest row AND its materialized ref must compose to EXACTLY ONE bench
    /// entry, and the survivor is the ref (source of truth — transcribed).
    @Test func composeBenchClips_dedupsManifestAndRef_refWins() throws {
        try withSeededClip(status: .transcribed, transcript: "from-ref") { clip, ctx in
            // Materialize → a ref exists. Then re-seed the manifest row (the
            // stale duplicate the migration window can leave behind).
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            InboxManifest.shared.acceptClip(clip)
            #expect(InboxManifest.shared.clips.contains { $0.clipId == clip.clipId },
                    "stale manifest row present — the double-render setup")

            let refs = try #require(try? ctx.fetch({
                let r = NSFetchRequest<MediaReference>(entityName: "MediaReference")
                r.predicate = NSPredicate(format: "edges.@count == 0 AND recycledAt == nil AND mediaType == %@",
                                          MediaReference.MediaType.voice.rawValue)
                return r
            }()))
            let composed = ArrivedClipMaterializer.composeBenchClips(
                manifestClips: InboxManifest.shared.clips, refs: refs)

            let matches = composed.filter { $0.clipId == clip.clipId }
            #expect(matches.count == 1, "exactly one bench entry — no double-render")
            #expect(matches.first?.transcriptionAttempted == true, "the survivor is the ref (post-attempt)")
        }
    }

    // MARK: - Migration = materializeAll runs on every bench appear (idempotent)

    /// The launch-migration contract: `materializeAll` runs on EVERY bench
    /// appear, so it must converge. A first pass migrates the pre-existing
    /// transcribed clips; a second pass (next appear) materializes nothing new
    /// and mints no duplicates — the "runs every appear" safety.
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

        let first = ArrivedClipMaterializer.materializeAll(in: ctx, moveAudio: { _ in true })
        #expect(first == 3, "first appear migrates all pre-existing transcribed clips")
        let second = ArrivedClipMaterializer.materializeAll(in: ctx, moveAudio: { _ in true })
        #expect(second == 0, "second appear is a no-op — nothing left to migrate")

        let total = try ctx.count(for: NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        #expect(total == 3, "exactly 3 refs — no duplicates across two passes")
    }

    /// The accidental-clip derivation: a transcribed clip with an EMPTY
    /// transcript still materializes — the empty-transcript ref IS the
    /// accidental signal (design decision #1, derived-from-store).
    @Test func materialize_emptyTranscript_stillMaterializes_asAccidentalSignal() throws {
        try withSeededClip(transcript: "") { clip, ctx in
            ArrivedClipMaterializer.materialize(clip, in: ctx, moveAudio: { _ in true })
            let ref = try #require(fetchRef(id: clip.clipId, in: ctx))
            #expect((ref.transcript ?? "").isEmpty, "empty-transcript ref = accidental, not absent")
        }
    }
}

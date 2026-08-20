import Testing
import Foundation
@testable import HiMem

/// Money tests for the P8b uniform clip bin (July 20 2026) — unpromoted
/// bench clips (`InboxClip`) get a per-device manifest `recycledAt` and a
/// Recently-Deleted round-trip, plus watch-redelivery gating so a recycled
/// clip can't resurrect on the bench.
@MainActor
@Suite
struct InboxClipRecycleTests {

    private func sample(_ id: UUID = UUID(), transcript: String = "hi") -> InboxClip {
        InboxClip(
            clipId: id, capturedAt: Date(), duration: 5, transcript: transcript,
            latitude: nil, longitude: nil, source: "watch",
            audioFilename: "\(id.uuidString).m4a",
            transcriptionAttempted: true, rollGroupId: nil, status: .transcribed
        )
    }

    @Test func recycleThenRestore_roundTrips() {
        let m = InboxManifest.shared
        let id = UUID()
        m.acceptClip(sample(id))
        defer { m.purgeRecycledClip(clipId: id); m.remove(clipId: id) }

        m.recycleClip(clipId: id)
        #expect(!m.clips.contains { $0.clipId == id })                       // left the bench
        #expect(m.loadRecycledClips().contains { $0.clipId == id && $0.recycledAt != nil })

        m.restoreClip(clipId: id)
        #expect(m.clips.contains { $0.clipId == id })                        // back on the bench
        #expect(!m.loadRecycledClips().contains { $0.clipId == id })
        #expect(m.clips.first { $0.clipId == id }?.recycledAt == nil)
    }

    /// A recycled clip must gate a watch redelivery — status is "known" and
    /// `acceptClip` no-ops, so it can't resurrect on the bench + duplicate.
    @Test func recycledClip_gatesRedelivery() {
        let m = InboxManifest.shared
        let id = UUID()
        m.acceptClip(sample(id))
        m.recycleClip(clipId: id)
        defer { m.purgeRecycledClip(clipId: id) }

        #expect(m.status(for: id) != nil)          // arrival tracker drops it
        m.acceptClip(sample(id))                    // redelivery
        #expect(!m.clips.contains { $0.clipId == id })   // not resurrected
        #expect(m.loadRecycledClips().filter { $0.clipId == id }.count == 1) // no dupe
    }

    @Test func purge_permanentlyTombstones() {
        let m = InboxManifest.shared
        let id = UUID()
        m.acceptClip(sample(id))
        m.recycleClip(clipId: id)
        m.purgeRecycledClip(clipId: id)

        #expect(!m.loadRecycledClips().contains { $0.clipId == id })
        #expect(m.status(for: id) == .disposed)     // permanent tombstone, recycledAt cleared
    }

    @Test func recycledAt_survivesCodable_legacyDecodesNil() throws {
        let clip = sample().withRecycledAt(Date(timeIntervalSince1970: 1000))
        let decoded = try JSONDecoder().decode(InboxClip.self, from: JSONEncoder().encode(clip))
        #expect(decoded.recycledAt != nil)

        // A manifest row written before P8b has no `recycledAt` key → nil.
        let legacy: [String: Any] = [
            "clipId": UUID().uuidString, "capturedAt": 1000.0, "duration": 5.0,
            "transcript": "x", "source": "watch", "audioFilename": "a.m4a"
        ]
        let d2 = try JSONDecoder().decode(InboxClip.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(d2.recycledAt == nil)
    }

    /// **The BATCH recycler had no coverage** — found while routing
    /// "Delete session" through Recently Deleted (ruled 2026-08-19).
    ///
    /// That path used to call `remove(clipId:)`, which tombstones the row,
    /// emits a watch ack and deletes the staged audio: a deleted **session**
    /// was unrecoverable while a deleted **clip** was not. One destructive
    /// verb, one meaning — so it now recycles, in one batch.
    ///
    /// The singular round-trip is `recycleThenRestore_roundTrips` above; this
    /// is the plural form the session path actually calls, which nothing
    /// exercised.
    @Test func recycleClipsBatch_movesEveryClipToRecentlyDeleted_andRestores() {
        let m = InboxManifest.shared
        let a = UUID(), b = UUID()
        m.acceptClip(sample(a))
        m.acceptClip(sample(b))
        defer {
            m.purgeRecycledClip(clipId: a); m.purgeRecycledClip(clipId: b)
            m.remove(clipId: a); m.remove(clipId: b)
        }
        #expect(m.clips.contains { $0.clipId == a } && m.clips.contains { $0.clipId == b })

        m.recycleClips(clipIds: [a, b])

        #expect(!m.clips.contains { $0.clipId == a }, "the session leaves the bench")
        #expect(!m.clips.contains { $0.clipId == b })
        let recycled = m.loadRecycledClips()
        #expect(recycled.contains { $0.clipId == a && $0.recycledAt != nil },
                "and lands in Recently Deleted — the promise the footnote makes")
        #expect(recycled.contains { $0.clipId == b && $0.recycledAt != nil })

        // Restorable, which is what makes it a delete the user can survive.
        m.restoreClip(clipId: a)
        #expect(m.clips.contains { $0.clipId == a })
        #expect(m.clips.first { $0.clipId == a }?.recycledAt == nil)
    }

}

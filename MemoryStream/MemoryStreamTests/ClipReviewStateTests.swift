import Testing
import Foundation
@testable import HiMem

/// Money tests for the P7-2 per-device review state (July 18 2026):
/// `InboxClip.reviewed` (rides the manifest JSON) + `BenchClipReviewStore`
/// (per-device UserDefaults for bench MediaReferences). New = not
/// reviewed, so the field MUST persist (encode/decode) and legacy
/// manifests MUST decode `false`, and the bench store must round-trip.
@Suite
struct ClipReviewStateTests {

    private func sampleClip(reviewed: Bool) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_000),
            duration: 12,
            transcript: "hi",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "a.m4a",
            reviewed: reviewed
        )
    }

    @Test func inboxClip_reviewed_survivesCodableRoundTrip() throws {
        let clip = sampleClip(reviewed: true)
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(InboxClip.self, from: data)
        #expect(decoded.reviewed == true)
        // And a false one stays false.
        let d2 = try JSONDecoder().decode(InboxClip.self, from: JSONEncoder().encode(sampleClip(reviewed: false)))
        #expect(d2.reviewed == false)
    }

    @Test func inboxClip_legacyManifest_decodesReviewedFalse() throws {
        // A manifest row written before P7-2 has no `reviewed` key — it must
        // decode to false (never crash, never default-true).
        let legacy: [String: Any] = [
            "clipId": UUID().uuidString,
            "capturedAt": 1_000.0,
            "duration": 12.0,
            "transcript": "hi",
            "source": "watch",
            "audioFilename": "a.m4a"
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(InboxClip.self, from: data)
        #expect(decoded.reviewed == false)
    }

    /// Money test for the per-session mark (July 19 2026): opening a
    /// session card marks EVERY clip in it reviewed in one act, and only
    /// those clips. A clip from another session is untouched, and a
    /// second open is a no-op (idempotent, no crash).
    @MainActor
    @Test func markReviewed_batch_marksListedOnly_idempotent() {
        let manifest = InboxManifest.shared
        let snapshot = manifest.clips
        defer {
            for clip in manifest.clips where !snapshot.contains(where: { $0.clipId == clip.clipId }) {
                manifest.remove(clipId: clip.clipId)
            }
        }
        func seed() -> UUID {
            let id = UUID()
            manifest.acceptClip(InboxClip(
                clipId: id, capturedAt: Date(), duration: 3, transcript: "",
                latitude: nil, longitude: nil, source: "watch",
                audioFilename: "test-\(id.uuidString).caf",
                transcriptionAttempted: false, rollGroupId: nil))
            return id
        }
        let a = seed(), b = seed(), other = seed()
        func reviewed(_ id: UUID) -> Bool { manifest.clips.first { $0.clipId == id }?.reviewed ?? false }
        #expect(reviewed(a) == false)

        // Opening the session marks its two clips; `other` is a
        // different session and stays New.
        manifest.markReviewed(clipIds: [a, b])
        #expect(reviewed(a) == true)
        #expect(reviewed(b) == true)
        #expect(reviewed(other) == false)

        // Re-opening a fully-seen session is a no-op, not a crash.
        manifest.markReviewed(clipIds: [a, b])
        #expect(reviewed(a) == true)
    }

    @Test func benchReviewStore_marksAndReads_idempotent() {
        let key = "com.himem.bench.reviewedRefIds"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        let id = UUID()
        #expect(BenchClipReviewStore.isReviewed(id) == false)
        BenchClipReviewStore.markReviewed(id)
        #expect(BenchClipReviewStore.isReviewed(id) == true)
        // Idempotent — a second mark doesn't error or duplicate.
        BenchClipReviewStore.markReviewed(id)
        #expect(BenchClipReviewStore.isReviewed(id) == true)
        // A different id is independent.
        #expect(BenchClipReviewStore.isReviewed(UUID()) == false)
    }
}

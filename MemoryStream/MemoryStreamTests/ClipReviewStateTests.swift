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

    /// **Asserts only about ids it minted, and clears nothing.**
    ///
    /// This used to `removeObject` the whole key and restore it in a `defer`.
    /// Both are destructive whole-key writes on a process-global store, and
    /// Swift Testing runs suites in parallel — `.serialized` orders tests
    /// *within* a suite, it does not stop two suites interleaving. So this
    /// test wiped state other suites were mid-way through asserting on, and
    /// `NewLensReviewTests.reset()` (same key, same pattern) wiped this one's
    /// mark between line "mark" and line "read". That is what failed the
    /// 2026-08-03 gate, and it is not fixed by the store's lock: a wipe is a
    /// complete, correctly-locked operation — there is nothing torn about it.
    ///
    /// A fresh `UUID` is unique by construction, so none of the assertions
    /// below need an empty store. Removing the clearing makes the test
    /// order-independent instead of order-dependent-and-hoping.
    @Test func benchReviewStore_marksAndReads_idempotent() {
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

    // MARK: - The store has one owner (2026-08-03)

    /// **THE money test — the production shape, exactly.**
    ///
    /// `BenchReviewBackfillMigration.runIfNeeded` calls `apply(refIds:)` inside
    /// `ctx.perform` on a **background** context (`LaunchScreenView:329`), while
    /// `ClipEditorModal.onAppear` calls `markReviewed(_:)` on the main actor.
    /// Both were an unsynchronized read-modify-write of one `UserDefaults` key:
    /// read the set, insert, write the whole array back.
    ///
    /// The damaging interleaving is specific and one-way. If the UI's write
    /// lands *after* the backfill's, using a set it read *before* it, the
    /// backfill's several-hundred ids are gone — and `apply` has already set
    /// `doneKey`, so **the backfill never runs again**. Months of historical
    /// clips flood the New lens permanently, which is the precise symptom the
    /// backfill exists to prevent, on a one-shot upgrade path with no recovery.
    ///
    /// Asserted from both sides: neither the batch nor the singles may be lost.
    /// **Exactly two blocks on a private queue, deliberately.** The production
    /// shape is two writers — one background migration, one main-actor UI —
    /// and two is all the interleaving this needs.
    ///
    /// An earlier draft used `DispatchQueue.concurrentPerform`. It reproduced
    /// the race just as well and **broke
    /// `DebouncedTriggerTests.spacedFires_produceIndividualActions`**:
    /// `concurrentPerform` blocks its calling thread *and* fans out across the
    /// global pool, starving the Swift concurrency cooperative pool that the
    /// debounce test's `Task.sleep` and pending action need — and that test's
    /// `waitUntil` gives up silently after 3s rather than failing loudly, so
    /// it surfaced as a bare `callCount == 3`. Confirmed by A/B: HEAD under the
    /// same machine load gave the baseline 8 failures, this suite's earlier
    /// draft gave 9. **A money test that destabilises its neighbours buys one
    /// guard and spends another.**
    @Test func benchReviewStore_backfillConcurrentWithUiMarks_losesNeither() {
        let backfilled = (0..<300).map { _ in UUID() }   // the migration's library
        let tapped = (0..<120).map { _ in UUID() }       // clips she opens meanwhile

        let queue = DispatchQueue(label: "test.benchReviewStore", attributes: .concurrent)
        let group = DispatchGroup()
        queue.async(group: group) {
            BenchClipReviewStore.markReviewed(backfilled)
        }
        queue.async(group: group) {
            for id in tapped { BenchClipReviewStore.markReviewed(id) }
        }
        group.wait()

        let lostFromBackfill = backfilled.filter { !BenchClipReviewStore.isReviewed($0) }
        let lostFromTaps = tapped.filter { !BenchClipReviewStore.isReviewed($0) }
        #expect(lostFromBackfill.isEmpty,
                "\(lostFromBackfill.count)/300 backfilled ids lost — those clips flood New forever, and doneKey is already set")
        #expect(lostFromTaps.isEmpty,
                "\(lostFromTaps.count)/120 opened clips reverted to unseen")
    }

    /// The same defect at the single-id API, which is every UI write. Separate
    /// from the batch case because they are separate read-modify-writes and a
    /// fix could plausibly cover one and not the other.
    @Test func benchReviewStore_concurrentSingleMarks_loseNothing() {
        let ids = (0..<120).map { _ in UUID() }
        let queue = DispatchQueue(label: "test.benchReviewStore.singles", attributes: .concurrent)
        let group = DispatchGroup()
        for slot in 0..<2 {
            queue.async(group: group) {
                for (i, id) in ids.enumerated() where i % 2 == slot {
                    BenchClipReviewStore.markReviewed(id)
                }
            }
        }
        group.wait()
        let lost = ids.filter { !BenchClipReviewStore.isReviewed($0) }
        #expect(lost.isEmpty, "\(lost.count)/120 marks lost to a torn read-modify-write")
    }

    // MARK: - The two-store write owner (2026-08-10)

    /// **A clip with no manifest row must still be marked seen.**
    ///
    /// This is the whole defect, as a behaviour. `InboxManifest.markReviewed`
    /// walks `clips` and returns silently for an id it has no row for — which
    /// is every **materialized** clip, and on a mature bench that is most of
    /// them (`materializeAll` drains each transcribed row into a ref).
    ///
    /// `SessionListView.markSessionReviewed` called only that, so opening a
    /// session left its ref-backed voice clips unseen. Under F37 admission is
    /// per-session and a session is admitted whole while anything in it is
    /// unreviewed, so such a clip re-admitted its session to New indefinitely:
    /// the user reads a sitting, leaves, and finds it exactly where it was.
    ///
    /// The id here is deliberately one the manifest does not know, because
    /// that is the case the old code silently dropped — a test using a
    /// manifest-backed id passes against the defect.
    @MainActor
    @Test func markingAClipWithNoManifestRowStillRecordsItSeen() {
        let refBacked = UUID()
        #expect(BenchClipReviewStore.isReviewed(refBacked) == false, "fixture id was already recorded")

        BenchClipReviewWriter.markReviewed(refBacked)

        #expect(BenchClipReviewStore.isReviewed(refBacked),
                """
                A clip the manifest has no row for was not recorded as seen. It is \
                materialized (ref-backed), so the manifest write no-ops — and under F37 \
                it re-admits its whole session to New forever.
                """)
    }

    /// **Bound the other side.** The test above passes if the writer drops the
    /// manifest call entirely — which would silently break the
    /// still-in-flight case, where the manifest row *is* the only record. A
    /// one-sided bound exonerates half the defect it was written to catch.
    ///
    /// Mechanical rather than behavioural because the manifest is a shared
    /// singleton persisting to `Documents/Inbox/manifest.json`; the honest
    /// behavioural version needs a production test seam, and adding one to
    /// ship so a test can mutate the real manifest is a worse trade than
    /// asserting the writer names both stores. **Stated so the gate is not
    /// read as stronger than it is:** this pins that the call exists, not that
    /// it lands.
    @Test func theReviewWriterWritesBothStoresNotJustTheRefOne() throws {
        let src = try Self.source("MemoryStream/Services/Storage/InboxManifest.swift")
        let body = try Self.blockBody(
            startingAtLineContaining: "static func markReviewed(clipIds: [UUID]", in: src
        )
        #expect(body.contains("InboxManifest.shared.markReviewed"),
                """
                The review writer no longer writes the manifest, so a clip that has not \
                been materialized yet has no record at all — the still-in-flight half of \
                the two-store rule. Body was:
                \(body)
                """)
        #expect(body.contains("BenchClipReviewStore.markReviewed"),
                """
                The review writer no longer writes the ref store, which is the half whose \
                absence made a session re-admit to New forever. Body was:
                \(body)
                """)
    }

    // MARK: - Source access

    static func source(_ relativePath: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            dir.deleteLastPathComponent()
        }
        // Never pass by finding nothing: a moved file must fail loudly.
        throw SourceLookupError.notFound(relativePath)
    }

    enum SourceLookupError: Error { case notFound(String), anchorMissing(String) }

    /// Brace-balanced body of the block whose opening line contains `needle`.
    /// Throws on a missing anchor so a rename fails rather than passing by
    /// matching nothing.
    static func blockBody(startingAtLineContaining needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw SourceLookupError.anchorMissing(needle)
        }
        var depth = 0
        var out: [String] = []
        for line in lines[start...] {
            out.append(String(line))
            for ch in line {
                if ch == "{" { depth += 1 }
                if ch == "}" { depth -= 1 }
            }
            if depth == 0 && out.count > 1 { break }
        }
        return out.joined(separator: "\n")
    }
}

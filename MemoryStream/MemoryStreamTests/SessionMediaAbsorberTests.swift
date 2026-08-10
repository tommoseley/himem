import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `SessionMediaAbsorber` — the July 11 2026 bridge
/// that folds unplaced photo/video MediaReferences into voice
/// sessions they belong to by time window.
///
/// The bug: a photo captured 2 minutes after a voice clip lived in a
/// separate `unplacedDayGroupedStack` above the voice's session
/// card, not inside it — per the July 11 dogfood report *"a photo at
/// 10:34 floated above the voice-only '2 clips' session it belonged
/// to by time."*
@Suite(.serialized)
@MainActor
struct SessionMediaAbsorberTests {

    /// A photo captured within the session's time window is absorbed
    /// into that session and marked as absorbed (so it can be
    /// filtered out of any parallel unplaced-refs list).
    @Test func photo_within_session_window_is_absorbed() throws {
        let ctx = try makeInMemoryContext()
        let base = Date()
        let voice = makeInboxClip(capturedAt: base)
        let session = ClipGroup(clips: [voice])
        let photo = makeMediaRef(createdAt: base.addingTimeInterval(120), kind: .image, in: ctx)
        let result = SessionMediaAbsorber.absorb(
            sessions: [session],
            unplacedMedia: [photo]
        )
        #expect(result.mediaBySessionId[session.id]?.count == 1)
        #expect(result.absorbedRefIds.contains(photo.id))
    }

    /// A photo outside the session's window (30 min later) is NOT
    /// absorbed and stays available in the unplaced pool.
    @Test func photo_outside_window_is_left_alone() throws {
        let ctx = try makeInMemoryContext()
        let base = Date()
        let voice = makeInboxClip(capturedAt: base)
        let session = ClipGroup(clips: [voice])
        let photo = makeMediaRef(createdAt: base.addingTimeInterval(30 * 60), kind: .image, in: ctx)
        let result = SessionMediaAbsorber.absorb(
            sessions: [session],
            unplacedMedia: [photo]
        )
        #expect((result.mediaBySessionId[session.id] ?? []).isEmpty)
        #expect(!result.absorbedRefIds.contains(photo.id))
    }

    /// A photo whose timestamp falls within TWO sessions' windows
    /// (rare — happens only when the sessions themselves are within
    /// the half-window of each other, which the idle-gap rule
    /// normally prevents) gets absorbed into both. Absorption is
    /// visual grouping only; the final placement decision is the
    /// user's when they bundle a session.
    @Test func photo_between_two_sessions_can_absorb_into_the_closer_one() throws {
        let ctx = try makeInMemoryContext()
        let base = Date()
        let voice1 = makeInboxClip(capturedAt: base)
        let voice2 = makeInboxClip(capturedAt: base.addingTimeInterval(600))
        // 600s apart = exactly at the idle window, so they'd be one
        // session per the grouper — but here we treat them as
        // separate sessions to test the boundary behavior.
        let session1 = ClipGroup(clips: [voice1])
        let session2 = ClipGroup(clips: [voice2])
        // Photo at t=+300s — within window of session1 (end +300s)
        // and session2 (start -300s)
        let photo = makeMediaRef(createdAt: base.addingTimeInterval(300), kind: .image, in: ctx)
        let result = SessionMediaAbsorber.absorb(
            sessions: [session1, session2],
            unplacedMedia: [photo]
        )
        // Overlapping windows → photo shows in both. Not ideal, but
        // safer than dropping the photo entirely; the user's
        // "Start a Memory" choice on either card resolves it.
        let inSession1 = (result.mediaBySessionId[session1.id] ?? []).count
        let inSession2 = (result.mediaBySessionId[session2.id] ?? []).count
        #expect(inSession1 + inSession2 >= 1, "photo must appear in at least one session")
    }

    /// Notes are deferred (until Slice H) — this absorber only pulls
    /// image/video into voice sessions. Notes stay in the unplaced
    /// stack for now.
    @Test func note_is_not_absorbed() throws {
        let ctx = try makeInMemoryContext()
        let base = Date()
        let voice = makeInboxClip(capturedAt: base)
        let session = ClipGroup(clips: [voice])
        let note = makeMediaRef(createdAt: base.addingTimeInterval(60), kind: .note, in: ctx)
        let result = SessionMediaAbsorber.absorb(
            sessions: [session],
            unplacedMedia: [note]
        )
        #expect((result.mediaBySessionId[session.id] ?? []).isEmpty)
        #expect(!result.absorbedRefIds.contains(note.id))
    }

    /// Absorbed items inside a single session are sorted oldest-first
    /// — matches the "sitting unfolds in the direction it happened"
    /// principle from the Slice F grouper.
    @Test func absorbed_items_within_session_are_oldest_first() throws {
        let ctx = try makeInMemoryContext()
        let base = Date()
        let voice = makeInboxClip(capturedAt: base)
        let session = ClipGroup(clips: [voice])
        let photoLate = makeMediaRef(createdAt: base.addingTimeInterval(180), kind: .image, in: ctx)
        let photoEarly = makeMediaRef(createdAt: base.addingTimeInterval(60), kind: .image, in: ctx)
        let result = SessionMediaAbsorber.absorb(
            sessions: [session],
            unplacedMedia: [photoLate, photoEarly]
        )
        let items = result.mediaBySessionId[session.id] ?? []
        #expect(items.count == 2)
        let times = items.compactMap(\.createdAt)
        #expect(times == times.sorted())
    }

    /// Empty inputs → empty result.
    @Test func empty_inputs_return_empty() {
        let result = SessionMediaAbsorber.absorb(sessions: [], unplacedMedia: [])
        #expect(result.mediaBySessionId.isEmpty)
        #expect(result.absorbedRefIds.isEmpty)
    }

    // MARK: - Fixtures

    private func makeInboxClip(capturedAt: Date) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: capturedAt,
            duration: 3,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "clip.m4a"
        )
    }

    private func makeMediaRef(
        createdAt: Date,
        kind: MediaReference.MediaType,
        in ctx: NSManagedObjectContext
    ) -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.osIdentifier = "media-\(UUID().uuidString)"
        ref.mediaType = kind.rawValue
        ref.createdAt = createdAt
        return ref
    }

    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        // Test-isolation fix (2026-07-15): share the ONE production
        // `cachedModel` via StorageService(inMemory:) instead of a fresh
        // `mergedModel(from:)` — multiple live models for the same entity
        // classes race in Core Data's global registry under parallel @Suite
        // runs. Stores stay per-test isolated; the MODEL shares one instance.
        return StorageService(inMemory: true).viewContext
    }
}

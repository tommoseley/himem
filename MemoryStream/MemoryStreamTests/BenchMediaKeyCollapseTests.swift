import Testing
import Foundation
import CoreData
@testable import HiMem

/// **B25 — the money test. Two voiceless sessions must each resolve their own
/// media.**
///
/// `mediaBySessionId` is keyed by the **projected** `ClipGroup.id`, and
/// `projectGroup` keeps voice only — so a media-only session projects to
/// `ClipGroup(clips: [])`, whose id is `ClipSessionGrouper.emptyGroupId`, a
/// fixed sentinel introduced by `18021bc` to close the Clips freeze. Its own doc
/// says *"two empty groups now COLLIDE"*; that was reasoned about for `ForEach`
/// identity and never joined to the fact that the same value is a dictionary
/// key.
///
/// So every voiceless session writes one bucket, each overwriting the last, and
/// every one reads back whatever the last writer left. On device:
/// `resolved=6 legacy=1` and `resolved=4 legacy=1` twice, all reporting
/// `key=00000000 map=HIT` with media-only `kinds=`.
///
/// **A session holding exactly one media item agrees by coincidence** (`0 + 1`),
/// which is why only some sessions reported and the set rotated between runs.
/// This fixture therefore gives each session a *different* number of items, so
/// neither can pass by accident.
///
/// ---
///
/// **RE-POINTED BY THE FIX, 2026-08-19 — read this before touching the
/// assertions.**
///
/// This landed first against the legacy pair and failed exactly as predicted:
/// `keyA != keyB` failed with both ids `…E317`, and `map[keyA]?.count == 2`
/// failed reading back **3** — session A returning session B's refs. The third
/// assertion PASSED, because B was the last writer; that passing line is what
/// explained the device's rotating report.
///
/// The fix retires the projection and the map, so the subject those assertions
/// named no longer exists to call. They are therefore computed through
/// `ResolvedSession`, the value that replaced the pair — **the three
/// assertions and their messages are unchanged**, because the invariant is
/// unchanged: two voiceless sessions must each keep their own media. Only the
/// route to it moved. Nothing here was weakened to make it pass.
///
/// The legacy formulation is preserved in the commit that introduced it, so
/// the original red is recoverable from git rather than only described.
struct BenchMediaKeyCollapseTests {

    private func makeRef(in ctx: NSManagedObjectContext, at date: Date) throws -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.osIdentifier = "asset://test"
        ref.createdAt = date
        try ctx.save()
        return ref
    }

    private func item(_ id: UUID, at date: Date) -> BenchClipItem {
        BenchClipItem(id: id, kind: .image, capturedAt: date, rollGroupId: nil)
    }

    @Test
    func twoVoicelessSessionsEachKeepTheirOwnMedia() throws {
        let ctx = StorageService(inMemory: true).viewContext
        let base = Date(timeIntervalSinceReferenceDate: 0)

        // Session A: two photos. Session B: three, far enough away to group apart.
        let a1 = try makeRef(in: ctx, at: base)
        let a2 = try makeRef(in: ctx, at: base.addingTimeInterval(60))
        let b1 = try makeRef(in: ctx, at: base.addingTimeInterval(50_000))
        let b2 = try makeRef(in: ctx, at: base.addingTimeInterval(50_060))
        let b3 = try makeRef(in: ctx, at: base.addingTimeInterval(50_120))

        let sessionA = UnifiedSession(items: [item(a1.id, at: base), item(a2.id, at: base.addingTimeInterval(60))])
        let sessionB = UnifiedSession(items: [
            item(b1.id, at: base.addingTimeInterval(50_000)),
            item(b2.id, at: base.addingTimeInterval(50_060)),
            item(b3.id, at: base.addingTimeInterval(50_120)),
        ])

        let mediaById = [a1.id: a1, a2.id: a2, b1.id: b1, b2.id: b2, b3.id: b3]
        let voiceById: [UUID: InboxClip] = [:]   // neither session has voice — the whole point

        // Composed exactly as `recompose` composes it now.
        let resolvedA = ResolvedSession.resolve(sessionA, voiceById: voiceById, mediaById: mediaById)
        let resolvedB = ResolvedSession.resolve(sessionB, voiceById: voiceById, mediaById: mediaById)

        let keyA = resolvedA.id
        let keyB = resolvedB.id

        #expect(keyA != keyB, "Two distinct sessions must not share a map key — a fixed sentinel for 'no voice clips' makes every voiceless session the same session as far as this map is concerned")
        #expect(resolvedA.media.count == 2, "Session A holds two photos and must read back two")
        #expect(resolvedB.media.count == 3, "Session B holds three photos and must read back three")

        // Nothing was silently dropped on the way — `projectGroup` resolved
        // with `compactMap` and would have hidden it.
        #expect(resolvedA.unresolved.isEmpty)
        #expect(resolvedB.unresolved.isEmpty)
    }

    /// **B25's SECOND SITE — the drill-in lookup** (`SessionListView`'s
    /// `openedSessionContent`, `allSessions.first(where: { $0.id == sessionId })`).
    ///
    /// Retiring the media map does not touch this one, which is why it was
    /// ruled into the same slice. `first(where:)` over N sessions that all
    /// carry the same sentinel id returns whichever collided first, so opening
    /// one voiceless session could show another's contents.
    ///
    /// **Guard the caller, not just the owner.** The assertion above proves two
    /// sessions resolve to distinct ids; this proves the property the *lookup*
    /// depends on — that a whole bench of voiceless sessions is distinguishable
    /// — and does it by performing the same `first(where:)` the drill-in
    /// performs, rather than trusting that distinctness implies a correct
    /// lookup. Four sessions, because two can collide by accident in ways four
    /// cannot.
    @Test
    func aBenchOfVoicelessSessionsIsDistinguishableByTheDrillIn() throws {
        let ctx = StorageService(inMemory: true).viewContext
        let base = Date(timeIntervalSinceReferenceDate: 0)

        var sessions: [UnifiedSession] = []
        var mediaById: [UUID: MediaReference] = [:]
        // Four voiceless sittings, each a different size so no two can agree by
        // the `0 + 1 == 1` coincidence that kept B25 quiet on device.
        for (index, size) in [1, 2, 3, 4].enumerated() {
            let start = base.addingTimeInterval(Double(index) * 50_000)
            var items: [BenchClipItem] = []
            for n in 0..<size {
                let at = start.addingTimeInterval(Double(n) * 60)
                let ref = try makeRef(in: ctx, at: at)
                mediaById[ref.id] = ref
                items.append(item(ref.id, at: at))
            }
            sessions.append(UnifiedSession(items: items))
        }

        let resolved = sessions.map {
            ResolvedSession.resolve($0, voiceById: [:], mediaById: mediaById)
        }

        #expect(Set(resolved.map(\.id)).count == 4, "Four voiceless sessions must carry four ids — under the projection all four were the empty-group sentinel")

        // The drill-in's own expression, per session.
        for expected in resolved {
            let found = resolved.first(where: { $0.id == expected.id })
            #expect(found?.id == expected.id)
            #expect(found?.media.count == expected.media.count, "Opening a session must show that session's items, not the first colliding session's")
        }
    }
}

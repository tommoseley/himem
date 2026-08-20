import Testing
import Foundation
import CoreData
@testable import HiMem

/// **C2 step 4 — the card layer's "+ media" term, made inexpressible.**
///
/// The cards speak `ClipGroup`, which is voice only, so every derived quantity
/// carried a separately-scoped media term from `mediaBySessionId`. Two sites in
/// `SessionListView` are the same line verbatim:
/// `session.clips.count + (mediaBySessionId[session.id]?.count ?? 0)`.
/// `ResolvedSession.count` reads one set, so there is no second term to forget.
///
/// **The first mutation at C2 step 1 found a hole in the rebuild's own suite** —
/// `keptItems` lost its trim filter and every test passed, because each one had
/// exercised it with an empty trim. So these fixtures deliberately mix voice and
/// media, and assert the media half specifically: a suite that only ever
/// resolves voice would pass with the media branch deleted.
struct ResolvedSessionTests {

    private func makeContext() throws -> NSManagedObjectContext {
        StorageService(inMemory: true).viewContext
    }

    private func makeRef(in ctx: NSManagedObjectContext, at date: Date) throws -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.osIdentifier = "asset://test"
        ref.createdAt = date
        try ctx.save()
        return ref
    }

    private func makeClip(at date: Date) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: date,
            duration: 30,
            transcript: "test",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(UUID()).caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
    }

    private func item(_ id: UUID, _ kind: BenchClipItem.Kind, at date: Date) -> BenchClipItem {
        BenchClipItem(id: id, kind: kind, capturedAt: date, rollGroupId: nil)
    }

    @Test
    func aResolvedSessionCountsVoiceAndMediaAsOneSet() throws {
        let ctx = try makeContext()
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let clip = makeClip(at: base)
        let photo = try makeRef(in: ctx, at: base.addingTimeInterval(60))

        let session = UnifiedSession(items: [
            item(clip.clipId, .voice, at: clip.capturedAt),
            item(photo.id, .image, at: base.addingTimeInterval(60)),
        ])

        let resolved = ResolvedSession.resolve(
            session,
            voiceById: [clip.clipId: clip],
            mediaById: [photo.id: photo]
        )

        #expect(resolved.count == 2, "the count is one set — voice and media alike, with no second term to add")
        #expect(resolved.unresolved.isEmpty)
        #expect(
            resolved.items.contains { if case .media = $0 { return true }; return false },
            "the media branch must actually resolve — a suite that only exercises voice would pass with it deleted"
        )
        #expect(resolved.count == session.items.count, "nothing added, nothing dropped")
    }

    /// **An item with no backing is REPORTED.** `projectGroup` resolves with
    /// `compactMap`, so a missing backing vanishes — and a clip vanishing
    /// silently is the failure this rebuild keeps finding.
    @Test
    func anItemWithNoBackingIsReportedRatherThanDropped() throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let clip = makeClip(at: base)
        let ghost = UUID()

        let session = UnifiedSession(items: [
            item(clip.clipId, .voice, at: base),
            item(ghost, .image, at: base.addingTimeInterval(60)),
        ])

        let resolved = ResolvedSession.resolve(session, voiceById: [clip.clipId: clip], mediaById: [:])

        #expect(resolved.unresolved == [ghost], "the missing item must be named, not silently absent")
        #expect(resolved.count == 1, "and it must not be counted as drawn — the count describes what the card can draw")
    }

    /// Newest-first, matching `ClipGroup.clips`, so migrating a consumer does
    /// not also reorder it. Media participates in the ordering — it is an item,
    /// not an appendix.
    @Test
    func itemsAreNewestFirstAcrossBothKinds() throws {
        let ctx = try makeContext()
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let older = makeClip(at: base)
        let middle = try makeRef(in: ctx, at: base.addingTimeInterval(600))
        let newest = makeClip(at: base.addingTimeInterval(1200))

        let session = UnifiedSession(items: [
            item(older.clipId, .voice, at: older.capturedAt),
            item(middle.id, .image, at: base.addingTimeInterval(600)),
            item(newest.clipId, .voice, at: newest.capturedAt),
        ])

        let resolved = ResolvedSession.resolve(
            session,
            voiceById: [older.clipId: older, newest.clipId: newest],
            mediaById: [middle.id: middle]
        )

        #expect(resolved.items.map(\.id) == [newest.clipId, middle.id, older.clipId])
    }

    // MARK: - The remainder rule (C2 step 4 slice C)

    /// **A partly-claimed session's remainder draws no media.**
    ///
    /// The cluster card owns it — kept refs in its glyphs, set-aside refs in
    /// its own "Set aside" block — so the loose card drawing them too is the
    /// duplication class F35(b) closed.
    ///
    /// **This rule had NO test, and was enforced by accident.** The card layer
    /// looked media up in a map keyed by the projected `ClipGroup.id`; a
    /// remainder's projection derives from a different first clip, so the
    /// lookup missed. Slice C retires that map, which would have inverted the
    /// rule silently with the whole gate green. Written now because "then write
    /// the test that would have caught it" is the half that keeps the class
    /// closed.
    @Test
    func aRemainderDropsItsMediaAndKeepsItsVoice() throws {
        let ctx = try makeContext()
        let base = Date(timeIntervalSinceReferenceDate: 0)

        let ref = try makeRef(in: ctx, at: base.addingTimeInterval(60))
        let clip = makeClip(at: base)
        let ghost = UUID()

        let session = UnifiedSession(items: [
            BenchClipItem(id: clip.clipId, kind: .voice, capturedAt: base, rollGroupId: nil),
            BenchClipItem(id: ref.id, kind: .image, capturedAt: base.addingTimeInterval(60), rollGroupId: nil),
            BenchClipItem(id: ghost, kind: .image, capturedAt: base.addingTimeInterval(90), rollGroupId: nil),
        ])

        let resolved = ResolvedSession.resolve(
            session,
            voiceById: [clip.clipId: clip],
            mediaById: [ref.id: ref]
        )
        #expect(resolved.media.count == 1, "precondition: the whole session carries its media")
        #expect(resolved.voice.count == 1)

        let remainder = resolved.withoutMedia()

        #expect(remainder.media.isEmpty, "the cluster card owns a remainder's media — drawing it here duplicates it on one screen")
        #expect(remainder.voice.count == 1, "the voice half must survive: the remainder exists to bring set-aside CLIPS back")
        #expect(remainder.count == 1, "the count follows the items, so a card cannot describe media it does not draw")
        #expect(remainder.id == resolved.id, "identity is the session's, not a function of its membership")
        #expect(remainder.unresolved == [ghost], "an item with no backing is a finding regardless of who draws the media")
    }

}

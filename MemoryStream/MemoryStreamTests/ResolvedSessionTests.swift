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
}

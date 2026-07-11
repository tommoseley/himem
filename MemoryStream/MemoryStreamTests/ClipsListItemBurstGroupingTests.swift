import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the July 9 2026 burst-grouping rule per
/// `docs/design/screens-clips-page.jsx` §BurstRow: contiguous
/// same-minute + same-place photo/video runs collapse into ONE row so
/// a photo-heavy day doesn't wall the list with identical "Photo"
/// rows.
@MainActor
@Suite(.serialized)
struct ClipsListItemBurstGroupingTests {

    private func makeStorage() -> StorageService {
        StorageService(inMemory: true)
    }

    private func seedMemory(_ storage: StorageService) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "", inputType: .typed)
        try storage.viewContext.save()
        return entry
    }

    /// Builds a MediaReference outside `createMediaReference` so the
    /// tests can control every attribute (createdAt, mediaType,
    /// placeName). No edges are attached — these refs render as
    /// unplaced.
    private func makeRef(
        in storage: StorageService,
        type: MediaReference.MediaType,
        at date: Date,
        place: String? = nil,
        transcript: String? = nil
    ) throws -> MediaReference {
        let ctx = storage.viewContext
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.osIdentifier = UUID().uuidString
        ref.mediaType = type.rawValue
        ref.isAccessible = true
        ref.createdAt = date
        ref.placeName = place
        ref.transcript = transcript
        try storage.save(context: ctx)
        return ref
    }

    // MARK: - Voice/note never burst

    /// Voice clips must always render as `.single`, even if they land
    /// in the same minute at the same place. The rule targets the
    /// visual "wall of photos" specifically — voice/note previews
    /// carry text and are useful individually.
    @Test func voiceClipsNeverBurstEvenWhenAdjacent() throws {
        let storage = makeStorage()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let ref1 = try makeRef(in: storage, type: .voice, at: base, place: "CIA")
        let ref2 = try makeRef(in: storage, type: .voice, at: base.addingTimeInterval(10), place: "CIA")

        let items = ClipsListItem.group(refs: [ref1, ref2])
        #expect(items.count == 2)
        for item in items {
            if case .burst = item { Issue.record("voice must not burst") }
        }
    }

    // MARK: - Photos within 60s + same place → burst

    @Test func photosSameMinuteSamePlaceCollapseIntoBurst() throws {
        let storage = makeStorage()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var refs: [MediaReference] = []
        for i in 0..<4 {
            refs.append(try makeRef(
                in: storage,
                type: .image,
                at: base.addingTimeInterval(Double(i) * 5), // 0, 5, 10, 15s apart
                place: "Tybee Island"
            ))
        }

        let items = ClipsListItem.group(refs: refs)
        #expect(items.count == 1)
        if case .burst(let bursted) = items.first {
            #expect(bursted.count == 4)
        } else {
            Issue.record("expected a single burst of 4 photos")
        }
    }

    // MARK: - Different place breaks the burst

    /// Two photos taken 5 seconds apart but in different places must
    /// remain as separate rows — they didn't share a moment.
    @Test func differentPlaceBreaksBurst() throws {
        let storage = makeStorage()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let a = try makeRef(in: storage, type: .image, at: base, place: "Home")
        let b = try makeRef(in: storage, type: .image, at: base.addingTimeInterval(5), place: "Marsh Walk")

        let items = ClipsListItem.group(refs: [a, b])
        #expect(items.count == 2)
        for item in items {
            if case .burst = item { Issue.record("different places must not burst") }
        }
    }

    // MARK: - Gap > 60s breaks the burst

    /// A 90-second gap between two same-place photos is beyond the
    /// same-minute window — they emit as two singles.
    @Test func gapOverSixtySecondsBreaksBurst() throws {
        let storage = makeStorage()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let a = try makeRef(in: storage, type: .image, at: base, place: "CIA")
        let b = try makeRef(in: storage, type: .image, at: base.addingTimeInterval(90), place: "CIA")

        let items = ClipsListItem.group(refs: [a, b])
        #expect(items.count == 2)
        for item in items {
            if case .burst = item { Issue.record("gap > 60s must not burst") }
        }
    }

    // MARK: - Voice in the middle splits the burst

    /// A voice clip between two photos flushes the current burst and
    /// starts a fresh one — bursts are runs of contiguous media.
    @Test func voiceInterruptsAndSplitsPhotoBurst() throws {
        let storage = makeStorage()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let p1 = try makeRef(in: storage, type: .image, at: base, place: "CIA")
        let voice = try makeRef(in: storage, type: .voice, at: base.addingTimeInterval(10), place: "CIA")
        let p2 = try makeRef(in: storage, type: .image, at: base.addingTimeInterval(20), place: "CIA")
        let p3 = try makeRef(in: storage, type: .image, at: base.addingTimeInterval(25), place: "CIA")

        let items = ClipsListItem.group(refs: [p1, voice, p2, p3])
        // Expect: single(p1), single(voice), burst(p2, p3)
        #expect(items.count == 3)
        if case .single(let r) = items[0] { #expect(r.id == p1.id) } else { Issue.record("[0] wrong") }
        if case .single(let r) = items[1] { #expect(r.id == voice.id) } else { Issue.record("[1] wrong") }
        if case .burst(let bursted) = items[2] {
            #expect(bursted.count == 2)
            #expect(bursted[0].id == p2.id)
            #expect(bursted[1].id == p3.id)
        } else {
            Issue.record("[2] expected burst of 2")
        }
    }

    // MARK: - Photos and videos burst together at same time+place

    /// A photo followed by a video 10s later at the same place still
    /// counts as one burst — spec's "N items" wording handles mixed
    /// media.
    @Test func mixedPhotoAndVideoCanBurstTogether() throws {
        let storage = makeStorage()
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let p = try makeRef(in: storage, type: .image, at: base, place: "Tybee")
        let v = try makeRef(in: storage, type: .video, at: base.addingTimeInterval(10), place: "Tybee")

        let items = ClipsListItem.group(refs: [p, v])
        #expect(items.count == 1)
        if case .burst(let bursted) = items.first {
            #expect(bursted.count == 2)
        } else {
            Issue.record("mixed media at same time+place must burst")
        }
    }

    // MARK: - Single lonely photo does NOT burst

    /// One photo alone must emit as `.single`, not `.burst`. Bursts
    /// need at least 2 members to earn the compressed layout.
    @Test func singlePhotoRendersAsSingle() throws {
        let storage = makeStorage()
        let ref = try makeRef(
            in: storage,
            type: .image,
            at: Date(timeIntervalSinceReferenceDate: 800_000_000),
            place: "Home"
        )

        let items = ClipsListItem.group(refs: [ref])
        #expect(items.count == 1)
        if case .single = items.first {} else {
            Issue.record("single photo must not burst")
        }
    }
}

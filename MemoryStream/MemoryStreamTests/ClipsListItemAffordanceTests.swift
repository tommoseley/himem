import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the Clips-bench flat-row affordance rules (CC directive
/// July 22 2026). The reported device bug: tapping ✎ on a 4-photo burst
/// silently opened clip 1 (`refs.first`). The invariant that prevents its
/// return: a **burst carries no top-level ✎** — editing a burst is
/// per-clip inside the expanded accordion. And the carat is uniform:
/// single voice/note and multi-clip bursts expand in place.
@MainActor
@Suite(.serialized)
struct ClipsListItemAffordanceTests {

    private func ref(_ s: StorageService, _ type: MediaReference.MediaType, at t: Date) -> MediaReference {
        let r = MediaReference(context: s.viewContext)
        r.id = UUID(); r.osIdentifier = UUID().uuidString; r.mediaType = type.rawValue
        r.isAccessible = true; r.createdAt = t; r.placeName = "Home"
        return r
    }

    /// **The money test.** A media burst must NOT expose a top-level edit
    /// target — that was the `refs.first` clip-1 bug. Editing is per-clip
    /// inside the expanded accordion.
    @Test func burst_hasNoTopLevelEdit_andIsExpandable() {
        let s = StorageService(inMemory: true)
        let t = Date()
        let photos = [ref(s, .image, at: t), ref(s, .image, at: t.addingTimeInterval(5)),
                      ref(s, .image, at: t.addingTimeInterval(10)), ref(s, .image, at: t.addingTimeInterval(15))]
        let items = ClipsListItem.group(refs: photos)
        let burst = try! #require(items.first)
        // Same-minute same-place photos coalesce into one burst.
        if case .burst(let refs) = burst {
            #expect(refs.count == 4)
        } else {
            Issue.record("Expected a burst for 4 same-minute photos")
        }
        #expect(burst.hasTopLevelEdit == false, "A burst must never carry a clip-1 top-level ✎")
        #expect(burst.isExpandable == true, "The carat expands the burst to all its clips")
    }

    @Test func singleVoice_isExpandable_andEditable() {
        let s = StorageService(inMemory: true)
        let item = ClipsListItem.single(ref(s, .voice, at: Date()))
        #expect(item.isExpandable == true, "A single voice row expands to its full transcript")
        #expect(item.hasTopLevelEdit == true, "A single clip's ✎ edits it directly")
    }

    @Test func singleNote_isExpandable_andEditable() {
        let s = StorageService(inMemory: true)
        let item = ClipsListItem.single(ref(s, .note, at: Date()))
        #expect(item.isExpandable == true)
        #expect(item.hasTopLevelEdit == true)
    }

    @Test func singlePhoto_notExpandable_butEditable() {
        let s = StorageService(inMemory: true)
        let item = ClipsListItem.single(ref(s, .image, at: Date()))
        #expect(item.isExpandable == false, "A single photo has no transcript to expand in place")
        #expect(item.hasTopLevelEdit == true, "Its ✎ opens the modal directly")
    }

    @Test func singleVideo_notExpandable_butEditable() {
        let s = StorageService(inMemory: true)
        let item = ClipsListItem.single(ref(s, .video, at: Date()))
        #expect(item.isExpandable == false)
        #expect(item.hasTopLevelEdit == true)
    }

    /// The convergence adapter (2026-07-22): the bench renders through the
    /// shared Memory-Detail cards (`CompactClipRow` / `MediaCard`) via
    /// `MediaReference.displayItem`. If this mapping drifts, the shared
    /// cards get wrong data — guard every field the cards read.
    @Test func displayItem_mapsAllFieldsForSharedCards() {
        let s = StorageService(inMemory: true)
        let r = ref(s, .voice, at: Date(timeIntervalSince1970: 1_700_000_000))
        r.transcript = "hello world"
        r.mediaDescription = nil
        r.placeName = "Kingfisher Wharf"
        try! s.viewContext.save()

        let d = r.displayItem
        #expect(d.id == r.id)
        #expect(d.localIdentifier == r.osIdentifier)
        #expect(d.mediaType == .voice)
        #expect(d.transcript == "hello world")
        #expect(d.placeName == "Kingfisher Wharf")
        #expect(d.createdAt == r.createdAt)
        #expect(d.isAccessible == r.isAccessible)
    }

    @Test func displayItem_photo_carriesDescriptionAndType() {
        let s = StorageService(inMemory: true)
        let r = ref(s, .image, at: Date())
        r.mediaDescription = "sunset over the harbor"
        try! s.viewContext.save()

        let d = r.displayItem
        #expect(d.mediaType == .image)
        #expect(d.mediaDescription == "sunset over the harbor")
    }
}

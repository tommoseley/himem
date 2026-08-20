import Testing
import Foundation
import CoreData
@testable import HiMem

/// **B18 — a label was being used as an identity.**
///
/// `ClipsTabView:1574` rendered the "In <memory> <memory>" chip row as
/// `ForEach(memoryTitles.prefix(3), id: \.self)` over `[String]`, so **two
/// memories sharing a title collide**. SwiftUI logged it outright:
/// *"the ID … occurs multiple times within the collection, this will give
/// undefined results!"* — and the duplicate in the device log was a memory
/// title.
///
/// **Same family as the `ClipGroup.id` freeze closed in `18021bc`**: an
/// identity that is not a function of a stable key. That one also looked
/// harmless first — it was a fresh `UUID()` per read, and it locked the phone.
/// A label is a display value; it is never an identity.
///
/// Titles are not unique by construction and cannot be made so: `displayTitle`
/// falls back to derived text, so two clips captured in one sitting can easily
/// render the same string.
@MainActor  // B24: `viewContext` is NSMainQueueConcurrencyType; without this the
            // suite body runs on the Swift cooperative pool and `save()` aborts the host.
struct MemoryChipIdentityTests {

    @Test
    func twoMemoriesSharingATitleKeepDistinctIdentities() throws {
        let storage = StorageService(inMemory: true)
        let context = storage.viewContext

        let shared = "Building repeatable AI workflows for software specs"
        let first = JournalEntry(context: context)
        first.id = UUID()
        first.title = shared
        first.createdAt = Date()
        let second = JournalEntry(context: context)
        second.id = UUID()
        second.title = shared
        second.createdAt = Date()
        try context.save()

        let chips = MemoryChip.chips(for: [first, second])

        #expect(chips.count == 2, "self-test: both memories must reach the row, or the identity assertion is vacuous")
        #expect(chips[0].title == chips[1].title, "self-test: the fixture must actually collide on the label")
        #expect(
            chips[0].id != chips[1].id,
            "Two memories sharing a title must keep distinct identities — keying a ForEach by the label gives SwiftUI duplicate IDs and, in its own words, undefined results"
        )
        #expect(Set(chips.map(\.id)).count == chips.count, "identity must be unique across the whole row, not just pairwise")
    }

    /// The label still has to reach the screen — an identity fix that silently
    /// changed what is displayed would be a different defect.
    @Test
    func theChipStillCarriesTheTitleItDisplays() throws {
        let storage = StorageService(inMemory: true)
        let context = storage.viewContext
        let entry = JournalEntry(context: context)
        entry.id = UUID()
        entry.title = "Sparrow Quarry"
        entry.createdAt = Date()
        try context.save()

        let chips = MemoryChip.chips(for: [entry])
        #expect(chips.map(\.title) == ["Sparrow Quarry"])
        #expect(chips.map(\.id) == [entry.id], "identity is the memory's id")
    }
}

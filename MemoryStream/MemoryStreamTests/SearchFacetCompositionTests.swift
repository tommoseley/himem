import Testing
import Foundation
import CoreData
@testable import HiMem

/// Integration tests for the object-scope + When facets at the ViewModel
/// seam (`SearchViewModel`) — that scope selects memories/clips/both and
/// the When range composes with the text query.
@MainActor
@Suite(.serialized)
struct SearchFacetCompositionTests {

    private func makeVM() -> (StorageService, SearchViewModel) {
        let s = StorageService(inMemory: true)
        let vm = SearchViewModel(engine: SearchEngine(storage: s), storage: s)
        return (s, vm)
    }

    private func utcDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        return c.date(from: comps)!
    }

    private func looseClip(in s: StorageService, id: String, transcript: String, createdAt: Date = Date()) {
        let r = MediaReference(context: s.viewContext)
        r.id = UUID(); r.osIdentifier = id; r.mediaType = MediaReference.MediaType.voice.rawValue
        r.isAccessible = true; r.createdAt = createdAt; r.transcript = transcript
        try! s.viewContext.save()
    }

    private func search(_ vm: SearchViewModel, _ text: String) {
        vm.onQueryChanged(text)
        vm.submit()
    }

    @Test func objectScope_selectsMemoriesClipsOrBoth() throws {
        let (s, vm) = makeVM()
        _ = try s.createEntry(content: "tomato harvest notes", inputType: .typed)
        try s.viewContext.save()
        looseClip(in: s, id: "loose.caf", transcript: "tomato trellis idea")

        // Default: Memories only — the loose clip is invisible.
        search(vm, "tomato")
        #expect(vm.hits.count == 1)
        #expect(vm.clipHits.isEmpty)

        // Clips only.
        vm.setObjectScope(.clips)
        #expect(vm.hits.isEmpty)
        #expect(vm.clipHits.count == 1)
        #expect(vm.clipHits.first?.status == "Unconnected")

        // All — both, interleaved.
        vm.setObjectScope(.all)
        #expect(vm.hits.count == 1)
        #expect(vm.clipHits.count == 1)
        #expect(vm.flatResults.count == 2)
    }

    @Test func whenRange_composesWithText() throws {
        let (s, vm) = makeVM()
        let m2023 = try s.createEntry(content: "garden tomato", inputType: .typed)
        m2023.createdAt = utcDate(2023, 6, 1)
        let m2024 = try s.createEntry(content: "garden tomato", inputType: .typed)
        m2024.createdAt = utcDate(2024, 6, 1)
        try s.viewContext.save()

        search(vm, "tomato")
        #expect(vm.hits.count == 2, "Both years match the text")

        vm.setWhen(range: WhenPopover_yearInterval(2023), label: "2023")
        #expect(vm.hits.count == 1, "When: 2023 narrows to the 2023 memory")
        #expect(vm.hits.first?.entry.createdAt == m2023.createdAt)

        vm.clearWhen()
        #expect(vm.hits.count == 2, "Clearing When restores both")
    }

    /// Mirror of `WhenPopover.yearInterval` (that helper is private to the
    /// view); keeps this test independent of the UI layer.
    private func WhenPopover_yearInterval(_ year: Int) -> DateInterval {
        var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        // Match Calendar.current used by the VM's date predicate.
        let cal = Calendar.current
        let start = cal.date(from: comps) ?? Date()
        let end = cal.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}

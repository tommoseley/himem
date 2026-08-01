import Testing
import Foundation
import CoreData
@testable import HiMem

/// F23 · T2.4 — **`entryCount()` set a predicate on one request and counted a
/// different one.**
///
/// `EpigraphService.swift:127-132` built an `NSFetchRequest<NSNumber>`, gave it
/// the live-entry predicate and `.countResultType` — then passed a **freshly
/// constructed, predicate-less** `NSFetchRequest<JournalEntry>` to
/// `count(for:)`. The configured request was never used, so recycled memories
/// were counted as live.
///
/// That count is the input to `todaysEpigraphWithSource(entryCount:)`
/// (`LaunchScreenView:248`), which picks the epigraph *stage*. A user who
/// deleted most of their memories kept being addressed as though they still
/// had them — a small dishonesty, but the same Honest-Label class: a number
/// stated with certainty that is not the number it claims to be.
///
/// This is the shape a compiler cannot catch and a reviewer's eye slides over:
/// the discarded request is well-formed and sits two lines above the one that
/// runs.
@MainActor
@Suite(.serialized)
struct EpigraphEntryCountTests {

    /// THE MONEY TEST. Recycled memories are not live memories.
    @Test func recycledMemoriesAreNotCounted() throws {
        let storage = StorageService(inMemory: true)
        let live = try storage.createEntry(content: "kept", inputType: .typed, title: "Kept")
        let trashed = try storage.createEntry(content: "gone", inputType: .typed, title: "Gone")
        let alsoTrashed = try storage.createEntry(content: "gone too", inputType: .typed, title: "Gone too")
        trashed.isRecycled = true
        alsoTrashed.isRecycled = true
        try storage.viewContext.save()
        _ = live

        let count = EpigraphService.shared.entryCount(in: storage.viewContext)

        #expect(count == 1, "two of the three are in Recently Deleted; the epigraph stage must not count them")
    }

    /// The non-empty companion: real memories ARE counted. Without it,
    /// `return 0` would pass the money test.
    @Test func liveMemoriesAreCounted() throws {
        let storage = StorageService(inMemory: true)
        for i in 0..<4 {
            _ = try storage.createEntry(content: "m\(i)", inputType: .typed, title: "M\(i)")
        }
        try storage.viewContext.save()

        #expect(EpigraphService.shared.entryCount(in: storage.viewContext) == 4)
    }

    /// An empty store counts zero — the stage-selection floor.
    @Test func anEmptyStoreCountsZero() {
        let storage = StorageService(inMemory: true)
        #expect(EpigraphService.shared.entryCount(in: storage.viewContext) == 0)
    }
}

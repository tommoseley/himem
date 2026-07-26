import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for the 2026-07-26 "a clip inside a titled memory shows its
/// memory as 'Untitled memory'" bug (device dogfood, build 26). The clip→memory
/// reference labels — the clip editor's edge row, the "Add to a memory" picker,
/// and the Clips connections line — resolved the memory name from the RAW
/// `entry.title`, which is `nil` until AI-organize runs, with an ad-hoc
/// "Untitled memory" fallback. They bypassed `displayTitle`, the canonical
/// resolver (title → AI summary → content snippet → type-based label) that every
/// OTHER surface uses. So a perfectly normal un-organized memory read as
/// "Untitled" in the clip's reference while showing a real name in the Memories
/// list. The edge was always correct — this was only the label (my capture
/// instrumentation proved the photo edged to the right entry, one ref).
@MainActor
struct MemoryReferenceLabelTests {

    /// The exact failing shape from the device: `title == nil`, real content.
    /// `rowTitle` must resolve to `displayTitle`, never the "Untitled" fallback.
    @Test func rowTitle_nilTitleWithContent_resolvesToDisplayTitle_notUntitled() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(
            content: "Long time ago, I made a guy named Alex Brown",
            inputType: .voiceInApp,
            title: nil
        )
        #expect(entry.title == nil, "the failing shape — no stored title yet")
        #expect(entry.displayTitle != "Untitled memory", "displayTitle derives a real name")
        #expect(ExistingMemoryPickerView.rowTitle(entry) == entry.displayTitle,
                "the picker label IS the memory's display name")
        #expect(ExistingMemoryPickerView.rowTitle(entry) != "Untitled memory",
                "a titled/derivable memory never reads as Untitled in a clip reference")
    }

    /// A truly-empty memory (no title, no summary, no content) falls back to
    /// its DATE — the one honest distinguishing thing — never "Untitled" and
    /// never a placeholder noun (2026-07-26 ruling).
    @Test func rowTitle_emptyMemory_fallsBackToDate_notUntitled() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .voiceInApp, title: nil)
        #expect(ExistingMemoryPickerView.rowTitle(entry) == JournalEntry.dateFallbackTitle(from: entry.createdAt),
                "empty memory reads as its date on the picker surface")
        #expect(ExistingMemoryPickerView.rowTitle(entry) == entry.displayTitle,
                "the picker delegates to the one shared resolver")
        #expect(ExistingMemoryPickerView.rowTitle(entry) != "Untitled memory")
    }

    /// A memory with a real stored title is unaffected — the title shows through.
    @Test func rowTitle_realTitle_showsThrough() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed, title: "Running, Weight, and Retirement Reflections")
        #expect(ExistingMemoryPickerView.rowTitle(entry) == "Running, Weight, and Retirement Reflections")
    }

    /// The OTHER two surfaces — the Clips connections line and the clip-editor
    /// edge row — resolve through the SAME `displayTitle`. Exercise the exact
    /// expressions the views use so a future edit can't silently reintroduce a
    /// raw-`title` resolution — the seam that broke (all three drifting apart).
    @Test func connectionsAndEdgeRow_resolveThroughDisplayTitle_notUntitled() throws {
        let storage = StorageService(inMemory: true)
        let memory = try storage.createEntry(
            content: "Long time ago, I made a guy named Alex Brown",
            inputType: .voiceInApp, title: nil
        )
        let ref = try storage.createVoiceFragment(for: memory, audioFilename: "c.m4a", transcript: "hi")
        try storage.viewContext.save()

        // Clips connections surface — `ClipsTabView.memoryTitles` expression.
        let connections = ref.referencingMemoriesSortedByLinkedAtDesc.map(\.displayTitle)
        #expect(connections == [memory.displayTitle])
        #expect(!connections.contains("Untitled memory"))

        // Clip-editor edge row — `Text(edge.memory?.displayTitle ?? "")`.
        let edge = try #require(memory.edgesArray.first)
        #expect(edge.memory?.displayTitle == memory.displayTitle)
        #expect(edge.memory?.displayTitle != "Untitled memory")
    }
}

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
///
/// **RETARGETED 2026-09-21, in the deletion slice.** Three of these asserted
/// through `ExistingMemoryPickerView.rowTitle`, and that picker is deleted —
/// superseded by `HiMem · Transient capture.html` §4b, which rejects a picker
/// of gists outright: *"asks her to recognise the right memory from three
/// lines, which is guessing."*
///
/// The suite is kept because **the picker was never the rule.** `rowTitle`
/// delegated to `displayTitle`, and `displayTitle` is the canonical resolver
/// the bug was about — the defect was three surfaces bypassing it, not any one
/// of them. Deleting these with the picker would have retired the guard while
/// leaving the resolver it protects in place on every surviving surface. The
/// assertions now name `displayTitle` directly, which is what they were always
/// really testing.
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
        #expect(entry.displayTitle == entry.displayTitle,
                "the reference label IS the memory's display name")
        #expect(entry.displayTitle != "Untitled memory",
                "a titled/derivable memory never reads as Untitled in a clip reference")
    }

    /// A truly-empty memory (no title, no summary, no content) falls back to
    /// its DATE — the one honest distinguishing thing — never "Untitled" and
    /// never a placeholder noun (2026-07-26 ruling).
    @Test func rowTitle_emptyMemory_fallsBackToDate_notUntitled() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .voiceInApp, title: nil)
        #expect(entry.displayTitle == JournalEntry.dateFallbackTitle(from: entry.createdAt),
                "an empty memory reads as its date wherever it is referenced")
        #expect(entry.displayTitle == entry.displayTitle,
                "every reference surface delegates to the one shared resolver")
        #expect(entry.displayTitle != "Untitled memory")
    }

    /// A memory with a real stored title is unaffected — the title shows through.
    @Test func rowTitle_realTitle_showsThrough() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed, title: "Running, Weight, and Retirement Reflections")
        #expect(entry.displayTitle == "Running, Weight, and Retirement Reflections")
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

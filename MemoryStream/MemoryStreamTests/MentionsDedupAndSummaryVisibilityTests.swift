import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the two bugs Tom hit 2026-05-18:
///
///   1. **Duplicate mentions accumulating** — the entry showed
///      "Enlist Bob for kielbasa expertise" twice with different
///      colored dots, plus other near-duplicates. Root cause was
///      `ProcessingEngine.entityKey(type:value:)` including the type
///      in the dedup key. Same string, different types → not deduped.
///      Tighten to value-only dedup.
///
///   2. **Accepted summary doesn't render** outside the AI Suggestions
///      card. `pass.summaryText` is read in exactly one place. Memory
///      detail and journal feed never display it. Fix: derived
///      `entry.renderedSummary` returning the owner-rendered summary
///      when the user has accepted it, nil otherwise.
@MainActor
@Suite(.serialized)
struct MentionsDedupAndSummaryVisibilityTests {

    // MARK: - Problem 1 — value-only dedup

    @Test func entityKey_sameValueDifferentType_producesSameKey() {
        let asPerson = ProcessingEngine.entityKey(type: "person", value: "Bob")
        let asProject = ProcessingEngine.entityKey(type: "project", value: "Bob")
        #expect(asPerson == asProject, "Cross-type duplicates must share a dedup key — Bob is Bob regardless of how the model categorized this pass")
    }

    @Test func entityKey_sameValueDifferentCase_producesSameKey() {
        let lower = ProcessingEngine.entityKey(type: "person", value: "sarah")
        let title = ProcessingEngine.entityKey(type: "person", value: "Sarah")
        let padded = ProcessingEngine.entityKey(type: "person", value: "  Sarah  ")
        #expect(lower == title)
        #expect(title == padded)
    }

    @Test func entityKey_differentValues_produceDifferentKeys() {
        let bob = ProcessingEngine.entityKey(type: "person", value: "Bob")
        let bobby = ProcessingEngine.entityKey(type: "person", value: "Bobby")
        #expect(bob != bobby)
    }

    // MARK: - Problem 2 — renderedSummary visibility

    private func makePassWithSummary(
        in storage: StorageService,
        for entry: JournalEntry,
        summary: String,
        accepted: Bool
    ) throws -> OrganizePass {
        let pass = OrganizePass(context: storage.viewContext)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = Date()
        pass.summaryText = summary
        pass.entry = entry
        if accepted {
            pass.markRowAccepted(.summary)
        }
        try storage.viewContext.save()
        return pass
    }

    @Test func renderedSummary_returnsOwnerRenderedTextWhenAccepted() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        _ = try makePassWithSummary(
            in: storage,
            for: entry,
            summary: "<User> is exploring sausage standardization.",
            accepted: true
        )

        let rendered = entry.renderedSummary
        #expect(rendered == "You are exploring sausage standardization.")
    }

    @Test func renderedSummary_nilWhenSummaryNotAccepted() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        _ = try makePassWithSummary(
            in: storage,
            for: entry,
            summary: "<User> is exploring HiMem.",
            accepted: false
        )

        #expect(entry.renderedSummary == nil)
    }

    @Test func renderedSummary_nilWhenNoPass() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        #expect(entry.renderedSummary == nil)
    }

    @Test func renderedSummary_nilWhenPassHasNoSummaryText() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        let pass = OrganizePass(context: storage.viewContext)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = Date()
        pass.entry = entry
        pass.markRowAccepted(.summary)
        try storage.viewContext.save()

        #expect(entry.renderedSummary == nil)
    }

    @Test func renderedSummary_usesMostRecentPass() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        // Older pass — accepted, but should be shadowed by the newer one.
        let older = OrganizePass(context: storage.viewContext)
        older.id = UUID()
        older.entryId = entry.id
        older.createdAt = Date(timeIntervalSinceReferenceDate: 0)
        older.summaryText = "<User> stale summary."
        older.entry = entry
        older.markRowAccepted(.summary)
        // Newer pass — accepted with fresh text.
        let newer = OrganizePass(context: storage.viewContext)
        newer.id = UUID()
        newer.entryId = entry.id
        newer.createdAt = Date(timeIntervalSinceReferenceDate: 1000)
        newer.summaryText = "<User> fresh summary."
        newer.entry = entry
        newer.markRowAccepted(.summary)
        try storage.viewContext.save()

        #expect(entry.renderedSummary == "You fresh summary.")
    }
}

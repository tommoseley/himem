import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for `SummaryFieldMigration` — the launch-time backfill
/// that copies the accepted AI summary from `OrganizePass.summaryText`
/// to the new `JournalEntry.summary` field (Tom 2026-06-09 unified
/// editing model).
///
/// The migration's load-bearing rules:
/// 1. **Idempotent.** Re-running on a backfilled entry is a no-op
///    (the predicate filters out non-nil `summary`).
/// 2. **Doesn't set `summaryUserEdited`.** The backfill is the AI's
///    accepted text, not a user edit — leaving the marker false is
///    what preserves the auto-pass-no-clobber semantic post-migration.
/// 3. **Only backfills accepted summaries.** An OrganizePass that
///    exists but whose summary row wasn't accepted (or is empty) is
///    left untouched; the user gets nil → render-time fallback to the
///    old computed path until they actually organize.
@MainActor
@Suite(.serialized)
struct SummaryFieldMigrationTests {

    @Test func backfill_copiesAcceptedSummaryToEntry() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "Met with Sarah.", inputType: .typed)
        let pass = OrganizePass(context: storage.viewContext)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.entry = entry
        pass.createdAt = Date()
        pass.summaryText = "You met with Sarah about the garden."
        pass.acceptedRowsJSON = #"["summary"]"#
        try storage.viewContext.save()

        #expect(entry.summary == nil, "pre-migration entry should not have summary set")

        SummaryFieldMigration.runIfNeeded(in: storage.viewContext, force: true)

        #expect(entry.summary == "You met with Sarah about the garden.")
        #expect(entry.summaryUserEdited == false,
                "backfill must NOT mark the row as user-edited — that would defeat the auto-pass-no-clobber rule")
    }

    @Test func backfill_skipsEntriesWithoutAcceptedSummary() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "Pure note.", inputType: .typed)
        // A pass exists but its summary row was never accepted.
        let pass = OrganizePass(context: storage.viewContext)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.entry = entry
        pass.createdAt = Date()
        pass.summaryText = "You wrote a pure note."
        pass.acceptedRowsJSON = #"[]"#
        try storage.viewContext.save()

        SummaryFieldMigration.runIfNeeded(in: storage.viewContext, force: true)

        #expect(entry.summary == nil,
                "an unaccepted pass must not silently overwrite summary at migration time")
    }

    @Test func backfill_skipsEntriesAlreadyMigrated() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "Sarah", inputType: .typed)
        // Already has a summary (could be user-edited; could be from
        // a previous migration run).
        entry.summary = "User's own wording — do not touch."
        entry.summaryUserEdited = true
        let pass = OrganizePass(context: storage.viewContext)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.entry = entry
        pass.createdAt = Date()
        pass.summaryText = "AI wording."
        pass.acceptedRowsJSON = #"["summary"]"#
        try storage.viewContext.save()

        SummaryFieldMigration.runIfNeeded(in: storage.viewContext, force: true)

        #expect(entry.summary == "User's own wording — do not touch.",
                "the predicate must keep migrated/edited rows out of the walk")
        #expect(entry.summaryUserEdited == true,
                "the marker must not be cleared by the migration")
    }

    @Test func backfill_doesNothingForEntryWithNoPass() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "Never organized.", inputType: .typed)

        SummaryFieldMigration.runIfNeeded(in: storage.viewContext, force: true)

        #expect(entry.summary == nil,
                "never-organized entry has nothing to backfill from")
        #expect(entry.summaryUserEdited == false)
    }

    @Test func backfill_isIdempotent() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "Test.", inputType: .typed)
        let pass = OrganizePass(context: storage.viewContext)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.entry = entry
        pass.createdAt = Date()
        pass.summaryText = "AI summary."
        pass.acceptedRowsJSON = #"["summary"]"#
        try storage.viewContext.save()

        SummaryFieldMigration.runIfNeeded(in: storage.viewContext, force: true)
        let firstResult = entry.summary
        SummaryFieldMigration.runIfNeeded(in: storage.viewContext, force: true)
        let secondResult = entry.summary

        #expect(firstResult == secondResult)
        #expect(firstResult == "AI summary.")
    }
}

import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the dismiss-discard lifecycle change (spec §8 reversal,
/// 2026-07-24): X on the review/reorganize sheet discards the uncommitted draft
/// and returns the memory to its last committed state — never a "Draft
/// organized" strand. Covers both cases + the caveat (orphaned summary must not
/// survive an unorganized memory).
@Suite(.serialized)
struct ReorganizeDismissDiscardTests {

    @MainActor
    private func makeEntry(_ storage: StorageService) throws -> JournalEntry {
        try storage.createEntry(content: "the memory content", inputType: .typed)
    }

    @MainActor
    private func addPass(to entry: JournalEntry, committed: Bool, createdAt: Date, in ctx: NSManagedObjectContext) -> OrganizePass {
        let pass = OrganizePass(context: ctx)
        pass.id = UUID()
        pass.entryId = entry.id
        pass.createdAt = createdAt
        pass.summaryText = committed ? "committed summary" : "draft summary"
        pass.suggestedTitle = committed ? "Committed Title" : "Draft Title"
        pass.dismissedAt = committed ? Date() : nil
        pass.entry = entry
        return pass
    }

    @MainActor
    private func addInferenceSummary(to entry: JournalEntry, in ctx: NSManagedObjectContext) {
        let inf = InferenceSummary(context: ctx)
        inf.id = UUID()
        inf.entryId = entry.id
        inf.summaryText = "an AI summary of the memory"
        inf.createdAt = Date()
        inf.entry = entry
    }

    /// Case 1 — a prior committed pass exists (Reorganize then X): discarding
    /// the draft resurfaces the committed pass; the memory reads Organized and
    /// keeps its InferenceSummary.
    @MainActor
    @Test func case1_reorganizeDismiss_restoresPriorCommittedPass() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let entry = try makeEntry(storage)
        let committed = addPass(to: entry, committed: true, createdAt: Date(timeIntervalSinceReferenceDate: 100), in: ctx)
        let draft = addPass(to: entry, committed: false, createdAt: Date(timeIntervalSinceReferenceDate: 200), in: ctx)
        addInferenceSummary(to: entry, in: ctx)
        try ctx.save()
        #expect(entry.latestOrganizePass?.id == draft.id)  // draft is on top before discard

        EntryLifecycleService.discardDraftPass(draft, in: ctx)

        #expect(entry.latestOrganizePass?.id == committed.id)  // prior committed restored
        #expect(entry.inferenceSummary != nil)                 // summary belongs to it — kept
    }

    /// Case 2 — first draft, never committed, X'd: discarding the only pass
    /// returns the memory to unorganized AND removes the orphaned
    /// InferenceSummary (the caveat: no "unorganized but shows a summary").
    @MainActor
    @Test func case2_initialDismiss_returnsToUnorganized_andDropsOrphanSummary() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext
        let entry = try makeEntry(storage)
        let draft = addPass(to: entry, committed: false, createdAt: Date(timeIntervalSinceReferenceDate: 100), in: ctx)
        addInferenceSummary(to: entry, in: ctx)
        try ctx.save()
        #expect(entry.latestOrganizePass?.id == draft.id)
        #expect(entry.inferenceSummary != nil)

        EntryLifecycleService.discardDraftPass(draft, in: ctx)

        #expect(entry.latestOrganizePass == nil)   // unorganized → Organize CTA
        #expect(entry.inferenceSummary == nil)      // orphan summary gone — no contradiction
    }
}

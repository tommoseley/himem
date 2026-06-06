import Testing
import Foundation
import CoreData
@testable import HiMem

/// Integration tests for the Reorganize per-field commit contract
/// from `AI Organize · spec.md` §8.0 (June 6 2026). Exercises
/// `OrganizePass.commitReorganize(on:titleChoice:summaryChoice:previousSummary:)`
/// directly with every combination of per-field choices, plus the
/// chip-state transition (`isReviewed: false → true`) that the user
/// observes after tapping "Keep this version."
///
/// Live UI wiring (the OrganizeMemorySection callback, the
/// `capturedCurrentSummary` snapshot) is exercised manually on device;
/// the pure value-shuffle is what's pinned here.
@MainActor
@Suite(.serialized)
struct ReorganizeCommitTests {

    /// Builds an entry with an Organized pass, then a *second* (new)
    /// pass that represents the AI's freshly-rolled draft awaiting
    /// review. Mirrors the state immediately after
    /// `ProcessingEngine.processReorganize` lands.
    private func makeEntryWithReorganizedPass(
        storage: StorageService,
        currentTitle: String,
        currentSummary: String,
        newTitle: String,
        newSummary: String
    ) throws -> (JournalEntry, OrganizePass) {
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        entry.title = currentTitle
        entry.titleSourcedFromAI = false

        // First pass — the prior "Organized" pass, already reviewed.
        let firstPass = OrganizePass(context: storage.viewContext)
        firstPass.id = UUID()
        firstPass.entryId = entry.id
        firstPass.createdAt = Date(timeIntervalSinceNow: -60)
        firstPass.suggestedTitle = currentTitle
        firstPass.summaryText = currentSummary
        firstPass.dismissedAt = Date(timeIntervalSinceNow: -50)
        firstPass.markRowsAccepted([.title, .summary])
        firstPass.entry = entry

        // Second pass — the "new draft" from reorganize. Not reviewed.
        let newPass = OrganizePass(context: storage.viewContext)
        newPass.id = UUID()
        newPass.entryId = entry.id
        newPass.createdAt = Date()
        newPass.suggestedTitle = newTitle
        newPass.summaryText = newSummary
        newPass.dismissedAt = nil
        newPass.entry = entry

        try storage.viewContext.save()
        return (entry, newPass)
    }

    // MARK: - All four choice combinations

    @Test func commitReorganize_keepCurrent_keepCurrent_preservesEverything() throws {
        let storage = StorageService(inMemory: true)
        let (entry, newPass) = try makeEntryWithReorganizedPass(
            storage: storage,
            currentTitle: "Cur Title",
            currentSummary: "Cur Summary",
            newTitle: "New AI Title",
            newSummary: "New AI Summary"
        )

        #expect(newPass.isReviewed == false)

        newPass.commitReorganize(
            on: entry,
            titleChoice: .current,
            summaryChoice: .current,
            previousSummary: "Cur Summary"
        )

        // Entry title unchanged.
        #expect(entry.title == "Cur Title")
        #expect(entry.titleSourcedFromAI == false)
        // Pass overwritten to reflect the choice — no v1/v2 branching.
        #expect(newPass.suggestedTitle == "Cur Title")
        #expect(newPass.summaryText == "Cur Summary")
        // Chip flips to "Organized" — pass is reviewed.
        #expect(newPass.isReviewed == true)
        #expect(newPass.dismissedAt != nil)
    }

    @Test func commitReorganize_acceptNewTitle_keepCurrentSummary() throws {
        let storage = StorageService(inMemory: true)
        let (entry, newPass) = try makeEntryWithReorganizedPass(
            storage: storage,
            currentTitle: "Cur Title",
            currentSummary: "Cur Summary",
            newTitle: "New AI Title",
            newSummary: "New AI Summary"
        )

        newPass.commitReorganize(
            on: entry,
            titleChoice: .new,
            summaryChoice: .current,
            previousSummary: "Cur Summary"
        )

        // Title updated on the entry; AI provenance recorded.
        #expect(entry.title == "New AI Title")
        #expect(entry.titleSourcedFromAI == true)
        // Pass's title still the new (the user accepted it).
        #expect(newPass.suggestedTitle == "New AI Title")
        // Pass's summary reverted to the previous.
        #expect(newPass.summaryText == "Cur Summary")
        #expect(newPass.isReviewed == true)
    }

    @Test func commitReorganize_keepCurrentTitle_acceptNewSummary() throws {
        let storage = StorageService(inMemory: true)
        let (entry, newPass) = try makeEntryWithReorganizedPass(
            storage: storage,
            currentTitle: "Cur Title",
            currentSummary: "Cur Summary",
            newTitle: "New AI Title",
            newSummary: "New AI Summary"
        )

        newPass.commitReorganize(
            on: entry,
            titleChoice: .current,
            summaryChoice: .new,
            previousSummary: "Cur Summary"
        )

        // Entry title unchanged.
        #expect(entry.title == "Cur Title")
        // Pass title overwritten to reflect the choice.
        #expect(newPass.suggestedTitle == "Cur Title")
        // Pass summary keeps the new AI value (user accepted it).
        #expect(newPass.summaryText == "New AI Summary")
        #expect(newPass.isReviewed == true)
    }

    @Test func commitReorganize_acceptNewTitle_acceptNewSummary() throws {
        let storage = StorageService(inMemory: true)
        let (entry, newPass) = try makeEntryWithReorganizedPass(
            storage: storage,
            currentTitle: "Cur Title",
            currentSummary: "Cur Summary",
            newTitle: "New AI Title",
            newSummary: "New AI Summary"
        )

        newPass.commitReorganize(
            on: entry,
            titleChoice: .new,
            summaryChoice: .new,
            previousSummary: "Cur Summary"
        )

        // Both fields accept the new AI version.
        #expect(entry.title == "New AI Title")
        #expect(entry.titleSourcedFromAI == true)
        #expect(newPass.suggestedTitle == "New AI Title")
        #expect(newPass.summaryText == "New AI Summary")
        #expect(newPass.isReviewed == true)
    }

    // MARK: - Chip-state transition

    @Test func commitReorganize_flipsIsReviewedTrueRegardlessOfChoices() throws {
        let storage = StorageService(inMemory: true)

        // Three runs, one per non-trivial choice combination, all
        // starting from `isReviewed: false`. After commit, every one
        // must read `isReviewed: true` — the chip flip is independent
        // of which fields the user kept.
        for (titleChoice, summaryChoice) in [
            (ReorgFieldChoice.current, ReorgFieldChoice.current),
            (.new, .current),
            (.current, .new),
            (.new, .new)
        ] as [(ReorgFieldChoice, ReorgFieldChoice)] {
            let (entry, newPass) = try makeEntryWithReorganizedPass(
                storage: storage,
                currentTitle: "T\(titleChoice)",
                currentSummary: "S\(summaryChoice)",
                newTitle: "NT\(titleChoice)",
                newSummary: "NS\(summaryChoice)"
            )
            #expect(newPass.isReviewed == false)
            newPass.commitReorganize(
                on: entry,
                titleChoice: titleChoice,
                summaryChoice: summaryChoice,
                previousSummary: "S\(summaryChoice)"
            )
            #expect(newPass.isReviewed == true, "isReviewed must flip true for (\(titleChoice), \(summaryChoice))")
        }
    }

    // MARK: - Edge cases

    /// If the AI produced an empty title and the user "accepts new,"
    /// we don't blow away the entry's existing title with empty string —
    /// the AI proposal is treated as "nothing to offer here."
    @Test func commitReorganize_acceptNewTitle_emptyNewLeavesEntryTitleAlone() throws {
        let storage = StorageService(inMemory: true)
        let (entry, newPass) = try makeEntryWithReorganizedPass(
            storage: storage,
            currentTitle: "Cur Title",
            currentSummary: "Cur Summary",
            newTitle: "",
            newSummary: "New AI Summary"
        )

        newPass.commitReorganize(
            on: entry,
            titleChoice: .new,
            summaryChoice: .new,
            previousSummary: "Cur Summary"
        )

        // Entry title preserved despite "accept new."
        #expect(entry.title == "Cur Title")
        // titleSourcedFromAI NOT set since no real value crossed over.
        #expect(entry.titleSourcedFromAI == false)
    }
}

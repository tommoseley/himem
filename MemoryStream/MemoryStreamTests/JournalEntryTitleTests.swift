import Testing
import Foundation
import CoreData
@testable import MemoryStream

/// Tests for `JournalEntry.derivedTitle(from:)` — the content-derived fallback
/// that fires when the AI didn't return a title and we want something better
/// than the static "Hands-free capture" placeholder on the card.
@MainActor
@Suite(.serialized)
struct JournalEntryTitleTests {

    // MARK: - End-to-end via displayTitle on a real JournalEntry

    @Test func displayTitle_usesDerivedFallback_whenTitleNilButContentSet() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .voiceInApp)
        entry.content = "Well this is better can you hear me interesting with the clock only runs when I'm speaking"
        try storage.viewContext.save()

        // No AI title — should fall back to derived from content, NOT to
        // the static "Hands-free capture" placeholder.
        #expect(entry.displayTitle != "Hands-free capture")
        #expect(entry.displayTitle.contains("Well this is better"))
    }

    @Test func displayTitle_usesAITitle_whenSet() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "Some content", inputType: .voiceInApp)
        entry.title = "AI generated title"
        try storage.viewContext.save()

        #expect(entry.displayTitle == "AI generated title")
    }

    @Test func displayTitle_usesPlaceholder_whenContentEmpty() throws {
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .voiceInApp)
        try storage.viewContext.save()

        // No content, no title → placeholder fallback per input type.
        #expect(entry.displayTitle == "Hands-free capture")
    }

    @Test func displayTitle_prefersInferenceSummary_overContent() throws {
        // Mirrors the user's actual on-device case:
        //   - entry.title nil (AI didn't return a title)
        //   - entry.content is the user's transcript ("As an interesting quote…")
        //   - InferenceSummary attached with descriptive third-person text
        // Expected: title derived from the inference summary, NOT a quote
        // of the content.
        let storage = StorageService(inMemory: true)
        let entry = try storage.createEntry(content: "", inputType: .voiceInApp)
        entry.content = "As an interesting quote that was on the screen year notice where you notice"

        let inference = InferenceSummary(context: storage.viewContext)
        inference.id = UUID()
        inference.entryId = entry.id
        inference.summaryText = "This entry appears to be a fragment or incomplete thought about a quote or notice, but lacks sufficient clear information to extract actionable entities."
        inference.createdAt = Date()
        inference.entry = entry
        try storage.viewContext.save()

        // Title should be derived from "This entry appears…" (the inference),
        // not "As an interesting quote…" (the user's words).
        #expect(entry.displayTitle.hasPrefix("This entry appears"))
        #expect(!entry.displayTitle.contains("As an interesting"))
    }

    // MARK: - derivedTitle (pure-string)


    @Test func emptyContent_returnsNil() {
        #expect(JournalEntry.derivedTitle(from: "") == nil)
        #expect(JournalEntry.derivedTitle(from: "   \n   ") == nil)
    }

    @Test func shortSingleSentence_returnedAsIs() {
        let title = JournalEntry.derivedTitle(from: "Mulch bed three.")
        #expect(title == "Mulch bed three")
    }

    @Test func multipleSentences_takesFirstOnly() {
        let content = "The tomatoes are early. The peppers are late. Cherry plants flowering."
        #expect(JournalEntry.derivedTitle(from: content) == "The tomatoes are early")
    }

    @Test func longSingleSentence_capsAtTenWords() {
        let content = "Today I noticed several different kinds of insects visiting the basil flowers in bed five"
        let title = JournalEntry.derivedTitle(from: content)
        #expect(title?.hasSuffix("…") == true)
        let words = title?.dropLast().split(separator: " ").count ?? 0
        #expect(words == 10)
    }

    @Test func multilineContent_stopsAtFirstNewline() {
        let content = "Garden update\nMore details on the next line."
        #expect(JournalEntry.derivedTitle(from: content) == "Garden update")
    }

    @Test func leadingTrailingWhitespace_trimmed() {
        let content = "   Quiet morning thought.   "
        #expect(JournalEntry.derivedTitle(from: content) == "Quiet morning thought")
    }

    @Test func questionMark_treatedAsTerminator() {
        let content = "What's blooming today? A few things."
        #expect(JournalEntry.derivedTitle(from: content) == "What's blooming today")
    }

    @Test func exclamation_treatedAsTerminator() {
        let content = "First flower! On the cherry tomato."
        #expect(JournalEntry.derivedTitle(from: content) == "First flower")
    }
}

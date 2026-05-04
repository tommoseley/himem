import Testing
import Foundation
@testable import MemoryStream

/// Tests for `JournalEntry.derivedTitle(from:)` — the content-derived fallback
/// that fires when the AI didn't return a title and we want something better
/// than the static "Hands-free capture" placeholder on the card.
struct JournalEntryTitleTests {

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

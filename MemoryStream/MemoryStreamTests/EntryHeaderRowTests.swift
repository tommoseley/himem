import Testing
import Foundation
@testable import MemoryStream

/// Tests for EntryHeaderRow.fitting — the truncation ladder applied to the
/// inline location string on max-density cards. Behavior is doc-commented:
/// drop trailing comma segments until the result fits, never mid-token "…".
struct EntryHeaderRowTests {

    @Test func fitting_shortString_returnedUnchanged() {
        #expect(EntryHeaderRow.fitting("Columbus Circle") == "Columbus Circle")
    }

    @Test func fitting_28CharString_returnedUnchanged() {
        let s = String(repeating: "a", count: 28)
        #expect(EntryHeaderRow.fitting(s) == s)
    }

    @Test func fitting_dropsTrailingSegmentToFit() {
        // "18 Columbus Cir, Bluffton, SC" = 29 chars, over budget.
        // Drop "SC" → "18 Columbus Cir, Bluffton" = 25 chars, fits.
        #expect(EntryHeaderRow.fitting("18 Columbus Cir, Bluffton, SC") == "18 Columbus Cir, Bluffton")
    }

    @Test func fitting_dropsMultipleTrailingSegments() {
        // "Time Warner Center, New York City, NY" = 37 chars
        // Drop "NY" → "Time Warner Center, New York City" = 33 chars, still over.
        // Drop "New York City" → "Time Warner Center" = 18 chars, fits.
        #expect(EntryHeaderRow.fitting("Time Warner Center, New York City, NY") == "Time Warner Center")
    }

    @Test func fitting_singleLongSegment_returnedAsIs() {
        // No comma to drop on; SwiftUI does the visual truncation.
        let long = "ThisIsAnUnreasonablyLongSinglePlaceNameWithNoSeparators"
        #expect(EntryHeaderRow.fitting(long) == long)
    }

    @Test func fitting_emptyString_returnsEmpty() {
        #expect(EntryHeaderRow.fitting("") == "")
    }

    @Test func fitting_customMaxChars() {
        // With a tighter budget of 10 chars, "Hello, World" (12) → "Hello" (5).
        #expect(EntryHeaderRow.fitting("Hello, World", maxChars: 10) == "Hello")
    }

    @Test func fitting_neverEndsWithCommaOrEllipsis() {
        // Critical contract — the design rule is "never trailing comma+ellipsis".
        let result = EntryHeaderRow.fitting("18 Columbus Cir, Bluffton, SC, USA")
        #expect(!result.hasSuffix(","))
        #expect(!result.contains("…"))
    }
}

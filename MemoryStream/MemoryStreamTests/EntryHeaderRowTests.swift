import Testing
import Foundation
@testable import HiMem

/// Tests for PlaceName.fitting — the truncation ladder applied to the
/// inline location string on the memory card. Behavior is doc-commented:
/// drop trailing comma segments until the result fits, never mid-token "…".
///
/// (Previously named for `EntryHeaderRow.fitting`; the helper was moved
/// to `PlaceName` when the EntryHeaderRow wrapper struct was retired with
/// the Memories list redesign — see docs/design/Memories list · spec.md.)
struct PlaceNameTests {

    @Test func fitting_shortString_returnedUnchanged() {
        #expect(PlaceName.fitting("Columbus Circle") == "Columbus Circle")
    }

    @Test func fitting_28CharString_returnedUnchanged() {
        let s = String(repeating: "a", count: 28)
        #expect(PlaceName.fitting(s) == s)
    }

    @Test func fitting_dropsTrailingSegmentToFit() {
        // "18 Columbus Cir, Bluffton, SC" = 29 chars, over budget.
        // Drop "SC" → "18 Columbus Cir, Bluffton" = 25 chars, fits.
        #expect(PlaceName.fitting("18 Columbus Cir, Bluffton, SC") == "18 Columbus Cir, Bluffton")
    }

    @Test func fitting_dropsMultipleTrailingSegments() {
        // "Time Warner Center, New York City, NY" = 37 chars
        // Drop "NY" → "Time Warner Center, New York City" = 33 chars, still over.
        // Drop "New York City" → "Time Warner Center" = 18 chars, fits.
        #expect(PlaceName.fitting("Time Warner Center, New York City, NY") == "Time Warner Center")
    }

    @Test func fitting_singleLongSegment_returnedAsIs() {
        // No comma to drop on; SwiftUI does the visual truncation.
        let long = "ThisIsAnUnreasonablyLongSinglePlaceNameWithNoSeparators"
        #expect(PlaceName.fitting(long) == long)
    }

    @Test func fitting_emptyString_returnsEmpty() {
        #expect(PlaceName.fitting("") == "")
    }

    @Test func fitting_customMaxChars() {
        // With a tighter budget of 10 chars, "Hello, World" (12) → "Hello" (5).
        #expect(PlaceName.fitting("Hello, World", maxChars: 10) == "Hello")
    }

    @Test func fitting_neverEndsWithCommaOrEllipsis() {
        // Critical contract — the design rule is "never trailing comma+ellipsis".
        let result = PlaceName.fitting("18 Columbus Cir, Bluffton, SC, USA")
        #expect(!result.hasSuffix(","))
        #expect(!result.contains("…"))
    }
}

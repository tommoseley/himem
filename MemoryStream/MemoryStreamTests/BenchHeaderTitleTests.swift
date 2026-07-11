import Testing
import Foundation
@testable import HiMem

/// Money tests for `BenchHeaderTitleBuilder` — the pure title formatter
/// for the Clips bench section header (currently rendered by
/// `SessionListView.headerTitle`).
///
/// Per `CLAUDE.md` §Phone (July 10 2026, line 142 corollary): the
/// bench is no longer Watch-only. Phone Clips-FAB captures land as
/// InboxClips too, so the header must be **source-agnostic** —
/// **"N new clips," never "N from your Watch."** Source lives per-clip
/// as a Watch/phone glyph on the card, never as the headline.
@Suite(.serialized)
struct BenchHeaderTitleTests {

    @Test func singular_one_clip() {
        #expect(BenchHeaderTitleBuilder.title(clipCount: 1) == "1 new clip")
    }

    @Test func plural_multiple_clips() {
        #expect(BenchHeaderTitleBuilder.title(clipCount: 3) == "3 new clips")
    }

    @Test func plural_zero_clips() {
        // Zero uses plural "clips" — parallel to iOS system idiom
        // ("0 photos"), and the header is only rendered when the bench
        // is non-empty anyway, so this branch is a defensive default.
        #expect(BenchHeaderTitleBuilder.title(clipCount: 0) == "0 new clips")
    }

    /// The word "Watch" must never appear in the headline vocabulary —
    /// per July 10 lock, source is per-clip metadata, never headline.
    @Test func title_never_names_a_source() {
        for n in 0...10 {
            let title = BenchHeaderTitleBuilder.title(clipCount: n)
            #expect(!title.lowercased().contains("watch"),
                    "title should not name a source: \(title)")
            #expect(!title.lowercased().contains("phone"),
                    "title should not name a source: \(title)")
            #expect(!title.lowercased().contains("from your"),
                    "retired copy: \(title)")
        }
    }
}

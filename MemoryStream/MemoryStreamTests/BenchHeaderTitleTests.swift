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
/// **"N clips," never "N from your Watch."** Source lives per-clip
/// as a Watch/phone glyph on the card, never as the headline.
///
/// **These pin the literal string DELIBERATELY, and that is the exception
/// rather than the rule** (`CLAUDE.md` § Assert the Meaning, Not the
/// Phrasing). Here the copy *is* the subject: the label is a locked
/// decision, so a failure means "the ruled label changed" and needs a
/// ruling, not a reflexive update.
///
/// **Updated 2026-08-10 with C2 step 2b-ii-c2: the adjective drops.** Tom
/// ruled "N clips", not "N new clips" — **"new" was doing work the lens
/// already does.** A session appears in the New view *because* it contains
/// something unseen, so the view's presence is the claim. Under F37 the
/// count means *items in admitted sessions*, reviewed members included, so
/// the old adjective would have described a subset of the number beside it —
/// the Honest-Label fault F35 named, one layer along.
///
/// **The promise did not move; the wording did.** What these tests guard is
/// unchanged: one clip reads singular, many read plural, zero reads plural,
/// and the headline never names a source.
@Suite(.serialized)
struct BenchHeaderTitleTests {

    @Test func singular_one_clip() {
        #expect(BenchHeaderTitleBuilder.title(clipCount: 1) == "1 clip")
    }

    @Test func plural_multiple_clips() {
        #expect(BenchHeaderTitleBuilder.title(clipCount: 3) == "3 clips")
    }

    @Test func plural_zero_clips() {
        // Zero uses plural "clips" — parallel to iOS system idiom
        // ("0 photos"), and the header is only rendered when the bench
        // is non-empty anyway, so this branch is a defensive default.
        #expect(BenchHeaderTitleBuilder.title(clipCount: 0) == "0 clips")
    }

    /// The retired adjective must not creep back in. Pinned as its own
    /// assertion so a failure names *which* promise broke — the label ruling
    /// or the source-agnostic one — rather than reporting only that a string
    /// changed.
    @Test func title_does_not_call_the_count_new() {
        for n in 0...10 {
            #expect(!BenchHeaderTitleBuilder.title(clipCount: n).contains("new"),
                    """
                    "new" is back in the header. It duplicates what the lens already says, \
                    and under F37 the count includes reviewed members of admitted sessions, \
                    so the adjective would describe a subset of its own number.
                    """)
        }
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

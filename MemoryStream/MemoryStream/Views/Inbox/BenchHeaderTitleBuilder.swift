import Foundation

/// Pure formatter for the Clips bench section header title.
///
/// Per `CLAUDE.md` §Phone (July 10 2026, line 142 corollary): the
/// bench is no longer Watch-only. Phone Clips-FAB captures land as
/// InboxClips too, so the header must be **source-agnostic** —
/// **"N new clips," never "N from your Watch."** Source lives per-clip
/// as a Watch/phone glyph on the card, never as the headline.
///
/// Extracted as a pure function so the copy contract is unit-tested
/// (`BenchHeaderTitleTests`) without instantiating any view.
enum BenchHeaderTitleBuilder {
    static func title(clipCount: Int) -> String {
        clipCount == 1 ? "1 new clip" : "\(clipCount) new clips"
    }
}

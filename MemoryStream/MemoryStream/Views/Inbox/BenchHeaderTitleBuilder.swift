import Foundation

/// Pure formatter for the Clips bench section header title.
///
/// Per `CLAUDE.md` §Phone (July 10 2026, line 142 corollary): the
/// bench is no longer Watch-only. Phone Clips-FAB captures land as
/// InboxClips too, so the header must be **source-agnostic** —
/// **"N clips," never "N from your Watch."** Source lives per-clip
/// as a Watch/phone glyph on the card, never as the headline.
///
/// **The adjective drops — "N clips," not "N new clips"** (ruled by Tom,
/// 2026-08-10, with F37).
///
/// *Why:* **"new" was doing work the lens already does.** A session appears
/// in the New view *because* it contains something unseen, so the view's
/// presence is the claim and the header need not repeat it. Under F37 the
/// count means *items in admitted sessions* — the full contents of everything
/// drawn, reviewed members included — and calling those "new" would be the
/// Honest-Label fault F35 named, one layer along: the word would describe a
/// subset of the number beside it.
///
/// Two alternatives were rejected in the same ruling. Counting *sessions*
/// instead makes clips invisible when the clip is the unit she is actually
/// shaping. Admitting only wholly-new sessions was the worst of the three: it
/// reintroduces a filtered count, and it would hide a session from her because
/// she had glanced at one clip inside it.
///
/// Extracted as a pure function so the copy contract is unit-tested
/// (`BenchHeaderTitleTests`) without instantiating any view.
enum BenchHeaderTitleBuilder {
    static func title(clipCount: Int) -> String {
        clipCount == 1 ? "1 clip" : "\(clipCount) clips"
    }
}

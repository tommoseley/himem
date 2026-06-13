# Memory Detail · long-memory navigation

**Status:** Locked June 9 2026. Built on `Himem · Memory Detail.html` (§ "Long memory · Full ⇄ Compact"); implemented in `screens-memory-detail.jsx`.

## The problem

A long recording produces a long memory. A 25-minute lecture transcribes to **14 clips · 3,581 words · ~11 pages**. Reading is fine; *finding* a moment in that wall is painful, and opening the memory face-plants the user into pages of transcript before they reach Mentions or the Organized card.

The transcript is **derived content** — per Crucible it must never demote the primary media (audio) or the at-a-glance summary. So the fix is to make the transcript *navigable*, not to let it dominate the surface.

## The rule (one sentence)

**Any memory with more than one clip shows a Full / Compact toggle on its transcript section header; memory size picks only the default mode.**

### Showing the toggle — no magic
- **> 1 clip → show the header + toggle.** An index is meaningful exactly when there's more than one thing to index.
- **1 clip → no toggle.** Nothing to navigate; render the single clip.
- There is **no word-count gate on *whether* the control appears.** (This replaced an earlier "earned past 1,500 words" rule — deleted as needless magic.)

### Default mode — size-driven
- **Larger memories open compressed (Compact).** `> 6 clips` **or** `> 1,500 words` → opens in the Compact index. A long lecture lands as a scannable table of contents, never an 11-page wall.
- **Smaller multi-clip memories open Full.** A 2–3 clip memory in Compact would be a pointless near-empty index; show it expanded.
- Helpers: `transcriptOpensCompact(count, words)` and `defaultTranscriptMode(count, words)` in `screens-memory-detail.jsx` are the single source of truth.
- **Persist the user's last explicit choice** so someone who always wants Full isn't re-collapsing every time. (Behavior note for the build; the canvas mock doesn't persist.)

## The two modes

### Full
Continuous clip cards, top to bottom — the read-straight-through view. Each card carries its date · time · location header (unchanged from base Memory Detail).

### Compact
One **row per clip**: `time · first line · chevron`. The 14-page transcript becomes a 14-row index you scan in roughly one screen.

- **Each row is a single-open accordion expander.** Tap a row → its full transcript drops in **in place**, below the row. Opening another row closes the previous one, so the index never explodes into a wall.
- **The lead line is a collapsed-state preview only — never duplicate it.** Collapsed, the row shows `media-icon · time · first-line-of-transcript · chevron`. **Expanded, the header collapses to `media-icon · time · chevron` (no lead text)** and the full transcript renders below. The first sentence must appear **once**: as the lead when collapsed, as the start of the body when expanded — never both at once. (Build bug seen June 9: the expanded row showed the first sentence as a bold lead *and* again as the opening of the full transcript.)
- **Each compact row carries a leading media-type icon.** A small glyph on the leading edge tells the user *what kind* of clip each entry is without opening it — mic (voice, the default), camera (photo), video, or note. A photo clip in the index reads as a photo at a glance; without the icon the index hides media type behind identical-looking rows. Open state is signalled by the **rotated chevron + ochre time/lead** — *not* a box or border around the content. (An earlier ochre-bordered "anchored clip" highlight was removed: a box reads as an error/selection signal the color vocabulary doesn't support.)
- **A Compact row is still a clip.** It keeps the same swipe actions as a full clip card — trailing red **Trash** (delete the clip → Recently Deleted), leading ochre **Edit**. The compact treatment changes how a clip *reads*, never what it *is* or what you can *do* to it. (See `HiMem · Buttons & Actions.html`.)

## The toggle control

- Lives on the **transcript section header**, not the top nav toolbar — it governs only the transcript, and keeps the nav cluster (trash / folder / share / edit) uncluttered.
- Two conventional density glyphs in a small segmented control: **text-lines = Full**, **stacked-rows-with-dots = Compact**.
- Eyebrow beside it states the scale honestly: `Transcript · 14 clips · 3,581 words`.

## Scope / deliberately out

- **Search-within-memory** was discussed and **deferred** — not built. When it returns, it works in either mode (highlight + jump) and rides on the transcript header alongside the toggle.
- The toggle governs the transcript only. Title, summary, topics, mentions, and the Organized card are never affected by it.

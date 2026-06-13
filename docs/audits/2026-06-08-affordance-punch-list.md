# Affordance punch list (refreshed against locked standards) — 2026-06-08

The standards are now locked in `docs/design/HiMem · Buttons & Actions.html`
and `docs/design/CLAUDE.md` (the "Button & action colour code" rule).
Most of the items that were CD-ambiguous in the first pass are now
resolved. This refresh drops the resolved items into concrete fixes
and shrinks the open-question list dramatically.

## What the locked standard says, in one paragraph

**Colour follows form, not meaning.** Ochre = a button (press to act).
Blue = an inline link, or an AI status signal. Red = destruction
(swipe actions only). **All real buttons are ochre** — there is no
AI-vs-user color split on buttons; that was inside baseball.

**Button ranks (all ochre):**
- **Primary** — filled ochre, full-width, ≥50px. One per surface. The commit.
- **Secondary** — hairline-bordered ochre, full-width, sits under primary. The alternative.
- **Tertiary** — bordered ochre pill inline; **filled** only when it's the sole action of its card.

**Bare-text actions live only in the nav/sheet top bar.** `Cancel` plain ink2 left; `Done`/`Save` ochre right. Anywhere else, a tappable text-link is **blue**.

**Destruction is a red full-height swipe rectangle.** Two flavors:
- **Trash** — destroys the thing (memory/clip → Recently Deleted).
- **Recycle** — unlinks (memory/item survives, returns to the pool).
- Both red. Glyph + label carry the difference. Edit swipe = ochre + pencil, leading edge.
- **Never a floating circle. Never a peer button in a row.**

**AI status (Draft organized, sparkle, Summary eyebrow)** stays AI-blue but as a **quiet label, never a button**. The implied action it suggests (e.g. *Review draft*) is a separate ochre button.

---

## A · Things I just shipped that are now wrong

These three landed yesterday and need to flip to match the locked color code.

### A1 — Review draft button: AI-blue → ochre
**File:** `Views/Pricing/OrganizeMemorySection.swift:185` (`reviewDraftButton`)
**Current.** Full-width filled **AI-blue** with sparkle glyph + "Review draft" in white.
**Fix.** Full-width filled **ochre** (`Crucible.Color.accent`) with the sparkle glyph + "Review draft" in white. Sparkle stays — it's still an honest AI status indicator beside the action label.
**~5 min.**

### A2 — Reorganize button: AI-blue bordered → ochre bordered
**File:** `Views/Pricing/OrganizeMemorySection.swift:179` (`reorganizeButton`)
**Current.** Bordered AI-blue with arrow + "Reorganize" in AI-blue.
**Fix.** Bordered ochre (`Crucible.Color.accent`) with arrow + "Reorganize" in ochre. ≥44pt tall stays.
**~5 min.**

### A3 — Project Find-the-thread "Run": AI-blue → ochre
**File:** `Views/Projects/ProjectDetailView.swift:401` (Find-the-thread card)
**Current.** Compact filled AI-blue "Run" button.
**Fix.** Compact filled **ochre** "Run" button. Per Section 1 Rank-3, a tertiary button is filled when it's the sole action of its card — which Run is. Same shape, ochre color.
**~5 min.**

---

## B · ReorganizeReviewSheet (the "A fresh take" sheet)

The whole reorganize sheet has multiple violations the standards now resolve.

### B1 — Header "Draft organized" inline pill: dashed AI-blue → quiet label
**File:** `Views/Pricing/ReorganizeReviewSheet.swift:271–295`
**Current.** Inline-rendered dashed AI-blue pill with sparkle + "Draft organized" text. The exact shape the June 8 lock retired.
**Fix.** Replace inline render with the shared `OrganizedChip` quiet label (sparkle + AI-blue text, no border, no pill). Same fix the Memory-Detail cluster already got yesterday.
**~10 min.**

### B2 — Per-field "Current · kept" / "New suggestion · tap to use": checkmark + colored borders → selection ring only
**File:** `Views/Pricing/ReorganizeReviewSheet.swift` (per-field row blocks)
**Current.**
- "Current · kept" row: orange checkmark glyph + bold orange text + orange-bordered card.
- "New suggestion · tap to use" row: AI-blue open-ring glyph + AI-blue text + hairline-bordered card.

Mixes selection signals (the orange checkmark) with the actual selection ring (the row border).

**Fix.** Apply the locked **selection = ring** rule exactly:
- Each row's whole card is the tap target.
- **Selected** row: solid ochre 1.5pt border (selection ring); ochre eyebrow text on top.
- **Unselected** row: hairline-only border; ink2 eyebrow text on top.
- **No checkmark on either row.** Selection is the ring, end.
- The eyebrow copy stays as today ("Current · kept" / "New suggestion · tap to use").

**~25 min.** Touches both the title and summary field rows.

### B3 — "Reorganize again" cream-sunk button: → bordered ochre secondary
**File:** `Views/Pricing/ReorganizeReviewSheet.swift:138`
**Current.** Full-width cream/sunk background, no visible border, plain text. Barely a button.
**Fix.** Full-width **hairline-bordered ochre** (Rank 2 secondary). Sits directly under the primary "Keep this version" button. Same height as primary (≥50pt).
**~5 min.**

### B4 — "Keep this version" — already correct
**File:** `Views/Pricing/ReorganizeReviewSheet.swift:120`
Filled ochre full-width primary. ✓

---

## C · The delete vocabulary sweep

The locked standard names two destructive swipe semantics:
**Trash** (destroys → Recently Deleted) and **Recycle** (unlinks, item survives). Both **red** full-height swipe rectangles. Floating circles and grey "Remove" pills are retired.

| File:line | Current | Fix |
|---|---|---|
| `Views/Journal/JournalView.swift:316` | "Remove" + `tray.and.arrow.down` + grey tint | **"Trash"** + `trash` + red (memory goes to Recently Deleted) |
| `Views/Journal/ChronologicalCaptureStream.swift:54` (voice clip) | "Delete" + `trash` + red | **"Trash"** + `trash` + red (label-only change) |
| `Views/Journal/ChronologicalCaptureStream.swift:70` (note) | "Delete" + `trash` + red | **"Trash"** + `trash` + red |
| `Views/Journal/ChronologicalCaptureStream.swift:86` (media) | "Delete" + `trash` + red | **"Trash"** + `trash` + red |
| `Views/Inbox/SessionListView.swift:357` | "Discard session" + `trash` | **"Trash"** + `trash` + red (a session-trash is still a trash; one verb) |
| `Views/Projects/ProjectListView.swift:63` | "Delete" + `trash` + red | **"Trash"** + `trash` + red (the project goes away) |
| `Views/Projects/ProjectDetailView.swift:183` | "Remove from Project" + `minus.circle` + red **rectangle** | **"Recycle"** + recycle glyph (`arrow.triangle.2.circlepath`) + red (the memory survives in the pool) |

**Total: ~25 min** across the seven swipe sites.

**Note on iOS swipe rendering.** SwiftUI's `.swipeActions(allowsFullSwipe:)` renders as a full-height rectangle when fully revealed and as a circle when partially revealed. The "floating circle" shape in the screenshots is the partial-swipe state, not a code shape we'd need to override. As long as labels/glyphs/colors are right, the visual matches the standard once a user pulls the row open.

---

## D · Mentions chips — drop the person-icon variant

**File:** `Views/Journal/EntryExpandedView.swift:659–680`
**Current.** Person-type entities render with a `person.fill` glyph + name in an orange-tint wash pill. Other entity types render with a leading colored dot.
**Fix.** Drop the `person.fill` variant. All mention chips render as solid pill + leading dot, where dot color encodes entity type (person = ochre, place = green, idea/project = AI-blue, per Crucible palette). Per the standards Section 4: managed content = solid pill + leading dot, full stop.
**~15 min.**

---

## E · Sheet "Done" is a `Text`, not a `Button`

`Text("Done")` wrapped in tap zones — no `Button`. Accessibility regression I introduced; should fix.

- `Views/Components/ManageTopicsSheet.swift:99`
- `Views/Components/EditTextSheet.swift:69`
- `Views/Search/VoiceSearchView.swift:86`

**Fix.** Wrap in `Button { … } label: { Text("Done") }` so VoiceOver focuses correctly and announces "button". Visual stays as ochre bold per the nav-bar rule.
**~10 min.**

---

## F · The AudioPlayerSheet "Retry transcription" link colour

**File:** `Views/Components/AudioPlayerSheet.swift:202–223`
**Current.** Ochre (`Crucible.Color.accent`) arrow + "Retry transcription" text. Per the standards' Section 2 mockup, this is exactly the shape of a "blue inline link" — but it's ochre.
**Fix.** Change foreground from `Crucible.Color.accent` to `Crucible.Color.aiBlue`. Match the standards' canonical example exactly: blue, ≥44pt tap target, no border, no pill.
**~3 min.**

---

## G · The big sweep — topic chip unification

**Five different TopicChip implementations** exist:

| File | Component | Used by |
|---|---|---|
| `Views/Components/TopicChip.swift` | `TopicChip` (canonical, 4 states) | DraftReviewSheet, ManageTopicsSheet, EntryExpandedView |
| `Views/Components/TopicTabBar.swift` | inline chips | Memories list top filter bar |
| `Views/Journal/EntryCardView.swift:267` | `EntryCardTopicChip` | Memory cards on Memories list |
| `Views/Search/SearchView.swift:512` | `TopicChipModel` + inline render | Search facets |
| `Views/Inbox/CreateMemoryFromClipsSheet.swift:422` | `newTopicChip` | Bundle sheet |

The standards lock the visual rule (solid pill + leading dot, ≥40pt) but don't dictate a single render path. Today each duplicate has slightly different padding/font/dot size, which means:
- 44pt floor breaks on the smaller variants (the screenshots show memory-card chips around ~24-28pt).
- Visual rhythm changes across surfaces.

**Fix.** Consolidate to a single `TopicChip` component everywhere. Add a `.compact` size variant (28pt visible body + row gap to clear 44pt tap zone) for memory cards and filter bars where the canonical 40pt chip is too tall. Delete the four duplicate implementations.

**~2 hr** — touches 4 files, all small, but needs visual review on each surface.

This is the only remaining "real refactor" item. Everything else is surgical.

---

## H · Smaller calls for CD

These three are the only places I think still need a design decision before I touch them. Everything above is unambiguous given the locked standards.

### H1 — Compact TopicChip minimum visible height
The canonical chip is 38pt. For memory cards / filter bars, that's too tall and crowds the card content. CD's call:
- (a) compact variant at ~28pt visible body + 10pt row gap (total tap zone 38pt; below the strict 44pt floor but the "≥38pt visible with separating gap" allowance in the lock applies)
- (b) compact variant at ~32pt body + 12pt gap (total 44pt — strictly compliant)
- (c) accept the strict 44pt everywhere and adapt the card layout to fit taller chips

My read: **(a) is best for the reflective surfaces** since it preserves card density without violating the rule's spirit. CD to confirm.

### H2 — Memories list "All" filter pill
The "All" pill has no leading dot; sibling filter pills do. Pick:
- (a) Give "All" a neutral dot (ink3 or hairline color).
- (b) Keep "All" dotless — it's a structural pill (scope toggle), not a per-topic filter.

CD to confirm.

### H3 — AI sparkle on ochre action buttons
The standards say AI sparkle is an AI status signal (used in the quiet "Draft organized" label, AI summary eyebrow, etc.). Some action buttons that initiate AI passes — *Review draft*, *Run*, *Reorganize* — currently include the sparkle glyph next to the button label. After the color flip in §A, those buttons are ochre with a sparkle next to text.

Two reads:
- (a) **Keep sparkle on AI-pass action buttons.** The sparkle is just an icon at that point; the button color (ochre) carries the actionable signal; the sparkle is informational.
- (b) **Drop sparkle from action buttons.** Sparkle = AI status only, used on quiet labels. Buttons get a generic action glyph (or no glyph).

My read: **(a) — keep the sparkle on the button**. It's still honest: the action it triggers IS an AI pass. The label "Review draft" + sparkle communicates that without color-coding it. CD to confirm.

---

## I · Already correct — leave alone

- Memory Detail Draft state, post the §A1+A2 color flips: quiet sparkle label + ochre full-width Review draft button + ochre bordered Reorganize button on Organized state. ✓
- Topic chip `.set` (ochre dot, wash1, no border, ≥38pt). ✓
- Topic chip `.new` (sparkle, dashed AI-blue border, "NEW" label) — dashed = provisional, color = AI signal. Both correct. ✓
- Topic chip `.pick` (ochre selection ring, no checkmark) — post slice C. ✓
- `+ Edit` affordance (dashed ochre, ≥38pt). ✓ Per "dashed = add/provisional only".
- The FAB orange capture circle. ✓ Primary action of Today; ochre filled circle.
- DraftReviewSheet bottom buttons (Looks good filled ochre + Edit hairline bordered ochre). ✓
- iOS Picker(.segmented) for Memories/Projects toggle — codified as iOS-native pattern exception (same family as bare-text Cancel/Done in nav top bar). ✓

---

## Estimated total

| Section | Work | Time |
|---|---|---|
| §A | 3 color flips on Memory Detail / Projects | **15 min** |
| §B | Reorganize sheet (header + selection + secondary button) | **40 min** |
| §C | Delete vocabulary sweep across 7 sites | **25 min** |
| §D | Mentions person-icon retirement | **15 min** |
| §E | Sheet Done → Button wrappers | **10 min** |
| §F | Retry transcription color flip | **3 min** |
| §G | Topic chip unification (5 → 1) | **2 hr** |
| §H | CD's calls before implementation | (gate) |

**Without §G: ~1.5 hr of clear quick wins.**
**With §G: ~3.5 hr total.**
**Gated on CD: H1 (compact chip height), H2 (All filter pill), H3 (sparkle on action buttons).**

§A, B, C, D, E, F can all run in parallel — they don't touch the same files. I can do them today if you give the go.

§G should wait for H1's answer. The unification is straightforward once we know the compact height target.

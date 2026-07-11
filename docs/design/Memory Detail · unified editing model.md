# Memory Detail · unified editing model

**Status:** Locked June 9 2026. Built on `Himem · Memory Detail.html` (§ "Unified editing model"); implemented in `screens-memory-detail.jsx`. Supersedes the scattered edit/delete mechanisms (pen button, tap-OR-pen title, +Edit pill, pen-based mentions, pen→✕ memory-delete).

## The problem it replaces

Memory Detail had grown **four gestures for "edit" and three buried paths for "delete"**: title edited via tap *and* pen; topics via a "+ Edit" pill; clips via swipe; mentions via the pen; media *looked* editable but needed a swipe; deleting the whole memory was hidden behind pen → ✕-inside-a-mention-pill. That last one was simply a bug — a memory-level destructive action buried inside an unrelated token control.

The root cause wasn't "too many gestures." It was a **mode problem**: the screen couldn't decide whether it was for consuming or managing, at the same time.

## The content hierarchy (the realization)

```
Memory
├─ Title          ← text
├─ Summary        ← text
├─ Transcript     ← text  ← the working object
├─ Topics         ← metadata
├─ Mentions       ← metadata
└─ Media evidence ← audio/photo/video
```

Audio landed at the **bottom** — not because it's unimportant, but because it's **evidence**. The transcript is what the user actually reads, fixes, and searches. (Validated by the only user to date: *"I edit when the transcript makes an error. That's it. I never listen to the audio."*) This is the flip that resolves the old "tap = play vs tap = edit" ambiguity.

## The model — one rule per category

| Category | Items | Interaction |
|---|---|---|
| **Text** | Title, Summary, **Transcript** | **Tap to edit in place.** |
| **Media** | Photo, Video, Audio | **Tap to consume** (photo opens, video/audio play). **Every clip that has an original recording shows a quiet "Original recording · m:ss" play control beneath its transcript — always, in read state, not just on tap.** This is the load-bearing reason tapping transcript text can mean *edit* (Play is its own visible control). |
| **Deletion** | Clip, memory, project | **Open the item, scroll past all content, full-width Delete button at the bottom.** No swipe, no confirm dialog — opening + scrolling *is* the deliberation; Recently Deleted (30 days) is the safety net. |
| **Relocation** | Clip | **"Where does this belong?"** from the clip's edit state — move to another memory, pull into a new memory, or **"Remove from this memory"** (= move to the Captured Clips bench; the clip survives). Same placement primitive and wording as the workbench (`Kingfisher Language.md`). *survives*). Parallel to a project's Remove-from-project. Distinct from Delete clip (which destroys). |
| **The memory itself** | — | The same bottom Delete button — no toolbar trash, no list-row swipe. |
| **Metadata** | Topics | **Tap any chip → topic management sheet.** Dashed **+ Add** to add. |
| | Mentions | **Lightweight inline** manage. Dashed **+ Add** to add. |

### Media presence is mandatory, not decorative (pinned June 10 2026)

**Every clip with an available original recording renders its play control in the read state — unconditionally.** The control is not revealed on tap, not gated behind a menu, not optional. It is the visible *Play* affordance that makes the whole "tap text = edit" model unambiguous; without it, the surface loses the one signal that distinguishes consume from edit.

- **Read state:** each clip card / expanded compact row shows `▷ Original recording · m:ss` beneath its transcript.
- **Edit state:** the same control stays put (criterion 8) — you replay while fixing the text.
- **Only condition for absence:** the clip genuinely has no recording (e.g. a typed note). Text-only clips show no play control; every voice clip does.
- (Build bug seen June 10: the play control was missing from **all** clips, in both read and edit — not just during edit. The control had been dropped entirely rather than conditionally hidden.)

**No pen button. No persistent edit mode.** You edit one thing and return to viewing — the Draft Review philosophy (a focused task, not a mode you can get trapped in). Editing is unambiguous because Play is its own control: tapping transcript text always means *edit*.

### Why no edit mode
95% of the time the user is reading, not editing. A persistent mode imposes a constant "am I viewing or editing?" tax and the occasional trap in the wrong one. Direct manipulation avoids both.

### Discoverability
No pen, no visible "Edit" affordance on text. We **trust the consistency** — the same single rule (tap text → edit) across title, summary, and transcript means it's learned once. One tap reveals the keyboard; users adapt fast. (The rule's uniformity *is* the discoverability.)

## Moving clips between memories (locked July 5 2026)

Dogfood surfaced the need: a clip lands in the wrong memory (mis-clustered by Sort, or the user reconsiders), and they need to move it — or at least get it *out* without destroying it.

**One primitive, because a clip always lives somewhere.** A clip is either inside a memory or loose on the Captured Clips bench. So a single placement action — the sheet titled **"Where does this belong?"** (the same question the workbench asks a loose clip; one primitive, one wording per `Kingfisher Language.md`) — covers every case:

- **Move to another memory** — pick from recent/searched memories; the clip leaves this memory and joins that one.
- **New memory** — pull the clip out on its own.
- **Remove from this memory** — the plain-language name for *move to Captured Clips*. The clip returns to the bench, unfiled, and **survives**. This is the direct answer to "at the very least, remove a clip from a memory."

**This is the clip-level analog of Projects' Delete vs Remove-from-project** — the same "unlinks; the thing survives" pattern, one level down. Delete clip *destroys* (→ Recently Deleted); "Where does this belong?" *relocates* (the clip lives on).ove *relocates* (the clip lives on).

- **Where it lives:** the clip's **edit state**, beside Delete clip — not in the calm read view (consistent with clip-delete placement). The edit-state bottom is **two rows**: a *clip-fate management row* — **Delete clip** (destroy) and **Where does this belong?** (relocate/remove) — above the *text commit row* (Cancel / Done). Four actions never share one line (44px floor).ement row* (`🗑 Delete clip` · `↪ Move to…`) above the *text-edit commit row* (`Cancel` · `✓ Done`). Four actions never share one line — they'd fail the 44px touch floor. *(This evolves the earlier single `Delete clip … Cancel Done` bar; the management actions split onto their own row.)*
- **Staleness reuses the existing mechanism.** Moving a clip *out* changes this memory's content; moving one *in* changes the destination's. **Both memories go stale and offer Reorganize** — identical to new clips arriving. No new concept.
- **Empty memory after the last clip leaves (decision a):** moving out a memory's final clip offers to **delete the now-empty memory** ("Nothing left in this memory — delete it?", recoverable via Recently Deleted). *Keep it empty* is the quiet secondary. No orphaned empty memories by accident, but the user can keep a shell they've titled.
- **Reuses the existing "add clips to a memory" path** (the Captured Clips bundle flow already targets new *or* existing memories). Move is that same reassignment, initiated from the clip instead of the bench.

*Specimen: `Himem · Memory Detail.html` § "Moving clips between memories" → `clip-move-sheet` + `clip-empty-after-move`.*

## Committing an edit (accept / cancel) — by weight

The commit model **scales with how much an edit can change**, so a person never wonders "does this one have a Cancel?":

| Edit | Enter | Accept & leave | Cancel | Remove |
|---|---|---|---|---|
| **Title, Summary, Clip transcript** | tap the text | **Done** (ochre, anchored below the field) | **Cancel** (plain ink, beside Done) — discards changes, exits | Clip transcript's edit state carries a **clip-fate row** above the commit row: **Delete clip** (destroy) and **Move to…** (relocate/remove). Title/summary aren't removable. |
| **Edit Project (sheet)** | tap title/goal | **Save** (nav, ochre) | **Cancel** (nav) | — |
| **Mention chip (inline)** | tap the chip | Return or tap-away (commit-on-exit) | none — commit-on-exit is the accept; re-tap to fix | tap ✕, or clear + tap-away |

**The rule:** anything that opens a full editing context — title, summary, and especially a **clip transcript** (you might rewrite a paragraph) — gets an explicit **Cancel / Done** pair **anchored directly below the field being edited** (not in the nav — the commit lives on the control, where the eye is). *Cancel discards the in-progress changes and returns to view; Done (ochre, with a check glyph) commits and returns to view.* Tap-away on these is **not** an implicit commit (too easy to lose a paragraph by mis-tapping). Only the **inline mention chip** uses commit-on-exit, because a token is trivially reversible. (The `edit-active` artboard shows the transcript case: the field with a bottom `Cancel  ✓ Done` bar; the nav stays in its normal view state.)

*Done is **ochre**, never a green check — green is reserved for confirmed-status, and ochre is the "you act" color. Cancel is plain ink, never a red ✕ — red means destruction (a swipe), and cancelling an edit destroys nothing.*

### Editing a clip transcript — exact layout behavior (pinned June 9 2026)

The principles above were too loose: a build can honor "tap to edit" and "Cancel/Done below the field" and still produce overlapping chrome. These are the **non-negotiable layout rules** for the active edit state, so nothing floats over anything:

1. **The edit field expands *in flow* and pushes siblings.** The tapped clip grows to fit the editable text; the clips above and below **move**, they are never overlapped. The edit field must never be a floating/absolute layer on top of other rows. (Build bug seen June 9: the edit box overlapped the clip bubble above it.)
2. **The Cancel / Done bar is a real row beneath the field**, reserving its own height in the layout — it pushes the next clip down. It is **never** a floating bar laid over the following row. (Build bug seen June 9: the bar floated over the next clip "So maintaining a landfill…".)
3. **The FAB hides during any active text edit.** Title, summary, or transcript editing → the + is gone until the edit commits or cancels. It must never sit over the text being edited. (Build bug seen June 9: the FAB covered the caret line.) The mock enforces this (`{!editingClip && <MDFAB/>}`).
4. **On edit-begin, scroll the edited field fully above the keyboard** — the entire field plus its Cancel/Done bar must be visible above the keyboard, with the caret line never under the keyboard. Standard keyboard-avoidance; the field is the scroll anchor.
5. **In Compact mode, editing happens on the expanded row, but expand/collapse is NEVER disabled.** A row must be expanded (its full transcript visible) before its body is editable. The chevron stays live during edit: **collapsing the edited row, or opening another row, commits the in-progress edit (Done semantics) and then collapses/switches** — it never discards (only the explicit **Cancel** button discards), and the expander is **never** disabled. (Build bug seen June 10: the expander was locked during edit, so opening another row collapsed the editor and left a dead control that couldn't re-expand. A disabled expander is the trap; commit-then-switch is the fix.)
6. **One edit at a time.** Entering an edit on any field commits/closes any other open field first (per rule 5, the prior edit commits, not discards). There is never more than one active editor on the screen.
7. **The edit field shows the *entire* value and mirrors the read view's metrics.** The active field renders at the **same font size, line-height, weight, and width** as the displayed text, and **auto-grows to fit the whole transcript** — a 6-line clip edits in a 6-line field. It is **never** a shorter fixed-height box the user must scroll inside, and the text is never rendered smaller in edit than in read. (Build bug seen June 9: the edit box was a small single-line-ish field while the displayed clip was many lines, so most of the text was hidden/scrolled.)
8. **The media play control is present in read AND edit — for every voice clip.** If a clip has an original recording, its quiet "Original recording · m:ss" play control renders in the read state **and** stays visible during edit (replaying the audio is precisely what the user does *while* fixing a transcript). It is not tap-to-reveal and not edit-only. Absent only when the clip truly has no recording. (Build bug seen June 10: the play control was missing from every clip in both states — dropped entirely, not just hidden during edit.)

These eight are testable acceptance criteria — a build that overlaps any two of {edit field, adjacent clips, Cancel/Done bar, FAB}, **shrinks/clips the editable text below its read-view size**, **disables the expander mid-edit**, or **hides the play control while editing**, is wrong regardless of how the colors look.

## Locked decisions inside the model

- **Summary is editable** (tap to edit), like all text. The earlier "AI writes it, user only accepts/rejects" framing doesn't earn an exception.
- **Editing does NOT revert "Organized" → "Draft organized."** *"Organized"* means *the AI draft was reviewed and accepted* — not *frozen forever*. Fixing "Anthropic" → "Anthropic Claude" is an improvement, not an un-organizing. Kicking the user back to Draft would be punitive. If edit history is ever needed, track an **"Edited"** marker separately from the AI state — never conflate them.
- **Topics keep their management sheet.** Topics aren't just chips — they carry palette discipline, find-or-create against the global topic table, fragmentation control. That complexity justifies the sheet (`ManageTopicsSheet`). The only change: the entry gesture is now **"tap any chip,"** not a dedicated "+ Edit" pill.
- **Mentions stay lightweight inline** — simpler tokens, no canonicalization story, so they don't need a sheet.

## Interaction with the Full ⇄ Compact transcript toggle

In **Compact**, a row has two hit-zones and they must stay distinct:
- **Tap time / chevron → toggle expand/collapse** (navigation).
- **Tap the transcript body when expanded → edit** (consistent with tap-to-edit text everywhere).

**The build must not let the expanded body re-trigger expand/collapse.** Clip deletion follows a different placement than memory/project deletion: **a clip has no Delete in its view state.** Delete clip appears **only while editing the transcript**, as a red text+icon affordance on the **left** of the bottom commit row (`Delete clip` … `Cancel` `Done`). Rationale: a clip lives inside a memory, so its delete shouldn't sit in the always-visible flow competing with the memory-level Delete; surfacing it only in edit mode keeps the read view calm and still gives a deliberate, scroll-to-it path.

## What gets deleted

The pen button; the leading ochre **Edit swipe** (tap-to-edit replaces it); **every swipe-to-delete** (the bottom Delete button replaces it, June 12 2026); the toolbar trash; the "+ Edit" pill as the topic entry point; pen-based mention editing; and the pen→✕-in-pill memory-delete.

## Applies to every surface, not just Memory Detail

The five rules are app-wide. How they land per surface:

| Surface | Text (tap to edit) | Consume | Delete / remove | Notes |
|---|---|---|---|---|
| **Memory Detail** | title, summary, transcript | media (audio demoted) | clip → bottom **Delete clip** (in expanded clip); memory → bottom **Delete memory** | canonical |
| **Today / Home** | — (browsing surface) | tap a memory card → open | open the memory → bottom **Delete memory** (no list-row swipe) | no edit or delete affordances on the list; both happen in detail |
| **Projects · Detail** | tap **title / goal** → Edit Project sheet | tap a memory card → open | project → bottom **Delete project**; member memory → bottom **Remove from project** (memory survives) | nav is back · add-memory · share — **no pen, no trash** |
| **Projects · Edit sheet** | Name, Goal (real fields, ochre focus) | — | — | topics are **derived, read-only** (not edited here); Cancel / Save nav |
| **Captured Clips** | clip transcript (inbox *or* bundled) | — | open the session → bottom **Delete session**; open a clip → bottom **Delete clip** | operational surface; the **session** is the primary unit — tapping a session card opens it |

The invariants that must hold everywhere: **no pen button; no persistent edit mode; tap text to edit; tap media to consume; open an item and use the full-width Delete button at its bottom to destroy it (red, no swipe, no confirm); the object's own delete lives at the bottom of the object, never in a toolbar or a list-row swipe; metadata managed inline or via a sheet, never via a pen.**

## Implementation details (pinned June 9 2026)

Two gaps the rules above leave open, resolved so iOS can build without guessing.

### 1 · Where an edited summary lives, and how Reorganize treats it

- **One canonical `summary` working value on the entry.** **Field home: add `summary` + `summaryUserEdited` to `JournalEntry`** (not `InferenceSummary`) — cleaner joins, one fewer table for the index-v2 thesis. `InferenceSummary.summaryText` keeps the AI *draft* only; on accept it's copied into `JournalEntry.summary`. A user edit writes to that same `summary` field **and sets `summaryUserEdited`** (separate from the AI/review state — editing never reverts Organized → Draft).
- **AI never silently overwrites a user-edited field.** This is the whole point of the marker. A Reorganize (or a Plus automatic pass) **proposes** a new summary; it does not replace `summary` directly.
- **The load-bearing case is the *automatic* one.** A Plus auto-organize **must not swap `summary` when `summaryUserEdited == true`** — it proposes (surfaces a draft to review), never clobbers. (Manual Reorganize is already safe because it routes through the approval review below; this rule is what protects the user's fix on the silent auto-pass path that a future tier feature might add.)
- **Reorganize reconciles through the existing review, not a clobber.** Per the reorganize spec, both new values require explicit approval and the review **defaults to the current value**. A user-edited summary is simply that current value — so the user's fix is what's kept unless they deliberately adopt the new wording. No separate `userEditedSummary` field is needed; the marker + the approval step are sufficient.

### 2 · What "lightweight inline" means for mentions

A new Crucible pattern — **managed chip · edit state** (mentions only; topics keep their sheet):

- **Rest:** a solid pill + leading dot (managed content).
- **Tap → edit state:** the chip's label becomes an **inline text field** sized to its content (caret, ochre — user action), and a **trailing ✕** appears *within the chip* to remove it.
- **Commit on return or tap-away** (rename); **tap ✕** removes the mention. No sheet, no popover, no separate screen.
- **Accept & leave edit mode = Return (keyboard) or tap-away.** Either commits the rename and returns the chip to rest. There is **no Cancel button and no Done button** on an inline chip — the commit-on-exit model *is* the accept, because the edit is one tiny token and trivially reversible (re-tap to fix). This is deliberate: explicit **Cancel / Done** chrome belongs only to the heavier text edits (title, summary, transcript) and sheets (Edit Project), where a person can change a lot and wants an explicit out. The commit model scales with the edit's weight — inline token = commit-on-exit; full field/sheet = Cancel/Done.
- **Empty-commit = remove.** If the user clears the label to empty and taps away, treat it as a removal (matches the ✕ semantic and how chip systems conventionally behave) — never persist an empty mention.
- **The ✕ needs an expanded hit zone.** The visible ✕ is ~22px; the *tappable* region must clear the touch floor — give the ✕ a transparent overlay covering the chip's trailing portion (SwiftUI `.contentShape(Rectangle())` + zone-mapped handler), so tapping the right end of the chip hits remove and the rest hits rename. The chip's `minHeight: 40` covers the vertical.
- One tap, two unambiguous targets: the **label** (rename) and the **✕** (remove). This is the only place a ✕-on-a-chip is allowed — and only in the active edit state, never at rest (a chip at rest must never look like it carries a delete affordance).

*Specimen: `Himem · Memory Detail.html` § "Unified editing model" → `mention-edit` artboard (resting + active + multi-chip wrap). Drawn June 9 2026 — iOS can wire against it.*

### 3 · Captured Clips inbox clips edit the same way

A clip's transcript is **tap-to-edit whether it's in the inbox (pre-bundle) or inside a bundled memory** — same rule, same gesture. The watch-sync inbox must not grow its own editing pattern.

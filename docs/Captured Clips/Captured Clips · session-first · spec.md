# Captured Clips · session-first · spec

Operational surface. May 2026. Locked for v1.

> **v2 of this spec, May 19 2026.** The earlier version described a session-detail screen with multi-select rings, a sliding bottom action bar, and "Bundle as memory" verbs. Building that produced screens we hated. This rewrite kills the drill-in screen, kills clip-level multi-select, and renames the action everywhere. If older code or design references contradict this doc, this doc wins.

## Why this exists

The shipping Captured Clips screen showed every clip as a card with its own selection ring, check, and play button. Nine clips across three sessions meant nine rings before the user saw nine clips — chrome out-shouting content. Worse, it put everyone in granular-management mode by default when most users, most of the time, want one thing: turn this batch into a Memory.

The conceptual climb: the unit on Captured Clips is the **session**, not the clip. Sessions are proto-Memories. Clips are sub-components of sessions, exposed only when the user opts in. The screen should make sessions primary and bury clip-level tools as exception handling **inside the same card**, not on a separate screen.

This is also where the **operational vs reflective** principle gets cashed: Memory surfaces are rooms the user lives in (reflective — Source Serif, cream paper, audio-as-hero); capture surfaces are workflows the user moves through (operational — SF Pro, denser grids, throughput-optimized). Bringing the gallery aesthetic to the workshop floor was making the workshop floor harder to use.

## What it is, in one line

Captured Clips shows ad-hoc clips grouped into sessions. Each session is one card with a single primary verb: **Make a Memory**. One tap and the session becomes a Memory. Clip-level triage lives inside the card, accessed by tapping the body — never on a separate screen.

## Model

- **A *clip* is one audio file.** Today: produced exclusively by the watch.
- **A *session* is a deterministic grouping of clips** by time + location, plus the `rollGroupId` from On a roll (a UUID stamped at recording start, preserved across Next taps).
- **Sessions are proto-Memories.** A session, on confirm, becomes a Memory. The session ID is retired; the Memory carries the audio segments forward.
- **One session = one Memory, normally.** Manual split / merge is post-MVP. The default mapping is 1:1.
- **A single-clip session is still a session.** Same card shape. No regression to per-clip UI for N=1.
- **Accidental clips** (no speech detected, sub-2-second clips, palm-muted) are flagged at sync time and **auto-excluded from the bundle.** The card surfaces the exclusion count as a quiet line ("1 clip auto-excluded · no speech"). The user can include an excluded clip back from the expanded card view. They can also exclude a "good" clip the same way.
- **No AI in the grouping itself.** Grouping is deterministic. AI helps with the title on bundle (existing rule, unchanged).

## Two capture paradigms (background — see CLAUDE.md)

HiMem has two capture modes. **Structured** = user intentionally creates a Memory (phone direct-voice, append, iPad). **Ad-hoc** = user catches fragments to sort later (today: watch). Captured Clips exists to consolidate ad-hoc captures into Memories. Structured captures bypass this surface entirely — they go straight to Memory Box.

## Surfaces

| Surface | What's there |
|---|---|
| Today header banner | "X new from Apple Watch" pinned banner when inbox count > 0. (Existing.) |
| **Captured Clips · session list** | The only top-level Captured Clips surface. Each session is one card. Cards expand in place. **No drill-in screen.** |
| Bundle confirm sheet | The seam: operational hands off to reflective. AI-suggested title in Source Serif AI blue, topic chip, optional project chip. Same sheet as existing New-memory flow. |
| Settings → Captured Clips | Top-level row, `N pending`. Never buried. (Existing.) |

**Deleted from the previous spec:** session-detail drill-in screen, clip-list drill-in screen, bottom action bar with N-selected indicator. None of these exist.

## The interaction

### Session list (the only top-level surface)

- **Chrome.** Back `<` left, **"Done"** right. No eyebrow strip. No `✕`. No "Edit" mode.
- **Title block.** "N from your Watch" (SF Pro 22, weight 600 — *not* Source Serif; this is operational). Sub-line: "M sessions · today, 12:17 – 3:36 PM" — pure metadata, no instruction.
- **No helper copy.** No "Tap to select. Swipe to delete." Affordances do their own teaching.
- **Session cards stacked.** Each card carries, top to bottom:
  - **Meta row.** "3:36 PM · 4 clips · 0:12" in SF Pro 12 ink2.
  - **Transcript preview.** A single block of quoted speech, joined with "… " between clips, capped at ~3 lines and ellipsized. Not a list of separate quoted lines.
  - **Auto-exclude note** (when relevant). "1 clip auto-excluded · no speech." Muted ink2. Not a chip, not amber, not a warning — it's a note that we already handled it. Tappable to expand.
  - **Primary action.** `Make a Memory →` as a full-width pill *inside the card*, ochre tinted (cream text on ochre at 100%, OR ochre text on 8% ochre tint — pick the contrast level by hierarchy; on light cards we want the heavy variant). One verb. One tap. This is the action of the card.
- **No play button on the card.** Preview is not a primary list-level affordance — keep the card visually quiet. Playback lives inside the expanded view.
- **Tap the card body** (anywhere except the Make a Memory pill) → **expand in place.** No screen transition. The card grows downward to reveal per-clip rows. Other cards stay where they are.
- **Tap Make a Memory** → bundle confirm sheet directly. The 80% case.
- **Swipe-left on the card** → red `Discard` action slides in. Tapping it expands the action to `Discard N clips?` — a second tap commits. Two-tap because hard delete. No undo toast.
- **Long-press the card** → contextual menu: "Make a Memory," "Discard session," "Cancel." Power-user shortcut; not the primary path.

### Card expand (in place — replaces the session-detail screen)

- **Expand animation.** Card height grows, accordion-style, with the per-clip rows fading in. ~220ms, easeOut.
- **Per-clip rows.** Tabular, dense. Each row:
  - Left: a circular **toggle** (filled = included, empty = excluded). **Never a check glyph.** Selection = ring. Tap to flip.
  - Center: relative offset + duration ("0:00 · 0:03", "+3s · 0:02"), and transcript on the next line.
  - Right: small play glyph (12pt outline, ink2). Tap = inline play; does not navigate.
- **Excluded clip styling.** Empty ring, transcript text at 50% opacity. For auto-excluded clips: italic "No speech detected · likely accidental" in ink2 instead of transcript.
- **Swipe-left on a clip** → red `Delete` action slides in. Hard delete.
- **No multi-select.** No "N selected." No "Bundle N as memory" action that changes copy with selection count. The user toggles inclusion on individual clips as needed; **the card's Make a Memory pill always says the same thing** and always bundles the currently-included clips. If everything is excluded, the pill disables.
- **`Discard session` link** sits inline in the bottom-left of the expanded card's action row — text only, ink2 SF Pro 13, demoted. Paired across from the `Make a Memory` pill. This is the discoverable path for users who don't know the swipe gesture. Tap once → the link swaps to a red `Discard N clips?` confirm; second tap commits. Same two-tap pattern as the swipe action.
- **No bottom action bar.** The primary action is still the card's own pill, which stays anchored to the bottom of the expanded card content.
- **Tap card chrome** (the meta row) → collapse. Or tap another card → that one expands and this one collapses.

### Bundle confirm sheet

(Unchanged from previous spec — reproduced here so this doc is self-contained.)

- **Header**: `Cancel · New memory · Create`.
- **Session summary chip**: ochre-tinted, single line: "3 clips · 3:36 PM · 0:12" with sub-line "1 clip excluded" when relevant.
- **Title field**: AI-suggested title in Source Serif AI blue (`#1E5C8E`) with an `AI` tag. Tap to rewrite — tag disappears once user-authored.
- **Topic field**: Topic suggestion if AI confident; chip-row with `+ New` at the end. (Existing pattern.)
- **Project field** (optional): chip-row with existing projects + `+ New project`.

The bundle sheet is **where voice softens** from operational to reflective. Serif AI-blue title is the first true thing the user sees on this sheet — they're moving from triage into Memory creation.

## Vocabulary (locked)

| Use | Don't use |
|---|---|
| **Make a Memory** (button, every count of clips) | Bundle, Bundle as memory, Save as memory, Create memory |
| **Captured Clips** (chrome name) | Inbox, Pending, Watch queue |
| **N from your Watch** (title copy when N > 0) | Captured clips ready, Pending clips |
| **Auto-excluded** (status word for accidentals) | Accidental, Likely accidental as a primary label, Invalid |
| **Session** (internal noun — appears in long-press menu as "Delete session") | Capture session, Recording, Batch |

The word **Bundle** is retired in user-facing copy. It survives in this spec as engineering shorthand only.

## Color (locked, restated)

- **Ochre `#C64A1C`** is the only chromatic accent on this surface, used on the Make a Memory pill and nothing else at rest. Not on rings. Not on play glyphs. Not on borders.
- **Amber `#B87322`** does **not** appear on this surface in normal state. "Auto-excluded · no speech" is muted ink2, not amber. Amber is reserved for things the user must act on; auto-exclusion is something we *already handled.*
- **AI blue `#1E5C8E`** does not appear on the list. It enters when the bundle sheet opens (suggested title).
- **Confirmed green** is for "Memory created" toast, not for inclusion toggles.

## States

| State | What it looks like |
|---|---|
| **Empty inbox** | "Nothing new from your Watch" title, sub-line "Audio you record on your Apple Watch lands here." No action button. Reached from Settings → Captured Clips even when count = 0. No eyebrow. |
| **Inbox with sessions** | Default session list. |
| **All-excluded session** | Card shows "All clips auto-excluded · no speech" instead of transcript preview. Make a Memory pill is disabled (60% opacity, non-tappable). The `Discard session` link appears on the *collapsed* card here — the only state where it does — because the primary action is dead and the user needs a visible exit. Same two-tap confirm. |
| **Single-clip session** | Same card shape. Meta row reads "3:36 PM · 1 clip · 0:01". Transcript preview is just that one quote. No regression to a different layout for N=1. |
| **Sync in progress** | Card greys to 60% opacity while clips are still uploading. Sub-line "Syncing · N of M". Expand allowed; only already-synced clips show inside. |
| **Stale (no recent capture)** | List shows in reverse-chrono regardless of age. No "old vs new" partitioning in MVP. |

## Discarding sessions

Three paths, ordered by discoverability:

1. **Swipe-left on the card** → red `Discard` slides in. Tap expands to `Discard N clips?`; second tap commits. Native iOS pattern; mirrors per-clip swipe-to-delete inside the expanded card.
2. **`Discard session` link** in the expanded card's action row, bottom-left, demoted text-only across from the ochre pill. Visible exit for users who don't know the gesture. Two-tap confirm.
3. **Long-press the card** → contextual menu with `Discard session`. Power-user shortcut.

The link **does not appear on collapsed cards in normal state** — swipe handles that case, and we don't want every card carrying a visible destructive affordance at rest. The single exception is the all-excluded edge state (see States), where the primary action is dead and the user needs an exit without expanding.

Why not other shapes:

- **Not a corner ✕ on every card.** Adds destructive chrome to every rest state. Same anti-pattern as the original clip-cards.
- **Not a trash icon beside Make a Memory.** Peer destructive action next to primary verb. The exact rule we broke in v1.
- **Not Edit mode + multi-select for discard.** The surface is one-thing-at-a-time. If a user wants to clear everything, they discard sessions one at a time — not a common enough flow to add a mode for.
- **No undo toast.** Two-tap confirm is the safety net. A toast on a triage surface adds chrome the user has to dismiss; the confirm tap is more honest.

## What this is *not*

- **Not a per-clip list at the top level.** Clip-level UI is the *contents of an expanded card*, never its own screen.
- **Not a drill-in flow.** There is no second screen between the inbox and the bundle sheet. If you find yourself drawing one, stop.
- **Not a multi-select surface.** No "N selected," no action bar that changes copy with selection count, no select-all. The user toggles individual clip inclusion; the Make-a-Memory action is always present and always means "bundle the currently-included clips."
- **Not an Edit mode.** No Edit button. Selection chrome (the inclusion ring) is the row's own affordance, always live, never modal.
- **Not a multi-screen drill-in inside the inbox.** No "Session detail" page. No "Clips" page. Card expand replaces both.
- **Not a reflective surface.** No Source Serif on the inbox title. No cream-paper-with-poetic-margins. Operational throughout, until the bundle sheet, where voice softens.
- **Not an AI-organized surface.** Grouping is deterministic. AI assists with the title on bundle. Nothing else.
- **Not a place for amber.** Auto-exclusion isn't a warning. See Color above.

## Bugs the v1 build kept making

These all came back in successive Code passes. Calling them out by name so they stop:

1. **"Bundle" verb survived.** Every list iteration shipped with "Bundle as memory →" somewhere. The verb is mechanical, breaks at N=1, and doesn't match the rest of the app vocabulary. **Use "Make a Memory" everywhere.**
2. **Selection = check, not ring.** Filled ochre checkmark circles for selected clips. Crucible rule (CLAUDE.md): selection is a ring, completion is a check. Inclusion in the bundle is a *selection*; the clip isn't "done." Use rings.
3. **Instructional helper copy.** "Tap to select. Swipe to delete." Banned. If you need to teach the gesture, the affordance is wrong. Make the toggle visible and obvious; let swipe-to-delete teach itself.
4. **Centered eyebrows over left-aligned titles.** Visually disjointed and adds chrome the title already carries. Drop them.
5. **Two dismiss controls.** Back `<` AND `✕` in the same chrome strip. One. Back if you came from somewhere; ✕ if you're in a modal. Captured Clips isn't a modal — back only.
6. **Stripe-checkout-style full-width ochre pill floating at the bottom of an otherwise quiet screen.** The Make-a-Memory action belongs *inside the card*, not docked. A floating dock conflates the screen-level action with the per-session action and reads e-commerce, not reflective-tier.
7. **Play button heavier than the primary action.** A filled triangle in a tinted circle out-weighs an ochre text link. If they're peers, both should be heavy or both should be quiet — but they're not peers. Play is secondary at most; on the list view, it's absent entirely.
8. **Transcripts shown as stacked separate quoted lines.** ("One, two, three." / "One, two, three, four, five." each on its own line.) Reads like a status log. Use a single block of quoted speech with " … " joins. Reads like the thought it was.
9. **Granular-management surface presented as the default.** Pre-checked checkboxes, "3 selected" indicator at the bottom — this puts the user in exception-handling mode on entry. Most users, most times, see a session and bundle it. Granular tools live behind a tap (card expand), not in front.
10. **No visible way to discard.** Hiding discard behind long-press alone is undiscoverable. Discard now has three paths: swipe (native), inline link in expanded card (visible), long-press (shortcut). See Discarding sessions.

## Tier behavior

| Tier | Captured Clips |
|---|---|
| Free | Fully available. Storage cap (50 unsynced clips on watch) is the same ceiling for everyone. |
| Plus / Founders | Same. |
| Studio (post-MVP) | Same. |

Capture and triage are always free. AI on the bundle sheet (title suggestion) costs nothing additional — it's part of the existing memory-AI assist allotment.

## Out of scope for MVP

Deferred — none block shipping:

- Cross-session merge ("bundle these two sessions into one Memory").
- Manual session split ("this clip belongs to a different thought").
- Search within the inbox.
- Bulk delete by criteria (e.g. "delete all auto-excluded from yesterday").
- A separate "Older" partition for clips > 48h unprocessed.
- Photo and video clips on this surface (today the inbox is audio-only).
- Per-clip retry-transcription affordance. (Re-sync the whole session if transcription fails; clip-level retry is post-MVP.)

## Implementation notes

- **Grouping job is unchanged.** Time + location heuristic, plus `rollGroupId` from On a roll as a deterministic override when present.
- **Auto-exclude detection** runs on phone after sync, not on watch. Heuristics: zero speech tokens in transcription, total amplitude below threshold, clip duration < 2s with no detected speech. Recoverable from the expanded card.
- **Session card transcript preview** — a single SF Pro block in ink2 with straight quotes, capped at 3 lines, ~60 chars per joined fragment, ellipsized. **No serif italic for transcripts at this level.** The operational register holds until the bundle sheet.
- **Card expand** is a self-contained accordion within the card. No portal, no sheet, no nav-stack push. State held in component, not in route. Expand state is single-cardinal: at most one card expanded at a time (tapping another card collapses the first).
- **No bottom action bar.** The Make-a-Memory pill is anchored to the bottom *of the card*, not of the screen. Safe-area is the bottom of the scrollview, not a fixed dock.
- **Reuse the existing bundle sheet** — the New-memory composer is already wired. Session-first list just changes how the user gets to it; the bundle flow downstream is identical.
- **The "Done" button** dismisses the screen, returning the user to wherever they came from (Today or Settings). It does not snooze, dismiss notifications, or change clip routing. Clips stay in pending; banner stays on Today next launch. Same as today.

## Related work (not in this spec)

- **AI attribution color sweep** — same task flagged in `Projects · MVP spec.md`. The AI tag and AI-blue title on the bundle sheet should already be AI blue. If shipping iOS code has them in ochre, fix as part of the same sweep.
- **On a roll** — Next-clip behavior on watch creates split clips that group into one session via `rollGroupId`. Session-first list relies on this to keep a roll of 5 clips visible as one card, not five.

## Open questions

- **Hour-bucketing for very long days.** 8 cards across 8 hours is manageable; 20 across 12 hours starts to need day-headers. Default for MVP: no day headers, reverse-chrono only. Revisit if pending-clip counts get large in practice.
- **What's the "share session" affordance?** None in MVP. Sessions don't ship as their own thing; Memories do.
- **Disabled-state copy on Make a Memory.** When all clips are excluded, what does the pill say — "Make a Memory" greyed, or "Nothing to bundle"? Lean toward staying greyed with the normal label, since "Nothing to bundle" uses the retired verb and is more text than the disabled state needs.
- **Discard confirm copy.** `Discard 4 clips?` reads cleanly for N>1 but `Discard 1 clip?` is slightly awkward. Acceptable; the count grounds the action. Alternative `Discard this session?` drops the count but loses the "this is permanent" weight that the number carries. Sticking with the count for now.

## Files

- `Himem · Captured Clips (session-first).html` — design canvas. Update to reflect this v2.
- `Himem · Captured Clips.html` — original Captured Clips design (clip-first). Retained as v0 reference; superseded.
- `screens-captured-clips-sessions.jsx` — primitives. Will need rework for in-card expand.
- `CLAUDE.md` — locked architectural rules: two capture paradigms, the consolidation ladder, operational vs reflective, selection-vs-completion, peer-action demotion.
- This spec is the source of truth for v1. Where this contradicts older designs, this wins.

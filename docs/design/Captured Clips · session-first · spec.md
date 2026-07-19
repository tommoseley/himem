# Captured Clips · session-first · spec

Operational surface. May 2026. Locked for v1.

> **v4, July 8 2026 — this surface is now the `Clips` tab's default view.** "Captured Clips" is no longer a standalone window reached from Settings; it's the **default (New) view of the first-class `Clips` page** (Clips · Memories · Projects). See `HiMem · the shaping model.md` and `HiMem · evidence and context.md`. Two consequences that override older prose below: (1) the **per-card "Make a Memory" pill is retired** — the workbench/Sort model (below) is the resting state, and the vocabulary is intent-language ("Where does this belong?" / "Start a Memory" / "Keep these · N memories") per `Kingfisher Language.md` §Vocabulary; wherever the v2 prose below says "Make a Memory pill inside every card," read it as the retired model. (2) There is **no "Settings → Captured Clips" entry** — the page is a tab. The mechanics (idle-gap grouping, expand-in-place, auto-exclude, day headers, Sort, dedup, set-aside) all stand.

> **v2 of this spec, May 19 2026.** The earlier version described a session-detail screen with multi-select rings, a sliding bottom action bar, and "Bundle as memory" verbs. Building that produced screens we hated. This rewrite kills the drill-in screen, kills clip-level multi-select, and renames the action everywhere. If older code or design references contradict this doc, this doc wins.

> **v3, July 4 2026 — the workbench model + Sort.** After several days of real dogfood use (20 clips across 3 days), the one-card-one-pill session list proved unusable: a wall of ochre, plus a road trip scattered across a dozen single-clip sessions with no way to combine them. This version reframes Captured Clips from a *queue* to a *workbench*, makes **Sort** (AI-proposed groupings) the bench's resting state, and **restores multi-select** as a relational "where does this belong" affordance — explicitly superseding v2's "no multi-select" rule (see *The workbench + Sort* below). v2's session-first mechanics (idle-gap grouping, expand-in-place, auto-exclude) all still stand; v3 is a layer on top, not a replacement. *(The "Make a Memory" verb v2 introduced is retired — see Vocabulary; the mechanic stands, the word doesn't.)*

## Why this exists

The shipping Captured Clips screen showed every clip as a card with its own selection ring, check, and play button. Nine clips across three sessions meant nine rings before the user saw nine clips — chrome out-shouting content. Worse, it put everyone in granular-management mode by default when most users, most of the time, want one thing: turn this batch into a Memory.

The conceptual climb: the unit on Captured Clips is the **session**, not the clip. Sessions are proto-Memories. Clips are sub-components of sessions, exposed only when the user opts in. The screen should make sessions primary and bury clip-level tools as exception handling **inside the same card**, not on a separate screen.

This is also where the **operational vs reflective** principle gets cashed: Memory surfaces are rooms the user lives in (reflective — Source Serif, cream paper, audio-as-hero); capture surfaces are workflows the user moves through (operational — SF Pro, denser grids, throughput-optimized). Bringing the gallery aesthetic to the workshop floor was making the workshop floor harder to use.

## What it is, in one line

Captured Clips shows ad-hoc clips grouped into sessions. Each session is one card with a single primary verb: **Start a Memory**. One tap and the session becomes a Memory — or, opt-in on the bundle sheet, gets appended to an existing one. Clip-level triage lives inside the card, accessed by tapping the body — never on a separate screen.

## Model

- **A *clip* is one captured fragment — media-agnostic (locked July 11 2026).** A clip is *one thing caught*: a voice recording, a photo, or a typed note. **Not audio-only.** (The old "a clip is one audio file, produced exclusively by the watch" definition is retired — it predated the July 9 media-agnostic Clips lock and the source-agnostic FAB. Clips now arrive from the watch *and* the phone, as voice/photo/note.) Each clip carries a capture timestamp and a source glyph (watch/phone); type is per-clip metadata, never a reason to segregate it.
- **A *session* is a deterministic grouping of clips** by an **idle-gap rule** (see *Idle-gap sessioning* below), plus the `rollGroupId` from On a roll (a UUID stamped at recording start, preserved across Next taps) as an override when present. Location is a secondary tiebreaker. **The rule groups by timestamp, not by media type** — a photo and a voice clip two minutes apart are *one sitting*, so they land in one session card together (a mixed "3 clips" card, not a voice card plus a stray photo row).
- **Sessions are proto-Memories.** A session, on confirm, becomes a Memory. The session ID is retired; the Memory carries the audio segments forward.
- **One session = one Memory, normally.** Manual split / merge is post-MVP. The default mapping is 1:1.
- **A single-clip session is still a session.** Same card shape. No regression to per-clip UI for N=1.
- **Accidental clips** (no speech detected, sub-2-second clips, palm-muted) are flagged at sync time and **auto-excluded from the bundle.** The card surfaces the exclusion count as a quiet line ("1 clip auto-excluded · no speech"). The user can include an excluded clip back from the expanded card view. They can also exclude a "good" clip the same way.
- **Deterministic grouping has no AI; *Sort* is the AI layer above it.** The idle-gap rule (below) is a clock, not a classifier. **Sort** (below) is the AI proposal layer that groups across sessions by time+place and word-match (Free/on-device) or semantics (Plus). The two compose: idle-gap forms sessions; Sort proposes which sessions/clips belong to one Memory. Title-on-bundle AI is unchanged.

### Clip lifecycle + the status lens (locked July 18 2026 — supersedes "New = unconnected")

The bench is a **library, not an inbox** — and a library's states are *recently-acquired / available / referenced*, not "old vs. new." A clip has **two orthogonal properties** — a review *state* and a connection *relationship* — and keeping them separate is what makes the model boring (in the good way):

**Axis 1 · Review state (a stored property):**
- **New** — `reviewed == false`. Never opened. Genuine fresh intake. **New means *unseen*, not *unconnected*** — this aligns the New filter with the tab dot (both = unseen arrivals).
- **Reviewed** — `reviewed == true`. **"Opened by you."** The definition is the *act of opening*, nothing about the outcome — you may review a clip and immediately attach it, or review and leave it loose; both are Reviewed.

**Axis 2 · Connection count (derived from the edges):** `0` · `1` · `n`. **Unconnected = `connectionCount == 0`** — covering *never-used ∨ previously-attached-then-deleted ∨ manually-detached*, since all three are simply "0 edges right now."

They combine naturally: *New + 0 memories*, *Reviewed + 0 memories*, *Reviewed + 3 memories*. **"Attached" is not a lifecycle state — it's a relationship** (edge count ≥ 1), so it isn't in the state enum.

**The status lens is `All · New · Unconnected`** (order locked July 19 2026 — **All** is left-most, but **New is the default selection on app entry**; label "Unconnected" over "Loose"/"Available": it names the graph relation `connectionCount==0`, is consistent with the status sheet's "Not yet connected" and "Capture once, connect many," and "Available" is imprecise since every clip is available), and each is one predicate — **New** = `reviewed==false` · **Unconnected** = `connectionCount==0` · **All** = everything. Type axis (Voice/Photos/Video/Notes) is unchanged and independent.

**`reviewed` is a persisted field, not derivable — and per-device, not synced (decided July 18 2026).** *reviewed=true, connections=0* is reachable two different ways — open-then-close, **or** attach-then-delete — and they're indistinguishable from connection history alone, so "has this been opened" **must be stored**. It lives as a **local field on `InboxClip` (manifest) and bench `MediaReference` — no CloudKit deploy** (the V7 batch already shipped). Review state is a noise-reduction signal, not load-bearing, so per-device is honest for v1 (the tab dot already clears locally on open); **cross-device review-sync is out of scope for v1** and is a property of the post-v1 bench→MediaReference unification, solved there once and consistently. Connection count *is* derived (count the edges).

*Why this changed:* deleting a memory returns its clips to the bench (the Let Go lock preserves them), and under the old "New = unconnected" definition those re-appeared as **New** — though they're not new, they're *previously-shaped, now loose*. Dogfood hit ~30 such clips masquerading as New. Splitting the review-state axis from the connection axis makes each honest.

**"Orphaned" is architecture-only.** The store can tell never-used from previously-attached if needed (via edge history / an `everConnected` bit), but the **UI only ever says "Unconnected"** — nobody thinks *"I have 37 orphaned clips,"* they think *"I've got loose stuff I don't need."* Future-proof: because *loose* and *reviewed* are clean primitives, Studio graph queries like "loose clips about gardening" or "reviewed but unattached" are meaningful.

### Unconnected-clip cleanup (locked July 18 2026; label July 19 2026)

- **No cascade, ever.** Deleting a memory/project never destroys its clips (the Let Go lock). They return to the bench as **Unconnected**.
- **Cleanup lives in the Unconnected filter.** Tap **Unconnected** → the zero-connection pile → **multi-select → Delete / Add to a memory** (Photos-style; reuses the Sort multi-select and its single ochre commit). Delete here is clip-deletion (**"Delete this Clip"**, destroys the atom, → Recently Deleted).
- **No branching at deletion time.** Let Go / Delete-project add **no** clip checkbox or modal — the honest sentence ("The clips stay…") is enough. Cleanup is a separate, deliberate act on the bench, not a fork inside a calm deletion flow.
- **The Unconnected count is never a nag.** No badge, no "N to clear." Unconnected is a filter you *choose* to open when you want to tidy — the workbench-not-queue rule still holds.

## Idle-gap sessioning (locked June 30 2026)

**Origin (dogfood, June 30):** a dinner at the CIA produced five separate clips between 6:09 and 6:18 PM — obviously *one sitting* — but each wrist-raise became its own session, so the day shattered into 13 one-clip cards and the consolidation burden landed entirely on the user. That is a perishability failure at the *organizing* end: the thing that is actually one memory (a dinner) arrived as five decisions. This rule makes a session mean *a sitting*, not *a wrist-raise*.

### The automatic rule (no user action)

- **Clips separated by less than the idle threshold belong to the same session; a gap ≥ the threshold closes it. Media type is irrelevant to the boundary — voice, photo, and note clips group together by timestamp** (a photo shot two minutes after a voice clip is the same sitting, and shares the card). Silence is the boundary. The dinner above arrives as **one card, five clips**, with zero effort.
- **Default threshold: 10 minutes of idle.** (Provisional — see open question below; a real dinner has 10–min+ lulls between courses, which the strict rule would wrongly split. This is exactly why the explicit hold-open affordance exists.)
- **`rollGroupId` always overrides.** An On-a-roll roll is one session regardless of gaps — the user already declared it as continuous.
- **Still deterministic, still no AI.** The threshold is a clock, not a classifier. This replaces “by time + location” with a named, testable boundary; location stays only as a tiebreaker when two rolls overlap in time.
- **Retroactive on sync.** Grouping runs on the phone after clips arrive, so late-syncing watch clips fold into the correct session by their capture timestamps, not their arrival order.
- **Side benefit:** fewer cards means fewer full-width ochre *Start a Memory* pills stacked down the list — directly easing the “wall of ochre” the per-card pill produces on a busy day.

### The explicit affordance — “hold a block open” (candidate, not v1)

For moments the user *knows* are one sitting but that span longer-than-threshold gaps (a dinner across courses, a lecture with a break, a museum walkthrough):

- A spoken or one-tap **“start a block”** holds a single session open across gaps that would otherwise close it. Everything captured until the block ends joins one session.
- **The idle timer is still the safety net** — the block auto-closes after a longer idle stretch (candidate: 10 min of *its own* silence, or a hard cap). There is **no mode to get trapped in** and **nothing the user must remember to turn off**; if they walk away, silence closes it.
- **Never blocks capture to set up.** If the block names a not-yet-existing destination (“…into a new *CIA Dinner* memory”), create it silently and tell the user after — the words keep flowing.
- **Voice-command form forks the intent-parser question.** “Hey HiMem, everything I say for the next hour is one block” is the first case where a spoken *command* is clearly not content. The parser must distinguish “start/hold a scoped session” from “a memory that happens to mention an hour.” That parser is the dependency that makes this post-v1; the **automatic idle-gap rule above ships without it.**
- This is the *prospective* sibling of the retroactive clustering, and the voice-declared sibling of in-context capture (CLAUDE.md · “In-context capture”). Same principle — structure forms from the user’s rhythm or one spoken breath, never from navigation.

## The workbench + Sort (locked July 4 2026)

**Origin (dogfood, July 4):** 20 clips accumulated across three days. Processing them one card at a time — twenty identical *Start a Memory* cycles — was emotionally exhausting, and a road trip (Nazareth, Martin Guitar, Milford) was scattered across a dozen non-adjacent single-clip sessions with no way to combine them. The fix is not a new object; it's a reframe of what Captured Clips *is*, plus an AI proposal layer.

### Captured Clips is a workbench, not a queue

- **Persistent work surface, not an inbox to zero out.** Clips sit on the bench. You pick one up, combine it, set it aside, come back tomorrow. There is **no nag-to-zero**, no "20 unprocessed" guilt count, no decay. (Aligns with the passive-notification rule — the badge informs, never scolds.)
- **Placement drains the bench.** A clip that lands in a Memory *leaves* Captured Clips — it found its home. The bench only ever holds **unplaced** raw material, so it shrinks as work gets done and grows as you capture. Nothing is deleted (the clip lives in its Memory now), so "never lose a thought" holds. This is the anti-hoard mechanic: the bench drains by placement, never by decay.
- **Safe to leave because the transcript already caught the substance.** You can leave a clip for a month without anxiety — the words are already preserved (transcript + audio in the user's iCloud). This is what separates the workbench from a pile of un-transcribed voice memos, which rot because you must re-listen. Perishability was satisfied at capture; organizing can wait.

### Sort is the bench's resting state

- **Sort is not a button you run — it's what Captured Clips looks like now.** Open the bench and it already shows: **confident groupings at the top** ("a few of these seem to belong together"), **loose clips below** ("these can wait"). New clips flow into the picture as they arrive. There is no "Run Sort" action to press and wonder about, so there is no "did anything happen?" confusion (resolves the re-run problem directly).
- **Dismissed groupings get an invisible set-aside flag.** Tapping *Not together* returns the clips to loose and marks that grouping so Sort won't re-propose it. The user never sees the flag; they just never get re-nagged with a grouping they already declined.
- **Loose clips look like normal clips** — the distinction isn't stamped on the clip; it's that grouping suggestions live *above* them when they exist. This **merges the old Sort screen and the compact session list into one surface** — no separate mode.

### Media clips — thumbnails, never a wall (locked July 9 2026)

**Origin (dogfood, July 9):** once the inbox held real photos, the compact list rendered four identical “Photo · 5:39 PM” rows — a grey glyph and a timestamp, nothing to tell one from another. A photo has no transcript, so a text-shaped row is *useless* for it. The bench became unreadable exactly when it filled up. Rules:

- **Photo and video clips render as real thumbnails, never a generic media glyph.** The thumbnail *is* the content preview — the visual equivalent of the transcript-preview line a voice clip gets. A grey camera glyph on a photo row is a bug.
- **Same-minute bursts collapse into one row.** Multiple photos/videos captured in the same minute (or tight cluster) become a single **burst row**: a horizontal thumbnail strip (up to ~5, then `+N`), the time, the count (“4 photos · 5:39 PM”), and the place if known. A 12-photo burst is one scannable line, not twelve walls. Tapping the burst opens the set.
- **A lone photo/video** is a compact row: thumbnail (~46px) + “Photo”/“Video” + time/place. Video thumbnails carry a small play badge.
- **These render rules apply wherever a media clip appears — inside a mixed session card or standing alone.** A photo that idle-gap groups *into* a session renders as a thumbnail row **within that session card**, alongside the voice/note rows; a photo that is genuinely on its own (no other clip within the idle window) is its **own single-clip session** and renders as the compact lone row above. "Lone photo → compact row" describes a photo that *is its own session*, never a reason to pull a photo **out** of a session it belongs to by timestamp.
- **Voice and note clips are unchanged** — they keep the transcript-preview line (the words are their thumbnail).
- **A media clip's description is editable right here on the bench.** A photo/video's description is *the clip's words* — the human stand-in for the future visual transcript, exactly parallel to a voice clip's transcript (AI Organize + search read it the same way). It belongs to the clip (evidence), not the memory, so it does **not** wait for a memory to exist. A lone media row shows the description as its body when written, or a quiet ochre **Add a description** invite when empty; the same invite rides a media row *inside* a session card. Tapping the row opens the **media clip detail** (the photo/video sibling of the voice clip detail), where the DESCRIPTION section carries the full editor — the slot a voice clip fills with Transcript. Ochre throughout (human-written, never AI blue); per item, optional, never blocks. Canonical components: `DescriptionEmpty` / `DescriptionFilled` (`screens-photo-description.jsx`), `MediaClipRow` / `SessionMediaRow` / `ScrMediaClipDetail` (`screens-clips-page.jsx`). Full field rules: `Clip model · spec.md` §Content.
- **Sort clusters show a thumbnail strip too** when their members are visual, so a proposed grouping of trip photos reads as *those photos*, not a text summary of them.
- This is the media-typed expression of “lead with signal”: the signal in a photo is the image; show it.

### Sort — place each proposal deliberately

- **Clusters are pre-accepted proposals**, shown only when confident. Per-card affordances are **quiet secondaries**: *Adjust* (blue text) and *Not together* (dismiss → clips fall back to loose).
- **The collapsed card shows a read-only teaser + "Show all" + "Add to a memory…" (locked July 17 2026).** Collapsed, the card shows the blue signal strip, the cluster title, and a short read-only teaser (time · first-line per clip). Its bottom row carries three quiet actions: **"Show all N ⌄"** (→ **"Done ⌃"** when expanded — open to read/trim), **"Add to a memory…"** (blue — place the group without expanding first), and **"Not together"** (dismiss → clips fall back to loose). "Show all" replaced the earlier **"Adjust ⌄"** (which named editing, not opening). **The whole card is the expand/collapse target** — head, title, and teaser rows all toggle it; "Show all" is the visible cue so the affordance is honest, not hidden. Editing/trim controls (✎, ⊖) and the Compact/Full toggle live *inside* the expanded state, not on the collapsed teaser.
- **Adjust = expand-in-place + subtractive trim (Model A, locked July 15 2026).** Tapping **"Show all N"** (or anywhere on the card) expands it in place to show all N clips as **`reflectiveCompact` rows in a single-open accordion** (reusing the Memory Detail long-memory pattern — glyph · time · one-line preview · **boxed ✎ (pencil only)** · **boxed ⊖ (`minus.circle`)**; **no per-row caret/chevron and no inline Play** — the row itself is the expand/collapse target, tap a row to expand its full transcript in place, opening one collapses the prior, global single-open across the editor; playback lives in the modal). Stacked full transcripts are *not* used — the accordion, not an 8-line preview, is what keeps 11 clips scannable. **Editing a clip is the boxed ✎ Edit button → the unified Clip Editor modal** (per `Clip Editor · unified modal · spec.md` — the one edit affordance on every row everywhere; this supersedes the earlier "row-tap opens the modal" and the "row-tap → Clip Detail is post-v1" notes). Each row carries a subtractive **Remove — rendered as a boxed `minus.circle` (⊖) icon** right of the boxed pencil (`✎ ⊖`), kept **on the card** (in-place trim is the point of Sort; moving it into the modal would mean opening N modals to trim N clips). It is *set-aside* semantics, **not** Trash/Delete (destruction stays the red full-width button on an opened item) — a minus-circle, never a trash can. A removed clip **sets aside** in place — its content dims but stays visible under a divider with a full-strength **Add back** control (≥44px; status/affordance is never opacity-alone), so the trim is *reversible*, not a vanish. **The trim is provisional until placement:** removed clips are simply not placed, so they stay loose after the group is added to a memory; nothing is persisted or told to the proposer (no clip-granularity set-aside — Model B was considered and rejected as over-build for v1, since after placement the kept clips leave and the maximal grouping can't reform). **`Keep these · N` updates N live** as clips are trimmed; **trim-to-0 disables commit** ("Nothing found to keep"). **Out of scope (post-v1):** pulling a clip *into* a cluster, and any bidirectional membership editor. Supersedes the earlier `// post-v1 cluster editor` placeholder, which was an implementer inference, not a design decision.
- **Compact / Full toggle on the expanded cluster card (locked July 17 2026).** The expanded card carries the **same segmented Compact/Full control as Memory Detail** (reuse it, do not mint a new affordance), **placed on the cluster title row, right-aligned next to the title** (not below it). **Segment order: Compact (line-item) on the LEFT as the default, Full (detail) on the right** — the default sits left, applied identically in Memory Detail (reorder there to match). **Compact** = `reflectiveCompact` single-line preview rows (the accordion default); **Full** = wrapped multi-line transcripts. **A multi-clip cluster defaults to Compact** — a 7- or 11-clip cluster must never open as a wall of text (same rule locked for long memories). Per-row expand still works within Compact (single-open accordion). This is the *display density* control; it is orthogonal to the subtractive trim below.
- **Placement is per-cluster via "Add to a memory…" — there is no batch commit bar (locked July 17 2026, supersedes the "one commit, not N" batch).** The ochre **"Keep these · N memories"** bar is **removed.** Each cluster is placed on its own through **"Add to a memory…"** (present on both the collapsed teaser and the expanded card). It opens the **same placement sheet the unified clip editor uses** (`Clip Editor · unified modal · spec.md`): a **New memory / Add to existing memory** toggle, Title, Topic, Project — acting on the cluster's **kept** clips **as a group** (set-aside/removed excluded; promote-then-place the whole set on confirm). On confirm the group is placed and the cluster leaves Sort. The ochre commit still exists — it is the sheet's **Create** button — it just moved off the list and into the deliberate placement step. *Tradeoff, accepted:* the old one-tap accept-all-as-new path is gone; in exchange every cluster can go to a **new or existing** memory (the batch only ever made new ones), and placement is a single titled confirm per cluster.
  - **The placement sheet's Title defaults to the cluster's proposed title** (e.g. `Kingfisher Wharf`) when opened from a cluster — not blank/AI-suggest. The user can edit or clear it (cleared → AI suggests). (A single loose clip opened from the bench has no cluster title, so its sheet stays optional/AI-suggest.) New memories are created **Draft organized**, renameable/reviewable later in Memory detail.
- **The proposals section is visually separated from the ungrouped clips.** The "A few of these seem to belong together" section (header + cluster cards) is followed by a divider and a quiet **"Not yet connected"** section header introducing the ungrouped clips, so the two regions read as distinct. (No floating commit bar sits between them — the batch bar is retired; placement is per-cluster.)
- **Recognition, not generation.** The proposals are pre-formed and recognizable, so the user approves or dismisses rather than organizing from scratch — and places each with a single titled confirm. Recognition is dramatically cheaper than generation; that's why it feels good, even one cluster at a time.

### Clustering is Honest-Label, and tiered

- **Only confident clusters appear. Never a vibe.** A blank suggestions area is honest; a confident wrong grouping is worse than none — it converts recognition back into detect-and-undo, which is *more* friction. Under-suggest.
- **Free (Capture, on-device):** deterministic clusters — same time-window + same place, and literal word/entity match. "Why" strings are **templates filled from the signals** ("5 clips · one 18-minute stretch, same place"), not LLM prose. Runs offline, no server, no cost. Handles the obvious cases (dinner by time+place; "Hosta Hideaway" by word-match).
  - **First-cut gates (tune in dogfood):** time+place = within ~90 min **AND** within ~200m, with **location a hard requirement** — a rolling time window single-links and blobs into an all-day cluster unless location breaks the chain. No/coarse location → don't cluster on time alone (tighten the time gate or skip); never invent a "same place" you can't confirm.
  - **Word-match must be *distinctive*, not merely non-stopword.** ≥ 2 chars + stopword filter is too loose — it false-positives on common content words ("restaurant," "town," "lovely"), which reads as random and inverts the magic. Require the shared token to be a **proper noun or low-frequency term in the user's own corpus** (cheap TF rarity check), and prefer a **shared bigram or ≥ 4-char distinctive token** over any single content word. A missed match is invisible; a false one erodes trust in every card. *(Dogfood, July 4: "little town" surfaced as a cluster — exactly the generic-bigram false positive this gate must reject; "Pennsylvania," a proper noun, is the kind of token that should pass.)*
- **One clip set = one candidate (overlap dedup — locked July 4 2026).** A cluster is defined by its **clip set**, not its reason. Multiple signals routinely point at the same clips (the Pennsylvania clips also share "little town"; a dinner matches on both time+place *and* a shared word). **Never show the same clips in two cards.** Before rendering, collapse candidates by clip-set overlap:
  - **Identical or subset/superset sets → one candidate** (keep the union of clips).
  - **Substantial overlap (≥ ~50% of the smaller set) → merge** into one candidate over the union. Minor incidental overlap (one shared clip between two otherwise-distinct groups) may stay separate, but **a clip may appear in at most one rendered candidate** — assign it to the strongest-signal cluster and remove it from the weaker.
  - The merged candidate's **"why" names the strongest/most-distinctive signal** and may mention the runner-up ("3 clips · same afternoon in Pennsylvania"), rather than spawning a second card. Signal strength: proper-noun word-match ≈ time+place > distinctive bigram > single content word.
  - **Why it matters:** within a single Sort pass, dedup prevents placing the same clips into N overlapping memories — double-filing at the moment of first placement, which is confusing. The pass must guarantee each clip lands in at most one *proposed cluster*. **Note (per `HiMem · evidence and context.md`):** a clip gaining a **second** memory *later* is legitimate and expected — that's the staged AI-association act, not a Sort bulk operation. Sort places once (primary memory); connection multiplies afterward. **each clip lands in at most one new memory.**
- **Plus (Connect):** *semantic* clusters the deterministic pass can't see (the wine-thermos clip + the Q-tips clip both being "packing gear" without a shared word), cross-day thematic grouping, and better cluster *names*. The "grow themselves" intelligence.
- **AI-blue is not a Plus signal.** Blue = "this is an inference moment," regardless of tier (on-device organize is already an AI-blue Free feature). Sort wearing Spark/`aiTint` on Free is consistent.

### Lead with signal, never bury the rest

- The bench shows the confident groupings **and** the loose pile, always, in plain sight. A filter you trust is *additive* ("here's what stood out"); a filter you fear is *subtractive* ("I decided what you don't need to see"). Never hide the rest — the loose pile is always one glance away. The "nothing's lost · they can wait" escape hatch is not decoration; it is the precondition that makes signal-forward feel calm instead of controlling.

### Multi-select restored (supersedes v2's "no multi-select")

- **v2 banned clip-level multi-select.** That rule predated multi-day, single-clip-session-across-days reality. Dogfood proved the need: hand-picking non-contiguous clips (four road-trip clips from different hours) into one Memory. **This section supersedes that ban.**
- **The verb is relational, not file-manager.** For a loose clip, the action is **“Where does this belong?”** — a sheet: *New memory* · *Suggested* (conservative, Honest-Label, floated to top) · *Recent memories & projects* (flat — the user shouldn't have to know which type the destination is). Multi-select survives as a *mechanism underneath* "where does this belong," for batching several loose clips into one destination — not as the headline interaction.
- **Selection = ring, never a check** (Crucible rule, unchanged). Select mode shows exactly one ochre commit (the bottom bar), so "one primary action per moment" holds there too.

## Two capture paradigms (background — see CLAUDE.md)

HiMem has two capture modes. **Structured** = user intentionally creates a Memory (phone direct-voice, append, iPad). **Ad-hoc** = user catches fragments to sort later (today: watch). Captured Clips exists to consolidate ad-hoc captures into Memories. Structured captures bypass this surface entirely — they go straight to Memory Box.

## Surfaces

| Surface | What's there |
|---|---|
| Memories arrival status | A **dot on the Clips tab** when new unseen clips have arrived (presence, not a count; clears on opening Clips). *(Retired the old "X new from Apple Watch" banner, July 10 2026 — redundant once Clips became an always-visible tab.)* |
| **Captured Clips · session list** | The only top-level Captured Clips surface. Each session is one card. Cards expand in place. **No drill-in screen.** |
| Bundle confirm sheet | The seam: operational hands off to reflective. AI-suggested title in Source Serif AI blue, topic chip, optional project chip. Same sheet as existing New-memory flow. |
| Settings → Captured Clips | Top-level row, `N pending`. Never buried. (Existing.) |

**Deleted from the previous spec:** session-detail drill-in screen, clip-list drill-in screen, bottom action bar with N-selected indicator. None of these exist.

## The interaction

### Session list (the only top-level surface)

- **Chrome.** Back `<` left, **"Done"** right. No eyebrow strip. No `✕`. No "Edit" mode.
- **Title block.** "N new clips" (SF Pro 22, weight 600 — *not* Source Serif; this is operational). **Source-agnostic** (locked July 10 2026): clips now arrive from the Watch *and* the phone Clips-tab FAB, so the header describes bench *state* ("3 new clips"), never provenance ("3 from your Watch") — source is a per-card glyph, not the headline. Sub-line: "M sessions · today, 12:17 – 3:36 PM" — pure metadata, no instruction.
- **No helper copy.** No "Tap to select. Swipe to delete." Affordances do their own teaching.
- **Session cards stacked**, grouped under **day headers**. Because the inbox routinely spans multiple days (dogfood, July 4: 20 sessions across 3 days), a time-only meta row is ambiguous — "12:09 PM" could be any of three days. So:
  - **Day-group headers** partition the list in reverse-chronological order: **"Today" / "Yesterday" / "Jun 30"** (SF Pro 13, weight 600, ink3, sticky optional). Matches the Memories-list day-grouping pattern — same vocabulary across surfaces.
  - Under a day header, a card's meta row stays time-only ("3:36 PM · 4 clips · 0:12") — the header supplies the date, no repetition.
  - **Cluster / Sort suggestion cards** (which float out of strict chronological order) carry the date **in the card meta** ("Jun 30 · 6:09–6:18 PM · 5 clips"), since a day header can't unambiguously cover them.
  - **Rule:** every entry must be unambiguously dateable at a glance — via its day header (chronological list) or its own meta (floated cluster). Never time-only in a multi-day inbox.
  Each card carries, top to bottom:
  - **Meta row.** "3:36 PM · 4 clips · 0:12" in SF Pro 12 ink2. (Date comes from the day header above; a floated cluster card prefixes the date — see day-grouping above.)
  - **Transcript preview.** A single block of quoted speech, joined with "… " between clips, capped at ~3 lines and ellipsized. Not a list of separate quoted lines.
  - **Auto-exclude note** (when relevant). "1 clip auto-excluded · no speech." Muted ink2. Not a chip, not amber, not a warning — it's a note that we already handled it. Tappable to expand.
  - **Primary action.** `Start a Memory →` as a full-width pill *inside the card*, ochre tinted (cream text on ochre at 100%, OR ochre text on 8% ochre tint — pick the contrast level by hierarchy; on light cards we want the heavy variant). One verb. One tap. This is the action of the card.
- **No play button on the card.** Preview is not a primary list-level affordance — keep the card visually quiet. Playback lives inside the expanded view.
- **Tap the card body** (anywhere except the Start a Memory pill) → **expand in place.** No screen transition. The card grows downward to reveal per-clip rows. Other cards stay where they are.
- **Tap Start a Memory** → bundle confirm sheet directly. The 80% case.
- **No swipe-to-delete, no long-press-to-delete** (June 12 2026 deletion lock). Deletion is not a gesture on this surface. To delete a session, expand the card and use the full-width **Delete session** button at its foot (see *Deleting sessions*). Expanding the card *is* the deliberation the gesture used to skip.

### Card expand (in place — replaces the session-detail screen)

- **Expand animation.** Card height grows, accordion-style, with the per-clip rows fading in. ~220ms, easeOut.
- **Per-clip rows.** Tabular, dense. Each row:
  - Left: a circular **toggle** (filled = included, empty = excluded). **Never a check glyph.** Selection = ring. Tap to flip.
  - Center: relative offset + duration ("0:00 · 0:03", "+3s · 0:02"), and transcript on the next line.
  - Right: small play glyph (12pt outline, ink2). Tap = inline play; does not navigate.
- **Excluded clip styling.** Empty ring, transcript text at 50% opacity. For auto-excluded clips: italic "No speech detected · likely accidental" in ink2 instead of transcript.
- **Deleting a single clip is not a swipe.** Tap the clip row → the clip opens as its own object (Clip Detail); its full-width **Delete** button lives at the foot of that detail, per the deletion lock. On the bench a clip is more often *excluded* (the inclusion ring) than deleted — exclusion keeps the clip, it just leaves it out of this memory.
- **No multi-select.** No "N selected." No "Bundle N as memory" action that changes copy with selection count. The user toggles inclusion on individual clips as needed; **the card's Start a Memory pill always says the same thing** and always bundles the currently-included clips. If everything is excluded, the pill disables.
- **`Delete session` button** sits at the **foot of the expanded card**, below all clip rows — full-width, danger red, hairline-bordered, ≥50px (the standard deletion affordance, per CLAUDE.md). It moves the session to **Recently Deleted** (30 days). **No confirm dialog** — expanding the card and scrolling past every clip to reach it *is* the deliberation. This is the one and only delete path; there is no swipe and no long-press alternative.
- **No bottom action bar.** The primary action is still the card's own `Start a Memory` pill, anchored to the bottom of the expanded card content; the `Delete session` button sits below it as the demoted destructive action — never a peer beside the pill.
- **Tap card chrome** (the meta row) → collapse. Or tap another card → that one expands and this one collapses.

### Bundle confirm sheet

(Mostly unchanged from the previous spec — reproduced here so this doc is self-contained. **May 25 2026 addition:** destination toggle + add-to-existing-memory flow.)

- **Header**: `Cancel · New memory · Create` when destination is a new memory; `Cancel · Add to memory · Add` when destination is an existing memory.
- **Destination toggle** (new, top of sheet, above session summary): segmented control with two options — `Make a new memory` (default) and `Add to existing memory`. Picking the second swaps the body content but stays on the same sheet.
- **Session summary chip**: ochre-tinted, single line: "3 clips · 3:36 PM · 0:12" with sub-line "1 clip excluded" when relevant. Shown in both modes.

**Make-a-new-memory mode** (default — existing behavior):

- **Title field**: AI-suggested title in Source Serif AI blue (`#1E5C8E`) with an `AI` tag. Tap to rewrite — tag disappears once user-authored.
- **Topic field**: Topic suggestion if AI confident; chip-row with `+ New` at the end. (Existing pattern.)
- **Project field** (optional): chip-row with existing projects + `+ New project`.

**Add-to-existing-memory mode** (new):

- **Inline picker** replaces the Title/Topic/Project fields. No screen push, no nav-stack — the sheet just changes what it shows.
- **Filter**: memories from the last **7 days**, sorted by most-recent-clip. Older memories are reachable via the search row at the bottom of the picker, which opens the existing global search filtered to memories.
- **Per-row layout**:
  - **Title** in Source Serif (sheet is the reflective seam, same family as the AI-suggested title).
  - Sub-line: topic dot + topic name + date · clip count (operational metadata in SF Pro 12 ink2).
  - Right edge: empty ring on rest; ochre check on selection. **Selection = ring fills in, then a check appears on commit** — standard Crucible selection convention.
- **Empty 7-day window**: if no memories were updated in the last 7 days, the picker reads "No recent memories… search to find an older one" with the search row visible.
- **Search row**: at the bottom of the picker, single line: `Search all memories…` with a magnifier glyph. Tap opens the global search prefiltered to memories.
- **On Add**: clips are appended to the chosen memory in chronological order. Behavior follows AI Organize spec § 8 (Provenance, editing, refresh) and the state matrix — the destination memory shows its existing Title + Summary plus the amber footer `"N new clips · Refresh · 1 assist"` (or `"Resets [date]"` when out of assists). **No automatic re-organize.** Refresh runs only on the user's tap.

The bundle sheet is **where voice softens** from operational to reflective. Serif AI-blue title (or serif memory titles in the picker) is the first true thing the user sees on this sheet — they're moving from triage into Memory creation, or into an existing Memory's life.

## Vocabulary (locked · reconciled to `Kingfisher Language.md` July 7 2026)

> **"Make a Memory" is retired along with the one-card-one-pill session list it lived on.** The workbench model speaks the intent language (`Kingfisher Language.md`): a loose clip asks **"Where does this belong?"** (placement), a recognized session's action is **"Start a Memory"** (shaping — "Create" is the allowed conscious-creation exception), and a Sort cluster batch commits with **"Keep these · N memories."** "Make" is a banned software verb. The old rejected-variants below still hold — *and now "Make a Memory" joins them.*

| Use | Don't use |
|---|---|
| **Where does this belong?** (loose-clip placement — sheet title + the relational action) | Make a Memory, Make or Add to Memory, Assign, File |
| **Start a Memory** (turning a recognized session into a memory) | Make a Memory, Make Memory, Bundle, Save as memory |
| **Add to a memory…** (place a cluster's kept clips — opens the New/existing placement sheet) | Keep these, Accept, Confirm, Make memories, Commit |
| **Adjust** (an AI cluster's affordance — expand-in-place + subtractive trim; the AI observed, the human trims and decides) | Review, Accept, Approve, Create Memory, Edit cluster |
| **Captured Clips** (this spec's title only) / **Clips** (the UI tab name, v4) | Inbox, Pending, Watch queue |
| **Clips** (the user-facing surface name) | workbench, bench, holding surface — internal metaphors only (July 8 lock), never in UI copy |
| **N new clips** (title copy when N > 0 — source-agnostic) | N from your Watch, Captured clips ready, Pending clips |
| **Auto-excluded** (status word for accidentals) | Accidental, Likely accidental as a primary label, Invalid |
| **Session** (internal noun — surfaces to the user only as the "Delete session" button) | Capture session, Recording, Batch |

The words **Bundle** and **Make** are retired in user-facing copy. They survive in this spec as engineering shorthand only.

## Color (locked, restated)

- **Ochre `#C64A1C`** is the only chromatic accent on this surface, used on the primary commit (the placement sheet's *Create* / *Start a Memory*) and nothing else at rest. Not on rings. Not on play glyphs. Not on borders.
- **Amber `#B87322`** does **not** appear on this surface in normal state. "Auto-excluded · no speech" is muted ink2, not amber. Amber is reserved for things the user must act on; auto-exclusion is something we *already handled.*
- **AI blue `#1E5C8E`** does not appear on the list. It enters when the bundle sheet opens (suggested title).
- **Confirmed green** is for "Memory created" toast, not for inclusion toggles.

## States

| State | What it looks like |
|---|---|
| **Empty inbox** | "Nothing new" title, sub-line **source-agnostic** (locked July 12 2026): "Clips you capture — with the + button, on your Watch, or with Siri — land here." NEVER "from your Watch" / "Audio you record on your Apple Watch lands here" — clips arrive from multiple sources; source is per-clip metadata, never the headline. No action button. No eyebrow. |
| **Inbox with sessions** | Default session list. |
| **All-excluded session** | Card shows "All clips auto-excluded · no speech" instead of transcript preview. Start a Memory pill is disabled (60% opacity, non-tappable). Because the primary action is dead, tapping the card still expands it so the user can reach the foot-of-card `Delete session` button — the visible exit. |
| **Single-clip session** | Same card shape. Meta row reads "3:36 PM · 1 clip · 0:01". Transcript preview is just that one quote. No regression to a different layout for N=1. |
| **Sync in progress** | Card greys to 60% opacity while clips are still uploading. Sub-line "Syncing · N of M". Expand allowed; only already-synced clips show inside. |
| **Stale (no recent capture)** | List shows in reverse-chrono regardless of age. No "old vs new" partitioning in MVP. |

## Deleting sessions

> **Retired July 11 2026 — swipe, the demoted text link, and the long-press menu.** They violated the June 12 2026 deletion lock (CLAUDE.md: *"Swipe-to-delete is retired everywhere… the user opens the item and scrolls past everything to reach Delete, and that scroll is the deliberation, so there is no confirm dialog"*). The word **Discard** is retired too (`Kingfisher Language.md`) — it's **Delete** everywhere. What follows is the single, current path; it matches the shipping mock.

**One path: the full-width `Delete session` button at the foot of the expanded card.**

- Danger red, hairline-bordered, ≥50px, **below every clip row** — the last thing in the card, never a peer beside the `Start a Memory` pill.
- **Deletes to Recently Deleted (30 days).** Recoverable; that window is the safety net.
- **No confirm dialog.** Expanding the card and scrolling past all its clips to reach the button *is* the deliberation — the same principle as the phone's open-and-scroll-to-Delete model. A confirm sheet on top would be redundant ceremony.
- **Reachable in the all-excluded edge state** by tapping the (dead-primary) card to expand it — the button is the visible exit.

Why not the retired shapes:

- **Not swipe-left.** Retired everywhere June 12; it hides destruction behind an undiscoverable gesture and skips the deliberation the open-and-scroll gives.
- **Not a corner ✕ on every card.** Adds destructive chrome to every rest state.
- **Not a trash icon beside `Start a Memory`.** Peer destructive action next to the primary verb — the exact rule v1 broke.
- **Not a demoted text link.** A destructive action gets the standard full-width Delete button, not a quiet link that reads like navigation.

## What this is *not*

- **Not a per-clip list at the top level.** Clip-level UI is the *contents of an expanded card*, never its own screen.
- **Not a drill-in flow.** There is no second screen between the inbox and the bundle sheet. If you find yourself drawing one, stop.
- **Not a multi-select surface.** No "N selected," no action bar that changes copy with selection count, no select-all. The user toggles individual clip inclusion; the Start a Memory action is always present and always means "bundle the currently-included clips."
- **Not an Edit mode.** No Edit button. Selection chrome (the inclusion ring) is the row's own affordance, always live, never modal.
- **Not a multi-screen drill-in inside the inbox.** No "Session detail" page. No "Clips" page. Card expand replaces both.
- **Not a reflective surface.** No Source Serif on the inbox title. No cream-paper-with-poetic-margins. Operational throughout, until the bundle sheet, where voice softens.
- **Not an AI-organized surface.** Grouping is deterministic. AI assists with the title on bundle. Nothing else.
- **Not a place for amber.** Auto-exclusion isn't a warning. See Color above.

## Bugs the v1 build kept making

These all came back in successive Code passes. Calling them out by name so they stop:

1. **"Bundle" verb survived.** Every list iteration shipped with "Bundle as memory →" somewhere. The verb is mechanical, breaks at N=1, and doesn't match the rest of the app vocabulary. **Use "Start a Memory" for a recognized session; "Where does this belong?" for a loose clip** (per Vocabulary). "Make a Memory" is *also* retired — don't reintroduce it.
2. **Selection = check, not ring.** Filled ochre checkmark circles for selected clips. Crucible rule (CLAUDE.md): selection is a ring, completion is a check. Inclusion in the bundle is a *selection*; the clip isn't "done." Use rings.
3. **Instructional helper copy.** "Tap to select. Swipe to delete." Banned. If you need to teach the gesture, the affordance is wrong. Make the inclusion toggle visible and obvious; deletion is the full-width `Delete session` button, which teaches itself by being plainly labelled.
4. **Centered eyebrows over left-aligned titles.** Visually disjointed and adds chrome the title already carries. Drop them.
5. **Two dismiss controls.** Back `<` AND `✕` in the same chrome strip. One. Back if you came from somewhere; ✕ if you're in a modal. Captured Clips isn't a modal — back only.
6. **Stripe-checkout-style full-width ochre pill floating at the bottom of an otherwise quiet screen.** The `Start a Memory` action belongs *inside the card*, not docked. A floating dock conflates the screen-level action with the per-session action and reads e-commerce, not reflective-tier.
7. **Play button heavier than the primary action.** A filled triangle in a tinted circle out-weighs an ochre text link. If they're peers, both should be heavy or both should be quiet — but they're not peers. Play is secondary at most; on the list view, it's absent entirely.
8. **Transcripts shown as stacked separate quoted lines.** ("One, two, three." / "One, two, three, four, five." each on its own line.) Reads like a status log. Use a single block of quoted speech with " … " joins. Reads like the thought it was.
9. **Granular-management surface presented as the default.** Pre-checked checkboxes, "3 selected" indicator at the bottom — this puts the user in exception-handling mode on entry. Most users, most times, see a session and bundle it. Granular tools live behind a tap (card expand), not in front.
10. **No visible way to delete.** Hiding deletion behind long-press alone was undiscoverable. Deletion now has **one** visible path: the full-width `Delete session` button at the foot of the expanded card. See *Deleting sessions*. (The old "three paths — swipe, link, long-press" answer is retired with the June 12 deletion lock.)

## Tier behavior

| Tier | Captured Clips |
|---|---|
| Free | Fully available. Storage cap (50 unsynced clips on watch) is the same ceiling for everyone. |
| Plus / Founders | Same. |
| Studio (post-MVP) | Same. |

Capture and triage are always free. AI on the bundle sheet (title suggestion) costs nothing additional — it's part of the existing memory-AI assist allotment.

## Out of scope for MVP

Deferred — none block shipping:

- **Cross-session merge** ("bundle these two sessions into one Memory"). Distinct from "append session to existing memory," which IS in MVP (see Bundle confirm sheet · Add-to-existing-memory mode).
- Manual session split ("this clip belongs to a different thought").
- Search within the inbox itself (session list).
- Bulk delete by criteria (e.g. "delete all auto-excluded from yesterday").
- **"Delete all"** — considered, deprioritized. Delete-all addresses a worst case (a bad day where nothing was worth keeping); add-to-existing addresses the common case the v1 spec missed. Worth revisiting if user research shows users routinely have piles of sessions they want to clear wholesale.
- A separate "Older" partition for clips > 48h unprocessed.
- Per-clip retry-transcription affordance. (Re-sync the whole session if transcription fails; clip-level retry is post-MVP.)

## Implementation notes

- **Grouping job runs the idle-gap rule** (see Idle-gap sessioning), not the old “time + location” heuristic. Clips sort by capture timestamp; a gap ≥ threshold starts a new session; `rollGroupId` from On a roll is a deterministic override that keeps a roll as one session regardless of gaps. Location is a tiebreaker only. Runs on the phone after sync so late-arriving clips fold in by timestamp.
- **Auto-exclude detection** runs on phone after sync, not on watch. Heuristics: zero speech tokens in transcription, total amplitude below threshold, clip duration < 2s with no detected speech. Recoverable from the expanded card.
- **Session card transcript preview** — a single SF Pro block in ink2 with straight quotes, capped at 3 lines, ~60 chars per joined fragment, ellipsized. **No serif italic for transcripts at this level.** The operational register holds until the bundle sheet.
- **Card expand** is a self-contained accordion within the card. No portal, no sheet, no nav-stack push. State held in component, not in route. Expand state is single-cardinal: at most one card expanded at a time (tapping another card collapses the first).
- **No bottom action bar.** The Start a Memory pill is anchored to the bottom *of the card*, not of the screen. Safe-area is the bottom of the scrollview, not a fixed dock.
- **Reuse the existing bundle sheet** — the New-memory composer is already wired. Session-first list just changes how the user gets to it; the bundle flow downstream is identical.
- **The "Done" button** dismisses the screen, returning the user to wherever they came from (Today or Settings). It does not snooze, dismiss notifications, or change clip routing. Clips stay in pending; banner stays on Today next launch. Same as today.

## Related work (not in this spec)

- **AI attribution color sweep** — same task flagged in `Projects · MVP spec.md`. The AI tag and AI-blue title on the bundle sheet should already be AI blue. If shipping iOS code has them in ochre, fix as part of the same sweep.
- **On a roll** — Next-clip behavior on watch creates split clips that group into one session via `rollGroupId`. Session-first list relies on this to keep a roll of 5 clips visible as one card, not five.

## Open questions

- **Idle-gap threshold value.** Default 10 min (see Idle-gap sessioning). A real dinner has 10-min+ lulls between courses, so a strict automatic 10-min close would split one sitting in two — which is precisely the case the explicit *hold-a-block* affordance exists to catch. Open: is 10 min right for the automatic rule, or should it be longer (15–20) to better match real sittings, accepting that longer gaps risk merging genuinely separate moments? Needs dogfood data on real inter-clip gaps before locking the number. The *rule* is locked; the *constant* is not.
- **Day-group headers (resolved July 4 2026).** Earlier this was punted ("no day headers, reverse-chrono only, revisit if pending-clip counts get large"). Dogfood made it large — 20 sessions across 3 days — and time-only cards became ambiguous. **Resolved: day-group headers** ("Today / Yesterday / Jun 30"), matching the Memories-list pattern; cards under a header stay time-only, floated cluster cards carry the date in meta. See *The interaction → Session list*.
- **What's the "share session" affordance?** None in MVP. Sessions don't ship as their own thing; Memories do.
- **Disabled-state copy on the primary pill.** When all clips are excluded, does the pill say "Start a Memory" greyed, or "Nothing to bundle"? Lean toward the greyed normal label — "Nothing to bundle" uses the retired *bundle* verb and is more text than the disabled state needs.
- **~~Discard confirm copy.~~ (Resolved July 11 2026 — no confirm.)** With the full-width `Delete session` button + Recently-Deleted safety net, there is **no confirm dialog** and therefore no confirm copy to word. Opening the card and scrolling past its clips to reach the button is the deliberation.

## Files

- `Himem · Captured Clips (session-first).html` — design canvas. Update to reflect this v2.
- `Himem · Captured Clips.html` — original Captured Clips design (clip-first). Retained as v0 reference; superseded.
- `screens-captured-clips-sessions.jsx` — primitives. Match v2 (in-card expand, no drill-in).
- `crucible-primitives.jsx` — `PX` tokens used here. Crucible-accurate (`#C64A1C` ochre).
- `CLAUDE.md` — locked architectural rules: two capture paradigms, the consolidation ladder, operational vs reflective, selection-vs-completion, peer-action demotion.
- This spec is the source of truth for v1. Where this contradicts older designs, this wins.

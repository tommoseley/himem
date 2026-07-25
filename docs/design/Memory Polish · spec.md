# Memory Polish · spec

> **Status:** PROPOSED · post-1.0, except §3 (auto-correct) which is a 1.0-adjacent candidate pending a spike. Not scheduled. No code until the spike reports.
> **Date:** 2026-07-25 · **Origin:** dogfood — a rambling walk recording, run through a frontier model, came back as readable prose. The magic moment was unmistakable.
> **Companion specs:** `AI Organize · spec.md` (derived artifacts, Honest Label, `TruthReconciler`), `Clip Editor · unified modal · spec.md` (the surface), `Project Templates · engineering design.md` (§2a "potential creations" axis), `Pricing model · Capture-Connect-Create.md` (§7c hero feature), `HiMem · Locked Decisions.html`.

## 1 · Three transformations, deliberately separate

These must not be built as one blurry "make my text better" feature. They differ in ambition, cost, risk, and tier:

| # | Transformation | What it does | Model | Tier |
|---|---|---|---|---|
| 1 | **Auto-correct** (§3) | Repairs ASR errors only. No restructuring, no added sentences. | On-device *if the spike allows*, else frontier | **Free** (candidate) |
| 2 | **Polish** (§4) | Editorial rendering of one memory: restructure, paragraph, preserve voice | Frontier | **Plus / Create** |
| 3 | **Project rendering** (§5) | Renders many memories into a journal / essay / chapter | Frontier | **Studio / Create** |

## 2 · The governing line — repair vs. assert

The single rule the whole feature hangs on:

> **Repair is allowed. Assertion is not.**

- **Repair** — correcting what the transcript got *wrong about what the user said*, or restructuring what they said into readable form. Fidelity to the source goes **up**.
- **Assertion** — adding a claim, conclusion, or sentence the user did not say. Fidelity goes **down**. This is the Lincoln-quote failure at paragraph scale, and in a memory-keeper it is the worst thing the product can do: silently putting words in someone's mouth and storing them as their memory.

Observed in the dogfood example: the frontier polish added *"That matters. But it isn't yet the answer."* and re-read a garbled clause into *"not always long hours, perhaps, but hard."* Both are assertions. A shipped polish feature must not do this unreviewed.

**Corollaries (all three tiers):**
- **Rendering, never replacement.** Audio is the source of truth; the original transcript is retained and canonical. Every output here is a *derived artifact* alongside title/summary/topics/cover — regenerate, edit, delete, all harmless.
- **Reversible.** One tap returns the pre-transformation text.
- **Reviewable.** The user sees what changed (§3/§4 review beats).
- **`TruthReconciler` cannot gate these the way it gates summaries.** The summary gate compares output against the clips; here the *clip text itself* is the thing being changed, so there is nothing to compare against. The guard is instead: constrained scope + retained original + visible diff. Name this explicitly so no one assumes the existing gate covers it.

## 3 · Auto-correct (ASR repair) — the 1.0-adjacent candidate

**What it does.** Fixes obvious mis-transcriptions in a clip's existing transcript: *"those epic"* → *"Ozempic"*, *"a lean waist called Mouda"* → *"a lean waste called muda"*, *"I'm not too sure. I can do"* → *"I'm not sure I can do."* Nothing else — no paragraphing, no reordering, no new sentences.

**Why it is *more* honest than the raw transcript, not less.** Audio is truth; the transcript is derived. A transcript that says "Mouda" when the user said "muda" **already misrepresents them**. Repair raises fidelity to the source. This inverts the usual AI-risk framing and is why auto-correct is a defensible **Free** feature where §4/§5 are not.

**Surface (Clip Editor, Zone 1).** Auto-correct *replaces* rather than joins the existing AI button — two blue AI buttons on one card violates one-primary-action:

| Clip state | Primary AI action |
|---|---|
| Transcript exists | **"Clean up with AI ✦"** |
| Transcript missing / transcription failed | **"Transcribe again with AI ✦"** (recovery) |

They serve different failure modes — *"the transcript is basically right but has errors"* (common) vs. *"transcription failed, re-run from audio"* (recovery). Rarely both as equal peers. Standard blue AI button, verb-naming-the-AI + trailing sparkle, per the Crucible button code.

**Safety.**
- Original transcript retained; **one-tap revert**.
- **Visible diff on first use** (what changed), so the user sees the work before trusting it; a quiet toast may suffice once trust is established. A wrongly "corrected" proper noun is the Lincoln failure in miniature — a silent rewrite of the user's own words is not acceptable.
- High-confidence corrections only; when unsure, leave the text alone (*say less before saying false*).

**Open — the spike gates the tier.** Can the on-device model do *constrained* correction acceptably? It is a far narrower task than synthesis (which the 3B demonstrably fails). If yes → Free, and every existing transcript improves. If no → frontier, and it moves to Plus. **Report quality on real library clips before any UI work.**

## 4 · Polish (editorial rendering of one memory) — Plus / Create

**What it does.** Renders a memory's transcripts into readable long-form prose: repairs ASR damage, restructures a ramble into paragraphs with a spine, preserves the author's cadence and asides, finds the throughline. Frontier only — the on-device model cannot synthesize two clips, let alone this.

**Governance.** §2 applies in full, plus:
- **A review beat, like the organize draft.** The user approves the rendering rather than discovering it. Given §2's assertion risk, this is not optional.
- The polished piece is a **named derived artifact** on the memory, sitting alongside (never over) the transcripts.
- Regenerating is free and unpenalized; the previous rendering is replaceable, the source never is.

## 5 · Project rendering — Studio / Create

Polish at project scale: many memories → a travel journal, an essay, a chapter, a photo-book text. This is exactly the **"potential creations"** axis already specced in `Project Templates · engineering design.md` §2a, and the edge-scoped meaning model (§4a there) is what lets the *same* evidence render differently per project. Arguably a stronger fit than single-memory polish, because a project is where the raw material actually accumulates.

Depends on: the memory×project edge entity (Templates §4a v1 carrier note) and the Templates lens/potential-creations fields.

## 6 · Pricing consequence — the §7c hero-feature candidate

`Pricing model · Capture-Connect-Create.md` §7c leaves open *"which feature becomes the hero."* **§4/§5 are the leading candidate**, ahead of suggested-memories or semantic recall: *"turn what I said on a walk into something I could actually read — or publish."* It is demonstrable in one screenshot, it is obviously worth money, and it is structurally impossible on the free on-device path (so it does not cannibalize Free). Flag it there as a candidate; do not lock until §3's spike and a cost estimate land.

**Tier integrity note:** §3 being Free keeps the honesty line intact — Free is not *less honest*, it is *less ambitious*. Free repairs; Plus renders. Consistent with the tier-independent honesty guarantee.

## 7 · Open questions

- **OQ-1 · §3 spike result** — on-device viable? Determines Free vs Plus. Blocks everything else here.
- **OQ-2 · Diff presentation for §3** — inline strikethrough, a side-by-side, or a change list? Needs a mock if it ships.
- **OQ-3 · Does polish (§4) live on the memory or as an export?** A stored artifact on the memory vs. a generated document the user shares. Affects whether it needs a schema field.
- **OQ-4 · §4 review granularity** — approve the whole rendering, or paragraph-level accept/reject (the organize-draft pattern scaled up)?
- **OQ-5 · Cost per polish run** at realistic memory lengths (the 25-minute lecture case), which bounds whether Plus can offer it unmetered.

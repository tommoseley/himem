# Archive · the assist-quota pricing model

**Retired June 4 2026.** These files implemented HiMem's original **metered-AI-assist** pricing: 3 starter assists, 50/month for Plus, buyable assist packs, Founders bonus assists, the Supporter tier, and all the exhausted/urgency/pack-purchase surfaces.

**Why retired.** The pricing direction moved to **Capture · Connect · Create** — tiers named for outcomes (life-stages of a memory), with the Free/Plus seam being *manual + on-device* vs *automatic + frontier*, not a quota. Nobody buys assists; people buy outcomes. The new model makes most of the counting machinery here unnecessary.

**Source of truth now:** `Pricing model · Capture-Connect-Create.md` (project root).

**Status:** kept as **reference only**. Do not load these into active canvases. The new model is still pending one hard dependency — prototyping Apple's on-device organize against the Honest-Label rubric — before its replacement screens get built. When that clears, new pricing screens get authored fresh against the new model; these are here so the prior reasoning (Founders scarcity, honest two-path upgrade prompt, no-blame exhausted copy) isn't lost.

## What's here
- `Himem · Pricing.html` — the 15-section assist-quota pricing canvas.
- `pricing-screens-*.jsx` — its screen modules (settings, modals, tier-states, memory-detail, free-flow, reorganize).
- `Pricing · QA test script.md` — QA walk of the assist states.
- `Open work · pricing flow.md` — the free-tier state-map handoff doc (assist journey).

## Still potentially reusable as *patterns* (not as the model)
- Founders live-scarcity counter + "cap closed" state.
- The honest two-path upgrade prompt (direction A) — no per-unit math at the emotional moment.
- No-blame exhausted/denied copy.
- The field-affordance and provenance-sparkle treatments (already lifted into active work).

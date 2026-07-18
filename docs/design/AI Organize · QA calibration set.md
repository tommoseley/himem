# AI Organize · QA calibration set

*Companion to `AI Organize · spec.md` §11. A gradeable target set: each fixture is a representative memory + its hand-written ideal title/summary (and topics where they matter). The on-device (Foundation Models) prompt is iterated against the **whole set** — a change is kept only if the set's aggregate rubric score improves, never because it fixed one memory. This is what turns "did it get better?" into a measurement instead of a vibe.*

*Version 1 · July 18 2026. Origin: the gardening-summary coldness finding (iOS 26 vs 2027 on-device). Fixtures 1–5 below are the launch seed; expand toward 20–30 per the spec before launch.*

---

## How to use this set

1. Feed each fixture's **clips** (the raw transcript/text, exactly as shown) to the organize prompt under test.
2. Grade the output against the **rubric** (§11 + the cadence line) using the fixture's **ideal** as the target — not for string-match, but for: claims-in-clips, proportional length, descriptive-not-interpretive, recognizable-in-6-months, **reads as one connected thought**, correct POV, topic-reuse-over-coining.
3. Record pass/fail per rubric item per fixture. Keep a prompt change only if the **aggregate** improves.
4. The **anti-target** on each fixture is the specific failure we've actually seen — the output must *not* look like that.

Rubric (per output):
- [ ] Every claim appears in the clips (no fabrication)
- [ ] Length proportional to substance (no floor-padding, no fluff)
- [ ] Descriptive, not interpretive (no mental-state / causal diagnosis)
- [ ] Recognizable from the summary in 6 months
- [ ] **Reads as one connected thought, not staccato declaratives** (cadence, locked July 18 2026)
- [ ] Owner is second-person "you"; others named with natural pronouns
- [ ] Prefers an existing topic/mention when one fits; coins **New** only when nothing does

---

## Fixture 1 · Gardening — the cadence exemplar

**Category:** single-speaker reflective voice memo · the warmth/cadence calibration case.

**Clips (raw):**
> "Out in the garden this morning before it got too hot. The peppers are doing well, tomatoes need more water than I expected in this humidity, and the eggplants are finally coming in. It's strange — since I retired I'm out here at seven instead of after work, and the whole rhythm of the day is different. South Carolina summer is brutal on everything by noon."

**Ideal title:** *Peppers, Tomatoes, and a Retirement Rhythm*
**Ideal summary:**
> "You're tending peppers, tomatoes, and eggplants through a hot, humid South Carolina summer, and finding a new rhythm for the garden since retirement — out early now, before the noon heat."

**Ideal topics:** Gardening, Retirement *(reuse if either exists in the palette)*

**Anti-target (the cold 2027 output we're fixing):**
> "You're tracking the needs of peppers, tomatoes, and eggplants. You're adjusting to a schedule change after retirement. The heat in South Carolina is affecting the garden."
*Why it fails:* three staccato declaratives (fails cadence); "the heat is affecting the garden" is a mild conclusion (fails descriptive-not-interpretive). Specificity and POV are correct — those stay.

**Also reject:** *"Gardening Challenges and Reflections"* (title — vague, "Reflections" is fluff) and any *"I discuss…"* summary (wrong POV).

---

## Fixture 2 · The thin clip — length floor test

**Category:** single short text clip. Proves the model doesn't pad thin substance.

**Clips (raw):**
> "Mmmm, pears."

**Ideal title:** *Pears*
**Ideal summary:**
> "You noted how good the pears were."

**Anti-target:**
> "You're reflecting on a sensory experience with pears, savoring the moment and appreciating the simple pleasures of fresh fruit."
*Why it fails:* invents mental state ("savoring," "appreciating simple pleasures") from three words — fabrication + interpretation + length wildly disproportionate. A thin clip gets a thin summary.

---

## Fixture 3 · Multi-person, mixed media — POV + pronouns

**Category:** multi-person memory, audio + a photo. Tests second-person owner, named others with pronouns, and media-referenced-not-described (v1 no-vision).

**Clips (raw):**
> [audio] "Walked the market with Darlene. She wanted to find the Basque cheesecake place Ben kept talking about — we did, finally, and it lived up to it."
> [photo] (no description)

**Ideal title:** *Basque Cheesecake at the Market with Darlene*
**Ideal summary:**
> "You walked the market with Darlene to track down the Basque cheesecake spot Ben had recommended. You found it, and it lived up to what he'd said. A photo is attached."

**Ideal mentions:** Darlene, Ben *(reuse from library if present)*

**Anti-target:**
> "You and Darlene explored the market together, bonding over a shared search for a special dessert that Ben had recommended, capturing the joy of the hunt in a photograph."
*Why it fails:* "bonding," "capturing the joy" — interpretation/fluff; "explored… together" softens the specific into the generic; describes the photo's content it cannot see (no-vision boundary). Keep the named people + the concrete fact (found it, lived up to it).

---

## Fixture 4 · Idea capture — descriptive, no forward-action fabrication

**Category:** work/idea voice memo. Tests that on-device does **not** fabricate `nextSteps` (Plus-only) and stays descriptive of what was said.

**Clips (raw):**
> "Thinking about the onboarding — the problem isn't the permissions screens, it's that we throw people into an empty app. Maybe the coach marks should fire on first real use, not up front. Also we still haven't decided the free project cap."

**Ideal title:** *Onboarding: Coach Marks on First Use*
**Ideal summary:**
> "You worked through the onboarding problem — the empty-app cold start, not the permission screens — and floated firing the coach marks on first real use instead of up front. The free project cap is still undecided."

**Ideal topics:** Onboarding, Product *(reuse over coining)*

**Anti-target:**
> "You're reflecting on onboarding challenges. Next steps: redesign the coach mark timing, finalize the free project cap, and rethink the empty state."
*Why it fails:* the "Next steps:" list is fabricated forward action — on-device must describe what was said, not manufacture a plan (the spike failure class). "reflecting on challenges" is fluff. Keep the open question stated as the user stated it ("still undecided"), not converted into a task.

---

## Fixture 5 · Pure-observation, no user voice — subject-out rendering

**Category:** photo/observation memory with no first-person audio. Tests the "leave the subject out" rule and share-parity (no "you" to substitute).

**Clips (raw):**
> [photo] description: "Sunset over the ridge behind the house, sky went deep orange."
> [no audio]

**Ideal title:** *Sunset Over the Ridge*
**Ideal summary:**
> "A deep-orange sunset over the ridge behind the house."

**Anti-target:**
> "You captured a breathtaking sunset, taking a peaceful moment to appreciate the beauty of the evening sky over your home."
*Why it fails:* injects "you," mental state ("peaceful moment to appreciate"), and an aesthetic verdict ("breathtaking") absent from the clip. A pure-observation memory names what's there and stops.

---

## Expansion targets (toward 20–30 before launch)

Still to author, one hand-written ideal each — categories from §11 not yet covered:
- On-a-roll session (5+ voice clips, one sitting) → one memory
- Pure-audio long memory (the 25-min lecture case) — proportional summary of a *long* substance
- Mixed languages in one memory (deferred behavior, but seed a fixture)
- Profanity / sensitive content — voice-preservation vs. sanitize (open question §13)
- A memory where the *right* move is fewer topics / empty mentions (proves restraint)

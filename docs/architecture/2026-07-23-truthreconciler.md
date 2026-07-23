# TruthReconciler — one Honest-Label gate for all AI output (2026-07-23)

## Principle: models are advisory; code is authoritative.

The organize summary/title/mentions/topics a model returns are a **proposal**.
What HiMem commits is what code has verified against the source clips. This is
the durable architecture for the Honest-Label guarantee — it does not live in a
prompt.

**Why the reframe.** The Free/on-device model (Apple Foundation Models) is a
platform-controlled moving target. It **regressed under iOS 27** — "much
colder," and it began **fabricating proper names** the clips don't contain (a
Lincoln-only memory drafted *"You, Ben, captured two clips…"*; device QA
reproduced it as *"Albert Einstein"*). "Ben"/"Einstein" are in neither the clips
nor the library. This is not our prompt and not an inherent limit we misjudged —
the floor moved on a surface we don't control, and Apple will keep changing it
every OS release. Prompt tuning against it is permanently whack-a-mole (re-fought
at 27.1, 28, every beta). So the guarantee is enforced in **deterministic code**,
and the guarantee is **HiMem's, not any vendor's** — which is why it runs on
both tiers, not just the one that happened to regress.

## Invariant (the honesty contract)

An AI summary/title may **compress, rephrase, reorder, generalize, and carry
tone**. It may **not introduce people, places, orgs, dates, events, actions, or
relationships absent from the source clips.** A proper name / concrete entity in
the model's output that is not present in the clips is a fabrication.

## Enforcement (deterministic)

`TruthReconciler` (`MemoryStream/Services/Processing/TruthReconciler.swift`) is
the deterministic library; `ProcessingEngine.reconcileResult` orchestrates:

1. **Verify** entities (proper names, places, orgs, dates) in the summary
   against the clip text. `fabricatedEntities(in:sourceText:strictness:)`
   detects mid-sentence capitalized tokens / contiguous runs that aren't
   grounded and aren't stopwords.
2. **Retry once** — re-run the same backend.
3. **Fall back** to a constrained **extractive** summary/title drawn verbatim
   from the clips (`extractiveSummary`/`extractiveTitle`) — it cannot introduce
   a name the source lacks. *Say less before saying false.*

The **summary/title gate (1–3) runs on both tiers.** The separate
**ungrounded-mention drop** — filtering a fabricated name out of the *mentions
field* — is the `.strict`/on-device palette-bleed guard **only**. On the
frontier tier the model extracts mentions from the clips and they pass through
`canonicalizeMentions` reconciliation, not a drop: dropping would be a no-op on
well-behaved frontier output and only risks discarding a legitimately-grounded
name. (Scoping call, 2026-07-23: the directive's both-tier requirement is the
summary/title gate; the mention drop was fix #2, on-device.)

Runs on **every organize path**: first-pass on-device (`processWithOnDevice`),
first-pass cloud (`processWithCloud`), and **reorganize drafts**
(`processReorganize` — the exact surface the "You, Ben…" fabrication appeared
on, previously ungated).

## Both tiers pass through; strictness is the only difference

| | grounding | rationale |
|---|---|---|
| **Apple on-device** | `.strict` — exact case-insensitive substring | the 3B model is a moving target; tightest check |
| **Anthropic frontier** | `.relaxed` — substring **or** a distinctive token (≥3 char, non-stopword) shared with the clips | the frontier legitimately paraphrases a name ("Lincoln" ↔ "Abraham Lincoln"); don't downgrade good prose — but a wholly-invented name shares no token and still falls back |

The **guarantee is identical** on both — only the false-positive tolerance
differs. Relaxed never launders a fabrication: a name with no token in common
with the source fails on both tiers (verified: `inventedSpeakerVariants_allFlagged_bothTiers`).

## Modules

`MentionReconciler` is TruthReconciler's **first module** (conservative mention
dedup / variant-collapse). `reconcileMentions` and `reconcileTopics` (→
`TopicPalette`) route those field-types through the one seam, so
summary/title/mentions/topics share a single authority. A further seam is
**reserved** for future AI output — Memory **cover** selection and **project**
suggestions — which must pass through TruthReconciler before they are surfaced.

## Known gaps (logged, not hidden)

1. **Semantic-claim entailment is NOT caught.** The entity check is deterministic
   over *named* things. An unsupported claim built only from common words —
   *"celebrated our anniversary"* when no clip says so, *"you decided to quit"*
   when the clips only muse — **names no entity and passes the gate.** Catching
   this needs entailment/NLI-class verification, not a token check. **Follow-up,
   not shipped.**
   - **Copy constraint that follows:** no user-facing "checked against your
     recordings" / "verified against your clips" claim may exceed what the gate
     actually verifies. It verifies **entities**, not **claims**. UI and
     marketing copy must not overstate the guarantee to the semantic level.
2. **Heuristic proper-noun detection.** Detection is capitalization + stopword
   based; it can miss a lowercased fabricated name or over-flag an unusual
   capitalized common word. Both fail safe — an over-flag downgrades to the
   honest extractive fallback ("plainer beats false"); an under-flag is the
   semantic-gap class above. Acceptable for v1; revisit if a class of misses
   shows up in dogfood.

## Tests

- `TruthReconcilerTests` — money tests: real Lincoln case, any-invented-entity
  probe (both tiers), in-source names not flagged, multi-word names, relaxed
  paraphrase allowance, extractive fallback can't fabricate, `reconcileMentions`
  routes through the module.
- `OnDeviceOrganizerCalibrationTests` (device, env-gated) — the 6-fixture QA
  panel mirrors production end-to-end (strict on-device); **FABRICATION is the
  hard check** (catches any invented proper noun, not a banned-string list —
  the check the old fixed-string antiTarget missed on "Albert"). POV/length/
  cadence are soft (logged 3B ceilings).

## Positioning consequence (Tom's call, not built)

This widens the Free-vs-Plus honesty gap on grounds outside our control:
Plus/frontier is stable and generative; Free/on-device is constrained to what it
can't get wrong. A defensible line for the pricing/positioning doc:
*"Free never lies to you; Plus writes more beautifully."*

## Sources of truth

`docs/design/AI Organize · spec.md` §2b · `TruthReconciler.swift` header ·
`OnDeviceOrganizer.swift` header · supersedes the on-device-only gate committed
in `aba4909`.

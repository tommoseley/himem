# HiMem · AI Organize spec

**Status:** Draft 2026-05-18 — derived from the pricing-model lock of 2026-05-15 and the Memory-Detail design conversations of 2026-05-18.
**Owner:** Tom
**Companion files:** `Himem · Pricing.html` (Sections 2, 2b, 2c, 2d), `CLAUDE.md`.

This is the design and behavior spec for the **AI Organize** feature: what one assist buys, what the summary should and shouldn't be, where suggestions surface in the UI, and how the system stays honest at scale. Read this before changing any AI-touched surface.

---

## 1. The Honest Label principle

> The summary's job is to give a memory a name its author will recognize six months later. It contains nothing the clips don't contain. Length matches substance. Voice is descriptive, not interpretive.

This is the principle the prompt cites, the QA grader applies, and every other rule in this spec serves.

The product promise is **"AI gives every memory a name."** Not insight. Not interpretation. Honest labels, at the scale a year of memories demands.

---

## 2. What one assist buys

A whole-memory pass that produces:

- **Title** — a concrete noun phrase, usually 3–8 words
- **Summary** — a 1–4 sentence honest label
- **Topics** — 1–3 topic suggestions, from a controlled vocabulary
- **Mentions** — 0–5 first-class entity suggestions (places, people, projects, ideas) the user can accept individually
- **Next steps** — 0–4 action items, only if the memory contains intent or unresolved threads

Fewer outputs is correct when the clips don't warrant more. Empty outputs are correct when there's nothing to say. Fluff to fill the card is never correct.

### Pricing rules

| Action | Cost |
|---|---|
| First Organize with AI on a memory | 1 assist |
| Accept, edit, or skip any individual suggestion | 0 assists |
| Manual edit of any field (Title, Summary, etc.) | 0 assists |
| Refresh after new clips arrive | 1 assist |
| Failed / aborted / errored pass | 0 assists |

The 1-assist cost is per-pass, not per-output. A user who accepts 1 of 5 suggestions paid the same as a user who accepted all 5.

---

## 3. Voice

Summaries are stored as plain strings with **"you"** baked in. That's the voice the owner sees in the app, in the journal, in search.

```
You're exploring how HiMem could capture creative fragments across watch, phone, and iPad.
You found three pears, the size of fists, hidden behind the leaves near the back fence.
You appreciated pears.
```

### On share or export

When a memory leaves the app (email, message, link, PDF export), the share path does a simple substitution:

```swift
sharedSummary = summary
    .replacingOccurrences(of: "You", with: user.firstName)
    .replacingOccurrences(of: "you", with: user.firstName)
```

The external reader sees first-name third-person: *"Tom is exploring how HiMem could capture…"* / *"Tom appreciated pears."*

This is crude. It's also enough for v1.

### Name requirement

The user must have set their first name **before they can share or export**. If the name isn't set, the share/export action prompts for it first.

### Tense

- **Present tense for thinking.** *"You're exploring how to capture…"*
- **Past tense for events.** *"You captured three audio clips."*

### Other voice rules

- **Plain English.** Specific nouns. Active verbs.
- **Pure-observation clips** (sunset photo, no audio): leave the subject out entirely. *"A sunset over the ridge."* No "you" needed — these summaries render the same on share.
- **Multi-person memories:** use other people's first names where known. *"You and Sarah talked about pears."* If a co-subject's name isn't known, use *"someone"* or omit.

### No third-person personal pronouns

The rule **only allows** *you / your* for the owner, plus proper names for everyone else. For **any other person** referenced in a memory, **always use the name**, on every reference. Never use *he, she, they, him, her, them, his, hers, theirs*.

This rule exists for one reason: we don't know any third party's pronouns and we will never ask the user to register them. Treating every co-subject by name sidesteps every assumption.

| Allowed | Not allowed |
|---|---|
| *"Sarah brought a camera."* | *"Sarah brought her camera."* |
| *"Sarah's recipe was older than the kitchen."* | *"Her recipe was older than the kitchen."* |
| *"You and Sarah talked. Sarah said the harvest was good."* | *"You and Sarah talked. She said the harvest was good."* |

**Possessives.** When the possessive isn't load-bearing, drop it: *"Sarah brought a camera"* not *"Sarah's camera."* When it is load-bearing, repeat the name: *"Sarah's recipe…"*

**Avoid name-collisions** by restructuring, not pronoun substitution. *"Sarah said Sarah was happy"* never ships; *"Sarah was happy"* does.

**Non-personal pronouns are fine.** *it, this, that, these, those* — the rule is specifically about third-person *personal* pronouns.

### Prompt instruction

The AI prompt's voice section is exactly:

> *Refer to the journal owner as "you" — always second-person, never with a name. For any other person mentioned, use that person's name on every reference. Do not use third-person personal pronouns (he, she, they, him, her, them, his, hers, theirs) anywhere. Restructure to avoid awkward repetition. Non-personal pronouns (it, this, that) are fine.*

### Hand-edited summaries

Once the user hand-edits a summary, the result is stored as a literal string. The share substitution still applies blindly — if the user wrote *"You'll need to revisit this…"* it becomes *"Tom'll need to revisit this…"* on share. That's a v1.1 problem; for v1 the user can fix it manually if it matters.

### Edited summaries

Once the user hand-edits a summary, the result is stored as a **literal string with no `<user>` token**. The audience-aware substitution doesn't apply. The user wrote what they wrote; it renders identically for every audience.

---

## 4. Operational rules — "describe, don't interpret"

The Honest Label principle is enforced by a single operational test:

> **If a sentence describes what the clips contain, it's allowed. If it describes what the clips _mean_ or what the user _feels_, it isn't.**

| Allowed | Not allowed |
|---|---|
| Paraphrase for concision | Inference about user's mental state (*"Tom was anxious about…"*, *"Tom seems excited"*) |
| Light contextualization from clip metadata (when, where, how many clips) | Inference about meaning (*"This represents a shift in…"*, *"Tom is exploring themes of…"*) |
| Cross-clip synthesis *when literally observable* (*"Tom returned to this idea three times across the day"*) | Cross-clip synthesis as connective fluff (*"Across these clips, a pattern emerges…"*) |

### Worked examples

All examples use stored form (the `<user>` token). For the owner UI, substitute `<user>` → *you* with verb agreement; for an external audience, substitute → the user's first name.

**Source clip:** *"Mmmm, pears."*

- ✅ `<user> appreciated pears.`
  - Owner sees: *"You appreciated pears."*
  - External sees: *"Tom appreciated pears."*
- ❌ `<user> is exploring questions of seasonality and the simple pleasures of late-spring abundance.` — invented depth, regardless of how it renders.

**Source:** multi-clip memory about a HiMem product concept

- ✅ `<user> is exploring how HiMem could capture creative fragments across watch, phone, and iPad. Audio recordings while showering are a real use case.`
- ❌ `<user> seems excited about a new app idea and is processing his anxieties about capture friction by recording his thoughts.` — inference about mental state (*"seems excited,"* *"anxieties"*) is the bug; storage form is irrelevant.

The bad versions are exactly as long as they need to be — that's the trap. Length isn't the test. **Groundedness is the test.**

---

## 5. Length — no floor, soft ceiling

- **No minimum.** A summary can be one short sentence. That's correct for thin clips.
- **Soft ceiling: ~90 words.** Past that the summary becomes its own thing to read, not a label.
- **Hard ceiling: the substance available.** Never manufacture words.

Most summaries should land in the 1-4 sentence range. The distribution should be heavily right-skewed toward the short end — most memories are not novels.

---

## 6. Photo and video boundary

### v1 — no vision

The summary model only sees:

- **Text clips**
- **Audio clips** — transcribed on-device first (free; doesn't cost a separate assist)
- **Clip metadata** — timestamps, location if attached, capture device

It **does not see** photo or video content as analyzable material. Only their metadata.

**Prompt rule:**
> "Photo and video clips are not visible to you. Refer to them by metadata only (count, type, capture context). Do not invent descriptions of visual content."

**UI rule:** On a memory whose clips are *only* photos and videos, the Organize card shows:
> *Summary describes text and audio. Photos and videos are referenced by count.*

The user can still spend the assist if they want metadata-only synthesis. But it's transparent that AI's input is limited.

A memory with zero analyzable content (no text, no transcribable audio) **should not display the Organize card at all** for v1. There's nothing for the assist to do.

### v1.5+ — vision opt-in

When photo/video analysis ships, the Organize card grows a second button:

- **Organize · 1 assist** — text + audio (unchanged default)
- **Organize with media · 3 assists** — text + audio + visual analysis

Vision is **opt-in per-organize-pass, never automatic**. The 1-assist default never includes vision. The 3-assist tier exists because vision is genuinely more expensive at the inference layer — passing that through transparently is honest, and 3 assists positions media analysis as meaningful but accessible (a Plus user can run ~4 full passes per day before hitting the monthly cap).

No new SKU. No new pricing page. The 3-assist option is just spending more of your existing allowance on a single memory.

---

## 7. Where the summary appears

### A · Memory view (canonical home)

**Top of the page**, between the title and the clips.

- **Eyebrow:** plain `SUMMARY` in small caps.
- **Body:** Source Serif 4, 14.5pt, ink color.
- **No `✦ AI` tag.** Once accepted, the synthesis is the memory's, not the AI's. Provenance lives in the **Organized chip** below the clips.
- **Collapsing:** past ~4 lines, show a "Show more" affordance. Long summaries shouldn't bury clips.

### B · Journal / list view (the scan line)

- **Organized memory:** title (serif) + first 20–22 words of summary, truncated to 2 lines.
- **Unorganized memory with text clips:** italic first-clip excerpt, prefixed by a small `from first clip` caption. Visually different from a real summary.
- **Unorganized memory, no text** (photos/audio without transcription): metadata line only — *"3 photos · garden"* or *"2 audio · home"*. No "from first clip" prefix.

The visible difference between organized and unorganized rows is **the value proposition for the assist**. The user sees the contrast and the assist's value becomes visible — not nagged, shown.

### C · Search results

Summary becomes the search snippet when present. This subtly changes prompt optimization: include specific nouns the user might search for. Don't over-abstract.

---

## 8. Provenance, editing, refresh

- **Once accepted, suggestions are the memory's.** No persistent AI badge on Title, Topics, Mentions, or Summary fields. The **Organized chip** is the only provenance indicator on the memory page; tap to re-open the review card.
- **Edits are free.** Editing any accepted field costs zero assists.
- **Refresh costs an assist.** If new clips arrive after a pass, the user can refresh; that's a new whole-memory pass at 1 assist. The previous summary remains visible until the refresh commits (never silently overwritten).
- **Failed passes cost zero assists.** Aborted, errored, or model-failure passes don't decrement.

---

## 9. State table

Inputs are stable across tiers. Auto-organize on Plus / Founder just changes *when* a memory enters the Organized state, never *what* gets rendered.

| `organized` | `reviewed` | `stale` | `assists > 0` | Memory view shows |
|---|---|---|---|---|
| false | — | — | true | Organize card · 1 assist |
| false | — | — | false | Organize card · muted · "Resets Jun 1 · See options" |
| true | false | — | — | AI Suggestions review card (modal sheet) |
| true | true | false | — | Title + Summary at top · clips · Organized chip |
| true | true | true | true | Same + amber footer: *"2 new clips · Refresh · 1 assist"* |
| true | true | true | false | Same + amber footer: *"Resets Jun 1"* (no refresh action) |

See `Himem · Pricing.html` Section 2 → "Decision tree · every condition set" for the full visual reference.

---

## 10. Empty states

| Case | Memory view | Journal row |
|---|---|---|
| Organized, summary present | `SUMMARY` section at top | Title + summary excerpt |
| Organized, summary intentionally empty (very thin clips) | `SUMMARY` section hidden | Title only; no summary line |
| Unorganized, has text clips | No `SUMMARY` section; Organize card visible | Italic first-clip excerpt with `from first clip` caption |
| Unorganized, photos/audio only | No `SUMMARY` section; Organize card shows boundary note | Metadata line only |
| Refresh pending (stale) | Old summary visible; chip shows stale state | Old summary excerpt (stale until refresh) |

---

## 11. QA — calibrating the model

**Build a QA set of 20–30 representative memories before launch.** Hand-write the ideal summary for each. Grade every model output against the set.

### Categories to include

- Single short text clip (the *"Mmmm, pears"* case)
- Single long text clip
- Multi-clip with a clear throughline
- Multi-clip with no obvious throughline (happens often in real use)
- Photo-only
- Audio-only
- Mixed (text + photos + audio)
- Multi-person memory
- Pure-observation memory (no user voice)

### Grading rubric

Per output:

- [ ] Does every claim in the summary appear in the clips?
- [ ] Is the length proportional to the substance?
- [ ] Is the voice third-person, user-named, descriptive?
- [ ] Does it avoid interpretation of mental state or meaning?
- [ ] Would the user recognize the memory from this summary in 6 months?

A summary that fails any single check fails the rubric. The whole grading set is run before every prompt change.

---

## 12. Failure modes to actively watch for

- **The fluff drift.** Model starts adding "exploring themes," "reflecting on," "processing." Catch in QA.
- **The therapist drift.** Model starts inferring emotion. Catch in QA.
- **The journalist drift.** Model starts with stage-setting ("On a sunny May afternoon, Tom…"). Catch in QA.
- **The TL;DR drift.** Model strips information to be "concise." Concision is good. Stripping specific nouns is bad.
- **The label drift.** Model says "a memory about gardening" instead of "the pear tree finally fruited." Specific nouns over abstractions, always.
- **The pronoun drift.** Model slips in *he / she / they / her / his* to avoid name repetition. The fix is to restructure the sentence, not to substitute a pronoun. Every QA pass greps the output for third-person personal pronouns and fails on any hit.

---

## 13. Open questions (deferred to v1.1+)

- **Multi-language memories.** Behavior when clips mix languages.
- **Profanity / sensitive content.** Whether the summary sanitizes or preserves the user's voice.
- **Stale-summary visibility threshold.** How many new clips trigger the stale state vs. silent? Currently: any new clip.
- **Search relevance ranking.** Whether summary or original clip text wins when both match a query.
- **Family-shared memories.** Whose first name renders into `<user>` when a memory is co-owned? Likely: each viewer sees their own perspective — the original creator's view shows *you*, the co-owner sees the creator's first name. To be specced when family sharing lands.
- **Pronouns.** Forbidden for third parties in v1 (see §3); owner is *you*, co-subjects are always named. Pronoun-preference handling is not on the roadmap — the rule sidesteps the entire question. The crude `replacingOccurrences` share substitution may produce odd contractions (*"You'll"* → *"Tom'll"*); fix in v1.1 if it shows up in practice.

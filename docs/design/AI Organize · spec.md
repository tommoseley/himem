# HiMem · AI Organize spec

**Status:** Draft 2026-05-18 — derived from the pricing-model lock of 2026-05-15 and the Memory-Detail design conversations of 2026-05-18.
**Owner:** Tom
**Companion files:** `Pricing model · Capture-Connect-Create.md` (current pricing direction); `archive/assist-model/` (retired assist-quota canvas + screens); `CLAUDE.md`.

> **Pricing direction:** Capture · Connect · Create — see `Pricing model · Capture-Connect-Create.md`. Free organize is **manual + on-device**; Plus organize is **automatic + frontier**. The metering model (assists/packs/quotas) is retired; its old canvas lives in `archive/assist-model/`. The Honest-Label rules, voice, QA rubric, and provenance behavior in this spec are all current and binding — and the on-device path must itself pass this spec's Honest-Label rubric (the open hard dependency).

This is the design and behavior spec for the **AI Organize** feature: what organize produces, what the summary should and shouldn't be, where suggestions surface in the UI, and how the system stays honest at scale. Read this before changing any AI-touched surface.

---

## 1. The Honest Label principle

> The summary's job is to give a memory a name its author will recognize six months later. It contains nothing the clips don't contain. Length matches substance. Voice is descriptive, not interpretive.

This is the principle the prompt cites, the QA grader applies, and every other rule in this spec serves.

The product promise is **"AI gives every memory a name."** Not insight. Not interpretation. Honest labels, at the scale a year of memories demands.

---

## 2. What an organize pass produces

A whole-memory pass that produces:

- **Title** — a concrete noun phrase, usually 3–8 words
- **Summary** — a 1–4 sentence honest label
- **Topics** — 1–3 topic suggestions. **Prefer the user's existing palette; coin a new topic only when the memory clearly doesn't fit** (see §2c). New topics are flagged for the user.
- **Mentions** — 0–5 first-class entity suggestions (places, people, projects, ideas) the user can accept individually
- **Next steps** — 0–4 action items, only if the memory contains intent or unresolved threads. **Plus-tier only** — see below.

Fewer outputs is correct when the clips don't warrant more. Empty outputs are correct when there's nothing to say. Fluff to fill the card is never correct.

### Output by tier (June 5 spike)

The on-device model (Free) and the frontier model (Plus) produce the *same shape* with one exception: **`nextSteps` is Plus-only.** The on-device model fabricated forward actions when given the field, so it was cut from the on-device schema (`OrganizeOutput` = title / summary / topics / mentions). This fits the seam — proactive "what to do next" is the system acting *for* you, which is the automatic/Plus side. Free describes what's there; Plus also tells you what's next.

### When organize runs (Capture · Connect · Create)

- **Free — manual, on-device.** Organize is a deliberate act: the user taps **Organize** on a memory. Runs on Apple Foundation Models (iPhone 15 Pro+/iOS 26), 1.2–1.7s, fully offline, or via a server fallback on older devices. There is **no counter, no allotment, no exhausted state** — organize and re-organize as often as you like. The output is an **editable first draft** (see §2b).
- **Plus — automatic, frontier.** The same pass happens **for you**, on capture, on a frontier model — plus `nextSteps` and the deeper connective work (mentions across memories, related memories, project suggestions). When a Plus user captures offline, the validated on-device draft serves immediately and the frontier polish lands silently on reconnect (one pipeline, two backends).
- **Re-running and editing never penalize.** Manual field edits, accepting/skipping individual suggestions, re-running after new clips, and failed/aborted passes all leave nothing to “spend.” There is nothing to count.

*(Full tier/pricing model: `Pricing model · Capture-Connect-Create.md`. On-device validation: `docs/architecture/foundation-models-spike-findings.md`.)*

## 2c. Topic lifecycle — visible home, review moment, palette discipline

When Reorganize was scoped to Title + Summary, topics lost their user-facing surface: suggested by the model but never shown for review or correction. And the on-device path coined fresh names every pass, fragmenting the palette (Garden / Gardening / Plants / Yard / Vegetables) until topics were useless as filters. The lock that fixes both (June 2026, design + GPT + CC aligned):

- **Palette discipline (the model rule).** The organizer is given the user's existing topics and **must prefer an existing topic when one fits.** It may coin a **new** topic only when the memory clearly doesn't fit the palette. New topics are **flagged as new** so the vocabulary grows on purpose, never silently.
  - **Plumbing fix:** both organizers already receive `existingTopics`. The Anthropic backend forwards it; the **on-device `OnDeviceOrganizer` currently ignores it** and always invents de-novo names. The on-device prompt must be updated to bias toward the supplied palette — this is the one-sided plumbing to close. Until it lands, the on-device path is the source of topic sprawl.
- **First organize reviews topics.** Topics are accepted in the draft→review→organized sheet, alongside title and summary. Existing-palette chips are **pre-selected**; a genuinely-new topic is **marked NEW** (AI-blue dashed chip) and can be dropped in one tap before it sticks.
- **Reorganize never touches topics.** Reorganize stays **Title + Summary only** (§8.0). A wording refresh must never churn the topic set — topics are orthogonal to the title/summary the model is rethinking.
- **Mentions follow the same palette discipline (locked July 17 2026).** Mentions are **library-backed** too — the organizer is handed the user's existing mentions (recurring people/places/projects) alongside `existingTopics`, and **must prefer an existing mention when one fits**, coining a new one only when nothing matches (flagged **New**, same as topics). This keeps people searchable across memories instead of fragmenting (Darlene / Darlene G. / Darlene Graham). **Plumbing:** pass an `existingMentions` palette to both organizers on every organize/reorganize pass, mirroring the `existingTopics` contract; the on-device path must honor it (same fix class as the topic plumbing above).
- **A persistent home.** Every memory shows a **topic chip row directly under the summary** — solid ochre-dot chips for assigned topics, with an **Edit** affordance opening a manage sheet (pick from the existing library, or add one). **Topic changes are deliberate user actions**, never an AI side effect of some other pass.
- **Color.** Topics are user-owned organization → **ochre** dots on wash chips. The only AI-blue moment is the *suggested / NEW* flag during review. *(Reference: `HiMem · Topics.html`.)*

### The unified managed-chip model (locked July 17 2026)

Topics, mentions, and projects are a memory's many-to-many associations, and they now share **one** interaction model — retiring four divergent mechanisms (topic sheet, mention ✕-pill, project no-inline-remove, and the toolbar folder-plus). Reference: `HiMem · Associations.html`.

- **Read state navigates, never removes.** Filled pills tap through to where each lives (topic → filter, project → open, mention → its people). No inline ✕. One dashed **Edit** per section is the only way in to add/remove.
- **One manage sheet, three types.** *On this memory* (tap a chip to remove — deselect, stays in library) · *Add a new…* · *From your library* (tap to add). One removal idiom, so **mentions are library-backed**.
- **Deselect vs. delete-from-library.** Deselect removes from *this* memory. The library's **Edit** toggle reveals a red minus per chip to **delete the vocabulary entry entirely**; deleting warns how many memories use it (mirrors clip-delete's live count) — the memories themselves are never touched. *(Projects delete via the project's own full-width Delete Project, not the library minus.)*
- **Glyph rule.** The leading **dot** means a palette-coloured topic — topics only. Mentions carry a **per-type glyph** (person · place · idea · org — mentions are typed, and the glyph tells the truth about the type; never a dot, never a uniform person glyph), projects a folder glyph.
- **One exception, named.** A memory opened *through* a project keeps a contextual **Remove from this project** shortcut at the bottom; general management still routes through the sheet.

## 2b. Honest Label on Free is an editable draft, not a guarantee

The June 5 spike validated the on-device model as **good enough to be the default Free layer** — 12/15 fixtures clean, the rest hand-editable. But three failure classes survive every prompt approach and are **model-capability ceilings, not prompt bugs**:

1. **Factual inversion / misreading** — e.g. "plumber called" rendered as "call a plumber"; weak agent/verb-direction tracking.
2. **Wrong-genre categorization** — an emerging concept gets filed under the nearest *well-known* category (a memory-capture app titled "Time Management").
3. **Purposive evasion (the *"to relieve stress"* class)** — clips pairing an emotion verb with a physical action get an invented purpose, even though the prompt explicitly bans *"to ___"*. This is the **most brand-central violation** — it's interpretation, the exact thing §3 forbids — and it appears at maximum-probability deterministic output.

**Design consequence.** On Free there is no Plus pass to catch these, so the on-device draft **must never be presented as authoritative.** The spike (§7.1) recommends a concrete treatment: while a pass is **unreviewed**, the chip reads **"Draft organized"** with **"Give this a glance"** review copy; once the user accepts or edits, it becomes plain **"Organized."** The label tracks **review state, not tier** — an unreviewed pass is a draft whether on-device or frontier — so a memory never gets stamped "Free," and "Organized" is never claimed before a human has confirmed it. Editing is first-class and frictionless (it already is — same flow as Memory Detail). The visible difference between a glanced-and-kept draft and an untouched one is also the honest upgrade nudge toward Plus's more-trustworthy output. *(Exact UI strings + the review-state transition: §9 state table; `Pricing model` · §7b.4.)*

**The on-device model is Apple's to move — so honesty is enforced in code, not the prompt (locked 2026-07-23).** The Free/on-device model (Apple Foundation Models) is a **platform-controlled moving target**: it **regressed under iOS 27** — "much colder," and it began **fabricating proper names** the clips don't contain (a Lincoln-only memory drafted *"You, Ben, captured two clips…"*; "Ben" is in neither the clips nor the library). This is not our prompt and not an inherent limit we misjudged — the floor moved on a surface we don't control and Apple will keep changing every OS release. The strategic consequence is a hard architectural line: **HiMem's Honest-Label guarantee can no longer be staked on the on-device model's behavior.** Prompt tuning against it is permanently whack-a-mole (re-fought at 27.1, 28, every beta).

So honesty is enforced by **`TruthReconciler` — one code-side Honest-Label gate for all AI output, tier-independent** (`ProcessingEngine.reconcileResult`; supersedes the on-device-only `HonestLabelGate`, 2026-07-23). **Principle: models are advisory; code is authoritative.** What HiMem commits is what the reconciler has verified against the source clips — the guarantee is HiMem's, not any vendor's.

- **Invariant.** An AI summary/title may compress, rephrase, reorder, generalize, and carry tone — it may **not introduce people, places, orgs, dates, events, actions, or relationships absent from the source clips.**
- **Enforcement (deterministic).** After the summary returns, verify its entities (proper names, places, orgs, dates) against the clip text → strip ungrounded mentions, retry the pass once, then fall back to a **constrained extractive/template summary** drawn from the clips, which cannot introduce a name the source lacks (*"say less before saying false"*, e.g. *"A reflection featuring an excerpt from Abraham Lincoln"*). This runs on **every organize path** — first-pass on-device, first-pass cloud, **and reorganize drafts** (the exact surface the *"You, Ben…"* fabrication appeared on).
- **Both tiers pass through; only strictness differs.** Apple on-device gets **strict** grounding (exact substring — the model is a moving target). Anthropic frontier gets **relaxed** grounding (a name that's a variant/paraphrase of one in the clips — "Lincoln" ↔ "Abraham Lincoln" — is accepted, so the frontier's good paraphrase isn't needlessly downgraded), but a wholly-invented name shares no token with the source and still falls back. The guarantee is identical on both.
- **Modules.** `MentionReconciler` is TruthReconciler's first module; mentions/summary/title/topics route through one seam. A seam is reserved for future AI output (Memory **cover**, **project** suggestions) — which must pass the same authority before surfacing.
- **QA.** The device panel carries the real Lincoln case + an **any-invented-entity** probe (not a fixed banned-string list, which missed "Albert").

**Known gap (logged, not hidden).** The entity check is deterministic over *named* things. It does **not** catch **semantic-claim entailment** — an unsupported claim built only from common words (*"celebrated our anniversary"* when no clip says so) names no entity and passes. Tracked as a follow-up in `docs/architecture/2026-07-23-truthreconciler.md` §Known gaps. **Copy constraint that follows from it:** no user-facing "checked against your recordings" claim may exceed what the gate actually verifies — it verifies *entities*, not *claims*. Don't let marketing/UI copy overstate the guarantee.

This sharpens the tier story on grounds outside our control: **Plus/frontier is stable and generative; Free/on-device is constrained to what it can't get wrong.** Positioning consequence for the pricing/positioning doc (decide before it's inferred): *"Free never lies to you; Plus writes more beautifully."*

Plus output, on a frontier model with the stricter rubric, meets the standard more reliably and gets the full §3–§8 treatment. The tiers differ by **quality and reach, not automation alone** — Plus drifts less and reaches across the library; that fidelity gap is the value prop, not just "skip the tap."

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
- **Cadence: connected reflection, not a status readout (locked July 18 2026).** Summaries must read as *one connected thought*, the way a thoughtful friend would recap — not a list of clipped subject-verb declaratives. A run of short "You're tracking… You're adjusting… The heat is affecting…" sentences reads as the system *logging observations about* the user (the surveillance stance the North Star forbids), even when every fact is true. Prefer flowing, subordinated sentences that connect the facts; let the summary breathe as prose, not a telegram. *(This is a **cadence + stance** rule, independent of specificity — named nouns like "peppers, tomatoes, eggplants" are good and stay; the fix is how they're strung together.)*
  - **Worked before/after (the on-device 2027 calibration exemplar):**
    - ❌ *cold* — "You're tracking the needs of peppers, tomatoes, and eggplants. You're adjusting to a schedule change after retirement. The heat in South Carolina is affecting the garden." (three staccato declaratives; the last is a mild *conclusion* the clips may not state → also an Honest-Label drift)
    - ✅ *warm, same facts* — "You're tending peppers, tomatoes, and eggplants through a hot, humid South Carolina summer, and finding a new rhythm for the garden since retirement." (one connected thought; descriptive, not diagnostic; correct second-person POV; specificity preserved)
  - **Note for the on-device (Foundation Models / 2027) prompt specifically:** newer on-device models fixed POV (second-person) and specificity but regressed on warmth/cadence — the prompt must carry this cadence rule as explicitly as it carries the specificity and POV rules, with the pair above as the in-prompt exemplar. This is prompt-tuning, not a model swap. *(The user-facing **voice register picker** — Plain / Reflective / Spoken — remains a post-v1 candidate; see `Kingfisher Language.md`. This rule tunes the single default voice, which must land on the "Reflective" warmth.)*
- **Pure-observation clips** (sunset photo, no audio): leave the subject out entirely. *"A sunset over the ridge."* No "you" needed — these summaries render the same on share.
- **Multi-person memories:** use other people's first names where known. *"You and Sarah talked about pears."* If a co-subject's name isn't known, use *"someone"* or omit.

### Pronouns for other people

Pronouns are allowed. Refer to the owner as **you** (second-person, never by name); for anyone else, use their name and **pronouns as appropriate** — *he, she, they, him, her, them, his, hers, theirs* — the way natural writing does.

**When a person's pronoun isn't established in the memory, default to singular *they*.** The model should never *guess* someone's gender from a name alone. If the clips make a pronoun clear (the speaker uses it, or it's otherwise unambiguous), use it; otherwise *they* is the safe, natural default.

| Natural (preferred) | Avoid |
|---|---|
| *"Sarah brought her camera."* | stilted name-on-every-reference: *"Sarah brought Sarah's camera."* |
| *"You and Sarah talked. She said the harvest was good."* | guessing an unknown pronoun — use *they* instead |
| *"Alex dropped by. They stayed for an hour."* (pronoun unknown) | inventing *he* / *she* for Alex with no basis |

**Name collisions** are still solved by restructuring, not awkward repetition: *"Sarah said she was happy"* is fine; *"Sarah said Sarah was happy"* is not.

The owner stays **you** in storage regardless — that's what the share/export substitution swaps for the first name.

### Prompt instruction

The AI prompt's voice section is exactly:

> *Refer to the journal owner as "you" — always second-person, never with a name. For any other person mentioned, use their name and pronouns naturally. When a person's pronoun is not clear from the memory, default to singular "they" rather than guessing. Restructure to avoid awkward name repetition.*

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
- **Audio clips** — transcribed on-device first
- **Clip metadata** — timestamps, location if attached, capture device

It **does not see** photo or video content as analyzable material. Only their metadata.

**Prompt rule:**
> "Photo and video clips are not visible to you. Refer to them by metadata only (count, type, capture context). Do not invent descriptions of visual content."

**UI rule:** On a memory whose clips are *only* photos and videos, the Organize card shows:
> *Summary describes text and audio. Photos and videos are referenced by count.*

The user can still run organize if they want metadata-only synthesis. But it's transparent that AI's input is limited.

A memory with zero analyzable content (no text, no transcribable audio) **should not display the Organize card at all** for v1. There's nothing for organize to do.

### v1.5+ — vision opt-in

When photo/video analysis ships, the Organize card grows a second option:

- **Organize** — text + audio (the default pass)
- **Organize with media** — text + audio + visual analysis

Vision is **opt-in per-organize-pass, never automatic**. The default pass never includes vision. Visual analysis is genuinely heavier at the inference layer, so it's a deliberate, separate choice (and a candidate for a higher tier) rather than something that fires silently. No new SKU, no new pricing page — just an explicit “analyze the images too” action on a single memory.

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

The visible difference between organized and unorganized rows is **the value of organizing**. The user sees the contrast and the value becomes visible — not nagged, shown.

### C · Search results

Summary becomes the search snippet when present. This subtly changes prompt optimization: include specific nouns the user might search for. Don't over-abstract.

---

## 8. Provenance, editing, refresh

- **Once accepted, suggestions are the memory's.** No persistent AI badge on Title, Topics, Mentions, or Summary fields. The **Organized chip** is the only provenance indicator on the memory page; tap to re-open the review card.
- **Edits never penalize.** Editing any accepted field is free and unmetered.
- **Refresh = re-run the pass.** If new clips arrive after a pass, the user can refresh — a fresh whole-memory pass (manual on Free; automatic on Plus). The previous summary stays visible until the refresh commits (never silently overwritten).
- **Failed passes change nothing.** Aborted, errored, or model-failure passes leave the prior state intact.

### 8.0 Reorganize — generous, not scarce (June 6 2026)

Organization is never metered. A user who looks at a memory and thinks *“that’s not quite right”* can hit **Reorganize** as often as they like — on Free it runs on-device (cost to us: effectively zero), on Plus it runs on the frontier model (the subscription already funds it). We are no longer selling *organization*; we are selling *better* organization. No counters, no “are you sure?”, no “2 reorganizations remaining.” Free reorganize being local is precisely what lets us be this generous.

The rules that keep this from growing version-management hair:

- **Scope: Title and Summary only.** Reorganize rethinks *only* the title and the summary. Topics and Mentions are **not** touched by a reorganize pass — they're managed separately and a reorganize never churns them.
- **Both new values require explicit approval — always.** Whether or not the user had hand-edited a field, the new title and new summary are each shown as a before/after and must be **approved to apply**. Each field defaults to the **current** value (selection ring + check on *“Current · kept”*); the new wording is the opt-in (*“New suggestion · tap to use”*). There is no silent refresh — the AI never swaps a value behind the user, even on a field they never touched.
- **Reorganize replaces the draft; it never branches.** Memory → current AI draft → reorganize → *new* AI draft. There is never a stored “v1 vs v2.” The before/after is a *transient review moment*, not persisted state.
- **Reorganize re-enters the same lifecycle.** The Organized memory drops back to `reviewed: false` (chip → *“Draft organized”*) and re-opens the review sheet. It is not a separate path — same states, same chip, same accept beat.
- **Dismissing the sheet = decide later, never discard (pinned June 12 2026).** Closing the review sheet (corner ✕, swipe-down) without deciding leaves the memory **in the Draft-organized state with the new draft held**: chip reads *“Draft organized”*, and the full-width **Review this draft** button (the standard Stage-2 affordance) is present to re-open the same sheet. The user’s previously accepted values remain the live title/summary until they approve the new ones — so nothing is lost in either direction. **Accept-or-lose is a bug:** the only ways a reorganize draft goes away are (a) the user approves/keeps values in the review, or (b) the user runs Reorganize again, which replaces the draft. *(Build bug seen June 12: closing the auto-opened sheet left no review entry point — the draft was unreachable, forcing accept-or-lose.)*
- **Opening the review mutates nothing (pinned June 12 2026).** Presenting the sheet must not flip `reviewed`, clear the draft-pending flag, or otherwise touch model state — review state changes **only on the user’s explicit accept/keep**. Implementation note: if the sheet’s presentation is bound to derived model state (e.g. `reviewed == false`) and opening marks it reviewed, the presentation condition dies the instant the sheet appears and it self-dismisses. Bind presentation to explicit UI state, and don’t let async pass-completion or sync updates change the presenting view’s identity mid-present. *(Build bug seen June 12: the review sheet rose and immediately dismissed itself with no user interaction.)*
- **Review is always shown**, even when nothing was hand-edited (the pure “let’s see what it comes up with” case). Seeing the fresh take can spur ideas; silently mutating the memory behind the user cannot.
- **Entry point.** A quiet AI-blue **Reorganize** affordance sits on the Organized memory (opposite the chip) — present but unobtrusive, never a nag. *(See `HiMem · Pricing.html` §2 → `life-3` / `life-3r`.)*

### 8.1 The list-level "App is inferring" prompt is retired (May 31 2026)

- **One review surface, and it's Memory Detail.** The old yellow/blue *"App is inferring"* card on the Memories list — a half-summary with Confirm / Adjust / Not this time inline on the row — is **retired**. Review happens only inside the memory, via the "Organized · review" card with per-field Accept.
- **Why.** The list is the wrong place to adjudicate AI output: the user can't see what's being summarized, and hosting a second confirm flow there means two review surfaces for one decision. The honest per-field flow in Memory Detail supersedes it.
- **The Memories list shows no review chrome.** It's a reflective surface — it shows memories, not a task queue of pending AI chores. No "review" badge, no inline prompt, no count of un-reviewed organizes. To review, the user opens the memory. (Considered and rejected: a quiet AI-blue "Organized · review" marker chip on the row — reintroduces operational chrome onto the gallery wall.)
- **Provenance is unchanged:** the **Organized chip** inside the memory remains the single provenance indicator; tap to re-open the review card.
- **iOS impact.** Shipped iOS still renders the list-level prompt; removing it is part of the same pre-TestFlight uniform AI sweep noted in `CLAUDE.md` (the ochre/amber → AI-blue pass), not a separate effort.

---

## 9. State table

Inputs are stable across tiers. Auto-organize on Plus just changes *when* a memory enters the Organized state, never *what* gets rendered. There is no exhausted/muted state — Free organize is manual and on-device, with nothing to run out of.

**Plus offline-grace reuses these states, no new ones.** When a Plus user organizes offline, the on-device draft enters `organized: true, reviewed: false` immediately; the frontier polish landing on reconnect is just the existing `reviewed`/`stale` transition (the same path new-clips-arriving already uses). One pipeline, two backends — the UI layer knows nothing about which model produced a given output. *(Spike §7.1.)*

| `organized` | `reviewed` | `stale` | Memory view shows |
|---|---|---|---|
| false | — | — | Organize card (Free: **Organize** button; Plus: already auto-organized) |
| true | false | — | AI Suggestions review card (modal sheet). **Chip reads *“Draft organized”*** — the pass ran but the user hasn't confirmed it. (Reorganize re-enters here: an Organized memory drops back to this row, chip returns to *“Draft organized”*, review sheet re-opens.) |
| true | true | false | Title + Summary at top · clips · **Organized chip** (earned once reviewed/accepted/edited) |
| true | true | true | Same + amber footer: *"2 new clips · Refresh"* (re-runs the pass) |

**The chip is a review-state label, not a tier badge.** Before review (`reviewed: false`) the chip reads *“Draft organized”* with *“Give this a glance”* review copy — on **both** tiers, because an unreviewed pass is a draft regardless of which model produced it. On accept or edit it becomes plain *“Organized.”* In practice Free dwells in the draft state more (manual review is the norm) and Plus's auto-organize often shows *“Draft organized”* until the user next opens the memory — but the *label tracks review, not tier*. This keeps the affordance honest without ever stamping "Free" on a memory.

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
- [ ] Is the voice second-person for the owner, named for others, descriptive?
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
- **The unknown-pronoun guess.** Model infers *he / she* for a person whose pronoun the memory never establishes. The fix is to default to singular *they*, not to guess from the name. (Pronouns themselves are fine — only *guessing* an unestablished one is the error.)third-person personal pronouns and fails on any hit.

---

## 13. Open questions (deferred to v1.1+)

- **Multi-language memories.** Behavior when clips mix languages.
- **Profanity / sensitive content.** Whether the summary sanitizes or preserves the user's voice.
- **Stale-summary visibility threshold.** How many new clips trigger the stale state vs. silent? Currently: any new clip.
- **Search relevance ranking.** Whether summary or original clip text wins when both match a query.
- **Family-shared memories.** Whose first name renders into `<user>` when a memory is co-owned? Likely: each viewer sees their own perspective — the original creator's view shows *you*, the co-owner sees the creator's first name. To be specced when family sharing lands.
- **Pronouns.** Allowed for everyone; owner is *you*, others are named with pronouns as appropriate. When a third party's pronoun isn't established in the memory, default to singular *they* (see §3). We don't ask users to register anyone's pronouns; *they* is the safe default. The crude `replacingOccurrences` share substitution may produce odd contractions (*"You'll"* → *"Tom'll"*); fix in v1.1 if it shows up in practice.

# Tutorials · triggers spec

**Status:** Locked June 10 2026. Surfaces built in `Himem · Tutorials.html` (`screens-tutorials.jsx`); the replay hub + "?" toolbar entry in `Himem · Settings.html` (`screens-settings.jsx`).

## What a tutorial is, and what it isn't

A tutorial is a **single iOS one-pager** (eyebrow · serif headline · intro · 2–3 points · ochre dismiss · footnote). It is delivered **in-context at first encounter** and **replayed on demand** from the **?** in the toolbar. It is never an onboarding step, never a modal nag, never a thing the user must hunt for to understand a core flow.

A tutorial earns its place **only** where the UI genuinely can't explain itself, where getting it wrong has a cost, or where it's a differentiator the user won't stumble onto. Most of the app teaches itself and gets **no** tutorial — browsing, search, settings, and **all editing** (the unified editing model's whole bet is that *consistency replaces instruction*: "tap text to edit" learned once works everywhere). Adding a tutorial there would signal a failed flow.

## The set (five)

| # | Tutorial | Job | Tier |
|---|---|---|---|
| 1 | **Capture · Next · Watch** | The one must on Free. Teaches recording, the **Next / on-a-roll** behavior no button can explain, and that the Watch records too. | All |
| 2 | **Organizing with AI** | Sets the mental model: AI drafts; *you're the editor*; editing never un-organizes. Light first-encounter. | All |
| 3 | **Find the thread** | What the project AI action does + suggested memories; you decide, nothing auto-adds. | Plus |
| 4 | **Captured Clips · the Watch story** | *Usage* — what to do with clips that have arrived. | All |
| 5 | **Watch discovery** | *Discovery* — that the Watch is a capture surface at all. Ownership-triggered. | All |

**#4 vs #5 — the distinction that matters.** #4 (usage) only fires once clips exist, which means the user already found the Watch. It cannot be the thing that *teaches the possibility*. #5 (discovery) is triggered by **owning** a watch, not using it — it's the actual answer to "what tells the user the Watch is a possibility."

## Triggers (the automated / push appearances)

Each fires at the feature's **first use**, in-context, once ever.

1. **Capture** → first time the **phone voice composer opens with zero prior recordings**. Shown **before** the record UI begins — never interrupting a live recording.
2. **Organizing** → **first appearance of a "Draft organized" state.**
   - *Free:* after the user taps **Organize** the first time, before the review sheet opens.
   - *Plus:* the first time they open a memory showing an auto-generated draft.
   - One unified trigger ("the first draft they'd ever see"), either path.
3. **Find the thread** → *Plus only.* First time a Plus user opens a **Project Detail with ≥ 3 memories** where Find the thread is unrun. **The ≥3 gate is the tutorial trigger, not the feature gate** — the feature itself activates at ≥1 per `Projects · MVP spec.md`; the *tutorial* waits for ≥3 because a 1–2-memory "thread" is too thin to make a good first impression.
4. **Watch story** → first time **Captured Clips is opened non-empty** (clips have actually arrived). Not on the empty state — nothing to explain yet.
5. **Watch discovery** → app-side gate `WCSession.isPaired && !isWatchAppInstalled && !hasSeenWatchDiscovery`. Surfaced **once on Today** (a calm surface), **after onboarding**.
   - `WCSession` is **app-level**, not an OS notification: you read `isPaired` / `isWatchAppInstalled` in-process (after `activate()`), or react to `sessionWatchStateDidChange(_:)`. **No permission, no system prompt** — the card is entirely the app's own UI on the app's own timing.
   - *Paired but watch app not installed* → "Add HiMem to your Watch" (primary) / "Later" (secondary). The real discovery moment.
   - **The CTA is best-effort, with a written fallback.** There is no public API that *guarantees* installing a watch app, and even deep-linking to the Watch app can fail. So "Add HiMem to your Watch" attempts the open/install, and **when it can't complete, fall through to a manual-instructions screen** (`t-watch-manual`): *Open the Watch app → scroll to Available Apps → tap Install next to HiMem.* The instructions always work because they're just text — never leave the user at a dead button. Its own CTA ("Open the Watch app") is likewise best-effort, but the written steps remain visible regardless.
   - *Paired and installed* → they likely know; a lighter "your Watch is ready," or skip.
   - *No watch paired* → **say nothing.** Never advertise hardware the user doesn't own.

## The "?" toolbar entry + Tutorials hub (the pull path)

Every tutorial is replayable on demand, so a first-time auto-fire is never the only chance to see one. The entry point is a **"?" glyph in the main toolbar**.

- **Placement.** Top toolbar of the main browsing surface (Today / Memories), in the trailing icon cluster **beside search and the settings gear** — `search · ? · settings`. Present on the primary surface, not buried in a menu.
- **Look.** A quiet **warm-ink** question-mark glyph (never iOS system blue, never ochre — it's neither an AI action nor a primary user commit; it's plain navigation chrome). Matches the weight of the search and gear glyphs next to it. ≥44px tap target.
- **Action.** Opens the **Tutorials hub** (a pushed screen / sheet). No badge, no dot, no attention-grab — it waits to be reached for.
- **Second entry.** Also reachable from **Settings → Tutorials** (Display group), for users who look for help there. Same destination.

### The hub

A single list, one row per tutorial — icon tile · title · one-line subtitle · chevron. Tapping a row **replays that tutorial** (the same one-pager the auto-trigger would have shown). Rows, in order:

1. **Capturing a memory** — "Recording, Next, and your Watch"
2. **Organizing with AI** — "Draft, review, and keep"
3. **Projects** — "Group memories and find the thread" *(Plus)*
4. **Topics** — "Your top-level categories"
5. **Captured Clips** — "From your Watch to a memory"
6. **Where your memories live** — "Private by default, in your iCloud"

The hub may list **more rows than there are auto-fired tutorials** — it's the catalog of *all* replayable explainers, including ones that never auto-fire (e.g. Topics, the data-custody explainer) because their concepts are minor enough not to warrant an interruption but useful enough to be lookup-able. Auto-fire is the curated subset (the five triggers above); the hub is the complete library. A row is never gated by "seen" state — everything is always replayable.

## Global rules (what keeps it from being annoying)

- **Every tutorial fires automatically, exactly once.** Each of the five is guaranteed to surface on its own at its trigger — the user never has to go find it. Persisted per-tutorial (a `hasSeen<Name>` flag); dismiss (× or CTA) = marked seen, and it never auto-fires again (the **?** hub is the replay path).
- **One auto-tutorial per session, and at most one per day — by deferral, never cancellation.** If two triggers would fire close together, show one and **defer** the other to its *next* natural moment. Deferral only delays; it must never consume the one-time fire. A deferred tutorial keeps its unseen state and re-attempts at its next trigger, so the once-each guarantee always holds.
- **Never during onboarding, never on cold launch.** Onboarding owns first-run; tutorials fire later, each at its own feature's doorstep.
- **Never mid-task.** Before recording, at the review beat, on opening a surface — never over a live capture or while the user is reading.
- **Tier-aware.** #3 is Plus-only. #2 fires for both tiers. #1, #4, #5 are universal (gated on the relevant state).
- **No badge, no "0 of 5 seen" nag.** Push is contextual; pull is the **?**. Never dangle completion bait.

## Coverage / edge cases

- **Both first-capture entry paths are covered.** Phone-first users get #1 (whose third point seeds the Watch); Watch-first users get #5 (discovery) and #4 (usage). No user reaches a capture surface uninstructed.
- **Free + Watch-first in one session** is exactly where "one per session, defer the rest" earns its keep: show the Watch story, defer Organizing to the next time they open a draft.
- **No watch paired:** suppress #5 entirely, and soften #1's Watch point to conditional ("If you have an Apple Watch…") rather than advertising a surface they can't use.

## Cross-references

- Surfaces: `Himem · Tutorials.html` (the five one-pagers) · `Himem · Settings.html` (Tutorials hub + the **?** toolbar entry).
- Capture/Next behavior: `On a roll · spec.md`, `Watch · spec.md`.
- Draft/organize model: `AI Organize · spec.md`, `Memory Detail · unified editing model.md`.
- Find the thread: `Projects · MVP spec.md`.
- No-tutorial-needed principle: a corollary of the unified editing model (`Memory Detail · unified editing model.md`).

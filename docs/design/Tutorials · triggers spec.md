# Tutorials · triggers spec

**Status:** Locked June 10 2026. Surfaces built in `Himem · Tutorials.html` (`screens-tutorials.jsx`); the replay hub + "?" toolbar entry in `Himem · Settings.html` (`screens-settings.jsx`).

## What a tutorial is, and what it isn't

## Two tutorial formats (July 5 2026)

There are **two** teaching formats, split by *what* they explain — a reproducible pattern intended to carry across future products, not just HiMem:

1. **Full-pager — explains WHAT A PAGE IS.** A single iOS one-pager (eyebrow · serif headline · intro · 2–3 points · ochre dismiss · footnote). Conceptual ("this is Captured Clips — clips from your Watch land here to become memories"). This is the format the rest of this spec describes.
2. **Anchored coachmark — explains WHAT THE CONTROLS DO.** Dim the screen with a warm-ink scrim, box the real element in an **ochre ring**, float a caption card (Source-Serif lead-in, quiet voice) with **Skip** (plain ink, dismisses the *whole* tour) and **Next/Done** (ochre) + a step counter. Best for control-specific orientation and for an **empty first-run screen** that has no content to anchor a full-pager. Crucible dress, never a borrowed yellow-on-navy. Specimen: `Himem · Memories.html` § "First-run coachmark tour" (`screens-coachmark.jsx`).

**Deployment discipline (the part that keeps it on-thesis).** The coachmark is *a great tool and a poor default*. A forced launch tour is the posture calm software rejects ("you already have enough load"; recognition-in-context beats generation-out-of-context; tours have high skip / low retention in the wild). So:
- **First launch stays the hand-off** — empty Today, written prompt, arrow to the FAB. **Capture is never gated by a tour.** (Preserves "hand-off, not handhold" and perishability.)
- **The screen walkthrough lives under the ?** hub as **"Take a tour of the screen"**, replayable any time, and is *offered* on the empty home via a quiet **"Show me around"** chip — never auto-forced between the user and capture.
- **"Every product launches with a tour" is NOT doctrine.** The reusable asset is the *kit* (two format components + trigger/skip rules + Crucible dress); each product earns its own *trigger* decision. Hardening "always auto-tour" into a rule would be exactly the bureaucracy the north star forbids. Treat any auto-run as a hypothesis to measure (skip rate, did it reduce first-run confusion), per "plans are hypotheses."
- **If a screen walkthrough auto-runs at all, the guardrails are absolute:** fires **once ever**, **Skip dismisses instantly** (the perishability escape hatch to the FAB), never chains without an always-present Skip.

### Per-tab coachmark on first arrival (locked July 9 2026)

HiMem *does* auto-run a small anchored coachmark — one per primary tab (**Clips · Memories · Projects**) — because tapping into a tab you've never opened is itself a curiosity signal ("teaching follows curiosity"), and each tab's job isn't obvious from its name alone. This is the in-product deployment of the Tour format; the ? → Learn hub remains the replay home.

The unguarded version ("show each tab's coachmark when first opened") is three interruptions in one session and lands one of them in the worst place. So the rule is guarded, and the guards are not optional:

1. **Once ever per tab.** First time the user lands on that tab, its coachmark fires; never again (persist a per-tab `seenCoachmark` flag). Three tabs → at most three lifetime auto-fires, each a different tab.
2. **Anchored coachmark, not a full-pager.** Dim scrim + ochre spotlight on the tab's key elements (the context-filter row, a representative card, the FAB) + one caption card, **Skip** (kills the whole tab's tour instantly) / **Next**. Crucible dress.
3. **Suppress the Clips coachmark when arriving from a capture.** Recording returns to Clips; if the user just spoke a thought and lands on Clips, a tour there is *interrupting creation*. Defer it to the next **neutral** arrival at Clips (opened from the tab bar, not from a just-finished capture).
4. **Never on cold first launch.** First launch stays the empty-home hand-off (prompt + FAB). Per-tab coachmarks begin on the **second session**, or once a tab has content to anchor to — whichever is first. A tour anchored to an empty screen teaches nothing.
5. **Skip is always present and always instant.** No step chains without a visible Skip; Skip ends that tab's tour immediately and marks it seen.

Copy is intent-first per `Kingfisher Language.md` (why before how) — e.g. Clips: *"Everything you've caught, before it's placed. Catch a thought here or on your Watch."* not *"This is the Clips tab."*

**Spotlight ring is the target end-state, not optional on populated tabs.** The anchored ochre ring around a specific element (a tab-bar item, the context-filter chip, the FAB) *is* the pattern — it's what makes this the "WHAT THE CONTROLS DO" format instead of a generic modal. A **centered caption card with only a dim scrim is the fallback for screens with nothing to anchor** (empty Clips/Projects), never the finished form. **On a tab that has content, the ring is required for v1** — a coachmark that can't point at the thing it's describing has degraded into "this is the Clips tab," the flat un-anchored teaching we explicitly rejected. *(Build status July 2026: v1 shipped the full mechanism — trigger, once-per-tab, suppress-from-capture, skip — with the centered-card fallback; per-control spotlight geometry is the outstanding piece and lands on populated tabs. The Learn-hub tour row resets the per-tab seen flags and re-fires for the current tab, which is why those flags stay individually addressable, not one global boolean.)*

---

A tutorial is a **single iOS one-pager** (eyebrow · serif headline · intro · 2–3 points · ochre dismiss · footnote). It is delivered **in-context at first encounter** and **replayed on demand** from the **?** in the toolbar. It is never an onboarding step, never a modal nag, never a thing the user must hunt for to understand a core flow.

A tutorial earns its place **only** where the UI genuinely can't explain itself, where getting it wrong has a cost, or where it's a differentiator the user won't stumble onto. Most of the app teaches itself and gets **no** tutorial — browsing, search, settings, and **all editing** (the unified editing model's whole bet is that *consistency replaces instruction*: "tap text to edit" learned once works everywhere). Adding a tutorial there would signal a failed flow.

## The set (six)

| # | Tutorial | Job | Tier |
|---|---|---|---|
| 1 | **Capture · Next · Watch** | The one must on Free. Teaches recording, the **Next / on-a-roll** behavior no button can explain, and that the Watch records too. | All |
| 2 | **Organizing with AI** | Sets the mental model: AI drafts; *you're the editor*; editing never un-organizes. Light first-encounter. | All |
| 3 | **Find the thread** | What the project AI action does + suggested memories; you decide, nothing auto-adds. | Plus |
| 4 | **Captured Clips · the Watch story** | *Usage* — what to do with clips that have arrived. | All |
| 5 | **Watch discovery** | *Discovery* — that the Watch is a capture surface at all. Ownership-triggered. | All |
| 6 | **Capturing with Siri** | *Discovery* — the two hands-free Siri phrases (open+record, and in-Siri dictation that never opens the app). A differentiator the user can't stumble onto, and the phone-side embodiment of the perishability principle. | All |

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
6. **Capturing with Siri** → *discovery-triggered, like #5* (the user can't stumble onto an invisible voice phrase). Fires **once on Today**, after onboarding, **after the capture habit is established** — gated on `memoryCount >= 3 && !hasSeenSiriTutorial`. Rationale: showing the faster path only lands once the user already values capture; firing on day zero (before they've recorded anything) wastes the one-time fire. Both phrases are All-tier (Plus only adds the background auto-organize, mentioned inline). If `WCSession` Watch discovery (#5) and this would collide, the **one-per-session deferral** applies normally.

## The "?" toolbar entry + Learn hub (the pull path)

Every tutorial is replayable on demand, so a first-time auto-fire is never the only chance to see one. The entry point is a **"?" glyph in the main toolbar**. The hub it opens is titled **Learn**, not Help — "Help" says *something is wrong*; "Learn" says *want to understand this better?* Kingfisher teaches, it doesn't rescue. *(Teaching vocabulary: this is the **Learn** primitive — see `Kingfisher · North Star.md`.)*

- **Placement.** Top toolbar of the main browsing surface (Today / Memories), in the trailing icon cluster **beside search and the settings gear** — `search · ? · settings`. Present on the primary surface, not buried in a menu.
- **Look.** A quiet **warm-ink** question-mark glyph (never iOS system blue, never ochre — it's neither an AI action nor a primary user commit; it's plain navigation chrome). Matches the weight of the search and gear glyphs next to it. ≥44px tap target.
- **Action.** Opens the **Learn hub** (a pushed screen / sheet). No badge, no dot, no attention-grab — it waits to be reached for. *Teaching follows curiosity: the hub is pull, never push.*
- **Second entry.** Also reachable from **Settings → Learn** (Display group), for users who look for help there. Same destination.

### The hub

A single list, one row per tutorial — icon tile · title · one-line subtitle · chevron. Tapping a row **replays that tutorial** (the same one-pager the auto-trigger would have shown). Rows, in order:

1. **Take a tour of the screen** — "What each button and area does" *(the anchored coachmark walkthrough — set apart at the top; "Show me around" on the empty home launches the same thing)*
2. **Capturing a memory** — "Recording, Next, and your Watch"
3. **Organizing with AI** — "Draft, review, and keep"
4. **Projects** — "Group memories and find the thread" *(Plus)*
5. **Topics** — "Your top-level categories"
6. **Captured Clips** — "Catch a thought, shape it later"
7. **Capturing with Siri** — "Hands-free, before it fades"
8. **Where your memories live** — "Private by default, in your iCloud"

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

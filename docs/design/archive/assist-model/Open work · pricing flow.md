# Open work · pricing flow + free tier state map

**Status:** drafted but not built. Picked up May 27 2026.

This document is the handoff for two related artifacts that need to land on the Pricing canvas (`Himem · Pricing.html`):

1. **Pricing flow decision tree** — the user's journey across tiers and time. Where do they start, what triggers each upsell moment, what surfaces lead to conversion. *Macro view.*
2. **Free tier state map** — what every Himem surface looks like across the conditions a free user can be in. *Surface-by-surface view.*

They complement each other: the tree says **when** the user hits a paywall; the map says **what they see** at that moment.

---

## Locked decisions (May 27 2026)

These are the answers to the two questions open when I closed the previous session:

### 1. Starter Project Assist is loud, not silent

The free tier's one starter Project Assist run is **visible to the user as a starter** — they know they're using their one free pass. Reason: avoid the "I wouldn't have used it on that!" regret if it were silent.

**Copy (locked):** the Find the thread button shows a small adjacent label *"Starter · free"* the first time, replaced by *"1 assist"* on subsequent passes (which fire the upgrade modal for free users). *(Rejected alternative, kept for reference: a one-time modal "You have one free Find the thread — use it on the project that matters most" with **Use it** / **Not yet** buttons. Dropped — the inline label doesn't interrupt the flow.)*

### 2. Plus users out of assists can buy more without re-subscribing

Currently the **Exhausted** state (2e on the Pricing canvas, `ScrMemoryExhausted` in `pricing-screens-memory-detail.jsx`) treats free and Plus users the same. They shouldn't be:

- **Free + exhausted:** CTA = "Upgrade" → subscription paywall.
- **Plus + exhausted:** CTA = "Get more · pack of N for $X" → assist pack purchase modal. Plus stays Plus; the pack is additive.

Two distinct destinations from one shared surface. Needs a new modal: **assist pack purchase**. The Pricing canvas already mocks the pack tiles (`PackTile` in `pricing-screens-settings.jsx`) — the missing piece is the modal that fires from Memory Detail's stale/exhausted footer.

**IAP dependency:** the pack-purchase modal is the user-visible end of the In-App Purchase pipe. It can be *designed* now (`PackTile` already exists, and the modal is mocked as `plus-pack-modal`), but it **cannot go live until the IAP infrastructure clears** — Paid Apps Agreement, tax, and banking setup are the blocker, not design work. Treat the modal as design-complete / ship-blocked, not done.

---

## Three gaps to resolve while building

Discovered during the previous session's draft:

### Gap 1 · Bundle sheet AI title for free users

The bundle sheet shows an AI-suggested title (`AI Organize · spec.md`). For a free user:

- **With assists:** the title suggestion costs 1 assist when the bundle is committed. ✓ Already specced.
- **With 0 assists:** the bundle sheet does not pre-suggest a title or burn an assist invisibly. Fallback: a generic timestamp title (*"Voice clips · May 27 4:32 PM"*) with a *"Get AI title · 1 assist"* link adjacent. **Locked:** the link routes to the **Upgrade Hub** (`ScrUpgradeHub`) — not a separate "upgrade modal." Built as `free-bundle-no-ai`.

### Gap 2 · Free tier second tap on "Find the thread"

After the starter run, free users tapping the button hits a paywall. Where is that modal? The Pricing canvas has an Upgrade Hub (`ScrUpgradeHub`) but no **inline paywall modal** from Project Detail. Needs to be designed:

- **Canonical identifier:** `ProjectAssistUpsellSheet` (carried over from the old CLAUDE.md bullet — preserved here for naming continuity when this gets built; not yet implemented).
- **Trigger:** free user, project already has summary, taps Find the thread.
- **Suggested shape:** sheet that pulls up from the bottom, showing "Find the thread refreshes summaries with new memories. Plus gets unlimited Find-the-thread runs." with **Upgrade to Plus** primary, **Buy an assist pack** secondary, **Not now** tertiary.

### Gap 3 · "1 assist left" urgency cue

Free user goes from 3 assists → 2 → 1. Where do they learn they're running out? Currently only Settings → Your AI shows the counter. Suggested addition: when assists drop to 1, a small ambient indicator appears in the Organize card itself (*"1 assist left this month · free tier"*). Not a banner, not a modal — just a visible counter on the surface where they'd spend it.

---

## Proposed structure for the build

New section in `Himem · Pricing.html`:

```
DCSection id="free-journey" title="3 · Free tier journey"
  subtitle="Where free users hit each paywall moment, and what each surface looks like at that beat."

  // Wide flow diagram — the decision tree
  DCArtboard id="free-flow" label="Decision tree" width=920 height=760
    <ScrFreeFlow/>   // new component

  // Phone-sized state map artboards (~340×735 each)
  DCArtboard id="free-start"        label="Onboarding · starter grant"
  DCArtboard id="free-3-left"       label="Memory Detail · 3 of 3 assists"  // reuse ScrMemoryIdle, badge
  DCArtboard id="free-1-left"       label="Memory Detail · 1 of 3 assists"  // NEW · urgency cue
  DCArtboard id="free-mem-exhaust"  label="Memory Detail · out (free)"      // NEW · differs from Plus
  DCArtboard id="free-proj-starter" label="Project · starter run available" // NEW · 'Starter · free' label
  DCArtboard id="free-proj-after"   label="Project · after starter used"    // NEW · upgrade modal
  DCArtboard id="free-bundle-no-ai" label="Bundle sheet · no assists"       // NEW · timestamp fallback
```

Plus a new section for the Plus-tier exhausted surfaces:

```
DCSection id="plus-pack" title="3b · Plus · assist pack purchase"
  subtitle="Plus user is out for the month; they can buy a pack without changing their subscription."

  DCArtboard id="plus-exhaust"      label="Memory Detail · out (Plus)"
  DCArtboard id="plus-pack-modal"   label="Buy a pack · modal"
  DCArtboard id="plus-pack-applied" label="Memory Detail · pack purchased"
```

## What already exists (reuse, don't redraw)

| Surface | Lives in | Status |
|---|---|---|
| `ScrOnboardingStarter` | `pricing-screens-settings.jsx` | Reuse for `free-start` |
| `ScrMemoryIdle` (2a) | `pricing-screens-memory-detail.jsx` | Base for free-3-left + free-1-left |
| `ScrMemoryExhausted` (2e) | `pricing-screens-memory-detail.jsx` | Base for both `free-mem-exhaust` and `plus-exhaust`, but copy must differ |
| `ScrSettingsYourAI` | `pricing-screens-settings.jsx` | Reuse — shows counters |
| `ScrUpgradeHub` | `pricing-screens-settings.jsx` | Reuse for context |
| `PackTile` | `pricing-screens-settings.jsx` | Reuse inside the new `plus-pack-modal` |

## What needs new design

- `ScrFreeFlow` — the wide flow diagram with swimlanes (suggested: swimlanes for *signup* / *first capture* / *first Organize* / *exhaust memory assists* / *first project* / *starter Find the thread* / *exhaust Find the thread* / *upgrade*).
- Urgency-cue treatment for "1 assist left" on Memory Detail (Organize card variant).
- Free-vs-Plus exhausted copy split (two variants of the muted Organize card).
- Free-tier starter-Project-Assist visible label ("Starter · free").
- Inline paywall modal from Project Detail's second-tap.
- Bundle sheet AI-less fallback (timestamp title + "Get AI title · 1 assist" link).
- Plus assist pack purchase modal (uses existing `PackTile` components).

---

## Cross-spec hooks

- `AI Organize · spec.md` § 8 already defines the state matrix this builds on. Don't re-spec; reference.
- `Projects · MVP spec.md` already locks the starter Project Assist rule and the ≥1 memory threshold. Don't re-litigate.
- `CLAUDE.md` § Projects already documents the tier model, including the starter-loudness decision (May 27 — now landed in CLAUDE.md). The exhausted-state tier split also landed in `CLAUDE.md` § AI Organize (May 31).

## CLAUDE.md updates (now complete)

Both additions are done; this section is kept as a record of what landed where.

**Done — starter loudness:** the starter-loudness rule now lives in `CLAUDE.md` § Projects — *"The starter run is **loud, not silent**…"* with the *Starter · free* label spec and the May 27 reversal justification.

**Done — exhausted-state tier split (May 31):** `CLAUDE.md` § AI Organize now has the bullet — *"Exhausted state splits by tier."* Plus → assist pack purchase, free → subscription paywall (Upgrade Hub), with a cross-reference back to this doc §2 for the modal spec and the IAP ship-block.

---

## Prompt for the new session

Paste this verbatim:

> I want to build the pricing flow decision tree + free tier state map for Himem. The handoff doc is `Open work · pricing flow.md` at the project root — please read it first, then re-read `Himem · Pricing.html`, `pricing-screens-memory-detail.jsx`, `pricing-screens-settings.jsx`, and `AI Organize · spec.md` § 8 for context. Confirm you understand the scope before drafting anything. Don't redraw surfaces that already exist — reuse `ScrMemoryIdle`, `ScrMemoryExhausted`, `ScrOnboardingStarter`, etc. The new pieces are the flow diagram (`ScrFreeFlow`), the urgency cue for "1 assist left," the free-vs-Plus exhausted split, the inline paywall modal from Project Detail, the bundle-sheet timestamp fallback, and the Plus assist-pack purchase modal. Start by listing what you'll build and where each artboard goes; wait for me to confirm before writing code.

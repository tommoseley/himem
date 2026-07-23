# Memory Cover · spec

> **Status:** PROPOSED · post-1.0 (1.1 headline candidate) · not scheduled. Not a v1 ship blocker. Design authority: a documented candidate, not a locked build. No code until scheduled.
> **Date:** 2026-07-21 · **Origin:** dogfood — a memory with a banner reads as "a place I remember," not "a database entry." (The App Store Frame 4 cover established the visual target.)
> **Companion specs:** `HiMem · evidence and context.md` (ontology), `AI Organize · spec.md` (derived artifacts + Honest Label), `Kingfisher · North Star.md` (recognition over generation), `CLAUDE.md` (data custody, tiers), `Pricing model · Capture-Connect-Create.md`.

## 1 · The idea

A **Cover** gives a memory a visual identity — the emotional "book cover" that makes it recognizable at a glance. It is **presentation, not evidence**: `Evidence → Memory → Presentation`. The cover is a **derived artifact** alongside title / summary / topics / mentions — never canonical, always overridable, regeneratable, and never part of the source material. Delete it, regenerate it, override it — all harmless.

Word choice: **"Cover,"** not "Banner." Cover is human (book/album/photo-album covers); banner is UI. It reinforces "you're opening a memory," not "editing a record."

## 2 · Where the cover comes from — precedence (locked shape)

1. **User-selected (highest authority)** — an attached photo the user picks, *or* a curated cover the user chooses. Always wins.
2. **AI-selected curated** — the AI picks the best-fitting image from a **curated built-in library** (see §3). Recognition, not generation.
3. **Neutral default** — a tasteful default cover when nothing else applies.

Every memory gets a cover automatically; the user never has to think about it. Basic and Plus both get the full precedence — the tier line is about *suggestion quality*, not access (§5).

## 3 · Curated library, NOT image generation (the load-bearing decision)

The AI **chooses from a curated set**, it does not generate images. This is decisive for reasons beyond cost:
- **No hallucinated history** — an illustrative cover never pretends to be a photograph of the event. Trust preserved.
- **No copyright surface, no latency, no per-image cost** — the AI returns one token ("snow").
- **Recognition over generation** — the AI answers "which mood fits?", the North-Star-aligned job, not "invent a picture."

**The set (illustrative, ~10 mood themes):** mountains · forest · ocean · desert · meadow · snow · night sky · sunrise · abstract warm · abstract cool. **Seasonal/time variants** (Forest·Autumn, not just Forest) multiply variety without growing the AI's job — it picks a theme; the system resolves a variant (by memory date/season).

**Honesty rule — a cover must read as a *cover*, not a *record*.** The curated art stays evocative/illustrative (paper-cut / watercolor / muted register, per the Frame-4 target), never photographic. Two covers must never be visually confusable across the documentary/symbolic line: **a user-photo cover reads as "your photo"; a curated cover reads as clearly illustrative.** If a curated image looks like a real place, it makes a claim the clips don't support — the exact trust line this design protects.

## 4 · The AI contract

Trivial and nearly free — rides the existing organize pass (no separate call):

```
From the memory's transcript/summary, select the single best-fitting cover theme:
mountains · forest · ocean · desert · meadow · snow · night-sky · sunrise · abstract-warm · abstract-cool
Return one token. Do not invent; if nothing fits, return none (→ neutral default).
```

Honest Label holds: the cover reflects the *mood the clips describe*, chosen from a fixed set — it adds nothing to the memory's substance. Never generated during organization as a blocking step; the theme token is just another field the pass emits.

## 5 · Tiering (quality, never gating)

- **Basic** — every memory gets a cover automatically (user photo → AI-curated → default). The user never thinks about it. Full override available.
- **Plus** — the AI becomes a *creative assistant*: **suggests** a cover with a human line ("This memory feels like a quiet winter morning") and offers a few options to pick from. (Far-future, if image models are ever used: "Generate an illustration **inspired by** this memory" — never "generate the memory"; the wording keeps evidence/presentation distinct.)

Healthy line: Basic *removes work* (capture · organize · search · a nice cover); Plus *adds insight/personalization* (better summaries, better organization, better cover suggestions). Never "Basic doesn't get covers."

## 6 · Data model

The cover is a derived field on the memory — presentation, not evidence:

```
Memory
├── Title · Summary · Topics · Mentions   (existing derived artifacts)
└── Cover
      ├── source: enum { userPhoto, curated, aiSuggested, default }
      └── assetRef: String?   // curated theme+variant id, or a clip/photo reference for userPhoto
```

- **Schema:** new optional fields on `JournalEntry` (`coverSource`, `coverAssetRef`) → CloudKit private DB, developer-unreadable, additive migration + **one deploy** (`recycledAt`-style). Curated art itself is **app-bundled** (not user data, not synced) — only the *choice* syncs.
- **Custody unchanged:** a user-photo cover references an existing clip/media the user already owns in iCloud; no new custody surface.
- **Derived-artifact rules inherited:** regenerate freely, override always wins, delete → falls back down the precedence chain.

## 7 · UX surface

- **Memory detail:** the cover sits at the top of the memory (the Frame-4 layout). A quiet **"Choose Cover…"** affordance (in the ✎ edit surface, not floating chrome).
- **Options, hierarchy per what's available:**
  - Has attached photos → `Auto (AI selected)` · `Use a photo…` · `Choose Cover…` · `None`
  - No photos → `Auto` · `Choose Cover…` · `None`
- **Plus** adds a "Suggested" row with the mood line + a few theme options + regenerate.
- Never blocks anything; a memory with no cover shows the neutral default, not an empty state.

## 8 · Why not 1.0

- Adds a CloudKit schema deploy right as Apple's account migration just cleared — avoid stacking deploys on the submit window.
- The core loop (capture → organize → browse → search) ships without it; a cover is delight, not function.
- It's a clean, self-contained 1.1 headline ("memories that feel like places") — better as a visible upgrade than a rushed pre-submit addition.

## 9 · Open questions (for when scheduled)

- **OQ-1 · Library size + art direction.** Final theme count, the illustration style (paper-cut vs watercolor vs muted-flat), and who produces the art. The style *is* the honesty guarantee (§3), so it's a real design commission, not clip-art.
- **OQ-2 · Seasonal variant resolution.** By memory `capturedAt` date? By hemisphere? Keep simple (date→season) v1 of the feature.
- **OQ-3 · User-photo cover vs. clip.** Does "use a photo" reference an existing photo clip in the memory, or allow any library photo? Lean: only a photo already in the memory (keeps evidence/presentation coherent).
- **OQ-4 · Cover in list/card contexts.** Does the cover appear on memory *cards* (Memories list) too, or only in detail? A thumbnail-cover on cards is a bigger visual change to the reflective list — separate call.

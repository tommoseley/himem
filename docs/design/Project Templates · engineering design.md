# Project Templates — Engineering Design Doc

> **Status:** PROPOSED · post-v1 · not scheduled. Design authority: this documents a *candidate*, not a locked decision. No code until it's scheduled and the open questions below are ruled.
> **Author:** design/spec side · **Date:** 2026-07-20 · **Origin:** the 45-day-trip use case (exposed the want for per-project operating patterns + organizing lenses).
> **Companion specs:** `Projects · MVP spec.md` (§ "Post-v1 candidate: Project templates"), `AI Organize · spec.md` (organize prompt contract), `HiMem · evidence and context.md` (ontology), `Kingfisher · North Star.md` / `Kingfisher Language.md` (voice + Honest Label).

---

## 1 · Problem

A Project today is a **container + a goal** — it connects memories (many-to-many) and can run *Find the thread*. It carries no notion of *what kind of continuity* the user is trying to preserve, so every project is organized by the same generic pass and assembled by the same manual gestures.

The 45-day trip surfaced the gap. A trip is naturally **one memory per day**, its memories **all belong to the trip**, and its clips **presumably belong to the current day**. Doing that as-is works but asks the user to re-establish the same context every day for 45 days: gather today's clips, make a memory, place it in the trip, hope the generic organizer titles it around the day's story rather than the timestamp. The friction isn't any single step; it's the *repetition of context the app could hold*.

The deeper miss: **a Project could tell HiMem what to notice.** A family-history project cares about people, relationships, and conflicting recollections; a creative project cares about alternatives and decisions; a trip cares about chronology, geography, and the offhand thing someone said in the car. Today all four get the same organize prompt.

## 2 · The idea, precisely

A **Project Template** gives a project two things:

1. **A default operating pattern** — expected cadence (memory-per-day / per-session / per-milestone), how loose clips are presumed to group, suggested metadata, and prompts. *Helpful defaults the user can ignore*, never a rigid workflow.
2. **An organizing lens** — a template-specific fragment injected into the AI organize prompt, so the project changes *what the model surfaces*, not just how the folder is labeled.

The reframe that makes templates more than starter folders:

> A Project stops being a **bucket** and becomes a **lens**.

### 2a · Three distinct axes (refinement, July 20 2026)

"Template" is really a bundle of **three independent vectors** that overlap but should stay separable — a project may set any subset:

| Axis | Question it answers | Example (the trip) | Feeds |
|---|---|---|---|
| **Structure** | How is the raw material grouped? | One memory per day | bench grouping hint + "continue today's memory" |
| **Lens (intent)** | What is this *about* — what should be noticed? | "A shared retirement journey" | the organize-prompt fragment (§6) |
| **Potential creations** | What might it eventually become? | Travel journal · essays · photo book | Studio/Create outputs (Phase 4), rollup prompts (Phase 3) |

Why keep them distinct: a built-in **template** is a convenient *preset* of all three (Trip = per-day + travel-lens + journal/essay outputs), but the axes are orthogonal — a user might keep a template's structure while writing their own lens ("not documenting attractions — Judi and me experiencing retirement"), or adopt no template yet still declare a creative intent. Collapsing them into one field would force a choice the model doesn't require.

The **lens is where creative intent lives**, and it's what makes the same clips support *many* outputs without reorganizing from scratch: a Day-14 memory, the Yellowstone section, an essay on what retirement travel feels like, photo captions, and the full 45-day narrative are all **views over the same evidence**, shaped by lens + potential-creation, not separate reorganizations. This is the bridge from Connect (organize/synthesize) to Create (Studio outputs): the project becomes *the place where capture, continuity, and eventual creation meet* — a materially richer definition than "a collection of related memories."

Data-model consequence (refines §5.2): the three axes are separate fields, not one `templateId`. A `templateId` is a **preset that seeds all three**, but `structure`, `lensCustomization`, and `potentialCreations` are independently editable and independently nullable. See §5.2.

## 3 · Goals / Non-goals

**Goals**
- G1 — A new project can adopt a template that carries defaults + an organizing lens.
- G2 — The organize pass for a memory *in a templated project* is shaped by that template's lens, composed on top of the core prompt.
- G3 — A one-sentence user customization further tunes the lens (`"This trip is about Judi and me, not documenting every attraction"`).
- G4 — Everything degrades to today's behavior: no template = exactly the current Project.
- G5 — Honest Label survives. A lens changes *emphasis and what's noticed*, never invents content the clips don't contain.

**Non-goals (explicit)**
- N1 — Not a rigid workflow engine. A template never *blocks* a gesture or forces a cadence.
- N2 — Not a "travel journal feature." Travel is the *first template*, not a special-cased surface.
- N3 — Not auto-placement of new memories into projects at capture time (separate deferred item; see `Projects · MVP spec.md` "Out of scope").
- N4 — Not final-output generation (photo book, timeline export) — that's Studio/Create tier, downstream.
- N5 — No change to the ontology. Clip = evidence, Memory = context, Project = intent, all many-to-many. A template is metadata *on* a project.

## 4 · Where it sits in the ontology

Unchanged: `Clip (evidence) → Memory (context) → Project (intent)`. A template is a **property of a Project** that (a) seeds project defaults and (b) contributes a prompt fragment to the organize pass of member memories. It does not create a new object type and does not alter edge semantics.

## 5 · Data model

All authoritative data stays in the user's **CloudKit private DB** (custody rule unchanged — no user content in HiMem's custody). Two shipped-vs-built options:

### 5.1 Template definitions (the catalog)
Built-in templates are **app-bundled static definitions**, not user data — a versioned JSON/Swift catalog compiled into the app. No CloudKit entity for the catalog itself.

```
TemplateCatalog (bundled, versioned)
  templateId: String        // "trip", "family-history", "creative", "health", "renovation", "conference"
  version: Int
  displayName: String
  cadence: enum { perDay, perSession, perMilestone, perStory, freeform }
  clipGroupingHint: enum { sameDay, sameSession, none }
  organizeLensPromptKey: String   // resolves to the lens fragment (see §6)
  suggestedPrompts: [String]      // daily/rollup prompts shown in-project
  suggestedMetadata: [enum]       // route, place, people, highlights…
```

### 5.2 Template binding (on the Project — CloudKit)
A project records **which** template it adopted and the user's one-sentence customization. Minimal, additive, one deploy.

```
Project (CloudKit private DB) — NEW optional fields:
  templateId: String?          // nil = untemplated; a PRESET that seeds the three axes below
  templateVersion: Int?        // pin the lens version the project was created under
  structureCadence: String?    // axis 1 — perDay/perSession/... (seeded by template, independently editable)
  lensCustomization: String?   // axis 2 — the creative-intent sentence (the organize-prompt lens)
  potentialCreations: [String]? // axis 3 — journal/essays/photo-book/... (drives Studio outputs + rollup prompts)
```

**Three-axis note (see §2a):** `templateId` is a *preset* that fills the three axis fields at creation; the axes are then **independently editable and independently nullable**. A user can keep a template's `structureCadence` while rewriting `lensCustomization`, or set a lens with no template at all. Do not model the three as one opaque blob keyed only by `templateId`.

**Decisions embedded:**
- Templates are **app-versioned**, bound-by-id on the project. The project pins `templateVersion` so a later catalog change doesn't silently re-organize old memories (see OQ-3).
- `lensCustomization` is the *only* free-text field and it is user content → private DB, developer-unreadable, like everything else.
- **No new entity, no per-memory template field.** A memory inherits its lens from its project(s) at organize time (see §6.3 for the multi-project case).

### 5.3 Migration
Purely additive optional fields on `Project`. Lightweight Core Data migration (`shouldMigrateStoreAutomatically` + `shouldInferMappingModelAutomatically`, matching the `recycledAt` precedent). One CloudKit schema deploy (Dev → verify → Prod ceremony). Existing projects: `templateId == nil` → identical to today.

## 6 · The organizing lens (AI contract)

This is the load-bearing half and the reason templates aren't decorative.

### 6.1 Prompt composition
The organize pass for a memory becomes an ordered composition:

```
[ core organize prompt ]              // Honest Label, voice, POV, cadence — unchanged, always first
  + [ project-template lens fragment ] // from templateId → organizeLensPromptKey, if the memory is in a templated project
  + [ project goal + lensCustomization ]  // the specific project's intent + the one-sentence tuning
  + [ existing topics + mentions palette ] // unchanged (palette discipline)
  + [ the captured material ]
```

The core prompt **always leads and always wins**. The lens can shift *emphasis* (what to notice, what to title around) but cannot override Honest Label, the descriptive-not-interpretive rule, the POV rule, or the palette contract. Guardrail: the lens fragment is **additive emphasis only** — phrased as "prefer / emphasize / notice," never "invent / infer / conclude."

### 6.2 Example lens fragments (illustrative, not final copy)
- **Trip** — "Preserve chronology and geography. Treat each day as one memory. Emphasize experiences, surprises, conversations, and sensory detail. Title around the day's actual story, not the date. Retain places and route."
- **Family history** — "Prioritize people, relationships, dates, and uncertainty. Preserve conflicting recollections rather than resolving them. Do not smooth contradictions into a single narrative."
- **Creative** — "Preserve ideas, alternatives, decisions, and how thinking evolved. Keep rejected directions."
- **Health** — "Emphasize changes, patterns, symptoms, and interventions over time. Do not force events into a story arc."

Each fragment is validated against the Honest-Label rubric in the same calibration harness used for the core prompt (`OnDeviceOrganizerCalibrationTests`), with per-template fixtures.

### 6.3 Multi-project memories (a real edge)
A memory belongs to **0–N projects**. If a memory is in two templated projects with different lenses, whose lens applies? Ruled default (see OQ-2): **the lens applies at the moment of an *explicit* organize/reorganize invoked from within a project context** — the lens is the *invoking* project's. A memory organized from the generic Memories surface uses the **core prompt only** (no lens), because there's no single project intent in play. This keeps the composition deterministic and avoids blending contradictory lenses.

### 6.4 Tier
The lens rides the existing organize tiers: **Free** = manual organize (on-device where supported), lens included in the on-device prompt; **Plus** = automatic + frontier. Templates themselves (adopting one, the defaults, the prompts) are **free** — they're structure, not intelligence. This matches "gate intelligence, not counts." *Find the thread* remains the Plus/Connect capability; a template can supply it a richer rollup prompt, but running it stays Plus.

## 7 · UX surface

### 7.1 Adopting a template
At **new-project** creation (the name+goal sheet — reached from the inline row or the Projects-list FAB, per the context-aware FAB lock), add an optional **template picker**: a small row of template chips + "None" (default). Picking one pre-fills nothing destructive — it seeds defaults and reveals the one-sentence lens field ("What's this project really about?"). "None" = today's blank project.

### 7.2 In-project
- Suggested prompts appear as **quiet, ignorable** affordances (Crucible voice), never a required form.
- The cadence hint informs the "start today's memory / continue today's memory" suggestion, but the user can always make any memory they want.
- The one-sentence lens is editable from the project's **✎ Edit** sheet (alongside name + goal).

### 7.3 What a template must never do
Block capture, force a naming step, gate a memory behind "which day is this," or auto-file without disclosure. Perishability wins: capture stays one action from anywhere; templates shape *reflection*, never *capture*.

## 8 · Phasing

- **Phase 0 (this doc):** design + ruling on open questions. No code.
- **Phase 1 — binding + defaults (no AI):** `Project.templateId/version/lensCustomization` fields + migration + deploy; template picker at create; in-project prompts + cadence hints. Ships value without touching the organize prompt. Verifiable, low-risk.
- **Phase 2 — the lens (AI):** prompt composition + per-template lens fragments + calibration fixtures; on-device + frontier. This is the load-bearing half; gated on Phase-1 stability and a green Honest-Label rubric per template.
- **Phase 3 — rollup lenses:** template-specific *Find the thread* rollup prompts (route/highlights for trips, timeline for family history). Plus-tier.
- **Phase 4 (Studio/Create, far):** final outputs — trip journal, photo book draft, shareable recap.

## 9 · Risks

- **R1 · Lens vs. Honest Label.** A lens that emphasizes "story" can tip the model toward embellishment. Mitigation: additive-emphasis-only phrasing; core prompt leads; per-template rubric fixtures; ship a template's lens only when it passes the same calibration bar as the core.
- **R2 · Rigid-workflow creep.** Templates could accrete required steps. Mitigation: N1 is a hard non-goal; every template affordance is ignorable by construction; review any template addition against "does this ever block a gesture?"
- **R3 · Template versioning drift.** A catalog update could retro-change how old memories read. Mitigation: projects pin `templateVersion`; re-organize uses the pinned version unless the user opts into the new one (OQ-3).
- **R4 · Multi-project lens ambiguity.** §6.3 rules it, but it needs a decision, not a guess (OQ-2).
- **R5 · Scope gravity.** "Templates" invites endless template requests. Mitigation: ship 1–2 (trip + one other) as the proof; the catalog is versioned and additive so more come later without rework.

## 10 · Open questions (need rulings before Phase 1)

- **OQ-1 · Launch set.** Which templates ship first? Recommendation: **Trip** (the proven use case) + **None**; add family-history/creative/health as fast-follows once the lens rubric holds.
- **OQ-2 · Multi-project lens.** Confirm §6.3 (lens = invoking project's; generic surface = core-only), or prefer another rule.
- **OQ-3 · Version pinning.** On a catalog update, do templated projects stay pinned to their creation-version lens (recommended) with an opt-in "use the updated lens," or float to latest?
- **OQ-4 · Custom/user templates.** v-later: can users save their own template from a project? Out for the first cut; note if the data model should leave room (it does — `templateId` could point at a user-defined catalog entry in the private DB later).
- **OQ-5 · Cadence enforcement strength.** Is the cadence purely a *suggestion* for the "continue today's memory" hint, or does it also bias clip grouping on the bench? Recommendation: suggestion only for v1 of templates; bench grouping stays time+place as today.

## 11 · What this doc does NOT change

The v1 ship path. Templates are post-launch. The ordinary workflow — capture all day → review the workbench → consolidate into one memory → place it in the trip project — already works, and the 45-day trip is the intended real-world stress test of exactly that before any of this is built.

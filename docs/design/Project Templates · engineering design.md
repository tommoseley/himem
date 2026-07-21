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

### 4a · Meaning-in-context lives on the edge (recursive-edge principle, July 20 2026)

A memory can belong to **0–N projects with different templates**, and the same memory *means something different in each*. Example: "Stopped at Devil's Tower, took this picture" is a **travel-day highlight** in *2026 Road Trip* and a **session/scouting entry** in *Astrophotography Log* — same evidence, two meanings.

The resolution the ontology is already shaped for: **context-specific meaning belongs on the edge, not the object — recursively.**
- Clip is evidence; its meaning *in a memory* lives on the **clip×memory edge** (the annotation, already built).
- Memory is context; its meaning *in a project* lives on the **memory×project edge** — the project-scoped lens view + (later) the domain-metadata extraction.

Consequences (bind the domain-metadata design, §12):
- **The memory stays single and authoritative** — one clip set, one core summary (lens-free or lightly lens-shaded), its own topics/mentions. Never two contradictory summaries; there is always one canonical memory.
- **Domain metadata is EDGE-scoped, not memory-scoped** — a memory in two templated projects carries *Road-Trip*'s extraction on one edge and *Astro-Log*'s on the other; neither overwrites the other because they live on different edges. This directly resolves the §12 "which schema applies?" collision and supersedes §6.3's earlier "lens = invoking project's" phrasing (that reached for edge-scoping but put it on the pass, not the carrier).
- **Honest Label holds on every edge** — each edge's view draws only from the same clips; the schema decides *what to look for*, never what to invent.
- **Cost:** extraction runs per (memory × templated-project) pairing, a Plus/Connect characteristic; fine, since most memories are in 0–1 projects and the multi-project-different-schema case is the rich exception.
- **v1 carrier note:** `MemoryClipEdge` already carries per-edge payload (annotation); the **memory×project edge is today a plain membership link** (`JournalEntry.projects`, Nullify many-to-many) with no payload. When domain schemas are built, the per-project metadata/lens-view must land on a **memory×project edge entity** from day one — putting it on the memory would be the migration trap. Building that edge entity is itself part of the §12 phase, not v1.

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
- **Copied-vs-referenced-vs-override (added July 20 2026 — resolves template-update ambiguity):** `structureCadence` and `potentialCreations` are **copied defaults** (seeded from the catalog at create; a later catalog change does NOT replace them). The catalog's **organizing + rollup prompts are referenced** (resolved via `templateId` + pinned `templateVersion`, so the version controls which prompt is active). `lensCustomization` is a **user override** (never touched by catalog updates).
- **`potentialCreations` is NOT a Phase-1 CloudKit field.** Nothing consumes it until Studio/Create exists (today the app is Free/Plus only; Create is future-facing UI). Keep creation possibilities in the **bundled template definition** for the first cut; add a project-level field only when something reads it. Don't ship a synced field whose only purpose is to preserve a future idea.
- `lensCustomization` is the *only* free-text field and it is user content → private DB, developer-unreadable, like everything else.
- **No new entity, no per-memory template field.** A memory does **not** inherit a lens into its canonical fields (see §6.3); project-scoped interpretation waits for the edge carrier (§4a).

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

### 6.3 Multi-project memories (a real edge) — lens does NOT touch the canonical memory (revised July 20 2026)

A memory belongs to **0–N projects**, and today the organizer writes results back to the memory's *single* canonical fields (title/summary/topics/mentions). There is no project-scoped version of those fields. So a lens applied at organize time would make the **last project used to reorganize win everywhere** — reorganize a road-trip memory from the trip project and the astro project now sees the travel interpretation, and vice-versa. That's a semantic context-leak, not a deterministic rule.

**Ruling (supersedes the earlier "invoking-project's lens" phrasing; aligns with §4a edge-scoping):** a project lens **may interpret a memory in the project's context, but must never silently rewrite what the memory is everywhere else.** Therefore:
- **Canonical memory organization stays lens-free** until a **project-scoped carrier** exists (the memory×project edge entity, §4a) to hold project-specific interpretation.
- **Lenses are used first only where the output is already project-scoped** — *Find the thread* (project rollup) interprets the project without rewriting any member memory. That is the safe home for a lens today.
- A memory organized from the generic Memories surface uses the **core prompt only** — unchanged.

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

## 8 · Phasing (revised July 20 2026 — project-scoped output before lens-on-memory)

Key reorder: **project-scoped intelligence (Find the thread) comes before any lens that touches a memory**, because it interprets the project without rewriting member memories (§6.3). Lens-on-canonical-memory is deferred to last and **gated on the edge carrier existing** (§4a).

- **Phase 0 (this doc):** design + rulings. No code.
- **Phase 1 — project pattern (no AI on memories):** `Project.templateId/version/structureCadence/lensCustomization` fields + migration + deploy; template picker at create; cadence hints + "continue today's memory" (builds on the existing `.createMemoryInProject` FAB path); suggested prompts. **Honest scope:** this is *foundation + modest UX value* — it improves project setup and daily continuation, but with automatic placement out (N3) and bench grouping unchanged (OQ-5) it does **not** by itself remove the 45-day shaping/placing repetition. Don't oversell it as the trip solution.
- **Phase 2 — project intelligence (lens, project-scoped only):** template-aware *Find the thread* — trip route/highlights/recurring themes; family-history chronology + uncertainty; creative decisions + rejected directions. The lens lives here first because the output is the project rollup, not the memory. Plus-tier.
- **Phase 3 — Create (Studio, far):** journal / essay outline / photo-book structure / recap.
- **Phase 4 — project-scoped memory interpretation:** *only after* a memory×project edge carrier exists (§4a) to hold per-project derived interpretation/metadata. This is where a lens may finally shade an individual memory's view — on the edge, never on the canonical memory.

## 9 · Risks

- **R1 · Lens vs. Honest Label.** A lens that emphasizes "story" can tip the model toward embellishment. Mitigation: additive-emphasis-only phrasing; core prompt leads; per-template rubric fixtures; ship a template's lens only when it passes the same calibration bar as the core.
- **R2 · Rigid-workflow creep.** Templates could accrete required steps. Mitigation: N1 is a hard non-goal; every template affordance is ignorable by construction; review any template addition against "does this ever block a gesture?"
- **R3 · Template versioning drift.** A catalog update could retro-change how old memories read. Mitigation: projects pin `templateVersion`; re-organize uses the pinned version unless the user opts into the new one (OQ-3).
- **R4 · Multi-project lens ambiguity.** Resolved (§6.3 / OQ-2): lens never touches the canonical memory; project-scoped output only until the edge carrier exists.
- **R5 · Scope gravity.** "Templates" invites endless template requests. Mitigation: ship 1–2 (trip + one other) as the proof; the catalog is versioned and additive so more come later without rework.

## 10 · Open questions (need rulings before Phase 1)

- **OQ-1 · Launch set.** Ruled (July 20): **Trip + None**; family-history/creative/health as fast-follows once the lens rubric holds.
- **OQ-2 · Multi-project lens.** Ruled (July 20): **reject** any invoking-project lens on the *canonical* memory — the last-reorganized project would win everywhere. Lenses apply only to **project-scoped output (Find the thread)** until the memory×project edge carrier exists (§6.3, §4a). Generic surface = core-only.
- **OQ-3 · Version pinning.** Ruled (July 20): **pin** to the creation-version behavior; allow an explicit opt-in upgrade later; never silently change the meaning of existing projects.
- **OQ-4 · Custom/user templates.** Ruled (July 20): **defer completely.** Keep `templateId` extensible (could point at a user-defined private-DB catalog entry later); design nothing now.
- **OQ-5 · Cadence enforcement strength.** Ruled (July 20): **suggestion only** — drives the "continue today's memory" hint; bench grouping stays time+place, unchanged.

## 11 · What this doc does NOT change

The v1 ship path. Templates are post-launch. The ordinary workflow — capture all day → review the workbench → consolidate into one memory → place it in the trip project — already works, and the 45-day trip is the intended real-world stress test of exactly that before any of this is built.

---

## 12 · Extension: domain metadata schemas (logged July 20 2026 — LATER than templates; own phase)

The trip and an **astrophotography log** use the same HiMem machinery but care about completely different things — an astro session wants target, location + Bortle class, moon illumination, focal length / aperture / ISO / exposure, frame count, focus method, what failed, what to change next time; organized as **Intent → Conditions → Setup → Captures → Results → Lessons → Next attempt**, not as a narrative. Title + summary + topics + mentions stop being enough once a project is *domain-aware*. This is the extension where a template stops being "a prompt + defaults" and becomes a **domain model**.

### 12.1 The shape
- **A template defines a typed metadata schema** (lightweight JSON-Schema-like: keyed fields with `type` + `description`), *not* just a prompt.
- **The project** stores the template binding + project-specific config.
- **A memory** stores *extracted values* conforming to that schema (JSON-backed, `schemaVersion`-stamped).
- **Clips** remain the raw evidence, untouched.
- **Creation + project intelligence** consume both the narrative *and* the structured metadata — enabling cross-session pattern surfacing ("best results with the 14mm came at f/2 · 15s"; "failed sessions involved late scouting").

The organize prompt becomes **partly generated from the schema**: "extract these fields where the captured material supports them; do not invent missing values; preserve uncertainty; keep each value traceable to its clip."

### 12.2 Three rules (non-negotiable if this is built)
1. **Metadata is optional.** A memory must still work beautifully with zero fields extracted. Never a form gate; never a required completion. (Perishability + "capture asks nothing but the thought.")
2. **Every extracted value is traceable to clips.** A metadata value carries a reference to the clip/segment it came from. Untraceable AI-filled metadata is how a structured layer becomes untrustworthy — and it's a direct Honest-Label requirement (nothing the clips don't contain). No provenance → don't store it.
3. **Schemas are versioned.** `schemaVersion` per template; adding fields must never break old memories. Old memories read under the version they were extracted with; re-extraction is explicit.

### 12.3 Why it's a *later* phase than templates (§8), not part of them
- It's an **AI-contract + storage-model change of a different magnitude**: typed extraction, per-memory JSON metadata with provenance, cross-session aggregation. Templates (§1–11) deliver value with three optional `Project` fields and a prompt fragment; this needs a schema registry, a metadata store on the memory, and a provenance link to clips.
- **Storage/custody:** the extracted metadata is user content → CloudKit private DB (developer-unreadable), same custody rule as everything else. Whether it's a typed Core Data structure vs. a validated JSON blob on `JournalEntry` is an open call (OQ-6) — but "ungoverned JSON blob" is explicitly rejected; the schema governs it.
- It turns HiMem into a platform for **specialized memory systems without hardcoding each specialty** — powerful, and exactly why it must not be rushed: an untyped or un-versioned first cut would be a migration trap.

### 12.4 New open questions (added to §10)
- **OQ-6 · Metadata storage form.** Typed Core Data entity per schema vs. a single validated-JSON attribute on `JournalEntry` (schema-checked at write). Lean: JSON attribute + a schema validator (flexible, versionable, no per-template migration), *provided* provenance + validation are enforced in code.
- **OQ-7 · Provenance model.** How a metadata value references its source clip/segment (edge? inline clipId + char range?). Must exist before any extraction ships (rule 2).
- **OQ-8 · Cross-session aggregation.** Where pattern-surfacing lives (a project-level pass over member metadata) and its tier (almost certainly Plus/Connect or Studio) — and it must obey Honest Label (describe the pattern, don't prescribe).
- **OQ-9 · Schema authoring.** Built-in schemas only at first; user-defined schemas are a far-later Studio-tier idea (ties to OQ-4 user templates).

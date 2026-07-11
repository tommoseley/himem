# HiMem · the shaping model

*The mental model the whole product hangs on. Codified July 8 2026, after a week of dogfood insights that all turned out to be one model surfacing in five places. Studio-adjacent: this is HiMem-specific, but the shape (capture → hold → place → build) is a candidate pattern for any Kingfisher product that turns fragments into things.*

*Name-agnostic on purpose. The one open naming question is flagged at the end; the model below is true whatever we end up calling the holding surface.*

> **Ontology update (July 8 2026):** the one-clip-one-memory assumption below is superseded by `HiMem · evidence and context.md` (locked for v1). A clip is **evidence** that can be referenced by **0–N memories** (many-to-many); *placed* now means "referenced by ≥1 memory," and "Where does this belong?" can be asked again for additional placements. The flow, states, and placement question below all still hold — read "placed in a memory" as "placed in **at least one** memory."

---

## The finding

HiMem started as a **capture app**. Capture is now nearly solved — voice, Watch, Siri, on-a-roll, idle-gap sessioning. What's actually emerging, and what the next phase of the product is about, is **shaping**: taking fragments of life and gradually turning them into memories, projects, and eventually stories worth keeping.

The interaction model was built for the capture product. The philosophy has outgrown it. This document draws the model the philosophy actually implies, so we stop patching screens and start building against one shape.

---

## The model

```
   Record
     │            a thought, a photo, a note — one action, from anywhere
     ▼
   Session          clips close to each other in time = one sitting
     │              (idle-gap sessioning; silence is the boundary)
     ▼
 ┌─────────────────────────────────────────────┐
 │  THE HOLDING SURFACE                          │   everything not yet placed:
 │  (working name: Workbench — see naming note)  │   new clips · sessions ·
 │                                               │   clips removed from a memory ·
 │  one question for everything here:            │   AI cluster suggestions
 │      “Where does this belong?”                │
 └─────────────────────────────────────────────┘
     │
     ▼
   Memory           emerges from related material — it is not "made"
     │
     ▼
   Project (optional)   something you're building over time — continuity, not a folder
```

The old model had **Captured Clips** where the holding surface sits — an *inbox*, a queue to zero. The shift is from *inbox* to *holding surface*: a place where unplaced things **wait to be placed**, not a backlog demanding to be cleared.

---

## The three object states

The model needs only three states, and they're the whole vocabulary:

- **Unplaced** — on the holding surface. Arrived from capture, or returned from a memory. Not "pending," not "unprocessed," not "waiting." Simply *available, not yet placed.*
- **Placed** — inside a memory. The clip answered "where does this belong?" with a memory (new or existing).
- **In a project** — a *placed* memory that's also part of something being built over time. Orthogonal: a memory is placed first, and *may or may not* join a project. (Topics and projects are the two orthogonal axes; a memory has one topic and 0–N projects — unchanged.)

A clip is *unplaced* (referenced by no memory) or *placed* (referenced by **one or more** — per `HiMem · evidence and context.md`). "Remove from a memory" removes one edge; the clip returns to *unplaced* only if that was its last. Nothing is ever destroyed by placement changes — destruction is a separate, deliberate act (Delete → Recently Deleted).

---

## The one question

Everything on the holding surface answers **"Where does this belong?"** — the single placement primitive (see `Kingfisher Language.md`). The possible answers *are* the model:

- **A new memory** — this starts something.
- **An existing memory** — this joins something.
- **A project** — (via its memory) this is part of something I'm building.
- **Nowhere yet** — stays unplaced. A legitimate, guilt-free answer; the surface is a bench, not a queue.

The UI never asks the user to *organize*. It helps them *place*. That single reframe is why the whole model feels calmer than an inbox.

---

## Walking every interaction through the model

The test of a model is whether every flow gets *simpler* under it. Each row below states the interaction and what the model makes it become. If any felt more contorted than today, the model would be wrong.

| Interaction | Under the shaping model | Simpler? |
|---|---|---|
| **Watch / Siri capture** | Creates unplaced clips; idle-gap groups them into a session on the holding surface. Capture never asks where — placement is always later. | ✓ same, clarified |
| **Delete a clip** | Destruction, not placement. Full-width Delete in the clip's edit state → Recently Deleted. Distinct from "return to holding surface." | ✓ cleanly separated |
| **Remove a clip from a memory** | Placed → unplaced. The clip *returns to the holding surface*, whole. Same "Where does this belong?" sheet, answered later. | ✓ becomes one primitive |
| **Move a clip between memories** | placed(A) → "Where does this belong?" → placed(B). Never a bespoke "move" verb; it's re-placing. | ✓ same primitive |
| **AI cluster suggestion (Sort)** | An observation *on the holding surface* — "these seem related." Never auto-places; it proposes an answer to "where does this belong?" for a set. Human concludes (Review). | ✓ fits, no new concept |
| **Search** | Searches placed *and* unplaced material — the words exist from capture regardless of state. Finding something unplaced is a nudge to place it, never a scold. | ✓ state-agnostic |
| **Notification** | Only "things arrived on your holding surface" (passive). Never "you have N unplaced" as pressure — arrival, not backlog. (Channel B already retired.) | ✓ aligns with retirement |
| **Badge** | Count of unplaced items = "materials on the bench," not "inbox to zero." This is exactly why the badge's meaning is *under review pending the holding-surface framing* — it's defensible as "materials here," indefensible as "unprocessed." | ✓ resolves the badge question |
| **Reflection** (future) | The holding surface is where raw material waits; reflection is a *different* act on *placed* memories (notice → remember → decide). The model keeps them distinct: shaping fills the memory; reflection revisits it. | ✓ gives reflection a clean seam |

Every flow either stays the same or collapses into the single placement primitive. Nothing gets harder. That's the signal the model is right.

---

## What this reframes (already decided, now explained by one model)

- **Projects are continuity, not containers** — a memory is *placed* first, and joining a project is a separate optional act of "building something over time." (Locked in `Projects · MVP spec.md` framing note.)
- **A memory emerges, it isn't "made"** — hence "Make a Memory" retired for "Where does this belong?" / "Create one memory." (Locked in `Kingfisher Language.md`.)
- **The holding surface is a bench, not a queue** — no guilt, no "clear it," badge-as-materials. (Drives the notification + badge decisions.)
- **Capture defers all structure** — the model puts *every* placement decision downstream of capture, which is the perishability principle expressed as an architecture.

---

## The name question — resolved (July 8 2026)

The naming problem **dissolved** rather than got answered. We were hunting for a product name for the holding surface (Workbench / Captured / In Progress / Unplaced). The resolution: there is no separate surface to name.

**The holding surface is the default view of a permanent, first-class `Clips` page** — one of the three primary objects (Clips · Memories · Projects = Evidence · Context · Intent). "Workbench" survives only as an **internal metaphor for a state**, never user chrome. A clip isn't "on the Workbench"; it's simply *not yet connected*, shown in the default view of Clips. No new noun to teach.

- **`Clips`** is the UI word; **Evidence** is the architecture word (same UI/architecture split as Memories/Narrative). "Captured Clips" is retired — it named an *event*; the page is about what *exists*.
- The default view shows AI suggestions + everything not-yet-connected (no "why" exposed); it reveals to All / Voice / Photos / Notes. Capture returns to Clips.

---

## Status

- **Model:** locked July 8 2026.
- **Primary objects + Clips-page framing:** locked July 8 2026 (see CLAUDE.md · Phone, and `HiMem · evidence and context.md`).
- **Next build move (when picked up):** the three-tab nav (Clips · Memories · Projects), cold-launch-to-Memories with session-scoped last-tab, and the Clips page (suggestions-plus-loose default, clip-as-primary-object detail with "Referenced in"). Nothing here forces an immediate rebuild — it's the map every shaping-surface decision now checks against.

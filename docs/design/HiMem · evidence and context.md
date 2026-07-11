# HiMem · evidence and context

*The ontology HiMem is built on. Locked July 8 2026. This is the deepest of the HiMem docs — `North Star` is why Kingfisher exists, `Kingfisher Language` is how it speaks, `the shaping model` is how the product flows, and **this is what the product is made of.** Studio-relevant: the evidence→context→creation layering is a candidate foundation for everything Kingfisher builds.*

*Decision that produced it (July 8 2026): adopt this ontology in **v1**, not as a v2 upgrade. HiMem hasn't shipped; baking the correct model in now avoids a migration that would jar a real user base later. The **ontology is locked for v1**; the full creator-facing surface is **staged** (see § v1 scope). Nothing here forces us to build every feature before launch — it forces us not to foreclose them in the schema.*

---

## The law

**A clip is evidence. Everything else is interpretation.**

A voice recording, a photo, a video, a typed note — with its transcript, timestamp, and location — records *what happened*. That never changes. Titles, summaries, topics, memories, projects, reflections are all *context*: what the evidence **means**, which depends on why you're looking at it and when.

HiMem doesn't store memories. **It stores evidence, and lets meaning grow wherever it belongs.**

This is the general law under principles we already locked: *audio is the source of truth*, *the transcript is derivative*, *Honest Label*. Those were three consequences of one idea we hadn't named. Now it's named.

---

## Three layers

| Layer | What it is | Mutability | Examples |
|---|---|---|---|
| **Evidence** | The primary source — what actually happened | **Immutable** (see transcript note) | Voice clip, photo, video, note · transcript · time · location |
| **Context** | Interpretation of evidence — what it means, and where | **Mutable, grows over time** | Memory, title, summary, topics, project membership, **annotations**, reflections |
| **Creation** | Artifacts built from context, for an audience | New works | (Studio, later) article, talk, family history, photo essay |

Every operation in any Kingfisher product answers one question: *am I preserving evidence, adding context, or creating something new?* Those are three fundamentally different acts, and keeping them separate means **we never overwrite history with interpretation** — the mistake most knowledge systems make.

---

## The core structural change: meaning lives on the edge

The interpretation does **not** live on the clip. It lives on the **relationship between a clip and a memory.**

```
                 ┌───────────────────────────── Memory: "CIA Dinner"
                 │  edge annotation: "Best meal we've had in years."
                 │
   Clip ─────────┼───────────────────────────── Memory: "Leadership"
   (evidence)    │  edge annotation: "Notice how comfortable he was
   waiter on     │   saying 'I don't know.' Expertise without ego."
   Basque        │
   cheesecake    └───────────────────────────── Memory: "Active listening"
                    edge annotation: "I remembered every detail because
                     I was recording instead of trying to memorize."
```

Same clip, three memories, three meanings, **nothing duplicated.** The evidence is stored once; each edge carries its own interpretation.

### Data model (the part that must be right in v1)

- **Clip ↔ Memory is many-to-many.** A clip can be referenced by **0–N memories**; a memory references **1–N clips**. *(This supersedes the earlier one-clip-one-memory assumption — see reconciliations.)*
- **The join is an associative entity, not a bare link.** The edge carries: an optional **annotation** ("why this matters *here*"), the clip's role/order within that memory, and the timestamp of the association (so "added later" is knowable). This is what makes reflection and cross-reference first-class without new object types.
- **Evidence is stored once.** No copy is made when a clip joins a second memory — both memories point at the same evidence. Deleting one edge never touches the evidence or the other edges.

This is the historian's model, not the note-taker's: a Lincoln letter (evidence) is cited by a biography, a Civil-War history, and a leadership essay (contexts). The letter never changes; the interpretations multiply. Lightroom's Collections are the shallow version of this (one photo, many collections) — but collections are *organization*; edges here carry *interpretation*.

---

## Object states, reconciled

The shaping model's three states still hold — they just generalize cleanly, which is the proof this is an *evolution* not a *break*:

- **Unplaced** — referenced by **zero** memories. On the holding surface.
- **Placed** — referenced by **one or more** memories. (Previously "in *a* memory"; now "in *at least one*.")
- **In a project** — a placed memory that's part of something built over time. Unchanged.

"Remove from a memory" removes **one edge**. The clip returns to *unplaced* only if that was its **last** edge; otherwise it stays *placed* (still evidence in other memories). "Where does this belong?" becomes, on an already-placed clip, "**where else** does this belong?" — placement stops being terminal, which is exactly the point.

---

## The annotation — experience, not schema

The edge annotation is the answer to *"why does this matter **here**?"* The implementation is edge properties; the experience must never say so.

- Surfaces as **"Add a note on how this fits here"** / **"Why does this matter in this memory?"** — never "annotate reference," never "edge note."
- **Optional.** A clip can sit in a memory with no annotation — it just contributes its transcript. The annotation is offered, never required.
- **Distinct from the memory's summary.** The summary describes the whole memory; the annotation describes *this piece's role in it.*
- **This is where reflection lives.** A reflection is an annotation added *later* — "Five years on, this dinner changed how I think about craft." The evidence didn't age; you did. Every revisit can deepen the relationship without changing the underlying record. That answers the months-old "where does reflection go?" — it's not a new object, it's a time-layered edge.

---

## Deletion — three different acts, made to feel different

Because evidence and context are different layers, deletion means different things and the UI must reflect that:

- **Remove from a memory** (delete an *edge*) — removes one interpretation. Evidence survives; other memories' links survive. Calm, low-stakes, undo-toast. *(Not even destruction — it's re-placement, per the shaping model.)*
- **Delete a memory** (delete a *narrative + its edges*) — removes an interpretation and its annotations. **The clips survive** as evidence, still linked to any other memories, or returned to the holding surface. Full-width bottom Delete → Recently Deleted.
- **Delete a clip** (destroy *evidence*) — the weightiest act, because it's irreversible loss of a primary source. If the clip is referenced by memories, **say so** ("This is evidence in 3 memories") before it goes to Recently Deleted. This is the one deletion that should feel heavier than the others.

---

## Transcript: correction is not interpretation

Evidence is immutable — but we do let users edit a transcript (unified editing model: "text = tap to edit"). These reconcile cleanly:

- **Editing a transcript is *correcting the record*** — fixing what the recognizer misheard so the evidence is faithful to what was actually said. That's fidelity, not reinterpretation.
- **Interpretation never touches the transcript.** What you *think it means* goes in the memory, the summary, the annotation — never by rewriting the words. You fix "Himem" → "HiMem" (correction); you do **not** rewrite the waiter's words to match your leadership point (that would be forging evidence).
- The original media is the ultimate backstop: the audio is the source of truth; the transcript is the best-effort record of it, correctable toward — never away from — what the recording contains.

---

## AI as editor, not organizer

Under this model the AI's job shifts from *filing* to *association* — and it gets more humble, which fits Honest Label exactly:

- Not *"This is about leadership."* → **"This might also matter in your Leadership memory. Connect it?"**
- The AI **proposes edges**, never creates them silently. Recognition over generation; the human concludes.
- **Cross-reference is offered, never a chore.** The moment linking becomes the *user's* manual job, this is Obsidian and we've failed — the North Star rejects exactly that burden. The many-connection engine is only Kingfisher-shaped if the connections are *surfaced*, not *filed by hand*.
- **"Find the thread" deepens:** today "find similar memories"; under this model, "show me every place this idea appears." Tapping a Leadership memory could surface *Referenced elsewhere · CIA Dinner · Photography journey · Factory sim* — not retrieval, but **discovering patterns in your own thinking.**

---

## Why this is the creator tool

Most PKM asks *"where should this note live?"* — a filing question with one right answer. HiMem asks *"what ideas does this evidence support?"* — a synthesis question with many. That's the difference between organization and **knowledge synthesis**, and it's why one dinner becomes a blog post, a leadership talk, a recipe, and a story for your grandson without being copied four times.

**Studio becomes inevitable, not bolted on:** evidence → memory → project → article/talk/book are interpretations at increasing scale. Same philosophy, larger canvas. The creator writing about leadership gets *"you've connected seven clips to Leadership — one is the cheesecake story"* — evidence they'd never have searched for but absolutely wanted. That surprising-connection surfacing is creative gold, and it's a direct consequence of the edge model.

---

## The principle

**Capture once. Connect many.**

The successor to *"Capture first, organize later."* That principle solved capture; this one describes shaping. A single moment can matter for many reasons — HiMem preserves the moment **once**, and lets meaning grow wherever it belongs.

---

## v1 scope — ontology locked, surface staged

The decision was to **bake the ontology in for v1**, because migrating a shipped user base from one-clip-one-memory to many-to-many would be risky and jarring. That means:

**In v1 (non-negotiable — schema):**
- Clip↔Memory is many-to-many with an associative edge carrying an optional annotation + timestamp. The data model ships correct.
- Deletion semantics distinguish edge / memory / clip as above.
- Evidence stored once; no duplication on multi-placement.

**In v1 (surface — the minimum that honors the model):**
- **`Clips` is a first-class primary object** — one of three tabs (Clips · Memories · Projects = Evidence · Context · Intent), retiring the standalone "Captured Clips" window. Its default view is the not-yet-connected clips (AI suggestions on top); it reveals to All / Voice / Photos / Notes. *(See CLAUDE.md · Phone and `HiMem · the shaping model.md`.)*
- **The three tabs share one chrome, and capture is on every one.** The top bar (HIMEM wordmark + search + settings) and the bottom `Clips · Memories · Projects` tab bar are identical across all three tabs; only the context-filter row and body change. **The capture FAB floats on every tab, in the same position** — capture is one tap from anywhere, per the perishability first principle; a tab where capture isn't one tap away fails the core promise. **The FAB is context-aware — the active tab declares intent** (locked July 10 2026): on **Clips**, capture lands as a new clip on the bench and *stays on Clips* (the clip drops into the list in view — recognition, no navigation); on **Memories**, it opens the structured memory composer; on **Projects**, + acts on the unit of the surface — at the **project list** it creates a **new project** (name + goal, the same sheet the "+ New project" row opens), and **inside a project** it creates a **memory in that project**. The generalizing rule: **+ creates one of whatever you're looking at a collection of** (Clips list → clip, Memories list → memory, Projects list → project, inside a project → memory-in-project). The Projects-list + is the one + that makes an empty container rather than catching a thought — fine, since no thought is in flight while browsing the list. Reading the tab you're visibly standing on isn't "magic"; teleporting you elsewhere after you capture *is*. Both destinations honor capture-now-decide-later and nothing is lost across them, so context-sensitivity is safe. Because the bench now takes clips from the Watch *and* the phone FAB, bench headers are **source-agnostic** ("N new clips", never "N from your Watch"). Cold launch lands on **Memories** (what you open HiMem *for*); last-used tab is remembered only while the app stays alive. New-arrival status is a **dot on the Clips tab** (presence, not a count; clears on open) — the old Memories arrival *banner* is retired. Tapping the active tab reveals a **status sheet** (Active Navigation Tap — see `Kingfisher · North Star.md`). *(Canonical chrome: `HiMem · Home.html`.)*
- Tapping a clip opens **the clip as the primary object** — transcript · media · date · **"Referenced in: [memories]"** · Projects. This is where multi-placement becomes visible and legible without teaching a word.
- A clip *can* be in more than one memory; the common path is still one. Placement uses "Where does this belong?" and doesn't fight a second placement.
- The annotation field exists where a clip sits in a memory ("why does this matter here?"), optional and quiet.

**Staged (not v1, not foreclosed — because the schema already supports them):**
- AI-proposed association ("this might also matter in X").
- "Find the thread" as cross-appearance discovery.
- Reflection-over-time as a deliberate surface.
- Studio creation from connected evidence.

The rule: **v1 ships the correct bones and the calm minimum of muscle. Everything staged is a UI addition later, never a schema migration.** That's the whole reason to do this now.

---

## Reconciliations (so no two docs disagree)

- **`HiMem · the shaping model.md`** — its "a clip is always in exactly one of the first two states / placed in *a* memory" line is superseded: *placed* now means "referenced by ≥1 memory," and "where does this belong?" can be asked again for additional placements. (Pointer added at the top of that doc.)
- **`Captured Clips · session-first · spec.md` — Sort dedup** — "one clip = one candidate, lands in at most one new memory" still governs **a single Sort pass** (first/primary placement; you're forming the initial memory, and a clip appearing in two *proposed* clusters at once is still confusing). What changes: a clip gaining a **second** memory later is now legitimate and expected — that's the staged AI-association act, not a Sort bulk operation. Sort places once; connection multiplies later.
- **`CLAUDE.md`** — "Memory is an Entry; multiple clips can become media on one Memory" is now "…and one clip can be evidence in many memories (many-to-many; the edge carries the annotation)." Data-custody note unaffected: edges + annotations are structured data in the user's private CloudKit DB; evidence media in their iCloud Files, stored once.

---

## Status

- **Ontology (evidence/context/creation, many-to-many, edge annotation):** locked v1, July 8 2026.
- **v1 surface:** the calm minimum above.
- **Creator surface (association, cross-appearance, reflection, Studio):** staged, schema-ready, not built.

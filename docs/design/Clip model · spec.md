# Clip model · spec.md

> **Locked July 11 2026.** The unified Clip → Collection → Memory model.
> Canonical mock: `HiMem · Clip Model.html` (shared components in
> `screens-clip-model.jsx`). This doc is the source of truth for how a clip
> looks and how a memory is built from clips. If it changes, mirror the change
> here and in the mock in the same PR.

## Why this exists

The same objects were being drawn three different ways. A single voice clip
looked like one thing inside a session on the Clips tab (ochre ring · offset ·
transcript · Retry · trailing play), something unrelated inside a Memory
(date·time·location header · transcript · "Original recording"), and something
else again as a loose row. A memory card and a session card shared no bones even
though a memory *is* a session plus a little context. The drift made "make a
memory" feel like converting a clip into a different kind of thing, when it
should feel like wrapping clips you already have.

This spec makes the ontology load-bearing: **one atom, one collection skeleton,
and a memory that is visibly a collection with a derived layer.**

## The three levels

### 1 · The clip atom — one structure, three registers

Every clip renders with the **same three parts, always in this order**:

1. **Timing header** — the clip's place in time. In a session: an *offset*
   (`+128s`) and, for audio/video, duration. In a memory: full
   `Day Date · Time · Location` (year only when not the current year).
2. **Content** —
   - voice / note → the **transcript** (the words are the content);
   - photo / video → a **real thumbnail** (never a generic glyph — the image
     *is* the content), plus an optional description line when the user has
     written one.

   > **The description is the media clip's *words*** — the human stand-in for
   > the future visual transcript, and the exact parallel of a voice clip's
   > transcript (AI Organize and search read it the same way). Because it
   > belongs to the clip (evidence), not the memory (context), it is
   > **editable wherever the clip is — including the Clips surface, before any
   > memory exists.** A media row shows the description as its body when
   > written, or a quiet ochre *Add a description* invite when empty; tapping
   > the row opens the media clip detail, where the DESCRIPTION section shows
   > the read/empty states (`DescriptionEmpty` / `DescriptionFilled` from
   > `screens-photo-description.jsx`) and, on tap, routes editing through the
   > one canonical **`ClipEditor` (`field="description"`)** — the slot a voice
   > clip fills with its Transcript. Ochre throughout (human-written, never AI
   > blue). Per item, optional, never blocks.
3. **Evidence control** —
   - audio / video → a **Play** affordance ("Original recording · 0:42" in a
     memory; a compact "▶ 0:03" in a session);
   - photo → none (the thumbnail already is the evidence);
   - note → none (the text already is the clip).

**Register is the only skin switch.** `ClipAtom` takes `register` — three
values, one component:

| | Operational — Clips / session | Reflective — Memory | Reflective Compact — Memory long-index |
|---|---|---|---|
| Type | SF Pro, denser | roomier | SF Pro, single-row index density |
| Inclusion ring | **yes** (ochre, "included in this session") | no | no |
| Timing | offset (`+128s`) | full date · time · location | time only (`6:12 PM`) |
| Content | transcript / thumbnail in full | transcript / thumbnail in full | first line of transcript as a preview (never a duplicate — see long-memory nav) |
| Evidence | compact (`▶ 0:03`) | named in full (`▶ Original recording · 0:42`) | none on the row (expanding delegates to the reflective body, which carries Play) |
| Retry (failed transcript) | shown | never | never |

**`reflectiveCompact` is a *density* of the reflective register, not a new
axis.** It renders **one collapsed index row** — `media-icon · time ·
first-line · chevron` — for a clip inside a long memory's Compact table of
contents (`Memory Detail · long-memory navigation.md`). It shares the **same
`ClipDisplayModel`** as the other two registers: the glyph is a projection of
`media`, the time a projection of `timing`, the preview a projection of
`transcript` — **no new field.** Expanding a compact row does not restyle the
atom; the container swaps the row for the clip's **reflective** body (the one
shared expanded body, identical in Full and Compact). Which rows are expanded,
the single-open accordion, and the Full ⇄ Compact toggle are **container
concerns** (Memory Detail owns them), never the atom's. **If `reflectiveCompact`
ever needs a field the other two registers don't, stop — that is a fork signal,
not a fourth register.**

The registers are **not** flattened into one look. The operational vs
reflective split is a locked Crucible rule (`CLAUDE.md` — "Operational vs
reflective surfaces get different visual languages"); this model honours it. The
consistency we require is **structural** (same three parts, same order, same
component), not pixel-identical chrome.

Consequence carried in from this pass: **photo/video clips in Memory Detail now
show a real thumbnail**, not the old 34px chip + "Photo" text. Thumbnails
everywhere (the July 9 "thumbnails, never a wall" rule) — reflective included.

### 2 · The collection skeleton

A **clip collection** = a **composition header** + a **body of clip atoms**.

- **Composition** (`ClipComposition`) — the timespan + media counts
  (`🎙3 📷1 🎦1`), plus a word count in the transcript-header context. This is
  **one shared primitive** (`MediaRow` is its media-count component): the same
  line heads a session card, rides on a memory card, and heads a memory's
  transcript section. One place to change how a collection summarises itself.
- **Body** — the clip atoms in capture order, divided by a hairline
  (`ClipDivider`). Present when the collection is opened; hidden when collapsed
  to a card.

### 3 · Memory = collection + derived data

A **session** is a collection with **no derived layer** — a proto-memory on the
workbench. A **memory** is a collection **plus a derived layer**: the AI title,
the AI summary, topic chips, and mentions.

One object, three states of maturity:

| State | What renders | Where |
|---|---|---|
| **Session** | composition + body + triage actions (Create one memory / Delete) | Clips tab |
| **Memory card** | derived layer + composition, **body collapsed** | Memories list |
| **Memory detail** | derived layer + composition + **full body** | Memory Detail |

"Create one memory" is exactly: take this collection, add the derived layer. The
clips never change; only what surrounds them does.

## Shared components (`screens-clip-model.jsx`) — the single definitions

**This file is the ONLY place a clip's view or editor is defined.** A surface
that needs to draw or edit a clip imports from here; it does not hand-roll clip
markup. If you are writing a clip row, a transcript editor, a description
editor, an inclusion ring, a Play control, or a Retry link *outside this file*,
stop — the component already exists here.

**The view:**
- `ClipAtom({ media, meta, transcript, description, duration, hue, register, ring, failed })` — the one clip view. `register` (`operational` | `reflective` | `reflectiveCompact`) is the only skin switch.
- `ClipEvidence({ media, duration, register })` — the Play/evidence control (media-aware: audio/video → Play; photo → thumbnail chip; note → nothing).
- `ClipRetry()` — operational-only failed-transcript link.
- `ClipRing()` — the operational inclusion ring.
- `ClipComposition({ timespan, media, words, register })` — the shared summary line.
- `ClipCollection({ derived, timespan, media, words, register, body, actions })`.
- `ClipDivider()`.

**The editor (locked July 11 2026 — one editor, two fields):**
- `ClipEditor({ field, value, media, duration, showMove, onCancel, onDone })` — the ONE clip editor. `field='transcript'` edits a voice/note clip's words; `field='description'` edits a photo/video clip's words. Both are *the clip's words* — the same act on the same slot — so they are the same component, differing only by which field label and media evidence they show. Owns the edit field (mirrors displayed text, auto-grows), the quiet Play/evidence control kept visible while editing, the fate-action row (`Delete clip`, optional `Move to…`), and the `Cancel`/`Done` commit row. This replaces the three former editors: `MDClipV2`'s editing branch, `MDClipCompactRow`'s editing branch, and the standalone `DescriptionEmpty`/`DescriptionFilled` edit path.

**Load requirement (the mechanical fix — was the root of the drift).** Because
these are the single definitions, **`screens-clip-model.jsx` must be loaded on
every page that renders a clip** (Clips, Memory Detail, Memories, Projects,
Home), right after `crucible-primitives.jsx`. The file is self-contained (it
carries its own thumbnail fallback and does not hard-depend on another surface
file). Before July 11 it was loaded by `HiMem · Clip Model.html` only — which is
precisely why every surface hand-rolled its own clip: it *could not* reference
the canon. A surface that renders clips without loading this file is a bug.

## Convergence status (honest — what actually consumes the canon)

The mapping below is **status, not aspiration.** ✓ = converged in code (renders
through the canonical component). ◐ = partially converged. ○ = still hand-rolled,
scheduled. New code is ✓-only; touching a ◐/○ surface means converging it, not
adding to it.

| Surface (file) | Clip view | Clip editor |
|---|---|---|
| Clips / session (`screens-clips-page.jsx`) | ✓ `SessionVoiceRow`/`SessionMediaRow` render through `ClipAtom register="operational"`; `ClipRing`/`ClipRetry`/`ClipEvidence` shared (the duplicate `RING`/`RETRY`/`PLAYTRI` consts are deleted) | ✓ media clip detail uses `ClipEditor field="description"` |
| Memory Detail (`screens-memory-detail.jsx`) | ◐ `MDClipContent` shares `ClipEvidence`; the reflective card keeps its own header (its long-memory Compact/Full navigation is governed by its own spec) | ✓ both edit branches use `ClipEditor field="transcript"` |
| Memory card (`screens-memories.jsx`) | ✓ already the collapsed collection form (`MediaRow` composition); it *is* the reference | — |

`MediaRow` (in `screens-memories.jsx`) stays the shared media-count primitive
that `ClipComposition` builds on. Loose/placed standalone rows and burst rows in
`screens-clips-page.jsx` are single-clip *list* chrome (chevron, download
progress, thumbnail strip), not collection bodies — they wrap a `ClipAtom`
rather than being replaced by one.

## The same discipline for Collection/Memory and Project

The clip is the first object to get a single definition; the other two follow
the identical rule, so CC builds all three the same way:

- **Collection / Memory — one view + one editor.** The view is `ClipCollection`
  (derived layer + `ClipComposition` + optional clip-atom body); a **memory
  card** is the collapsed form (body hidden), a **memory detail** the expanded
  form (body shown), a **session card** a collection with no derived layer.
  These are the *only* definitions — `screens-memories.jsx`'s card, the
  session-first card, and `MemoryCardMini` (App Store frames) must converge onto
  `ClipCollection`, not re-draw a memory. The memory editor (title/summary/
  topics/mentions, tap-to-edit in place) is the unified-editing model, defined
  once and reused.
- **Project — one view + one editor.** A `ProjectView` (name + goal + derived
  topic chips + member list) with derivations for the list row, the project
  detail, and project-in-a-tab; a `ProjectEditor` for the name + goal sheet
  (the one sheet reached from both "+ New project" and the Projects-tab FAB).
  `screens-projects.jsx`, `screens-projects-views.jsx`, and `screens-home.jsx`
  converge onto it rather than each drawing a project their own way.

**The rule, stated once for all three objects:** *there is exactly one view and
one editor per object; every surface renders the object through that pair;
writing object markup anywhere else is the bug this spec exists to prevent.*
Clip is converged now (this pass); Collection and Project are spec-locked here
and converge in a following pass.

## Relationship to existing specs (no contradictions)

- **`Memory Detail · unified editing model.md`** — the shared clip body (one
  view, tap-to-edit) is the same principle at the field level; this spec is that
  principle at the object level. The `ClipAtom` is what unified editing edits.
- **`Memories list · spec.md`** — the memory card's one-card, contextual-density,
  content-fallback rules are unchanged. This spec only names the card as the
  *collapsed collection* form.
- **`Captured Clips · session-first · spec.md`** — the session card, the
  media-agnostic idle-gap grouping, thumbnails-not-a-wall, and the Create-one-
  memory / Delete-session actions are unchanged. This spec names the session as
  *a collection with no derived layer* and routes its rows through `ClipAtom`.
- **`HiMem · evidence and context.md`** — this is the visual expression of that
  ontology: clip = evidence (the atom), memory = context (the derived layer),
  one clip can be evidence in many memories (the atom is surface-agnostic).

## Convergence acceptance checklist — known divergences to kill

Audited against the shipping iOS build (screenshots, July 11 2026). Each is a
place a clip is drawn differently than the canonical atom. CC checks these off
surface-by-surface; the slice tag says where the fix lands. This is the pass/fail
gate for "clip is converged" — not the prose above.

### Part 1 · Evidence control (the Play affordance)
- [x] **E1 · One Play glyph across registers.** `ClipEvidenceControl` now uses
  `play` for both operational and reflective — same shape, register-styled
  (operational 12pt ink3, reflective 14pt semibold accent). No more
  `play.circle.fill` filled disc.
- [x] **E2 · Reflective Full-stream clips carry the evidence line.** The
  atom's `reflectiveCard` renders `ClipEvidenceControl` when
  `ClipEvidenceProjection.project(model:register:) != .none`, and voice
  clips project to `.namedPlay(label: "Original recording", durationString:)`
  regardless of surface (single-clip memory vs Full stream). Locked by
  `voice_evidence_reflective_isNamedPlay` at the projection level.
  `TranscriptClipController.readState` (Slice 9b) is the single reflective
  render path for voice clips on Memory Detail — no divergent single-clip
  vs multi-clip code path exists to fork behavior.
- [x] **E3 · Compact expanded body carries evidence.** `CompactClipRow`'s
  expanded voice footer now uses the same `play` glyph + accent-triangle /
  ink3-label tint pair as the atom's `.namedPlay` render.

### Part 2 · Timing header
- [x] **T1 · One operational offset notation.** `formatOffset` always emits
  `+Ns` — first clip is `+0s`, never `0:00`. Locked by
  `timing_operational_firstClip_is_plusZeroSeconds`.
- [x] **T2 · Duration once, not twice.** Operational `ClipTimingHeader` no
  longer renders `durationString`; duration lives on the Play control only.
- [x] **T3 · Reflective header is mixed-case with location.** Dropped
  `.uppercased()` + `.tracking(0.4)` in the atom's reflective branch; the
  projection already returned the canonical
  `Sun May 17 · 6:12 PM · Bishop St, Bluffton` form — the view was the drift.
- [x] **T4 · One date format per surface.** `EntryExpandedView.fullTimestamp`
  now uses `EEE MMM d · h:mm a` (with `, yyyy` for prior years) — same shape
  as `ClipTimingProjection.formatDateTimePlace`. Memory Detail's memory-meta
  line and clip-header line share vocabulary; `July 5 · 3:44 PM` (long month
  name) is retired.
- [x] **T5 · Compact row time is one treatment.** Removed the `isEmphasized`
  time-color swap; the chevron rotation is the accordion cue.

### Part 3 · Content
- [x] **C1 · No double-printed lead line.** `ClipAtomView` gains
  `hidePreview: Bool` — `CompactClipRow` passes `hidePreview: isOpen`, so the
  collapsed preview sentence stops printing above the same sentence in the
  expanded transcript body.
- [x] **C2 · One quotation rule.** `CompactClipRow`'s expanded body now wraps
  the transcript in `"…"` — matches the atom's `.reflective` / `.operational`
  transcript render.
- [x] **C3 · Photo clip in an expanded session shows "Add a description."**
  `ClipAtomView.showDescriptionInvite` (with optional
  `onTapDescriptionInvite`). Session-expanded `mediaClipRow` passes true; the
  surrounding `NavigationLink` handles tap routing to Clip Detail's inline
  editor.

### Correct today — protect from regression
- [x] **Rings** present on operational rows, absent on reflective/compact.
- [x] **Session composition header** uses per-media glyphs (`🎙2 📷1`), matching
  the memory card (`ClipComposition`).

### Open decision, not a bug
- [ ] **D1 · Total duration on the collection header.** Operational session shows
  `· 0:06`; the reflective memory card omits it. Lock whether duration is
  register-specific (operational keeps it, reflective drops it) or dropped for
  strict parity — then write the one line into §2's `{timespan, media, words}`
  definition. Slice 8 must not silently re-decide it.

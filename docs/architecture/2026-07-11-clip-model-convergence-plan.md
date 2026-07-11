# Clip model convergence plan — 2026-07-11

**Status:** Slice 0 approved + locked in the source-of-truth spec files (CD's authoritative edits); Slices 1–10 pending. Slice 1 next.
**Source-of-truth spec:** `docs/design/Clip model · spec.md` (locked July 11 2026, `reflectiveCompact` as a *density of reflective*, three-column chrome table).
**Related specs (no contradictions):** `docs/design/Memory Detail · unified editing model.md`, `docs/design/Memory Detail · long-memory navigation.md` (§Compact carries the reflectiveCompact register cross-ref), `docs/design/Captured Clips · session-first · spec.md` (July 11 bullet: media clip description editable *right on the bench* — cross-refs Clip model §Content), `docs/design/HiMem · evidence and context.md`, `docs/design/screens-photo-description.jsx` (July 11 preamble bullet: description editable at clip level, not only inside a memory — same slot a voice clip fills with Transcript, canonical editor is `ClipEditor field="description"`).

## Process correction (2026-07-11)

CD caught a real process failure in the first version of this plan: it claimed **"Slice 0 delivered"** while the source-of-truth spec file still had a two-column table, the "two registers" heading, and no long-memory cross-ref. Uncommitted working-tree edits are not delivery. **A slice is delivered when the file diff is in the file** — not when the plan says it is. The spec-file redline is what CD reads; the plan is only a description of the spec. If the description and the spec disagree, the spec wins by construction.

The authoritative Slice 0 text was subsequently written by CD directly into `Clip model · spec.md` §1 and `Memory Detail · long-memory navigation.md` §Compact. That version supersedes the draft I authored. Going forward: no slice is marked delivered until the target file's diff is present in that file (and, ideally, committed).

## Why this exists

The iOS codebase currently hand-rolls clip markup in eight places: `LooseClipRow`, `MediaClipRow`, `BurstRow`, `ClipsListItemRow`, `SessionListView.clipRow`, `SessionListView.mediaClipRow`, `VoiceClipPanel`, `NotePanel`, `MediaCard`, `CompactClipRow`, `ClipDetailView`. Each drew its own timing header, evidence control, ring, and description slot. Two editors (`PhotoDescriptionEditSheet` + Memory Detail's inline transcript editing) did the same act on the same slot with different chrome. The Clip Model spec (locked July 11 2026) makes the ontology load-bearing: **one atom, one collection skeleton, one editor** — and this plan converges the iOS codebase to that.

## The four calls (with Tom's reasoning, verbatim)

**Q1 · Compact register.** `(a)+(c)`: add `reflectiveCompact` as a third value of the single register switch, in code and spec. Rejected `(b)` (a sibling view) as re-fragmentation. Guardrail: `reflectiveCompact` shares the same `ClipDisplayModel` as the other two — glyph + `HH:MM` is a projection of existing fields. **If Compact needs a field the other two registers don't need, stop and flag it as a fork signal.**

**Q2 · Description on operational rows.** `(c)`: quiet empty state on the dense rows; ochre "Add a description" invite only when the row is opened/expanded. Interaction state gates the invite, not surface identity. Full spec compliance without lighting up editorial chrome in scan mode.

**Q3 · `PhotoDescriptionEditSheet` retirement.** `(a)`: retire the sheet. Editing is a mode → inline `ClipEditor`; consumption (full-size QuickLook / video player) is a live thumbnail tap that works in read AND edit state. Real separation is edit-vs-consume, not sheet-vs-inline.

**Q4 · Burst thumbnail storm.** `(c)` both, but the two options fix different bugs. `(a)` is load-bearing: `providedThumbnail: UIImage? = nil` on `ClipAtomView` (nil = self-fetch, so default behavior and atom purity preserved; opt-in perf affordance). Burst container batch-fetches once, downsampled to strip size, through a bounded-concurrency queue (~3 concurrent). `(b)` is standing hygiene: `ThumbnailService` in-flight dedup by `osIdentifier` — **does not fix the burst** (burst is 12 distinct osIdentifiers, not duplicates), but retires cross-surface duplicate reads.

## Guardrails (invariants applied everywhere)

1. **Single register enum, three values.** `.operational(ring:)` · `.reflective` · `.reflectiveCompact`. If any consumer wants a fourth value or a second axis, stop and flag it as re-fragmentation.
2. **`ClipDisplayModel` is projected from evidence.** `reflectiveCompact` glyph + `HH:MM` is a projection of the existing fields, not a new field. Stop if Compact demands a fork.
3. **Description edit is an inline mode.** `PhotoDescriptionEditSheet` is deleted, not renamed.
4. **Description empty state = silent on scan-rows, ochre invite on opened row.** Interaction state gates the invite.
5. **Consume ≠ edit.** QuickLook / video player = the existing full-screen viewer, launched by thumbnail tap in both read and edit states.
6. **Thumbnails: `providedThumbnail: UIImage?` is opt-in.** `ThumbnailService` in-flight dedup is standing hygiene, never mistaken for a burst fix.

## The hazard (verified real) and its fix

`PhotoDescriptionEditSheet` is consumed by **both** `ClipDetailView` (Slice 7 territory) and `MediaCard` in Memory Detail (Slice 9 territory) via `EntryExpandedView.swift:864` → `MediaCard.onEditMediaDescription: { item in ... selectedMedia = item }` → `MediaFragmentEditorStack.sheet(item: $selectedMedia) { PhotoDescriptionEditSheet(...) }` at line 1424. **Deleting the sheet in Slice 7 red-lights the build for two slices.**

**Fix:** Slice 7 stops Clip Detail from calling the sheet (routes to inline `ClipEditor`), but leaves the shared `MediaFragmentEditorStack` / `selectedMedia` binding / `onEditMediaDescription` callback alive. Slice 9 converges `MediaCard`'s description edit to inline, which removes the last consumer, and deletes the file + shared plumbing at the end of the slice.

## Confirmed structural boundaries

Compact/Full toggle, single-open accordion, and swipe parity stay **container concerns** (Memory Detail owns them per `Memory Detail · long-memory navigation.md`), not `ClipAtomView` concerns. `VoiceClipController` wraps the atom with audio download/duration state and edit coordination; the atom stays pure. This boundary is what makes Slice 9 clean — the atom renders one clip in one register, nothing more.

## Slice map

Every slice is **bug-first tested + shippable independently + green-to-green**.

### Slice 0 · Lock the Clip Model spec (task #159 — delivered by CD, awaiting commit)

**Files:** `docs/design/Clip model · spec.md` §1 (three-column chrome table: Operational · Reflective · Reflective Compact; heading updated to "one structure, three registers"; guardrail paragraph stating `reflectiveCompact` is a *density* of reflective — not a new axis — with the fork-signal invariant); `docs/design/Memory Detail · long-memory navigation.md` §Compact (register cross-ref: collapsed row via `ClipAtom register="reflectiveCompact"`, expanded body swaps to reflective, accordion/toggle container-owned). CD also removed a stale convergence-status row pointing at `screens-captured-clips-sessions.jsx` (deleted July 11) that would have sent a future Slice 8 pass to converge a ghost. **Delivered:** both file diffs are present in the source-of-truth spec files. Commit pending.

### Phase 1 · Primitives (no consumers yet)

**Slice 1 · `ClipDisplayModel` + adapters** (task #160). Value-typed snapshot projected from `InboxClip` / `MediaReference` / `MediaDisplayItem`. Media enum members explicit: `{voice, photo, video, note}` (tightening 2). Fields: `media`, `timing`, `content`, `evidence`, `thumbnailKey`, `failed`, `place`. Money tests: (i) adapter round-trip parity across bench vs memory; (ii) `reflectiveCompact` needs no field the other two don't (invariant #2 against forking); (iii) note's evidence-slot semantics pinned (empty vs "Note" — decision, not accident).

**Slice 2 · `ClipEditor(field:)`** (task #161). Enum `ClipEditorField.{transcript, description}` with eyebrow + a11y verb metadata. Inline editor participating in `TextEditCoordinator.shared`. Money tests: `eyebrowMatchesField`, `competingEditorCommits` (rule #6 auto-commit-on-switch), `doneTrimsAndSkipsWhenUnchanged`, `showMoveGovernsMoveVisibility`.

**Slice 3 · `ClipAtomView` + sub-views** (task #162). `ClipAtomView(model:register:providedThumbnail:UIImage?=nil)` composes `ClipTimingHeader` + `ClipContentSlot` + `ClipEvidenceControl` + `ClipRing` + `ClipRetry`. **`providedThumbnail` declared HERE** per tightening 1 (part of primitive contract, not a Slice 6 reach-back). Ring state is `Binding<RingState>`. Reflective `ClipTimingHeader` reuses `CaptureTimestampLabel` for the `"Sun May 17 · 6:12 PM · Bishop St, Bluffton"` format (verified at `ChronologicalCaptureStream.swift:842-890`). Money tests: media × register 12-cell matrix (4 media × 3 registers) locking evidence-control label, retry visibility, ring presence, timing format, thumbnail source. **Plus a 13th anti-double-print assertion** (CD, 2026-07-11): the `reflectiveCompact` Content is a first-line preview *projected* from the transcript field — the atom must NOT render that preview line when the same clip is shown expanded (which swaps to reflective). Long-memory nav spec forbids the duplicate; the matrix as-written (single-cell, static) doesn't catch the collapsed→expanded transition. Assertion shape: given a clip with transcript "Ben said the Basque cheesecake…", the atom in `reflectiveCompact` renders "Ben said the Basque cheesecake…" as its preview; the same clip in `.reflective` renders the transcript body starting with the same sentence *and* the compact preview must NOT appear when the container swaps registers (which it will, since the container is what swaps). Test the invariant at the atom level: `reflectiveCompact` renders the preview; `.reflective` does not render a preview line at all. A pass on both cells + the long-memory spec's "never duplicate" rule at the container level closes the loop.

**Slice 4 · `ClipComposition` + `MediaCounts`** (task #163). Value input `CompositionModel {timespan, media: MediaCounts, words: Int?}`. Register-aware font/spacing. SF Symbols only (no emoji). Money test: pure `CompositionModel.from(clips:)` for a mixed 3-voice/1-photo/1-video sitting yields expected timespan/counts/words.

**Slice 5 · `ClipCollection`** (task #164). Generic `ClipCollection<Actions:View, Derived:View>` with `@ViewBuilder` slot closures for derived layer + actions row. Consumers hand `register` + `body: .collapsed | .expanded([ClipDisplayModel])`. No protocol soup.

### Phase 2 · Callsite convergence (leaves-first)

**Slice 6 · Clips flat list + BurstRow batch-fetch** (task #165). Converge `LooseClipRow` / `MediaClipRow` / `BurstRow` / `ClipsListItemRow` / `FlatClipsListView` onto `ClipAtomView(register: .operational)`. `BurstRow` becomes wrapper that batch-fetches its ≤5 strip images through bounded-concurrency queue (~3 concurrent), downsampled to strip size, then hands each atom its `providedThumbnail`. Description empty state per Q2: silent on collapsed row. Money test: burst renders N atoms without spawning N `ThumbnailService.cacheThumbnail` calls.

**Slice 7 · Clip Detail + editor rollout** (task #166). `ClipDetailView` renders through `ClipAtomView(register: .reflective)` — opened context, ochre "Add a description" invite lights up per Q2. Description tap → inline `ClipEditor(field: .description)`. Thumbnail tap → existing full-screen viewer (Q3 consume path). ADD `ThumbnailService` in-flight dedup as standing hygiene (Q4b) with test proving same-`osIdentifier` atoms fire one disk read. **Does NOT delete** `PhotoDescriptionEditSheet` or `MediaFragmentEditorStack` description binding — hazard fix.

**Slice 8 · Sessions bench** (task #167). `SessionListView`'s voice `clipRow`, absorbed `mediaClipRow`, and `sessionMetaRow` all die. `ClipAtomView(register: .operational)` for rows; `ClipComposition(register: .operational)` for meta. Wire ring `Binding` correctly (retires "unwired ring" TODO on absorbed-media row). Description invite still off on collapsed session row; tapping media row routes to Clip Detail (invite lit there per Slice 7).

**Slice 9 · Memory Detail Full stream + retirement** (task #168). `VoiceClipPanel` / `NotePanel` / `MediaCard` converge onto `ClipAtomView(register: .reflective)`. `VoiceClipController` wraps atom with audio download/duration state + edit coordination — atom stays pure. `MediaCard`'s description edit flips to inline `ClipEditor(field: .description)`. Real thumbnails on photo/video (retires "34pt chip + Photo text" bug). **At END of slice** (once nothing calls the sheet): delete `PhotoDescriptionEditSheet.swift`, delete `selectedMedia` binding in `MediaFragmentEditorStack`, delete `onEditMediaDescription` callback in `ChronologicalCaptureStream`. Hazard fix.

**Slice 10 · Compact + Create-Memory chip** (task #169). `CompactClipRow` (Memory Detail long-memory index) converges onto `ClipAtomView(register: .reflectiveCompact)`. Single-open accordion state stays container-owned (Memory Detail concern, not atom's). `CreateMemoryFromClipsSheet` summary chip → `ClipComposition(register: .operational)`, drops ~40 lines. Money test on invariant #2: `reflectiveCompact` renders without needing any `ClipDisplayModel` field the other registers don't need.

## Dependency DAG

```
Slice 0 (spec)
   ├── Slice 1 (ClipDisplayModel)
   │     ├── Slice 3 (ClipAtomView) ──── Slices 6, 7, 8, 9, 10
   │     └── Slice 2 (ClipEditor) ─────── Slices 7, 9
   └── Slice 4 (ClipComposition) ───┐
       Slice 5 (ClipCollection)   ──┴─── (consumers TBD in later passes)
                                         Slice 9 blocks Slice 10 (deletion order)
```

Enforced in the task tracker via `blockedBy` edges on tasks #159–#169.

## Deferred / not in scope this pass

- **Collection/Memory unification** (spec §"The same discipline for Collection/Memory and Project"). The spec locks the direction; this convergence pass ships the *Clip* atom + editor. `ClipCollection` (Slice 5) is the primitive; consuming it from Memory card / Session card is deferred to a following pass named in the same spec.
- **Project unification** (`ProjectView` + `ProjectEditor`). Spec-locked, not in this pass.
- **Search-within-memory** (per `Memory Detail · long-memory navigation.md` §"Scope / deliberately out"). Unchanged.

## Delivery cadence

Roughly one working session per slice at Tom's estimation calibration (memory: `feedback_estimation_calibration.md`): primitives 15–30 min each with tests, convergence slices 30–60 min each with the leaf tests + one build cycle + eyeball. Full convergence: ~10 working sessions. Bug-first tests co-located with each slice; every slice is green-to-green (previous callsites keep working through the slice boundary via the hazard fix).

## What ships when Slice 0 ships

Two spec-file edits committed alone (no code). Tom's redline gate keeps option (b) from creeping back at any later slice by having the spec table pinned before the first Swift line lands.

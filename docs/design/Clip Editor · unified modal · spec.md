# Clip Editor · unified modal · spec

**Status:** Locked July 16 2026. Built on `HiMem · Clip Editor.html` (canvas mock) and the `HiMem · Clip Model` ontology. Supersedes the scattered clip-edit paths named below.

**Why now.** The transcript-wipe P0 (July 16) was the *second* data-loss from a separate bespoke edit path (synthesized-note `077de8c`, transcript-wipe `ce4b191`). Both came from the same root: more than one place edits a clip, each with its own seed/commit logic. This spec collapses **all** clip editing into one modal invoked on tap, so the invariant ("seed synchronously before render; commit through `ClipEditorCommitDecision`") becomes *structural* — there is no second path to drift.

## The ontology it expresses

- **A clip is the atom** — evidence, stored once (Clip↔Memory is many-to-many; each edge carries an optional annotation, "why this matters here").
- **A memory is context** — a clip is evidence in 0–N memories.
- The editor makes this visible: **the clip once, then N edge-panels beneath it.** Editing the evidence happens in one place; managing its context happens per memory.

## Invocation

- **Tapping a clip's ✎ opens this same modal — on ANY surface.** The **boxed pencil button (✎ glyph only, no label, blue `#1E5C8E` hairline border) is the ONE edit affordance everywhere** — Clips bench, session, search results, the session cluster editor's rows, Memory Detail (Full *and* Compact). It stays **boxed** so it reads as a real button, not a bare glyph. There is no second way in: **no caret-to-edit, no whole-row-to-edit, no tap-the-transcript-text.** One convention, not one-of-several. On a cluster row, Remove remains an independent control (subtractive trim); ✎ is the edit entry (this **supersedes** the earlier §87 "cluster row tap opens the modal" — the row tap no longer edits; ✎ does).
- **Read stays inline; edit is always ✎ → modal.** In Memory Detail the clip renders inline for reading (Full shows the transcript; Compact's accordion expand-to-read stays — `openCompactRowId`, long-memory nav intact). Editing is **never** inline: the retired `expandedTranscriptArea` edit mode is replaced by the boxed ✎ pencil button, which appears **on every clip row and card, in every register, whether collapsed or expanded** — not expanded-state-only. Reading is not editing, so this closes the edit-path class without a modal-per-clip read slog.
- **✎ placement + the size trade (locked July 17 2026).** The boxed pencil is **right-aligned on the row** (note clips put it on the last metadata line). **Listen-back is not a row control** — there is no inline Play on cluster or Memory Detail Compact rows; playback + scrub live in the modal (consume there). In dense **Compact** rows the boxed pencil makes each row slightly taller — **accepted**: a single consistent edit affordance beats a tighter row with a divergent (or absent) one. ≥44px tap target. Same button, same behavior, Full and Compact and cluster alike.
- Presented as a **sheet** (grabber; `.medium`/`.large` detents). Top bar is the bare-text exception place: **Cancel** (plain ink, left) · **Done** (ochre, right). "Done" commits and dismisses; "Cancel" restores and dismisses.
- There is **no** other clip-edit surface. `AudioPlayerSheet`'s bespoke transcript edit, the standalone `PhotoDescriptionEditSheet` lineage, and any inline-only editor are retired into this one.

## Zone 1 · The clip (the atom) — must never wipe

- **Media + timing + source + content.** Voice/note → transcript; photo/video → description. Timing is the reflective format (`Wed Jun 3 · 9:47 PM · Bluffton`). **The clip's source is shown as a small glyph in the metadata line** (Watch / phone / Siri) *when known* — per the source-agnostic-headline rule, source is per-clip metadata (a small glyph), never a headline. **When source is unknown, show no glyph — never a defaulted one** (honest absence, not a guess). Today source lives on `InboxClip` (watch/phone); `MediaReference` (placed clips) has no source field yet, so placed clips show no glyph until `MediaReference.sourceDevice` ships in a bundled CloudKit deploy — the promote-then-place path must be ready to carry `source` forward when the field exists. Audio/video keep a **Play** control (consume ≠ edit); tapping a photo/video thumbnail opens the full-size viewer (consume path).
- **Tap the text to edit inline.** The field **seeds synchronously with the current text before render** — never blank-then-fill. A no-op Done can therefore never write an empty string over real content. This is the invariant the wipe bug violated.
- **Edited once, true everywhere.** Because the clip is stored once, an edit to transcript/description is true in *every* memory that references it. The edit state shows a blue AI line naming that consequence ("This is the clip itself — your edit shows in every memory that uses it").
- **Commit** routes through the shared `ClipEditorCommitDecision` (trim + skip-if-unchanged). Same rule as every other text edit in the app.
- **Refresh the transcript** — a blue AI action, **"Transcribe again with AI ✦"** (verb-names-the-AI + trailing sparkle), a bordered blue pill (tertiary) beneath the read-mode transcript. Voice/video only (a photo description is authored, not transcribed, so it has no re-transcribe). Re-runs the transcription pass on the original audio and reseeds the field with the result; the user still commits via Done. Never ghosted low-contrast — it stays a legible blue. On a *failed* transcription the operational **"Retry transcription"** (blue link) takes its place. Naming is fixed per the AI-action rule — never "Regenerate".

## Zone 2 · Memory sections (single-open accordion)

- **The clip stays the un-tabbed hero above; the edges collapse.** Zone 2 is a **single-open accordion** — same model as Memory Detail (`openCompactRowId`), one row open at a time. This keeps the evidence→context hierarchy visible (clip first, memories beneath) *and* stops a clip in many memories from burying Zone 3's Delete under a long scroll. (Chosen over top-level tabs, which would flatten the hierarchy and hide the many-to-many; see decision July 16 2026.)
- Section header: **"Evidence in N memories"** (0 edges → "Not in any memory yet").
- **Collapsed row:** memory title (serif) + date + a **one-line annotation preview** (ellipsized; empty → blue "Add a note"), with a chevron that rotates on open. Whole row is the ≥44px tap target.
- **Expanded row** adds:
  - **The annotation** — "why this matters here", editable inline (empty state: blue "Add a note"). Per-edge: the same clip can mean different things in different memories.
  - **Remove from this memory** — de-associates *this one edge*. The clip survives. Neutral weight (eject glyph), **not** destructive-red.
  - **Open ›** — opens that memory (link to context, not an edit).
- A **loose clip (0 edges)** shows the header + the add affordance only — same editor, sections simply absent.
- **Add to a memory** — a dashed ochre **"+ Add to a memory"** affordance below the rows (dashed = add/provisional; ochre = the user acts). Shown **always, including at 0 edges** (a loose clip's primary path into a memory). Opens a memory picker; associating creates a new edge (with an optional annotation). Additive membership from inside the editor — the counterpart to the per-edge Remove and the atom Delete.
- **For a bench clip (`InboxClip`, no `MediaReference` yet) "Add to a memory" is promote-then-place.** The clip has no edge because it has no reference yet; on **confirm** of a target the `InboxClip` is promoted to a `MediaReference` (audio moved to the memory store, ref minted) and the edge is created — unifying the model at the moment of association. Existing-memory target then runs the normal `PlaceClipSheet`; new-memory routes to `CreateMemoryFromClipsSheet`. **Promotion fires on confirm, never on opening the picker** — a cancelled "Add to a memory" leaves the `InboxClip` untouched on the bench (no orphan promoted-but-unplaced ref). The existing-memory single-clip picker may be staged after new-memory, but the affordance is never dropped. This is the ontology's "clip stored once; edge created on association" seen from the bench — and it confines all `InboxClip`-specific branching (audio store, absent Zone 2) to the pre-first-placement state.

## Zone 3 · Delete this Clip (atom-level)

- **Full-width red button at the bottom**, below all content — the deletion-lock placement (open item, scroll past everything; the scroll is the deliberation).
- **"Delete this Clip"** destroys the atom and **removes it from every memory that references it**, with a **live-count warning**: *"This clip is evidence in N memories. Deleting it removes it from all of them."* (0 memories → "This clip isn't in any memory yet.") Recoverable via Recently Deleted (30 days).
- **Distinct from Zone 2's Remove:** Remove = de-associate one edge (clip lives); Delete = destroy the atom (gone from all). The two destroy-levels finally read clearly because they sit in one surface at different scopes. (July 13 Trash-by-object lock.)
- **No confirm dialog** for the delete itself — consistent with the deletion lock (scroll-is-deliberation); the live-count line *is* the honest warning.

## Invariants (the reason this exists)

1. **One EDIT surface.** The modal is the single place a clip is edited; it opens on tap wherever the tap's purpose is to open the clip (bench/session/search), and via an explicit edit affordance where the clip already renders inline for reading (Memory Detail — expand-to-read stays). A new clip-*edit* surface that isn't this modal is a defect, not a style choice.
2. **Seed synchronously before render.** No async seed; no blank-then-fill window.
3. **One commit path** (`ClipEditorCommitDecision`) — trim, skip-if-unchanged, never wipe.
4. **Atom edited once, true everywhere; context managed per edge.** Transcript/description = Zone 1 (shared); annotation + membership = Zone 2 (per memory, single-open accordion — clip stays the hero, edges never bury Delete).
5. **Two destroy-levels, named honestly:** Remove-from-this-memory (edge) vs Delete-this-Clip (atom, all memories).

## Deferred / not in scope

- **Reordering a clip's position** within a memory — lives in Memory Detail, not here.
- **Full annotation-editing chrome** beyond a single inline note field — the edge annotation is one field for now.

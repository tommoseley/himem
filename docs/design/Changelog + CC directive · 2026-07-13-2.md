# Changelog + CC directive — 2026-07-13

**Canonical source:** this design project. **Mirror:** `tommoseley/himem` → `docs/design/`.
**Repo audited at:** `@8d7194b`. **My repo access is read-only** — I cannot push; the file copies and the Swift edits are yours/CC's to run.

---

## The one rule for this handoff

**CC's latitude is *how*, not *what*.** Every item below is a *what* — a decision already locked against the Architectural Invariants (`HiMem · Locked Decisions.html`). CC chooses the implementation: view structure, state plumbing, naming, where a toast component lives, how a list observes a change. CC does **not** re-decide the behavior, the copy, the verb, or the ontology. If an item seems to require changing a *what*, **stop and raise it as a challenge** — don't design around it, and don't "improve" it in passing.

Definition of done, per item: (1) *does this express the invariant it cites?* then (2) *does it meet the acceptance criteria?* Both checkable against the named file.

---

## Part 1 · What changed in the canonical source this session

Grouped by decision. Each names the spec that now holds the truth.

### A · Post-create transition (the bug Tom hit: empty memory, no feedback, clip stayed in New)
- **Locked in:** `Clip model · spec.md` § "Start a Memory — the post-create transition" (four acceptance criteria).
- The memory **shows** its clips immediately (never empty) · a **"Memory created · View"** toast confirms · the **session is consumed** (return to the Clips list) · **included clips leave New**, excluded return loose.
- Mocks added: `screens-clips-page.jsx` (`CreatedToast`, `ScrClipsAfterCreate`), `screens-memory-detail.jsx` (`ScrMemoryFresh`, `MDOrganizePrompt`).

### B · Source-agnostic Clips copy
- **Locked in:** `CLAUDE.md` (Phone bullet + corollary), `Captured Clips · session-first · spec.md` (empty-inbox row).
- No "from your Watch" anywhere — clips come from +, Watch, Siri. Empty state: "Nothing new" / "Clips you capture — with the + button, on your Watch, or with Siri — land here." Source is per-clip metadata (a small glyph), never the headline.
- Mocks: `screens-clips-page.jsx` (`ScrClipsEmpty`), `screens-settings.jsx` (empty sub-line).

### C · Status-sheet zero rows (reversal)
- **Locked in:** `CLAUDE.md` status-sheet bullet.
- The full source roster shows every time, **including sources at 0** — a stable, scannable list beats one that changes shape. Reverses the earlier omit-zeros rule.
- Mock: `screens-clips-page.jsx` (`ScrClipsStatusSheet`, `Siri 0`).

### D · Ontology wording (coherence fixes — words matching the model)
- **Locked in:** `CLAUDE.md` (Naming), `Clip model · spec.md`.
- **Project *connects* memories** (many-to-many) — does not contain or own them. **Memory *shows/references* its clips** — "CONTAINS" retired.

### E · Deletion / swipe on Watch
- **Locked in:** `Watch · spec.md`, `CLAUDE.md` deletion lock.
- Watch delete lives in the **per-clip detail** (tap row → Play + full-width Delete at the foot), **not** a swipe. Two-tap confirm kept as the documented Watch-only exception (unsynced audio, no Recently-Deleted net).
- Mock: `Himem · Watch.html` Section 4 rebuilt.

### F · Fresh-start breath (mock catch-up; app already correct)
- **Locked in:** `Watch · spec.md` (one-second breath, revised May 27).
- `Himem · Watch.html` §1b rebuilt: single ochre ring filling clockwise from 12, italic caption inside — the old 3·2·1 sequence removed. **The shipping app already implements this correctly; do not re-add a countdown.**

### G · New reference doc
- `HiMem · Locked Decisions.html` — the one-page Architectural Invariants + the review rule (two classes of edit). Read before any review.

### H · North Star amendment
- **Locked in:** `Kingfisher · North Star.md` — the #8 clarification ("Add to Project" is the approved verb).

---

## Part 2 · Files to sync into `docs/design/` (copy from this project → repo)

**Changed this session — overwrite the repo copy:**
- `CLAUDE.md`
- `Clip model · spec.md`  *(repo mirror is missing this entirely — add it)*
- `Captured Clips · session-first · spec.md`
- `Watch · spec.md`
- `Kingfisher · North Star.md`  *(repo mirror missing — add it)*
- `Kingfisher Language.md`  *(repo mirror missing — add it)*
- `Himem · Watch.html`
- `screens-clips-page.jsx`, `screens-memory-detail.jsx`, `screens-settings.jsx`
- `HiMem · Clips.html`, `Himem · Memory Detail.html`

**New files — add to the repo:**
- `HiMem · Locked Decisions.html`
- `Handoff · code-anchored punch list.md`
- this file

**New file — add at the repo ROOT (not `docs/design/`):**
- `AGENTS.md` — how implementation work is orchestrated (sequential by default, dependency-aware parallel cycles, Agent → CC → Tom escalation, four-part handoff). Lives at repo root beside `CLAUDE.md`, where CC reads its working instructions — it's an execution manual, not a design artifact. **Draft pending CC's review** (see the question at the top of the file) before it's adopted.

**Delete from the repo mirror (predate the Clips-tab model — actively misleading):**
- `docs/design/Himem · Captured Clips.html` (the old standalone window, 75 KB)
- `docs/design/Himem · Captured Clips (session-first).html` (superseded by `HiMem · Clips.html`)
- `docs/design/backups/2026-05-pre-tokens/` (pre-token backups)

> Verify each with a diff before overwriting — if the repo copy was hand-edited since the last sync, reconcile rather than clobber.

---

## Part 3 · Code punch list (the actual Swift work)

**The full code-anchored list is `Handoff · code-anchored punch list.md` — read it; it has file + line per item.** Do not re-derive the work from the chat log. Ordered summary:

0. **Answer the structural question first:** is `SessionListView.swift` still the live Clips tab, or is it the retired standalone window (dead like `JournalInboxBanner`)? If dead, **delete it** and apply fixes to the live Clips view. Do not patch both. *(This one gate determines whether half the items are patches or deletions — that's why it's step 0.)*
1. **P0 · Post-create (A):** the empty memory is a **render-path** bug (data attaches clips correctly in `createMemory()`); add the confirmation toast; verify the list refreshes after `removeBatch`.
2. **P1 · Source copy (B):** five string sites + delete `JournalInboxBanner.swift`.
3. **P1 · Bench vocab/deletion + P2 · Watch (E):** the **[DECISION]** items — confirm labels with Tom, then implement.
4. **Cleanup:** stale "3-2-1" comment in `WatchRecordingService.swift:344`.

**Already compliant — leave alone (don't "fix"):** the one-second breath in `WatchRecordingView.swift`; "Add to Project" verb; no "container" strings in code.

---

## Why this shape

Duplicated spec files in two places is what generates "which one is right?" One-time reconciliation now (Part 2), then keep this project canonical and let `docs/design/` be a mirror CC reads. The invariants doc + this changelog mean the next review is a **consistency check**, not a fresh argument — and CC's job is to express these faithfully, choosing only *how*.

# Handoff · code-anchored punch list — 2026-07-13

**For:** Claude Code (implementation) · **From:** design/spec side (read-only on the repo).
**Repo audited:** `tommoseley/himem@main` (commit 8d7194b).

## How to use this doc (read first)

1. **Read `HiMem · Locked Decisions.html` (Architectural Invariants) before touching anything.** Every item below serves one of those invariants; the "why" column names which.
2. **Source-of-truth order.** Spec named in the item wins over any mock. Where two specs disagree, `CLAUDE.md` (design) wins. Mocks illustrate; they don't define.
3. **Two classes of edit.** A *coherence fix* (wording that reconciles the code to an existing invariant) is green-light. A *vocabulary / architecture / principle change* needs Tom's sign-off — flagged inline as **[DECISION]**.
4. **Definition of done, per item:** first "does this express the architecture?", then the item's acceptance criteria. Each item names a file + line so there's nothing to guess.

---

## ⚠️ Structural finding that reframes everything below

`MemoryStream/MemoryStream/Views/Inbox/SessionListView.swift` is the **old standalone "Captured Clips" window** — pushed as its own screen, titled "Captured Clips", "Done" to dismiss. The locked ontology (July 8) **retired the standalone window**: Clips is now a first-class *tab* (`Clips · Memories · Projects`), and its default view is the bench.

**Before patching SessionListView line-by-line, confirm which is true:**
- **(A)** `SessionListView` is still the live content of the Clips tab → then the copy/verb/delete fixes below apply *to it*.
- **(B)** The Clips tab is a newer view (e.g. `ClipsTabView`) and `SessionListView` is dead like `JournalInboxBanner` → then **delete `SessionListView`** and apply the fixes to the live view instead.

Answer this first. Most items below carry a line number in `SessionListView`; if (B), port the same fix to the live Clips view and bin the old file. **Do not fix both.**

---

## P0 · Post-create transition (the "empty memory / no feedback / clip didn't leave" bug)

**Invariant:** *Start a Memory connects the session's clips to a new memory that shows them at once · confirm · session consumed · connected clips leave New.*
**Spec:** `Clip model · spec.md` § "Start a Memory — the post-create transition" (four acceptance criteria).
**File:** `MemoryStream/MemoryStream/Views/Inbox/CreateMemoryFromClipsSheet.swift` → `createMemory()` (line ~455).

Current `createMemory()` does the data correctly — moves audio, `saveEntry(...)` with `mediaCaptures`, copies per-clip transcripts onto the `MediaReference`s, drops manifest rows — then just calls `dismiss()`. Three of the four criteria are unmet at the UX layer:

1. **[VERIFY — render path] Memory shows its clips immediately.** The data attaches them, so the reported "empty memory" is almost certainly a **render bug**, not a save bug. Check `EntryExpandedView` (the memory-detail body): confirm a freshly-created entry with **no `OrganizePass`** still renders its clip bodies (transcript + Play). If the body is gated on `latestOrganizePass != nil`, that's the bug — the clip stream must render pre-organize. *Acceptance:* create a memory from 1 voice clip → its transcript is visible in the detail before any Organize tap.
2. **[MISSING] Confirmation.** `createMemory()` posts no feedback. Add a **"Memory created" toast with a "View" action** (View opens the new entry). *Acceptance:* after Create, a toast appears and auto-dismisses; View navigates to the new memory. Mock: `screens-clips-page.jsx` → `CreatedToast` / `ScrClipsAfterCreate`.
3. **[VERIFY — list refresh] Session consumed.** `InboxManifest.shared.removeBatch(...)` drops the bundled clips, so the session should vanish from the list on the next publish. Confirm the Clips list re-renders after `removeBatch` (InboxManifest is `@ObservedObject`; the sheet mutates the shared singleton — make sure the list observes it). *Acceptance:* after Create, the consumed session is gone from the list with no manual refresh.
4. **[OK] Excluded clips return to the bench.** Excluded clips aren't in `clips`, so they stay in the manifest = correct. No change.

---

## P1 · Source-agnostic Clips copy (no "from your Watch")

**Invariant:** *Clips arrive from +, Watch, and Siri; source is per-clip metadata, never the headline.*
**Spec:** `CLAUDE.md` Phone bullet + `Captured Clips · session-first · spec.md` (empty-inbox row).

| File · line | Current | Change to | Why |
|---|---|---|---|
| `SessionListView.swift:138` | "Nothing new from your Watch" | "Nothing new" | empty-state, source-agnostic |
| `SessionListView.swift:141` | "Audio you record on your Apple Watch lands here." | "Clips you capture — with the + button, on your Watch, or with Siri — land here." | " |
| `SessionListView.swift:229–231` (`headerTitle`) | "N from your Watch" | "N new clips" | title copy |
| `JournalInboxBanner.swift` (whole file) | "N new from Apple Watch" banner | **Delete the file** | Banner retired July 10 (arrival status is now the Clips-tab dot). CC already noted it has no callers. |
| `WatchInboxNotificationCoordinator.swift:466` | "New voice clip from your Watch" | **"There are new clips you can review"** | Source-agnostic + passive; works whether the clip came from Watch, Siri, or phone. |
| `CoachmarkView.swift:116` | "Thoughts from your Watch and the phone FAB land here." | "Clips you capture — with the + button, on your Watch, or with Siri — land here." (trim to coachmark length if needed) | **Coherence fix (added Cycle 2, CC-raised, Tom-approved).** Same source-agnostic headline invariant; the coachmark just wasn't in the original screen audit. |

**Leave as-is (legitimately Watch-specific):** `SyncStrip.swift` "Receiving from your Watch" — it names the literal watch→phone sync link, not a clip's origin.

---

## P1 · Vocabulary + deletion drift in the bench (SessionListView, if live per (A))

**Invariants:** *Named actions, not generic verbs* · *Delete = one deliberate path, no confirm dialog, swipe retired.*
**Specs:** `Kingfisher Language.md`, `CLAUDE.md` deletion lock, `Captured Clips · session-first · spec.md`.

1. **[DECIDED — "Start a Memory"]** Verb "Make or Add To a memory" (`makeAMemoryPill`, lines ~620 & context-menu ~330). Primary action label is **"Start a Memory"** (inside the opened session); add-to-existing is a separate secondary path — not one combined pill. *Acceptance:* the primary create action reads "Start a Memory"; no "Make or Add To" combined pill remains.
2. **Swipe-to-delete violates the deletion lock.** `expandedBody` uses `.swipeToDelete(...)` per clip (line ~), and the card uses `.swipeToDiscard(...)` (line ~). The lock retired swipe everywhere (June 12) in favor of a full-width Delete at the bottom of the *opened* item. *Acceptance:* no swipe-to-delete/discard on clips or sessions; deletion is the bottom-of-opened-item button.
3. **Confirm dialog violates the no-confirm rule.** `.confirmationDialog("Delete this clip?" … "This audio can't be recovered.")` (lines ~90–105). The lock says the deliberate scroll-to-bottom *is* the deliberation — **no confirmation dialog**. *Acceptance:* delete commits without a dialog (recoverability net is Recently Deleted, 30 days).
4. **[DECIDED — new deletion vocabulary, see below]** `discardSessionLink` and the `.confirmationDialog` copy are replaced by the object-specific deletion model in the next section. "Discard" is retired.

### Deletion vocabulary — object-specific, because clips are the atoms (locked July 13 2026)

**Invariant served:** *the clip is the atom; memories and projects are associations over clips.* The delete label must tell the truth about what is destroyed vs merely de-associated — Honest Label applied to destruction. Three distinct actions, each a full-width button at the foot of the opened item:

| Opened item | Button label | What actually happens | Copy under it |
|---|---|---|---|
| **Memory** | **Let Go of this Memory** | The memory (title · summary · topics · annotations — the *derived layer*) dissolves. **Clips used elsewhere survive** and return to availability; **clips unique to this memory move to Recently Deleted** with it (last-reference rule, July 19 2026). | "8 clips are also used elsewhere and will stay · 5 are only here and move to Recently Deleted for 30 days." (split disclosed, never asked) |to join other memories. Evidence is never destroyed by letting go of context. | "The clips stay — they'll be available to start other memories." |
| **Clip** | **Delete this Clip** | Destroys the **atom**. It is removed from **every** memory that references it. | "This clip is attached to N memories. Deleting it removes it from all of them." (N is live-computed from the reference count; singular/zero handled: "not attached to any memory yet" / "attached to 1 memory".) |
| **Memory, within a Project** | **Remove from Project** | De-associates the memory from the project. The memory survives everywhere else. (Unchanged; stated for the full trio.) | — |

*Acceptance:* letting go of a memory leaves its clips on the bench (verify a clip that was only in that memory reappears as loose/New, not deleted); deleting a clip decrements/【removes it from every referencing memory and the warning shows the real count; "Discard" appears nowhere.

> If (B) — SessionListView is dead — items 1–4 are moot for the old file; verify the live Clips view honors these and delete `SessionListView.swift`.

---

## P2 · Watch delete — swipe vs per-clip detail

**Invariant:** *Delete lives in the opened item; swipe retired.* (Watch keeps a documented two-tap confirm because unsynced audio has no Recently-Deleted net.)
**Spec:** `Watch · spec.md` (Pending list + delete).
**File:** `MemoryStream/Himem Watch Watch App/WatchPendingListView.swift:224` — `.swipeActions(edge: .trailing, allowsFullSwipe: true)` with a Delete button.

**[DECIDED — agree, drop `.swipeActions`]** The app drops the swipe in favor of tap → per-clip detail → full-width **Delete** at the foot (+ `WatchDeleteConfirmView` two-tap confirm kept — the documented Watch-only exception). `WatchDeleteConfirmView.swift` and `WatchPlaybackPeekView.swift` already exist to host it. *Acceptance:* deletion reachable only via the row's detail, not a swipe.

---

## Verified COMPLIANT — no code change (don't let CC "fix" these)

- **One-second breath countdown.** `WatchRecordingView.swift` already implements the May-27 one-breath model (`breathContent`, `runBreath()`, `BreathRing`). **Only cleanup:** a stale comment at `WatchRecordingService.swift:344–346` still says "3-2-1-Listening countdown" — reword to "the fresh-start breath". The *design mock* `Himem · Watch.html` §1b is the stale artifact (3·2·1 ring); that's on the design side and I'm fixing it separately — do not re-add a 3-second countdown to the app.
- **Ontology wording in code.** "Add to Project" (`EntryExpandedView.swift:752`, `ProjectDetailView.swift:166`) is the **approved** verb (Tom's call, #8). No "container of memories" strings exist in user-facing code. `folder` is only an SF Symbol name, not ontology. Nothing to change.

---

## Suggested order

1. **Answer the (A)/(B) structural question** — it determines whether P1-vocab/P2 are patches or deletions.
2. **P0** (the bug Tom actually hit) — toast + verify render + verify list refresh.
3. **P1 source-agnostic copy** — mechanical, five string sites + one file delete.
4. **P1 vocab/deletion** + **P2 Watch** — the **[DECISION]** items; confirm labels with Tom, then implement.
5. Stale-comment cleanup.

Re-audit against this doc after the diff lands; every acceptance criterion is checkable against the named file.

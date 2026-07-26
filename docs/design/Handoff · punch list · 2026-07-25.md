# Handoff · punch list — 2026-07-25

**For:** Claude Code · **From:** Design · **Status:** live list, supersedes ad-hoc directives from this session.
**Read first:** `HiMem · Locked Decisions.html`, `AGENTS.md`, `CLAUDE.md` (design authority: your latitude is *how*, never *what*; raise concerns, never deviate silently).

**Standing rules for every item below.** Bug-First (reproduce red → fix → verify green). Report before building anything marked SCOPE. Four-part handoff per item (does it express the spec / what changed / what tests prove it / unresolved risk). Never mark an item done because a commit touched the file — done means the acceptance criteria hold.

---

## P0-1 · Unblock the second dogfooder (merge + ship)

Tom's wife is a genuine new user testing a build that predates every fix from 2026-07-25. She is re-discovering closed bugs, which wastes the most valuable testing we have. She begins a **45-day road trip in ~9 days** and will be the primary multi-device user.

1. **Batch-merge the ready PRs:** #7, #9, #10, #11, #12, #13, #14, #15. **#12 must merge before #14** (#14 reuses `CaptureSource`). Report anything that doesn't merge cleanly — do not force.
2. **Push a TestFlight build** once P0-2 lands. Release notes should name what changed for her: the memory picker shows every memory, handedness follows across devices, voice clips can be placed, hands-free recordings auto-save at a limit.
3. **Add nothing else to that build.** Ship what's fixed.

**Done means:** she is on a build containing #7/#9–#15 + P0-2.

---

## P0-2 · The `Add to a memory` placeholder + dead "Transcribe again with AI"

**Symptom:** tapping *Add to a memory* on certain bench clips shows `InboxPromotePlacePlaceholder` — developer text ("Promote-then-place for a bench clip is wired in the follow-up cycle…") with only a Done button, in a **shipping TestFlight build**. On the same clips, *Transcribe again with AI* silently does nothing.

**Diagnosis to confirm (do not chase "Siri"):** the differentiator is almost certainly **backing type** — `InboxClip` (manifest-backed) vs `MediaReference` (ref-backed) — not the capture route. Phone voice → manifest (`PhoneCaptureBenchDispatcher`: voice→manifest, photo/video/note→ref), so Siri clips are manifest-backed and hit the stub; the photos that work are ref-backed and route to `PlaceClipSheet`. "New clips work" is the session/bundle *Start a Memory* path — a different flow. Confirm before building.

**Build (the ruled behavior, Option 1 promote-then-place):**
- *Add to a memory* offers **existing memory** → the shared searchable all-memories picker (the one PR #9 fixed) → on confirm, materialize `InboxClip` → `MediaReference` and create the edge; or **new memory** → **Start a Memory**.
- **Promotion happens on confirm, not on open.** Cancel leaves the `InboxClip` on the bench with no orphan ref.
- Fix *Transcribe again with AI* for the same backing. **Any genuinely unavailable action must be absent or disabled with a reason — never a button that silently does nothing.**

**Done means:** no developer text reachable in a shipping build; both actions work on both backings. Money tests cover add-to-memory and transcribe-again × both backings, plus cancel-leaves-no-orphan.

> **Note the overlap with P0-3.** If P0-3 lands first, promotion collapses into `createEdge` on an already-existing ref. Sequence to avoid building the same thing twice — flag if you think P0-3 should precede this.

---

## P0-3 · SCOPE FIRST — clips must sync across devices

**This reverses the earlier "ship the gap" decision. It is now a locked first principle:**

> **We don't make people hurt for the evidence** — a clip is an atom and follows the *person*, never the device: captured anywhere, reachable everywhere, with no chasing, no re-recording, no "which device was I on?" (`HiMem · Locked Decisions.html`, locked 2026-07-25)

**The problem.** A captured clip lives in a **per-device local JSON manifest** and becomes a CloudKit-synced `MediaReference` only when placed in a memory. So a day of watch/phone clips is invisible on iPad — breaking the intended workflow (capture all day on watch/phone → organize on iPad), the ontology ("capture once, connect many"), and the storage promise ("your journal is part of your iCloud").

**Do not estimate a sync build. The infrastructure exists and is proven** — memories already do exactly this: metadata in the CloudKit private DB, blobs in the iCloud Files ubiquity container. No new mechanism, no new schema, no new sync path. **The task is: stop reading the bench from a legacy local store; read it from the model that already syncs.** Every blocker previously identified (double-render, dedup-on-promote) is a cost of maintaining *two* stores, which this removes.

**Answer this first — it materially changes the size:** per the storage lock, all HiMem-created media already lives in the iCloud Files container. **Does a bench clip's audio blob already sync to the iPad today?** If yes, the audio is already cross-device and the only stranded thing is a metadata row sitting in local JSON instead of being a `MediaReference` — making this purely a metadata-representation change.

**The shape to scope:**
- **`MediaReference` becomes the single source of truth for any arrived clip.** The manifest is demoted to **in-flight transfer state only** (announced / received / downloading, watch ack, retry — that machine works, leave it alone). It stops being a render source entirely.
- **The bench reads one source:** zero-edge `MediaReference`s. Port session grouping / Sort / *Start a Memory* to operate on refs. This *removes* the two-store read rather than reconciling it.
- **Placement stops minting a fresh-UUID ref** (`createVoiceFragment`) and becomes **`createEdge` on the existing ref.** Placement gets simpler.
- **`reviewed` stays per-device** (UserDefaults) — accepted limit, do not solve it here.
- Confirm no CloudKit schema change is required.

**Deliverable: a scope report before any code** — go/no-go, an honest estimate *for this shape*, the migration path for clips already in existing manifests, and the top three risks. If it remains multi-hour/high-uncertainty, **say so plainly: the answer is then that Tom decides the submit date — not that we ship the gap.**

---

## P1-1 · CloudKit Production schema verification

PR #11's comment fix rests on a dashboard read, not a verified schema. Confirm whether `MediaReference.recycledAt` is genuinely deployed to **Production** (not just Development), finalize the `StorageService` comment to match reality, and **reopen the #4a provenance verdict only if it contradicts** the recorded finding (*inbound CloudKit sync of a recycle from a second install/device; no code path auto-recycles* — logged as explained-by-inference, defended by PR #10).

## P1-2 · Title-honesty gate

The honesty gate does **not** fabrication-check titles (title-casing defeats the proper-noun heuristic), so a title can invent an author — *"Ralph Waldo Emerson's Reflection"* on an unattributed quote — same Honest-Label class as the summary leak, higher visibility. Also: a **raw quote fragment as a title** (*"I am not bound to win"*) reads as if the user said it. Add a title-scoped grounding check: case-normalize before matching so title-casing can't hide an ungrounded name → retry → fall back to a structural title (*"A reflection on integrity"*). Own bug-first cycle with the QA panel.

## P1-3 · Left-handed FAB coverage

Confirm the preference moves the FAB on **every** FAB surface (Clips, Memories, Projects list, inside a project, composer/append) — not just where it was first wired — and that the mirrored position doesn't collide with leading-edge controls. The suppression rules (hidden in multi-select, hidden when the Delete footer owns the bottom) still apply, and the tab bar never moves. Money test: flipping the preference flips the resolved alignment; grep for any hardcoded trailing alignment left behind.

---

## Logged — do not build without a new ruling

- **Walk-away cap toast.** A bench toast of *"Saved — N minutes."* for the hands-free-cap case needs its own pass (no generic toast center exists). Today the cap lands the clip calmly on the bench and the Siri stop carries the spoken string — honest enough for now.
- **Free-on-ineligible-hardware disclosure.** Content going to Anthropic for Free users on devices without Apple Intelligence may not be disclosed anywhere user-facing. Pre-existing; a real custody-disclosure question; not a submit blocker.
- **Memory Polish §3 — concluded, do not retry on-device.** Three architectures, three failures (v3 destroyed three proper nouns: `Lisbon→Lime`, `Eureka→Lemon`, `combine→customer`). Tier resolved: **frontier/Plus, not Free.** The substitution-pair architecture is retained as the right shape for the frontier implementation. Harness stays on `memory-polish-spike`, unmerged.
- **`Memory Cover · spec.md`, `Memory Polish · spec.md` §4–§5, `Project Templates · engineering design.md`** — post-1.0, unscheduled.

---

## F6 · Pre-submit gate hygiene + CRAP audit (2026-07-26)

**F6 · A green gate that means green — DONE.** The known-red list had grown 2 → 3 → 4, each one locally reasonable to paper over. Fixed the last flaky pair (`ThumbnailServiceDedupTests`) *structurally*: the race was cross-**suite** (a parallel suite mutating `ThumbnailService.shared` while these asserted on its global `_inFlightCount`) — which `@Suite(.serialized)` **cannot** fix and would only hide, falsely greening the gate. The tests now assert on their own `ThumbnailService()` instance. **Suite is at zero known reds (1088 passing).** **Standing rule from here: no new known-red enters the ignore list without a tracked issue and a fix owner; a flaky test gets fixed or deleted.**

**F6a · CRAP audit — the anemic-domain-model read is a DESIGN observation, not a code-health emergency.** The whole-codebase audit (`docs/audits/2026-07-26-crap-audit.md`, delta vs 2026-06-07) does **not** confirm the anemic-domain-model concern as a *complexity* problem: **no function crosses CC > 30**, and the two long-standing god-views were **properly decomposed** (`JournalView.body` 26 → ~7, `EntryExpandedView.body` 22 → ~15 — the extractions the June audit recommended landed). F6a **stands as a design observation** — near-duplicate procedures, invariants living in the programmer's head, per-call-site backing switches — but it is **not** an urgent code-health item.

The measured risk **changed axis**: from function-complexity to **file-size**. Sixteen files now exceed 800 lines, five exceed 1300 (`ClipsTabView` 1929, `EntryExpandedView` 1694, `SessionListView` 1425, `EntryLifecycleService` 1410, `InboxManifest` 1319). None is a maze — the *new* code is decomposed (ClipsTabView spreads 22 types) — but a 1400-line file is **where the next inline feature lands by default**. **Frame the post-v1 pass as ownership + file-splitting, not complexity remediation.**

Both audit watch-items were taken this session (both ~1h, ride the build-27 archive): `HiMemTabView.body` (was ~30, on the critical line — extracted `tabRoutingObservers`; F2b's `restorePending` observer was the nudge) and `ProcessingEngine.processEntry` (regressed 8 → ~17 — factored a pure `organizeRoute(online:isPlus:hasAI:)` with 8 unit tests pinning the tier matrix, which had already drifted from its own inline comment).

---

## Non-negotiables

1. **No developer text, placeholder copy, or silently-dead controls in a shipping build.** P0-2 exists because one reached TestFlight.
2. **No silent no-ops.** Every action either works, is absent, or explains itself (per the AI Organize §8.2 honest-failure rule shipped in PR #15).
3. **Report before building** on anything marked SCOPE. A wrong architecture costs more than a day of scoping.
4. **Design authority.** Copy, verbs, interaction model, and ontology are decided. Raise a concern and wait for a ruling; never resolve an ambiguity by inventing a *what*.

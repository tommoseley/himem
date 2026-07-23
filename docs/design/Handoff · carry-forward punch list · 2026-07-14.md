# Handoff · carry-forward punch list — 2026-07-14

**For:** Claude Code · **From:** design/spec side (read-only on the repo).
**Supersedes:** `Handoff · code-anchored punch list.md` (2026-07-13) — **that list is COMPLETE and verified at pushed HEAD `077de8c`.** Do not re-execute it. This file is the fresh, current list.

## ⛱ While Tom is away (~45 days, from ~July 29 2026) — autonomous work order

Tom shipped v1 and is on a road trip. Run the open queue **without** him, in this order. The ordering is deliberate: everything that needs no ruling comes first; the one item with a decision gate is flagged. Do NOT change any *what* while he's away — if a genuine ambiguity appears that a spec doesn't cover, **stop and leave it for his return** rather than guess (an unbuilt item is cheap; a wrong-direction build is a round-trip he can't close). Keep every change on its own branch, four-part handoff per item, arbiter live on clip-writing/destroying paths.

1. **P8 · last-reference deletion** — the biggest, and it has a **blocking precondition**: ship clip-level Recently Deleted (`MediaReference.recycledAt` + `RecycleBinView` clip support) FIRST; only then wire the edge-count retire + split-count Let Go sheet. `recycledAt` rides the next CloudKit deploy — **stage on Dev, do NOT deploy Production while Tom's away** (schema deploy is a one-way ceremony he should be present for). So: build + test against Dev, hold the Prod deploy + the on-device verify for his return.
2. **P7 fast-follows** (all pure code, no deploy): add-to-**existing**-memory for Unconnected multi-select (this slice shipped add-to-new); the detach/reorg `everConnected`-recording edge; delete the stale "Loose" doc line at `CLAUDE.md:149`.
3. **Associations cycle remainder** — the ManageProjectsSheet + project read-section rework were greenlit; finish any unshipped slice. Mentions-library UI is already on device.
4. **Standing cleanups** (3/3b): retire the disabled inline-edit branches (`CompactClipRow.expandedTranscriptArea`, `MediaCard`) + migrate `EvidenceEdgeReadWriteTests` off `SortBatchCommit`. §4c ack-storm and §4d skip-if-AAC remain parked.

**Anything requiring a Production CloudKit deploy, a new *what*, or a design ruling waits for his return.** Dogfood bugs he hits on the road go to the top of this list when reported.

## How to use this doc

Same contract as always: read `HiMem · Locked Decisions.html` + `AGENTS.md` first. Latitude is *how*, never *what*. Coherence fixes apply freely; a changed *what* escalates to Tom. Four-part handoff per item (does-it-express-the-spec first, then files/behavior, tests, unresolved risk). Green tests are necessary, not sufficient — CC's diff review is the design-fidelity gate.

**Verified-complete last cycle (for the record, no action):** source-agnostic copy (notification, empty state, bench header, coachmark), "Start a Memory" verb (plus.circle, no sparkle), Watch swipe → peek+Delete, P0 empty-memory (dogfood-confirmed), synthesized-note bug (`077de8c`). (A)/(B) gate resolved: `ClipsTabView.swift` is live; `SessionListView` is the live bench renderer, not the retired window.

---

## INVARIANT (locked 2026-07-14) · Watch capture audio format — LIFT to Watch spec + Locked Decisions

**This is a locked invariant, not a task.** It has drifted silently for weeks because it lived in chat, never in a spec CC re-reads or a test that fails when violated. CC must copy this verbatim into `Watch · spec.md` and `HiMem · Locked Decisions.html`, and add the acceptance test below, *before* building the P0 compression fix.

> **Watch clips leave the watch as mono, 16 kHz, AAC — before `transferFile`.** Never multi-channel, never 48 kHz, never uncompressed PCM on the wire. Target ≈ 4 KB per audio-second (a 1-minute clip ≈ 230 KB, **not** 33 MB). Audio-is-truth is unaffected — AAC-16k-mono is the source-of-truth format for voice; transcription reads it directly.

**Acceptance test (its failure *is* the bug):** the pre-transfer artifact asserts `channels == 1 && sampleRate == 16000 && codec == AAC`; a transferred clip's `bytesPerAudioSec < ~8000`. Wire this as a real test, not a log line — a log didn't catch 33 MB for weeks; an assertion would have failed on dogfood #1.

---

## INVARIANT (locked 2026-07-14) · Watch→phone transport — LIFT to Watch spec + Locked Decisions

**Locked, not a task. Also lift verbatim into `Watch · spec.md` + `HiMem · Locked Decisions.html`.**

> **Watch→phone clip transfer is WatchConnectivity, permanently.** The watch **never** touches CloudKit and **never** writes an iCloud container. Two stages:
> - **Stage 1 — watch → phone:** record → transcode to mono/16k/AAC → `WCSession.transferFile`. That's the whole hop. A ~230 KB compressed clip is near-instant over WC, so WC is not a bottleneck once the payload is right.
> - **Stage 2 — phone → iCloud:** the **phone is the sole writer to the user's iCloud** — media into the Files container, metadata into the CloudKit private DB — done **at its leisure, off the capture hot path.**
>
> **"iCloud as the transfer transport" is RETIRED, not deferred.** Perishability is satisfied at stage 1 (the thought reached a real device fast); iCloud durability is a background concern. This keeps the phone as the single point that writes the user's iCloud (matches the locked data-custody model) and moots the "can watchOS write the Files ubiquity container / CKAsset-in-private-DB vs media-in-Files" wrinkle entirely — the watch is simply never in that path.

---

## P0 · Watch→phone audio transfer is ~144× too heavy — compress on the watch

**Class:** performance / product-credibility bug (a multi-minute sync makes capture feel broken). Bug-First. **Highest priority** — capture is the product's whole job.

**RESOLVED — it's payload size, decisively (not transport).** Instrumentation (`[XferPerf]`, branch `watch-transfer-speed-instrumentation`) settled the A-vs-B question on evidence:
- 58.5s clip = **33,757,696 bytes (~33 MB)**; 21.9s clip = ~12 MB. Rate ~576,000 B/s matches **3 ch × 48,000 Hz × 4 B (Float32) PCM** to the digit.
- `reachable=true` at enqueue both times — so this isn't even worst-case backgrounded throttle; a 33 MB file is just slow over any watch link.
- **Verdict:** compression makes the iCloud migration unnecessary *as a fix for this bug*. A ~230 KB AAC clip is near-instant on the current WCSession pipe. **iCloud transport stays a someday ceiling-remover, NOT this bug's answer.** (Custody caveat preserved below for whenever iCloud is revisited.)

**The fix — two levers, on the capture side:**
1. **Mono + 16 kHz** kills the 3ch×48kHz waste (~18× on its own, no codec needed).
2. **AAC on top** gets the rest (~144× total: 33 MB → ~230 KB).

**Approach (the *how* is CC's, but respect this constraint — it's a capture-pipeline *what* Tom signed off):** **whole-file transcode after stop, before `transferFile`** — NOT per-callback resampling. Per-callback resampling is what caused the July 5 VPIO/resampler reverts; do not reopen that. `AudioCompressor` is iOS-only (AVAssetWriter/Reader unavailable on watchOS) — use `AVAudioConverter`/`ExtAudioFile` or record direct-to-AAC via `AVAudioRecorder`. The phone's post-arrival `compressIfPossible` becomes a no-op for watch clips (fine).

**Companion bug — the mono premise is false on-device.** The July 5 fix assumed `setVoiceProcessingEnabled(false)` collapses the input to mono; the log shows `voice processing disabled` immediately followed by `input node format: 3 ch`. So clips are **3-channel**, a silent ~3× oversize *and* a possible transcription-quality bug (averaging across a dead channel). Fix as its own line item inside this work; the mono half of lever 1 depends on it.

**Parked (flag, don't chase now):** the log shows a storm of repeated `buffered ack for unknown clipId … will replay` (dozens per clipId) — possible separate duplicate-ack bug. Capture as a backlog item, do not chase this cycle.

**Transport is locked (see the transport invariant above):** watch→phone stays WatchConnectivity permanently; the phone is the sole iCloud writer, at its leisure. The "iCloud as transfer transport / watch→CloudKit" idea is **retired** — do not carry "someday iCloud transport" language forward in the decision doc; the custody wrinkle it raised is gone because the watch is never in the iCloud path.

**Leave alone (correct as shown, not defects):** the "Receiving from your Watch" sync card and "Receiving audio · 0:54" are legitimate live-transfer status. Once compression lands and transfers are near-instant, revisit whether the *"Keep HiMem open to finish faster"* copy still tells the truth (it becomes a lie on a 230 KB clip).

**Invariants:** perishability (capture must feel instant); audio-is-truth (AAC-16k-mono is the voice source-of-truth); the Watch-audio-format invariant above.

---

## P0 · Deleting a clip inside a session doesn't remove it; count desyncs; clip detail self-dismisses

**Class:** data-integrity + user-blocking bug (can't delete a clip). Bug-First. **Jumps the queue** ahead of P1–P5.
**Dogfood repro (in hand):** on-a-roll session of 3 voice clips → open clip 1 → delete it → return to session. Observed: Clips-list header updates to "2 new clips" but (a) the session still lists all 3 clips, (b) both waveform badges still read "3", and (c) reopening the deleted clip animates a blank clip-detail in (right-to-left) that then immediately sweeps itself closed. Other clips open normally.

**Three symptoms, likely one root cause — the delete mutates one store but not the session's clip array:**
1. **Delete doesn't reconcile the session.** The delete decremented the list-level "new clips" count (header = 2) but did **not** remove the clip from the session's `clips` array or the manifest rows the session card reads — session still renders 3 rows, both waveform counts still say 3. *Acceptance:* deleting a clip removes it from the session everywhere — row list, both waveform badges, header count — atomically.
2. **Orphaned clip detail self-dismisses.** Tapping the deleted clip opens a detail whose backing model no longer resolves (gone from one store, still referenced by the session's stale array), so it mounts blank and tears itself down — same mount-then-revert shape as the earlier `fullScreenCover` race, but triggered by a **nil/absent clip model**, not a competing presentation. *Acceptance:* a deleted clip isn't in the list to tap; if tapped mid-teardown, no blank view presents.
3. **Count is a lie in two places** (waveform badge 3, header 2) — no-data-slop / honest-label. All counts derive from one reconciled source.

**Where to look:** the clip-delete path (`Delete this Clip` / clip-detail delete) vs the session's clip-array + `InboxManifest` reconciliation. The list-count observer fires (header updated); the session view model + waveform-count derivation read a store the delete didn't update, or don't observe the same publish. **Failing test first:** deleting clip *i* from an N-clip session yields an (N−1)-clip session — row count, both waveform badges, and header count all N−1 — and the deleted clip is unreachable. Then fix so every count reads from the single reconciled source.

**Invariants:** clip is the atom (deleting it removes it from every referencing view); audio-is-truth (waveform count matches reality); no-data-slop (two counts on screen).

---

## P1 · Watch→phone sync latency — durable-wake kick

**Class:** implementation bug (the *what* — "Watch clips sync promptly without a manual tap" — is already locked intent; CC chooses the *how*). Bug-First.
**Root cause (CC-diagnosed, confirmed sound):** the `transferFile` transfer is durable and always *eventually* delivers — delivery is never the problem. The problem is what promptly **kicks a queued-but-idle transfer**, and the only automatic kick in the system is the *watch* foregrounding itself (`Himem_WatchApp.swift:24` scenePhase→.active → `retryPendingTransfers()`). The "manual watch tap" is really "the watch app becoming foreground." The phone has **no automatic channel** to nudge a backgrounded watch: `phone scenePhase→.active` doesn't kick it, and `phone reachabilityDidChange(true)` updates the label only.

**Fix:** the phone kicks the watch on foreground + reachability via a durable `transferUserInfo` — which wakes the backgrounded watch app to receive it, and that wake is itself the scheduling opportunity the queued `transferFile` needs. (The reachable-only `sendMessage` kick is worthless here — redundant with the watch's own self-kick, and can't reach a backgrounded watch. Re-queuing is a no-op: `flushPendingManifest → send()` hits the `outstandingFileTransfers` dedup guard. The lever is the *wake*, not the re-send.)

**Conditions:**
1. **Gate the wake on an actual outstanding inbound transfer.** Don't fire `transferUserInfo` on every phone-foreground/reachability transition — only when a clip is genuinely pending. Battery/wake cost is real and invisible to unit tests.
2. **Test only what's ours.** Deterministically test "phone requests the wake on foreground + reachability (when a transfer is pending)" — that gap is 100% our code. "…and the transfer then starts within N seconds" is iOS-scheduling, **device-dogfood territory, not a unit test.** Say so in the risk section; don't let the untestable half block the testable half.

*Acceptance:* with a clip pending and the watch backgrounded, bringing the phone to foreground (in range) triggers the durable wake without a manual watch interaction; dogfood confirms the transfer starts promptly.

> **Edge (state in risk):** the phone's "transfer pending" signal is `InboxArrivalTracker.shared.hasAnyInFlight` (pre-announced-but-not-cleared clips). Blind spot: if the pre-announce itself never reached the phone (phone fully offline at record time), the phone has no knowledge a clip is pending and won't fire the wake — that case falls back to iOS's own opportunistic delivery. Not a blocker; the honest edge.

---

## P2 · §8.4 PAUSED-label flicker — separate follow-up

**Class:** implementation bug (lying status label). **Do not bundle with P1** — different defect (time-to-kick vs a label that misreports).
**Symptom:** the phone reverts to "PAUSED" / "Waiting for your Watch" while the durable transfer is still trickling, because `.paused` fires on `isReachable=false` even mid-transfer. Documented as open work in the architecture doc §8.4.
**Direction (per the arch doc's own suggestion):** replace the reachability-driven label with a **"no-progress-in-N-seconds" stall detector** so the UI reflects actual transfer progress, not raw reachability. Status is never a lie (no-data-slop / honest-label).
*Acceptance:* a transfer that is still progressing never shows PAUSED; PAUSED appears only on a genuine stall.

---

## P3 · Render-side fail-safe for synthesized notes (durable fix for `077de8c`)

**Class:** tech-debt / latent-bug guard. Carry-forward from the synthesized-note fix (risk #2).
**Why:** `077de8c` cured the three current write paths (`save(voiceFilename:)`, `appendClips`, `createMemoryFromVoiceClips`) that set `entry.content` then mint voice fragments. But the defect **recurs** the instant any *future* path assembles voice fragments without reconciling `entry.content`. The point fix doesn't fail-safe against the next write-path.
**Fix:** a render-side guard in `migrateOrphanedContentIfNeeded` — treat "voice fragments present" as evidence the content came from those voices, so a stray joined-transcript note is never synthesized regardless of write-path bugs.
*Acceptance:* a memory with voice fragments never renders a synthesized `.note` duplicating the transcripts, even if a write path forgets to reconcile.

> Optional, decide when spread is known: a one-shot migration for **existing** dogfood memories already carrying the orphan note (walk memories where voice-fragment count > 0 AND a single `.note` exists with text == joined transcripts → delete the note). `077de8c` prevents new ones; it does not clean old ones.

---

## P4 · Swipe-retirement cleanup — RE-SCOPED (CC audit, 2026-07-14)

**My original P4 was wrong on the facts.** CC verified against `077de8c`: **zero live `.swipeActions` exist anywhere in the iOS app** — every hit is a comment. The three surfaces I named (`ChronologicalCaptureStream`, `JournalView`, `ProjectListView`) are **already compliant** (`JournalView.swift:353` documents the retirement; `ChronologicalCaptureStream` deletes via the fate-row button; `ProjectListView` has nothing). Taken literally my acceptance criterion was already met — the item would have been wrongly closed as done. Restated correctly, P4 is three smaller jobs:

**(a) [DECISION — Tom] The one genuine live swipe: `SettingsView.swift:126` `.onDelete(perform: deleteTopic)`** on the Topics-management list. This is a *what*, not a *how*: the deletion lock defines the object-specific full-width Delete for **memories / clips / projects** (evidence/context/intent objects). Whether it extends to a **Settings topic-management list** — which is *managed content*, not one of those objects — is a scope call. **CC correctly escalated rather than deciding.** Tom rules: does the topic list keep native `.onDelete` swipe (it's a management list, not an object surface), or convert to the full-width pattern?
- *Leaning (not a ruling):* a Settings management list is a different affordance class than opening a memory/clip/project; native `.onDelete` is idiomatic there and the deletion-lock's "deliberate scroll to a foot button" rationale doesn't fit a settings row. Keeping `.onDelete` is defensible. Tom's call.

**(b) [coherence] Delete the dead `SwipeToDelete` / `SwipeToDiscard` components** — zero callers repo-wide (only their own `#Preview` blocks). Retirement candidates; reuse/coherence cleanup.

**(c) [coherence] Scrub stale swipe doc-comments** in `ChronologicalCaptureStream.swift` (lines 9–20, 521 — "trailing swipe deletes") and `JournalView.swift` — they describe a mechanism that no longer exists.

*Order:* hold (a) for Tom's ruling; fold (b)+(c) into whatever cycle next touches those files.

---

## P5 · Stale comment cleanup

`CreateMemoryFromClipsSheet.swift:10-11` doc-comment still reads "(Make a Memory · confirm sheet)" — retired verb. Fix to "Start a Memory". **Bonus (CC):** the same comment references `docs/Himem · Captured Clips (session-first)-2.html`, itself a retired doc name — update in the same one-liner.

---

## Suggested order

1. **P1** (durable-wake) — the active dogfood frustration; standalone Bug-First cycle.
2. **P3** (render-side fail-safe) — cheap, closes the latent recurrence of a data-corruption bug.
3. **P5** (stale comment + retired doc ref) — trivial, fold into any cycle.
4. **P2** (PAUSED flicker) — its own cycle when P1 is proven in dogfood.
5. **P4** — hold (a) for Tom's ruling on the Topics-list swipe; fold (b) dead-component deletion + (c) stale-comment scrub into whatever cycle touches those files.

Watch, don't chase: the spreading test-flake (`DebouncedTriggerTests`, now `JournalViewModelLoadInitialTests`) — shared state across parallel `@Suite` runs; aligns with the existing `@Suite(.serialized)` rule in `CLAUDE.md` for shared-singleton suites. When a third flakes, stop and apply `.serialized` rather than whack-a-mole.

---

## P6 · "Let Go of this Memory" must NOT cascade-delete its clips (behavior verify — July 15 2026)

**Spec source:** `Memory Detail · unified editing model.md` (Deletion row) + `HiMem · Locked Decisions.html` — reconciled to the July 13 Trash-by-object lock this session.

**The *what* (not negotiable):** deleting a memory is **"Let Go of this Memory"** — the *derived layer* (title · summary · topics · annotations) dissolves, **but its clips survive** and return to availability on the bench to start other memories ("The clips stay — they'll be available to start other memories"). A memory deletion is **not** a clip deletion. Only **"Delete this Clip"** destroys an atom (and it removes that clip from *every* memory referencing it, with a live-count warning).

**CC action — verify, then fix only if it diverges:** confirm the shipped memory-delete path does **not** hard-delete the memory's clips. Clip↔Memory is many-to-many; letting go of a memory should tear down the *edges/derived context* and leave the clip atoms on the bench. If the current build cascade-deletes clips with the memory, that's a behavior bug against the lock — fix it so clips survive. If it already de-associates only, this is a no-op confirmation. Bug-First; four-part handoff. **This is the one item in the Memories reconcile that is more than a label** — the rest (labels, Active-Nav-Tap exemption, empty state) are spec/copy.

*Related deferred (not this item):* the `Delete this Clip` live-count warning UI ("attached to N memories…") — surface when Memories deletion UI is next built.

---

## P8 · Last-reference deletion rule (locked July 19 2026 — narrowly reverses the P6 "clips always survive Let Go" lock)

**Spec source:** `CLAUDE.md` § Phone (deletion sub-rule, Let Go) · `Memory Detail · unified editing model.md` (Deletion rows) · `HiMem · evidence and context.md` · `Captured Clips · session-first · spec.md` § Unconnected cleanup. Origin: dogfood — letting go of a memory left a pile of unexpected orphan clips ("untenable"). **This supersedes P6's blanket "its clips survive."**

**The rule (memory-deletion-only, decided from current edge counts at delete time — no `everConnected`/history field, no deploy for the decision itself):**
- Deleting a memory: a clip with **edge count > 1** (used by another memory) **stays**; a clip whose **single remaining edge is this memory** **moves to Recently Deleted** with it.
- **Detach-a-clip-from-its-last-memory does NOT auto-retire** — the clip stays Unconnected on the bench ("not *here*" ≠ "not wanted").
- **AI reorganization never auto-retires** — structural change, not user rejection.
- **Delete a clip** → Recently Deleted (explicit, unchanged).
- The Let Go sheet **discloses the split, never asks**: "8 clips are also used elsewhere and will stay · 5 are only here and move to Recently Deleted for 30 days." No checkbox forest.

**Hard precondition (blocking, not fast-follow):** retired clips need clip-level **Recently Deleted** — `MediaReference.recycledAt` (rides the next CloudKit deploy) + `RecycleBinView` clip support. The auto-retire path must not ship before the net exists.

**Consequence:** shrinks — does not remove — the Unconnected bucket (genuinely-free, never-attached clips still live there); P7's Unconnected cleanup surface stays.

**CC action:** implement the edge-count decision inside the memory-delete transaction; wire the split-count Let Go sheet; ship `recycledAt` clip-level Recently Deleted alongside. Bug-First; four-part handoff.

*Deferred post-v1 candidate (logged, not this cycle):* **AI suggests alternative summaries** — merged with the deferred voice-register picker (m1737); honest reframings (emphasis/length) only, never alternate tone; likely free (taste, not intelligence). Cheapest honest form is a *"Show another"* re-run on the reorganize review sheet, not a grid.

---

## P7 · Clips filter cycle — New·All·Unconnected + top-ordering + source-glyph write-side (July 18 2026; label July 19 2026)

**Spec source:** `Captured Clips · session-first · spec.md` § "Clip lifecycle + the status lens" and § "Unconnected-clip cleanup" (locked July 18 2026); `CLAUDE.md` § Phone (status axis redefined). One coherent cycle — the dogfood Clips screen (9-screenshot set, July 18) exposed all of these together.

**(1) [P1 · new] New/unshaped clips must sort to the TOP.** Shipped build buries the "N new clips" session block *below* months of reverse-chron flat list (new arrivals appear after May 19). Whatever is surfaced as "to look at" goes first — the session/new block is the top of the screen, older/connected clips below. Distinct from the model change; it's an ordering bug.

**(2) [pure code, no deploy] Redefine the status lens to `New · All · Unconnected`** (chip label "Unconnected," not "Loose"/"Available") per the lock: two orthogonal properties — **review state** (stored `reviewed` bool: New=`reviewed==false`, Reviewed=`reviewed==true`, "opened by you") and **connection count** (derived: Loose=`connectionCount==0`). Filters are one predicate each. New = unseen (aligns with the tab dot). **`reviewed` is per-device, NOT synced** — a local field on `InboxClip` (manifest) and bench `MediaReference`; the V7 batch already shipped, so this needs **no CloudKit deploy**. Cross-device review-sync is out of scope for v1 (rides the post-v1 bench→MediaReference unification). "Attached" is a relationship, not a state. "Orphaned" is architecture-only; UI says "Loose."

**(3) [pure code + per-device field] Unconnected-clip cleanup.** The Unconnected filter surfaces every `connectionCount==0` clip → **multi-select → Delete / Add to a memory** (Photos-style; reuse the Sort multi-select + its single ochre commit). Delete = "Delete this Clip" (destroys atom → Recently Deleted). **No cascade** at memory/project deletion (Let Go lock), **no branching** at deletion time — cleanup is the deliberate bench act. No Loose count/badge (workbench-not-queue). *This is the highest daily-value item — the dogfood bench is full of clearable throwaways.*

**(4) [pending, already flagged — needs its own deploy] Source-glyph write-side coverage.** Photo/video + watch clips show no source glyph because `sourceDevice` isn't threaded through watch-promotion + composer/append paths (read-side + helper already in place). Thread `.watch`/`.phone` through the remaining capture paths. `sourceDevice` shipped in the V7 batch, so this is **write-side wiring only, no new deploy**.

**(5) [deferred — YAGNI] Source as a filter facet.** A "Watch" chip in the *type* row is rejected (category error — a watch clip is a voice clip; source ≠ media type). If source-filtering proves useful in dogfood, it's a **third axis** ("From: any/watch/phone/Siri"), not a type chip. Deferred for v1; the glyph answers "where from?" without a filter. *Note: the Watch captures **audio only** (per `Watch · spec.md`), so a watch source is always a voice clip — reinforces that "Watch" is a source, never a media-type peer.*

*Order:* (1) ships independently now (pure code, no schema). (2)+(3)+(4) are all pure code / per-device local fields / write-side wiring — **no CloudKit deploy** (V7 already shipped `Mention`/`recycledAt`/`sourceDevice`). One cycle, verified on device (arbiter live for the delete paths). **Cross-device review-sync is explicitly out of scope** — logged as a post-v1 property of bench→MediaReference unification.

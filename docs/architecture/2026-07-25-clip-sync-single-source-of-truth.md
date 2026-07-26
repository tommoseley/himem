# Clip sync — MediaReference as single source of truth (P0-3)

**Status:** IN PROGRESS (2026-07-25). Locked first principle: *"We don't make people hurt for the evidence — a clip is an atom and follows the person, never the device"* (`HiMem · Locked Decisions.html`). A captured clip stranded on the device that caught it violates it.

## The change
A captured clip becomes a CloudKit-synced **zero-edge `MediaReference` on arrival** (when fully received + transcribed), not on placement. The bench reads zero-edge `MediaReference`s, not the per-device `InboxManifest`. Memories already sync this way — no new mechanism.

**Q1 finding (locked):** this is a **representation-only change**. Bench/inbox audio already lives in the iCloud Files ubiquity container (`Documents/Inbox/`), so the *bytes already sync*; only the metadata row was stranded (`manifest.json`, sandbox). **No blob relocation, no schema change, no external deploy gate.**

## Design decisions

### 1. `transcriptionAttempted` is derived from *which store the clip lives in* — a design improvement, not a workaround (Tom, 2026-07-25)
The bench's accidental / transcribing / failed state does **not** become a stored `MediaReference` flag. A ref only materializes **after** transcription completes (piece A's contract), and in-flight/transcribing clips stay in the manifest (manifest = in-flight transfer state only). Therefore:
- **transcribing** = still in the manifest (in-flight);
- a **materialized ref** is by definition post-attempt;
- an **empty-transcript ref** = accidental (ran, produced nothing).

This *derives* the state from position rather than storing a flag that can disagree with reality — the same discipline as deriving connection-count from edges (P0-2 / `referencingMemoryCount`) and the not-recycled state from `recycledAt`. It is strictly better than the old stored `InboxClip.transcriptionAttempted`.

### 2. `duration` is derived async (`AVURLAsset.load(.duration)`), degrading gracefully — no schema change (Tom, 2026-07-25, ruling a)
`MediaReference` has no `duration`; the session-duration line resolves asynchronously and degrades until it lands, **exactly as the All lens already does** for voice refs today. Keeps P0-3 a pure representation change with no CloudKit deploy.

### 3. Bench read path — synth-adapter (a *how*)
`SessionListView` fetches zero-edge voice refs (`edges.@count == 0 AND recycledAt == nil AND mediaType == voice`) and maps each to a synthetic `InboxClip` value, feeding the existing grouper/proposer/absorber/render UNCHANGED. `UnifiedBenchGrouper` is dead scaffold — not used. Reactivity swaps `@Published inbox.clips` → `@FetchRequest` / `NSManagedObjectContextObjectsDidChange` + `DebouncedTrigger` (the proven `ClipsTabView` pattern).

## Risk rulings (Tom, all three up front)
1. **Double-render** (a clip existing as both a manifest row and a materialized ref during the migration window) → hard **`id`-keyed dedup at the compose layer** + **migration-before-first-render**. Treated as a **P0 bug-first test**, not polish.
2. **`reviewed` per-device** → stays per-device (already is); flag carried in migration; cross-device New-dot inconsistency logged as known. **No scope expansion to sync it.**
3. **Watch redelivery** → the manifest **tombstone gate survives**. A materialized ref can be deleted (recycled → purged), so it cannot be the redelivery dedup marker; the manifest is **retained purely as a tombstone ledger** (acceptable residue — never a metadata source of truth).

## Sequence (all landed 2026-07-25, branch `clip-sync-single-source`)
- **A** ✅ `ArrivedClipMaterializer` — materialize-on-arrival (zero-edge ref `id == clipId` when transcription completes; manifest active row → `removeBatch` tombstone; in-flight + tombstones stay). Audio move injectable at the boundary. Commit `f938dbc`, 9 money tests.
- **B** ✅ bench reads refs — `SessionListView.composeBenchClips` unions in-flight manifest rows with synth-mapped zero-edge refs (`syntheticClip`), deduped by clipId (ref wins). Reactivity: recompute on manifest change, arrivals change, AND `NSManagedObjectContextObjectsDidChange`. `materializeAll` runs in `onAppear` before first render. `WatchSessionDelegate` materializes on transcription-complete (bench-open-independent). Commit `8b1f703`.
- **C** ✅ placement edges the existing ref — `createMemory` / `appendToExistingMemory` / `PlaceClipSheet.commit` now materialize-then-`attachExistingClips` (or `createMemoryFromExistingClips`). Deleted `placeInboxClip` / `createMemoryFromInboxClip` / `moveInboxAudioIfNeeded` + the sheet move-loops + `dumpPathDiagnostic`. Commit `20ca598`, 4 money tests. **The double-ref bug (B-without-C) is the thing C exists to prevent.**
- **migration** ✅ **`materializeAll` IS the migration** — it runs on every bench `onAppear`, so the first post-upgrade Clips-tab open sweeps every pre-existing `.transcribed` manifest clip into a ref (`id == clipId`, `reviewed` carried), idempotent thereafter (`materializeAll_isIdempotentAcrossAppears`). Kept OFF the cold-launch path (per the 400ms target) — pre-existing clips still render on the bench from the manifest union until that first sweep, so no data is lost in the interim; new clips sync immediately via the arrival-materialize wiring.

## Write-path coherence sweep (added after C — non-negotiable #2)
Post-materialize a bench clip is a ref, but several per-clip write paths were statically dispatched on the `.inbox` `Source` and so **silently no-op'd on a materialized clip**. All now route through backing-aware lifecycle methods (ref-if-exists-else-manifest):
- **transcript edit** (`ClipEditorModal` `.inbox`) + **Transcribe-again** (`SessionListView.applyClipRetryOutcome`) → `writeBenchClipTranscript`.
- **delete** (`ClipEditorModal.deleteClip` `.inbox`) → `recycleBenchClip`.
- **reviewed-on-open** (`ClipEditorModal` `.inbox`) → marks BOTH the manifest flag and the ref-keyed `BenchClipReviewStore`.
- **duration** — `BenchClipDurationStore` caches the payload duration at materialize (ref has no duration attribute); the bench card shows real session length on the originating device (`syntheticClip` reads it), degrading to 0 on a receive-only device pending async `AVURLAsset` derivation.
  - **Why the cache, not the ruling's plain async-only (Tom, 2026-07-25 — approved as an improvement on ruling a):** ruling (a) accepted *degradation until it resolves*, NOT a permanent "0:00." A permanently-wrong duration is a **lie in the UI — the same Honest-Label class as an invented name**, not graceful degradation. The cache gives the capture device the truth immediately and is still schema-free; async `AVURLAsset` derivation on the bench card for receive-only devices is the logged follow-up (`docs/issues/2026-07-25-p0-3-followups.md`), not a blocker.

Verified NOT gaps: `ClipsTabView.performSelectionDelete` partitions dynamically against the live manifest (materialized clips fall into `refIds`); `soloClipIds` is clipId-keyed on `benchClips` (backing-agnostic); `SessionListView`'s session-open review already marks both stores; `ClipDetailView` is dead (no constructors — superseded by `ClipEditorModal`), so its `.inbox` write path is unreachable.

## Follow-ups (flagged, not done in this PR)
- **`ClipDetailView` is dead** (no constructors) — remove it in a follow-up.
- `createMemoryFromVoiceClips` + `appendClips` are now **production-dead** (only test-covered) after C rewired their callers. Recommend removing them with `CreateMemoryFromClipsAssemblyTests` / `EntryLifecycleServiceAppendClipsTests` in a follow-up.
- Pre-existing red on the branch (NOT from this work, reproduced on the A-only state which touches no `ProcessingEngine` code): `ExistingMentionsRefinementTests.processEntry_sendsExistingMentionValuesToAnalyzer` + `…_dedupedCaseInsensitively` — `processEntry` sends an empty existing-mentions list. Worth its own bug-first cycle.

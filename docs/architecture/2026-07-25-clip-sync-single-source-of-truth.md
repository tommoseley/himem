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

## Sequence
- **A** · materialize-on-arrival (zero-edge ref when transcription completes; manifest active row → removed; in-flight + tombstones stay).
- **B** · bench reads refs (synth-adapter; reactivity swap).
- **C** · placement → `createEdge` on the existing ref; **delete** `placeInboxClip` / `createMemoryFromInboxClip` + the audio-move blocks.
- **migration** · one-shot launch migration of clips in existing manifests → refs, `id == clipId` idempotency key, carry `reviewed`.

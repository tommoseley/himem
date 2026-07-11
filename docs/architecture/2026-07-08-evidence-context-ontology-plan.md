# Evidence + Context ontology — build plan (v2, post-troika)

*2026-07-08. Plan for landing the many-to-many clip↔memory schema + three-tab nav + Clip Detail before TestFlight, per `docs/design/HiMem · evidence and context.md` (locked v1) and `docs/design/HiMem · the shaping model.md`.*

*v2 of this plan incorporates the July 8 troika review (R1 schema/migration, R2 ontology, R3 tests/scope). Key shape change from v1: **two-step model version bump** (v2 additive → v3 subtractive) with a per-version CloudKit deploy and a Prod-deploy soak between them; Phase 2 and Phase 3 merged so read+write flip atomically; scripted JSON export as the real rollback.*

---

## Goal

Ship v1 with the **correct data model** — a clip is evidence, referenced by 0–N memories via an associative edge that carries the annotation. Every read path walks the edge; membership is never encoded on the clip itself. The three-tab nav (Clips · Memories · Projects) replaces the current landing surface. A new Clip Detail screen makes multi-placement legible.

Everything below is v1, pre-TestFlight, non-negotiable per the ontology doc.

## Non-goals

- **Annotation writing surface** — the `annotation` field ships in the schema (nullable), no UI writes to it in v1. Post-launch surface.
- **AI-proposed association** — schema-ready, staged.
- **Cross-appearance discovery / reflection surfaces** — schema-ready, staged.
- **Studio surfaces** — post-launch.
- **Retiring `InboxManifest`** — it stays as the sync-arrival state (pre-transcription). See § "Why InboxManifest stays."
- **Retiring `textSegments` legacy field** — separate cleanup, filed as tech debt (§ Tech debt below).

## Decisions

1. **Edge entity name: `MemoryClipEdge`.** Mirrors the doc's language; unambiguous.

2. **"Capture returns to Clips" = UI-level, not flow-level.** After phone commit, land on Clips tab. Phone FAB voice stays direct-to-memory.

3. **Annotation UI is out of v1** (schema in, surface out). Nullable `String?`.

4. **Icon-badge count: dropped in v1.** Passive Channel A notification still fires.

5. **`MediaReference.entryId` and `MediaReference.entry` are removed — in v3, not v2.** v2 keeps them as a *read-only shim* (populated but not read); v3 deletes them once Phase 3 has flipped both read and write paths to edges and the fixup has completed on-device. See § Migration.

6. **Two-step migration.** v1 model → v2 (additive: adds `MemoryClipEdge` + `edges` inverses; keeps everything else) → fixup pass → v3 (subtractive: removes `entry`/`entryId`/`mediaReferences`). Each version deploys to CloudKit Production separately with a soak gate between.

7. **CloudKit Production schema deploy is a hard gate.** v2 deploy: between Phase 1 and Phase 2/3. v3 deploy: between Phase 4 land and Phase 5 start. **Between deploy and next phase, wait for a 24h Prod-schema-settle soak** — Apple gives no propagation SLA, and prior HiMem work confirmed multi-hour delays.

8. **The 2026-07-07 `capturedAt` post-save fixup is retired** — replaced by end-to-end `capturedAt` threading. Both fixup blocks disappear (`SortBatchCommit.swift:117-137` AND `CreateMemoryFromClipsSheet.swift:512-524`). The existing `SortBatchCommitCapturedAtTests` is **preserved as the end-to-end regression guard**; a new `CreateMediaReferenceCapturedAtTests` covers the creation-time contract at the unit level. Both stay in the suite.

9. **Rollback path is a scripted JSON export**, not "restore from Xcode backup." A debug command dumps every JournalEntry + MediaReference (with their pre-migration relationship) to Documents/pre-evidence-migration-YYYYMMDD-HHMM.json before Phase 1 lands. Runs automatically at first launch after the app is updated with Phase 1 code, once — flag in Core Data (not iCloud KV). If migration goes sideways, the JSON is the source of truth for recovery.

10. **The InboxManifest ↔ MediaReference dual-store is a defensible v1 pragma, not a workaround** — see § Why InboxManifest stays.

## Decisions — resolved 2026-07-08 by Tom

- **Doc leftover — CLAUDE.md line 187:** edited to "One canonical name in app chrome: **Clips**. 'X new from Apple Watch' remains banner copy for the arrival state." Confirmed.

- **Delete-clip copy:** "**This is attached to N memories**" (not the ontology's "evidence in" — softer, less architectural, still conveys the placement warning without sounding like the app is talking to itself). Confirmed by Tom.

- **"Referenced in" on Clip Detail** — title + date + one-line, tappable. Not full cards. Confirmed.

- **48h soak across v2 + v3 CloudKit Prod deploys** acceptable. Confirmed.

- **JSON snapshot rollback** (~5-10MB in Documents for Tom's dogfood store) is the recovery path we're committing to. Confirmed.

## Temporary v1 invariant: no zero-edge MediaReferences before Phase 4 lands

**During Phases 1 through 4, every `MediaReference` must have `edges.count >= 1` at all times.**

This is a *temporary* invariant — it exists so Phase 4's `V3MigrationPreconditionTests.refusesToAdvanceIfOrphanRefExists` guard has a clean rule to enforce and so the v2→v3 subtractive migration can't be pushed onto a device carrying orphan refs. **Post-Phase-4, once v3 is live, zero-edge refs become legitimate** — that's the "returned from a memory" state the shaping model requires and the Phase 6 Clips tab default view reads from.

Why this needs to be explicit:

- The Phase 4 guard is silent about *why* it rejects zero-edge refs. Read in isolation, it looks like a permanent rule against the ontology's "unplaced evidence" state, which it isn't.
- The zero-edge state is a *feature* that lands in Phase 6 (removing a clip from its last memory returns it to Clips as unplaced evidence). Reading Phase 6 without Phase 4's context, a future implementer could add the "remove from last memory" affordance without realizing it must not ship until Phase 4 has landed and locked the v3 schema.
- If a bug during Phases 1-3 accidentally creates a zero-edge ref (e.g. a write path forgets to create the edge), the invariant catches it at test time — not at Phase 4 when Tom's device fails to migrate.

Enforcement:
- **Test** (lives in the Phase 2+3 suite): `NoZeroEdgeMediaReferencesInvariantTests.everyWritePathCreatesAtLeastOneEdge` — exercise every entry point that creates a `MediaReference` (`createMediaReference`, `createVoiceFragment`, `createNoteFragment`, `SortBatchCommit`, `CreateMemoryFromClipsSheet.createMemory` / `appendToExistingMemory`, `EntryLifecycleService.appendClips` / `save` / `append` / `finalizeContribution` / `createNoteFragment`) → assert every resulting ref has `edges.count >= 1`.
- **Runtime assertion** in Debug: `StorageService.save` performs a lightweight sweep of newly-inserted `MediaReference` objects in the context and `assertionFailure`s on any with `edges.isEmpty`. Guarded by `#if DEBUG` so Release builds never crash a user for this. This catches drift in code paths the test suite doesn't cover (rare, but the invariant is load-bearing).
- **Phase 6 explicitly unlocks this.** When Phase 6 lands, both the test and the debug assertion are removed (the invariant no longer holds — zero-edge is legitimate). This is called out in Phase 6's deliverables so the removal isn't forgotten.

The plan calls out this invariant in:
- Phase 1 (fixup must create at least one edge per pre-existing ref — trivially true, but noted).
- Phase 2+3 (every new write must create an edge; test + assertion in place).
- Phase 4 (guard checks no zero-edge refs before v3 subtractive lands; the invariant lets this be an atomic `for ref in refs { if ref.edges.isEmpty { fail } }` check, not a heuristic).
- Phase 6 (invariant retired; test + assertion removed; zero-edge is now the "returned from memory" state).

---

## Why InboxManifest stays (v1 pragma)

The ontology says "evidence stored once." A strictly-pure reading would promote every `InboxClip` to a `MediaReference` at arrival, retiring `InboxManifest` as evidence storage and keeping only its wire-state tracking (announced / received / transcribing / transcribed).

We are NOT doing that in v1. Reasoning:

- **Arrival-time state is genuinely different from evidence.** A clip that's `announced` but the file hasn't landed isn't yet evidence — its bytes don't exist on this device. Promoting to `MediaReference` at that point means either creating placeholder refs (which introduce a "clip exists but has no audio" state we'd have to teach), or waiting until `.received` to promote (which is when the audio lands, i.e. arrival-time is real). The current split ("evidence exists once placement happens") IS an arrival-time promotion — placement is when the audio finishes moving to durable storage and the clip becomes a citable, indexable primary source.

- **CloudKit cost.** `InboxManifest` is a JSON side-store — not CloudKit-synced (per-device inbox state). Promoting arrival-side clips to `MediaReference` puts them into the CloudKit-synced Core Data store. Every arrival then syncs a full MediaReference record even for clips the user later discards — extra CloudKit ops, extra iCloud storage per user.

- **Delete-before-placement.** If a clip arrives, the user opens Sort, decides they don't want it, taps *Delete* on the loose card — that's a lightweight InboxManifest-only operation today. Under arrival-time-promotion, it becomes a CloudKit-synced MediaReference deletion — round-trip, tombstone, sync propagation.

- **What v1 must guarantee:** once a clip is `MediaReference` (i.e. placed), it *is* evidence, referenced by 1..N memories via edges. That invariant holds. The pre-placement transient state living in InboxManifest is a bookkeeping choice, not an ontology violation — the ontology is about evidence-once, and pre-placement clips aren't yet evidence in the ontology's own sense.

- **Post-v1 direction (not this plan):** the "returned from a memory" case (per shaping model) creates unplaced MediaReferences — they exist as evidence with no edges. Clips tab reads *both* stores (InboxManifest for pre-placement + MediaReference where `edges.count == 0` for returned). Two-source-of-truth for "unplaced" is legitimate: they're semantically different sub-states of unplaced. Unifying them at the store level is a v1.1 cleanup if dogfood shows the split leaks anywhere; the plan does NOT gate v1 on it.

## Schema

### New entity: `MemoryClipEdge`

CloudKit-synced (private DB).

| Field | Type | Nullable | Purpose |
|---|---|---|---|
| `id` | UUID | no | Primary key |
| `clipId` | UUID | no | Denormalized FK to `MediaReference.id`; enables CloudKit queries + uniqueness constraint |
| `memoryId` | UUID | no | Denormalized FK to `JournalEntry.id` |
| `clip` | Relationship to `MediaReference` | no | Inverse: `MediaReference.edges`. Delete rule: **Nullify** on the edge side (deleting an edge does NOT delete the clip). |
| `memory` | Relationship to `JournalEntry` | no | Inverse: `JournalEntry.edges`. Delete rule: **Nullify** on the edge side. |
| `annotation` | String | yes | "Why this matters here." No v1 UI writes it. |
| `orderInMemory` | Int16 | no | Position within the memory's chronological stream. `0` = first. |
| `linkedAt` | Date | no | When this edge was created. Enables "added later" surfacing. |

**Uniqueness constraint:** ~~compound `(clipId, memoryId)`~~ **removed** during Phase 1 build. `NSPersistentCloudKitContainer` documents that uniqueness constraints on Cloud-synced entities are ignored — the constraint would only fire in a Local-only test context, which is misleading. Enforcement lives at the application layer: `EvidenceEdgeMigration._run` and the (yet-to-land Phase 2+3) write paths do an `edgeExists(clipId:memoryId:)` check before insert. `fixupIsIdempotent` money test covers the crash-mid-fixup case; multi-device races are a documented v1.1 concern to address with read-time dedup if it surfaces.

**Delete rule symmetry:**
- On the `MediaReference` side: `edges` = **Cascade** (deleting the clip destroys its edges).
- On the `JournalEntry` side: `edges` = **Cascade** (deleting the memory destroys its edges).
- On the `MemoryClipEdge` side: `clip` = **Nullify**, `memory` = **Nullify** (deleting an edge never destroys its endpoints).

This is what "cascade from both sides" means unambiguously.

### `MediaReference` — v2 (additive)

Keeps `entryId: UUID` and `entry: JournalEntry?` (read-only shim during Phase 2+3).
Adds `edges: NSSet?` (to-many inverse of `MemoryClipEdge.clip`).

**Delete-cascade caveat (Phase 2+3 delete rewrite):** the legacy `JournalEntry.mediaReferences` relationship is Cascade in v2 (unchanged from v1 to keep the additive migration truly additive). Under the new ontology, deleting a memory must not destroy its clips. Phase 2+3's `EntryLifecycleService.delete(entryId:)` rewrite MUST explicitly clear the memory's `mediaReferences` set (removing the inbound references) before calling delete, so the Cascade has nothing to cascade. The edge cleanup happens separately via `MemoryClipEdge` Cascade rules. Test: `DeletionSemanticsTests.deleteMemoryDuringV2PreservesClipsDespiteLegacyCascade`.

### `MediaReference` — v3 (subtractive)

Removes `entryId` and `entry`. `edges` remains.

### `JournalEntry` — v2 (additive)

Keeps `mediaReferences: NSSet?` (read-only shim).
Adds `edges: NSSet?` (to-many inverse of `MemoryClipEdge.memory`).

### `JournalEntry` — v3 (subtractive)

Removes `mediaReferences`. `edges` remains.

## Migration

### Model versioning mechanics

- `MemoryStream.xcdatamodeld/` currently contains only `MemoryStream.xcdatamodel` (a single unversioned model). Bumping requires:
  1. Add new versions via Xcode: Editor → Add Model Version → name it `MemoryStream 2.xcdatamodel` (based on the current). Then again for `MemoryStream 3.xcdatamodel`.
  2. This creates `MemoryStream.xcdatamodeld/.xccurrentversion` (a plist pointing at the active version). **Verify this file exists and points at the correct version after each bump.**
  3. `StorageService` uses `NSPersistentCloudKitContainer` which handles lightweight migration automatically when `NSMigratePersistentStoresAutomaticallyOption` and `NSInferMappingModelAutomaticallyOption` are both true (verify in `StorageService.setupContainer` before Phase 1).

### v1 → v2 (Phase 1)

**Additive lightweight migration.** No fields dropped. Core Data infers the mapping automatically.

**Data fixup pass** (runs after migration completes, in `LaunchScreenView.runMigration()` on a background context, per `feedback_inboxmanifest_launch_gating.md`):

```
Marker: EvidenceEdgeMigrationMarker Core Data entity, single row, has_run: Bool.
     (Local marker, NOT UserDefaults/iCloud KV — the fixup is per-store, not per-user.)

Guard: if marker.has_run == true, no-op.

Pre-fixup rollback snapshot:
  Serialize all JournalEntries + MediaReferences + their (entryId → id) mapping
  to `Documents/pre-evidence-migration-<ISO8601>.json`. This is the debug rollback.
  Runs before any edge is written.

Fixup body (batched per-memory to bound transaction size):
  Fetch all JournalEntry ids.
  For each memoryId (in chunks of 20 memories):
    performBackgroundTask:
      For each JournalEntry E in this chunk:
        Sort E.mediaReferencesArray by (createdAt ?? distantPast)
        For each (order, ref) in enumerated:
          If no MemoryClipEdge exists with (clipId: ref.id, memoryId: E.id):
            Create MemoryClipEdge(
              clipId: ref.id,
              memoryId: E.id,
              clip: ref,
              memory: E,
              annotation: nil,
              orderInMemory: Int16(order),
              linkedAt: ref.createdAt ?? E.createdAt
            )
      Save this chunk's context.
  Set marker.has_run = true. Save.
```

**Batching rationale:** Tom's dogfood has ~100 memories × ~5 refs each = ~500 edges. A single transaction is fine at that scale; batching per-20 keeps it safe if the store grows. Never save inside the inner loop — batch at chunk boundaries.

**Idempotency:** the uniqueness constraint on `MemoryClipEdge(clipId, memoryId)` guarantees the "if no edge exists" check is safe under crash. On crash-mid-chunk, the next launch's fixup re-checks and skips existing edges. The marker prevents re-running the JSON snapshot.

### v2 → v3 (Phase 4)

**Subtractive lightweight migration.** Removes `entry`, `entryId`, `mediaReferences`. Core Data infers the mapping.

**Precondition to bump:** `EvidenceEdgeMigrationMarker.has_run == true` AND every existing `MediaReference` has `edges.count >= 1` (i.e. no orphans post-fixup). Guarded in `LaunchScreenView.runMigration()`.

If the precondition fails on Tom's device (e.g. a fixup bug), Phase 4 does not launch: app shows a hard error state and refuses to proceed. Better than silently dropping data.

### CloudKit deploy sequencing

- **Phase 1 ends** with v2 schema in CloudKit **Development** (auto-published from Debug build).
- **Manual step:** deploy v2 to CloudKit **Production** via Dashboard. **Wait 24 hours** for propagation. Verify on a fresh iCloud account that new schema is live.
- **Phase 2+3** starts only after v2 Prod is confirmed live.
- **Phase 4 ends** with v3 schema in Development.
- **Manual step:** deploy v3 to CloudKit **Production**. **Wait 24 hours.** Verify.
- **Phase 5** starts only after v3 Prod is confirmed live.

Total soak time: 48h across two Prod deploys. Non-negotiable.

### Migration risk register

| Risk | Mitigation | Test |
|---|---|---|
| Fixup fails partway (crash mid-loop) | Uniqueness constraint + idempotent skip-if-exists; per-chunk saves | `fixupResumesAfterCrash` (fault-inject after N iterations) |
| CloudKit inbound sync of old-schema records after v3 deploy | v2 kept the fields; only devices at v3 stop reading them. Cross-device skew during rollout uses the v2-additive-only step first. | `cloudKitRoundTripPreservesEdges` |
| User reinstalls before fixup completes | Fixup marker in Core Data (local store); reinstall recreates the local store from CloudKit which contains edges + legacy fields. Re-migration on next launch is a no-op if edges exist. | `fixupNoOpsWhenEdgesExist` |
| Tom's dev device has a partially-migrated store | Precondition guard on v2→v3 prevents advancing until fixup is complete. JSON export provides ground-truth for manual recovery. | Manual real-device gate before Phase 5 |
| Zero-mediaReferences memory | Fixup handles empty inner loop cleanly | `fixupHandlesEmptyMediaReferences` |
| Fixup accidentally touches `textSegments` | Loop only reads `mediaReferences`; no writes to other fields | `fixupDoesNotPerturbTextSegments` |

## Phased implementation

Each phase ends with all tests passing and a build that launches cleanly on device. Phases 2+3 are atomic (one PR). CloudKit soak gates are hard.

### Phase 0 — Naming decisions + doc cleanup

**Blockers:** Tom confirms name, delete-clip copy, CLAUDE.md line 187 fix.

**Deliverables:** CLAUDE.md leftover fixed. Naming locked in this plan.

**Tests:** none (doc pass).

### Phase 1 — v2 schema + fixup + JSON snapshot

**Deliverables:**
- `MemoryStream 2.xcdatamodel` (additive; keeps legacy fields; adds `MemoryClipEdge` + inverses).
- `EvidenceEdgeMigrationMarker.swift` entity (single-row marker in Core Data).
- `EvidenceEdgeMigration.swift` — idempotent fixup with per-chunk save. Runs in `LaunchScreenView.runMigration()`.
- `PreEvidenceMigrationSnapshot.swift` — writes JSON before fixup runs.
- `MemoryClipEdge.swift` — managed object subclass + convenience accessors.
- Uniqueness constraint on `(clipId, memoryId)` in the model.

**Money tests (each must fail before the phase and pass after):**
1. `EvidenceEdgeMigrationTests.fixupCreatesOneEdgePerRefEntryPair` — N memories × M refs → N×M edges with correct `orderInMemory`.
2. `EvidenceEdgeMigrationTests.fixupIsIdempotent` — running fixup twice = same edge count as running once.
3. `EvidenceEdgeMigrationTests.fixupPreservesOrderInMemory` — three clips at t0/t1/t2 → orderInMemory 0/1/2.
4. `EvidenceEdgeMigrationTests.fixupSetsLinkedAtFromClipCreatedAt` — historical clip times ride through.
5. `EvidenceEdgeMigrationTests.fixupResumesAfterCrash` — inject a fault after N iterations; re-run; assert no duplicate edges (uniqueness constraint) and complete coverage.
6. `EvidenceEdgeMigrationTests.fixupHandlesEmptyMediaReferences` — memory with zero clips → zero edges, no crash.
7. `EvidenceEdgeMigrationTests.fixupDoesNotPerturbTextSegments` — memory with `.textSegments` set → fixup leaves them untouched.
8. `EvidenceEdgeMigrationTests.uniqueConstraintPreventsDuplicateEdges` — attempt to create a second edge with same (clipId, memoryId) → constraint fires.
9. `PreEvidenceMigrationSnapshotTests.snapshotWrittenBeforeFixup` — snapshot file exists in Documents before fixup starts; contains all JournalEntry + MediaReference IDs + relationship map.
10. `EvidenceEdgeCloudKitRoundTripTests.edgesSurviveCloudKitMirror` — seed edges → mirror transactions → deserialize into fresh store → all edges intact with correct `orderInMemory` + `linkedAt`.

**Gate to Phase 2/3:** all 10 tests pass; Debug build against real device publishes v2 schema to CloudKit Development; **Prod deploy of v2 + 24h soak** before Phase 2/3 code lands.

### Phase 2+3 (atomic) — Read+write paths through edges

Read and write flip together in one PR. During transition (fixup ran, but before this phase), reads still walk legacy relationships. During this phase, reads walk edges + writes create edges. Legacy fields remain populated (v2 keeps them) but read-only shim.

**Files affected (verified via grep):**
- `MemoryStream/Models/JournalEntry.swift` — `mediaReferencesArray` walks edges. Add `edgesArray` computed prop for iteration.
- `MemoryStream/Models/MediaReference.swift` — add `edgesArray` + `memoriesArray` computed props. Keep `entry` present (read-only shim).
- `MemoryStream/Services/Storage/EntryLifecycleService.swift` — `joinedContent(from:)`, `regenerateContent`, `updateNoteFragment`, `updateMediaTranscript`, `updateMediaDescription`, `removeMedia`, `finalizeContribution`, `migrateOrphanedContentIfNeeded`, `appendClips`, `save`, `append` all walk edges.
- `MemoryStream/Services/Storage/StorageService.swift` — `createMediaReference` gains `memory: JournalEntry` param + optional `capturedAt: Date?`, creates the ref + edge atomically. Same for `createVoiceFragment`, `createNoteFragment`.
- `MemoryStream/Services/Storage/SortBatchCommit.swift` — creates memory + edges. **Deletes the post-save `capturedAt` fixup block (lines 117-137 per current file).**
- `MemoryStream/Views/Inbox/CreateMemoryFromClipsSheet.swift` — both `createMemory` and `appendToExistingMemory` create edges. **Deletes the post-save fixup block (lines 512-524 per current file).** `appendToExistingMemory` reuses existing `MediaReference` by `osIdentifier`, adds a new edge — never duplicates.
- `MemoryStream/Views/Journal/EntryExpandedView.swift`, `ChronologicalCaptureStream.swift`, `CompactTranscriptViews.swift` — reads.
- `MemoryStream/Views/Inbox/SessionListView.swift`, `ClusterCardStack.swift` — reads.

**Money tests:**
1. `EvidenceEdgeCreationTests.sortBatchCommitCreatesEdgesForEachClipInCluster` — 5 clips → 1 memory, 5 edges, `orderInMemory` 0..4 by capturedAt.
2. `EvidenceEdgeCreationTests.appendToExistingMemoryReusesExistingRefsWhenPresent` — clip already in memory A, appended to B → 1 MediaReference, 2 edges (never duplicate the ref).
3. `EvidenceEdgeCreationTests.clipReferencedByTwoMemoriesRemainsOneEvidence` — the load-bearing many-to-many invariant. Same clip, two memories, one ref, two edges, both `mediaReferencesArray` calls return the ref *by identity*. **This is the ontology's money test.**
4. `EvidenceEdgeCreationTests.createMediaReferenceStampsClipCapturedAt` — replaces the fixup pattern; `ref.createdAt == clip.capturedAt` at creation time.
5. `SortBatchCommitCapturedAtTests` (existing) — **preserved as end-to-end regression guard.** Same input, same assertion. Confirms nothing regressed at the outer surface.
6. `JournalEntryMediaReferencesArrayTests.arrayOrderedByEdgeOrderInMemory` — three clips, edges with `orderInMemory` 2/0/1 → array returns clip1, clip2, clip0.
7. `EntryLifecycleServiceJoinedContentTests.joinedContentUsesPerMemoryEdgeOrder` — clip in two memories with different `orderInMemory` in each → joined content per memory reflects that memory's ordering.
8. `MediaReferenceMemoriesArrayTests.arrayReflectsAllMemoriesReferencingClip` — clip in 3 memories → memoriesArray returns 3, sorted by `linkedAt`.
9. `ReadPathIgnoresOrphanRefEntryTests.orphanEntryFieldDoesNotSurfaceInMediaReferencesArray` — seed a ref with `.entry` set but no edge (simulates a hypothetical write-path bug) → `mediaReferencesArray` returns empty. Guards the reads-walk-edges invariant.
10. `NoZeroEdgeMediaReferencesInvariantTests.everyWritePathCreatesAtLeastOneEdge` — parameterized over every write entry point (`createMediaReference`, `createVoiceFragment`, `createNoteFragment`, `SortBatchCommit.commit`, `CreateMemoryFromClipsSheet.createMemory` / `appendToExistingMemory`, `EntryLifecycleService.appendClips` / `save` / `append` / `finalizeContribution`) → every resulting ref has `edges.count >= 1`. **Enforces the temporary invariant described in `§ Temporary v1 invariant`.** Removed in Phase 6.

**Gate to Phase 4:** all tests pass. Real-device dogfood: capture a clip, promote via Sort, view Memory Detail — no visible regression. All 703 pre-existing tests still pass.

### Phase 4 — v3 clean-cut subtractive (LANDED 2026-07-09)

**Status: SHIPPED.** Took the "fresh start" route rather than a lightweight-migration sequence — Tom is the only user and had exported his data, so we deleted v1 and v2 model versions from disk entirely, made v3 the only model, and removed the migration code (`EvidenceEdgeMigration`, `EvidenceEdgeMigrationMarker`, `PreEvidenceMigrationSnapshot`) altogether. Zero shim state, zero legacy fields, zero migration coordination.

**Sequence taken:**
1. Tom exported his current data outside the app.
2. Tom reset CloudKit Development in the Dashboard (nukes the v2 schema so v3 publishes clean).
3. I deleted `MemoryStream.xcdatamodel/` (v1) and `MemoryStream 2.xcdatamodel/` (v2) from disk. Only `MemoryStream 3.xcdatamodel/` remains.
4. I removed the legacy `@NSManaged` declarations (`JournalEntry.mediaReferences`, `MediaReference.entry`, `MediaReference.entryId`), mirror-writes in `StorageService.createX` and `FragmentMigration`, `EvidenceEdgeMigrationMarker` entity from the model, and all the migration Swift files + tests.
5. Bumped `schemaInitKey` to `"com.himem.cloudkit.schemaInitializedV5"` so the next Debug build republishes v3 to CloudKit Dev.
6. Tom will delete the app from his phone and reinstall to get a clean v3 install.
7. Deploy Dev→Prod when ready (single deploy, no soak sequence needed since Tom is the only user).

**Test infrastructure wins (landed alongside, permanent):**
- `StorageService.shared` returns an in-memory container under XCTest / Swift Testing — any accidental touch (SwiftUI view bodies, `JournalEntry.latestProcessingTask` fallbacks) is safe.
- `StorageService.isRunningTests` is a static so `MemoryStreamApp` can gate its pre-warm.
- `#if DEBUG` no-zero-edge assertion gates on `context.transactionAuthor == "viewContext"` so CloudKit-mirroring imports never trip it (imports use `NSCloudKitMirroringDelegate.import`).
- `NSPersistentCloudKitContainer(name:managedObjectModel:)` explicitly passes `cachedModel` — one model instance per process, no "Multiple NSEntityDescriptions" ambiguity.

**Root cause of the earlier batch-test failure** (finally isolated on this attempt): two NSPredicate literals still referenced the removed `mediaReferences` relationship — `SearchEngine.swift:247/257/259` (`ANY mediaReferences.mediaType == %@`) and `ExistingMemoryPickerView.swift:197` (`ANY mediaReferences.createdAt >= %@`). Once the relationship no longer existed on `JournalEntry`, every batch that scheduled a search-scope test crashed with `valueForUndefinedKey`. The CloudKit/model diagnoses were red herrings. Both predicates rewritten to `ANY edges.clip.mediaType` / `ANY edges.clip.createdAt`.

**Post-Phase-4 state:** 711 tests / 86 suites all green. Ontology invariants hold at the schema level, not just at the code level. No shim state to remember, no documentation debt.

**Preconditions (original):**
- Phase 2+3 lands and is dogfooded green for at least 24h.
- No code references `.entry` or `.entryId` on `MediaReference` (grep clean).
- No code references `.mediaReferences` on `JournalEntry` (grep clean).
- Migration marker `has_run == true` on Tom's device.
- **Temporary v1 invariant holds:** every `MediaReference` in the store has `edges.count >= 1`. Guaranteed by the invariant enforced during Phases 1-3 (see `§ Temporary v1 invariant`).

**Deliverables:**
- `MemoryStream 3.xcdatamodel` — subtractive; removes `entry`, `entryId`, `mediaReferences`.
- Precondition guard in `LaunchScreenView.runMigration()`: if marker not set OR any `MediaReference` has `.edges.count == 0` at v2 time, refuse to advance to v3.
- CloudKit Dashboard: deploy v3 to Production. Review diff. **Wait 24h.** Verify on a fresh iCloud test account.

**Money tests:**
- `V3MigrationPreconditionTests.refusesToAdvanceIfFixupNotComplete` — set marker=false, seed store, attempt v3 → guard blocks, no schema change.
- `V3MigrationPreconditionTests.refusesToAdvanceIfOrphanRefExists` — a `MediaReference` with `edges.count == 0` in the v2 store → guard blocks.
- `V3ReadPathTests.mediaReferencesArrayWorksAfterFieldRemoval` — a v2 store fixture, migrate to v3, `mediaReferencesArray` still returns clips (proving reads never depended on `.entry`).

**Gate to Phase 5:** v3 Prod live confirmed via test account; Tom's device migrates cleanly; all tests pass.

### Phase 5 — Three-tab nav shell

**Deliverables:**
- `HiMemTabView.swift` — root `TabView` (Clips · Memories · Projects).
- Session-scoped last-tab in `@State` at root; cold launch always Memories.
- `JournalView` moves into Memories tab.
- `ProjectListView` moves into Projects tab.
- `ClipsTabView.swift` skeleton (populated in Phase 6).
- Retire the Memories/Projects segmented control on JournalView.

**Money tests:**
- `HiMemTabViewTests.viewInstantiationDefaultsToMemoriesTab` (unit) — instantiating the view starts on Memories. *Note:* not a cold-launch test; that requires XCUITest.
- `HiMemTabViewColdLaunchUITests.coldLaunchLandsOnMemories` (XCUITest) — force-terminate + relaunch → Memories tab is active.
- `HiMemTabViewColdLaunchUITests.lastTabPersistsWithinSession` (XCUITest) — Clips → background → foreground → still Clips.
- `HiMemTabViewColdLaunchUITests.lastTabDoesNotPersistAcrossColdLaunch` (XCUITest) — Clips → force-quit → relaunch → Memories.

**Gate to Phase 6:** UI + tests.

### Phase 6 — Clips tab default view

**Deliverables:**
- `ClipsTabView` reads:
  - InboxManifest for unplaced clips (arrival + transcription in-flight).
  - `MediaReference` where `edges.count == 0` (returned-from-memory clips).
- Sort suggestions surface unchanged in shape (from `ClusterCardStack`), moves into this view.
- "Capture returns to Clips" — after phone FAB voice commit, land on Clips tab.
- **Retire the temporary v1 invariant.** Delete `NoZeroEdgeMediaReferencesInvariantTests` (its assertion was that no ref has zero edges — which the "remove from last memory" flow this phase enables would legitimately violate). Delete the corresponding `#if DEBUG` runtime assertion in `StorageService.save`. Both removals must land in the same PR as the "remove from last memory" affordance. Grep for `NoZeroEdgeMediaReferencesInvariant` and `edges.isEmpty` in `StorageService.save` before opening the PR to confirm nothing else references the invariant.

**Money tests:**
- `ClipsTabViewLoadTests.showsUnplacedClipsFromBothStores` — seed 3 InboxManifest arrivals + 1 MediaReference with 0 edges → view shows 4 unplaced.
- `ClipsTabViewLoadTests.hidesPlacedClips` — MediaReference with ≥1 edge does not appear in default view.
- `ClipsTabViewLoadTests.captureReturnsToClipsTab` — after phone voice commit, active tab is Clips.
- `ClipsTabViewLoadTests.returnedFromMemoryClipAppearsAsUnplaced` — remove clip's last edge → clip appears in Clips default view immediately.

**Gate to Phase 7:** UI + tests.

### Phase 7 — Clip Detail (new screen)

**Deliverables:**
- `ClipDetailView.swift` — transcript, media viewer, date, **Referenced in: [memories]** list (title + date + one-line snippet, tappable), Projects section (aggregated across referenced memories).
- Delete Clip button (full-width bottom, danger red).
- Copy: "**This is attached to N memories**" when `edges.count > 0`. Warning below button, above Recently Deleted destination line. (Softer than the ontology's architectural "evidence in" — user-facing copy avoids the schema word.)
- Tap-through from Clips tab + from Memory Detail's per-clip row.
- Model-layer computed: `MediaReference.referencingMemoryCount` and `MediaReference.referencingMemoriesSortedByLinkedAt`.

**Money tests (model-first):**
- `MediaReferenceReferencedInTests.referencingMemoryCountMatchesEdgeCount` — clip with 3 edges → count == 3.
- `MediaReferenceReferencedInTests.referencingMemoriesSortedByLinkedAtDesc` — 3 edges with different linkedAt → returned in reverse-chronological.
- `ClipDetailViewCopyTests.warningCopyRendersWithCountFromModel` — view test that reads model computed prop, asserts copy template.
- `ClipDetailViewTests.deleteClipCascadesEdges` — delete → both edges gone, memories survive.

**Gate to Phase 8:** UI + tests.

### Phase 8 — Delete verb split

**Deliverables:**
- `EntryLifecycleService.removeClipFromMemory(edgeId:)` — drop one edge. Clip survives.
- `EntryLifecycleService.delete(entryId:)` — existing; now explicit that edges cascade + clips survive.
- `EntryLifecycleService.deleteMediaReference(refId:)` — new; cascades edges; ref itself is destroyed. Audio file cleanup unchanged.
- Memory Detail per-clip Delete button: label = "Remove from this memory" when `edges.count > 1`, "Delete clip" when `edges.count == 1` (last edge = destroying the evidence).
- Clip Detail bottom Delete Clip is *always* evidence-destruction; the "remove from this memory" is at Memory Detail.

**Money tests:**
- `DeletionSemanticsTests.removeClipFromMemoryDropsEdgeOnly` — clip in 2 memories → remove from A → 1 edge remains, clip survives, `mediaReferencesArray` of A no longer contains ref, of B still contains it.
- `DeletionSemanticsTests.deleteMemoryCascadesEdgesButPreservesClips` — memory with 3 clips (2 unique to it, 1 shared with another memory) → delete memory → 0 edges from this memory, 3 clips survive, the shared clip still visible in the other memory.
- `DeletionSemanticsTests.deleteClipCascadesEdgesAndDestroysEvidence` — clip in 2 memories → delete clip → 0 edges, ref gone, both memories still exist as narratives with one fewer clip each.
- `DeletionSemanticsTests.deleteClipAlsoRemovesAudioFile` — clip's audio file exists at path → delete clip → file gone from disk.

**Gate to Phase 9:** UI + tests.

### Phase 9 — Troika full review + real-device dogfood gate

**Deliverables:**
- Spawn troika again on the full state (schema, migration, read/write, UI phases).
- Findings triaged; P0 fixed before upload.
- **Real-device dogfood gate on Tom's device:** with existing dogfood data (post-Phase-2+3 migration), verify:
  - No memory count regression.
  - Every memory's `mediaReferencesArray` returns the same clips as pre-migration.
  - Capture a new clip → promote via Sort → verify it lands correctly.
  - Manually add a clip to a second memory (via a test flag / hidden affordance) → verify multi-placement.
  - Delete a clip via the three verbs → verify semantics.
  - 24 hours of ambient background CloudKit sync → check Console for no errors.

**Gate to TestFlight:** troika clean + dogfood gate clean + all money tests + all pre-existing tests green + CloudKit v3 Prod deployed + soaked.

### Phase 10 — Ship

- Final regression sweep (all tests).
- Session log written.
- Memories updated.
- Upload to TestFlight.

## What we do NOT do

- No shim for `.entry`/`.entryId` after Phase 4. During Phase 2+3, they're populated by writes but unread — a shim by *v2 model*, not a shim in the code.
- No dual-store for unplaced clips beyond what already exists.
- No arrival-time promotion of InboxClip → MediaReference (deferred to v1.1).
- No cascading refactor into Studio-shape edges.
- No post-save fixups anywhere — data is right at creation time.
- No "we'll clean this up later" without a tech debt entry (§ Tech debt).

## Tech debt registered (out of scope for this plan, filed for later)

- **`textSegments` field on `JournalEntry`** — dead post-fragment-migration; not touched in this plan. Reason for deferral: fixup+read+write path is already sized right; tacking on a schema removal expands v2/v3 scope. Ticket: retire in a separate additive+subtractive model bump post-launch.

- **InboxManifest ↔ MediaReference unification** — v1.1 cleanup for the returned-from-memory case if dogfood shows the dual-store leaks.

- **CloudKit round-trip test for `MemoryClipEdge`** — Phase 1 test #10 (`EvidenceEdgeCloudKitRoundTripTests.edgesSurviveCloudKitMirror`) is deferred: `NSPersistentCloudKitContainer` doesn't expose a mirror stub that works cleanly with in-memory stores. Building one requires either (a) spinning up a real CKContainer against Development (nondeterministic, network-dependent, requires an iCloud account) or (b) mocking `NSPersistentCloudKitContainer` internals (unstable API). Real-device Prod-deploy soak covers this at the integration layer. Address in v1.1 if a CloudKit-mirroring bug slips through.

- **Multi-device edge dedup on read** — application-layer app dedup on write (`edgeExists`) handles Tom's single-device case. Cross-device races where two devices simultaneously create the same edge (same clipId, same memoryId) are theoretically possible post-multi-device. Fix if it surfaces: read-time dedup that groups edges by `(clipId, memoryId)` and picks oldest by `linkedAt`.

## Test strategy summary

Every phase ships with money tests that fail before the phase and pass after. All tests deterministic (`@Suite(.serialized)` where singletons involved), in-memory Core Data (`StorageService(inMemory: true)`), no external services.

Each phase's tests cover: **the invariant that would have caught the observed bug** + **at least one failure-mode test** (crash-mid, empty case, or orphan state). No happy-path-only phases.

## Rollback plan (real, not "restore from backup")

1. **Pre-Phase-1 JSON snapshot** is the ground truth. Written to `Documents/pre-evidence-migration-<ISO8601>.json` at first launch after Phase 1 code lands, before any edge is created. Contains: all `JournalEntry` fields, all `MediaReference` fields, and the (entryId → id) relationship map.

2. **If Phase 1 fixup fails on Tom's device:** the JSON is intact. Recovery path is:
   - Revert app code to pre-Phase-1 version.
   - Delete the app (dumps CloudKit local mirror; iCloud keeps a copy).
   - Reinstall the pre-Phase-1 app.
   - Watch it re-sync from CloudKit (which is still at v1 schema — we haven't deployed v2 to Prod yet).
   - Verify data integrity from JSON snapshot if any drift.

3. **If Phase 4 fails on Tom's device (post-v3 Prod deploy):** harder. CloudKit Prod is at v3, dropped fields are gone from the schema. Recovery requires:
   - Rolling CloudKit back (Dashboard supports schema history but it's ugly).
   - Reconstructing the `entry`/`mediaReferences` relationships from the local edges. Since edges carry `clipId + memoryId`, the relationships can be rebuilt from edges into `entry` on a rollback app version.
   - This is why the v2→v3 gate has a 24h soak + real-device dogfood before v3 deploy. Phase 4 must not fail in Production.

4. **The `pre-evidence-migration.json`** stays on-device until Tom deletes it. Include a Settings → Developer → Delete migration snapshot after v3 is confirmed stable.

## Approval requested

Before I start Phase 0:

1. Confirm `MemoryClipEdge` as the entity name (vs `EvidenceLink` / `MemoryClipReference`).
2. Confirm delete-clip copy uses the ontology word "evidence" ("This is evidence in N memories").
3. Confirm CLAUDE.md line 187 gets edited.
4. Confirm the 24h soak gate between CloudKit Prod deploys is acceptable timeline-wise (~48h total soak across v2 + v3 deploys, plus phase-2+3 dogfood).
5. Confirm the JSON snapshot rollback approach (~5-10MB file in Documents for Tom's dogfood).

---

## Revision history

- **v1** (2026-07-08 morning): initial plan.
- **v2** (2026-07-08 afternoon): folded troika review findings. Two-step model version bump (v2 additive → v3 subtractive) with per-version CloudKit deploy + 24h soak. Phase 2+3 merged into one atomic PR. `§ Why InboxManifest stays` written. Delete rules spelled out. Uniqueness constraint added. Batched saves. Rollback = JSON snapshot, not "Xcode backup." Test coverage strengthened at every phase (failure-mode tests, many-to-many invariant in Phase 3, XCUITest for cold launch, model-first for delete-warning). `textSegments` filed as tech debt.
- **v2.1** (2026-07-08 evening): Tom's approvals folded (edge name `MemoryClipEdge`, delete-clip copy = "attached to" not "evidence in", CLAUDE.md → "Clips" for canonical, 48h soak accepted, JSON snapshot accepted). Added `§ Temporary v1 invariant` (no zero-edge MediaReferences until Phase 6 lands) per Tom's catch — the Phase 4 guard's condition matches the future zero-edge state, so the invariant must be enforced *and* explicitly retired at Phase 6 so the retirement isn't forgotten. Added money test #10 in Phase 2+3 to enforce it and a `#if DEBUG` runtime assertion in `StorageService.save`.
- **v2.2** (2026-07-09, this doc): Phase 1 landed. Two discoveries during build folded: (1) compound uniqueness constraint retired — `NSPersistentCloudKitContainer` ignores uniqueness on Cloud-synced entities, so the constraint was dead metadata; enforcement is app-layer via `edgeExists`. (2) CloudKit round-trip money test #10 deferred to tech debt — `NSPersistentCloudKitContainer` has no clean in-memory mirror stub for deterministic tests; real-device Prod-deploy soak covers this at integration layer. Phase 1 tests down to 9 (all passing). Multi-device edge dedup filed as tech debt in the same section.

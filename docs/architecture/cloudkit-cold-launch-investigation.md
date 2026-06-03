# CloudKit cold-launch investigation

**2026-06-02 / 2026-06-03 · status: closed, no migration**

## TL;DR

HiMem's cold launch had degraded to ~18s on Tom's dev device. We measured, fixed the in-app side (down to ~1.5s steady-state), found a residual ~21s post-launch sync window that wouldn't go away, suspected `NSPersistentCloudKitContainer`, built a `CKSyncEngine` spike to test migration, and discovered the ~21s is **CloudKit's per-zone setup floor — O(1) in record count, not framework-specific.** Migration would not help. The fix is masking via onboarding (pacing the wait behind permission prompts the user is already moving through) plus schema hygiene to prevent future bloat. Decision: don't migrate. Ship masking. Defer ProcessingTask not-synced and InferenceSummary deprecation as separate workstreams.

---

## The symptom

Cold launch reported at ">9s, often closer to 18s" on Tom's iPhone running Tom's iCloud account. Subsequent cold launches (force-quit + re-tap on same install) had similar behavior. Repro was reliable.

## In-app fixes (shipped first, before any architectural investigation)

Six commits across the launch path. Each tracked with `OSSignposter` intervals in the `com.himem.app · PointsOfInterest` Instruments track.

- `ec72969` — cold-start instrumentation (`os_signpost` markers around suspected hot spots)
- `ff73683` — moved `EntitlementService` / `StoreKitService` / `FoundersCounter` / `TenureTracker` / `WatchInboxNotificationCoordinator` bootstrap out of `MemoryStreamApp.init`'s `DispatchQueue.main.async` block into `LaunchScreenView.onStorageLoaded`. The original code pre-empted the off-main storage warm because `EntitlementService.init` fetches viewContext. Also removed the 1.4s baked UX hold in `completeSync()`.
- `8038ba8` — splash now dismisses immediately when storage loads instead of waiting on `NSPersistentCloudKitContainer.eventChangedNotification`. The CloudKit observer still gates `FragmentMigration` (which genuinely needs CloudKit settled per the 2026-05-09 issue doc), but the user-visible splash dismissal is independent. Also moved `JournalViewModel.init`'s synchronous `loadEntries` + `mergeDuplicateTopics` + `mergeDuplicateEntities` into `loadInitial()` async, called from `JournalView`'s `.task`. Money tests in `JournalViewModelLoadInitialTests`.
- `1890648` — same publish-then-populate pattern applied to `ProjectViewModel`. Money tests in `ProjectViewModelLoadInitialTests`. Also removed `mergeDuplicate*` calls from `observeRemoteChanges` (they were running ~once per second during CloudKit's import window, pinning the main thread).
- `6dcd579` — removed `JournalView.onAppear`'s pre-fetch of speech + photo-library authorization. On fresh install, those `requestAuthorization` calls were firing the iOS permission prompts immediately, suspending the app to inactive while the user dismissed each one. Removing the pre-fetch deferred those prompts to the moment the user actually uses voice / photos.
- `8b3eacd` — post-launch instrumentation (loadEntries fire count + duration, observer fire events) so we could see exactly what the post-launch period was doing.

**Result of the in-app fixes:** steady-state cold launch dropped to ~1.1s `Foreground-Active` (down from ~5.5s baseline before any fix). On a populated CloudKit zone, however, a separate ~17–21s gap remained between `Foreground-Active` and "feed shows the user's data" — driven by CloudKit's mirror import, not by our code. **That gap is what we investigated next.**

## The agent-triage round

Three agents in parallel (literature lens, code-audit lens, diagnostic plan lens). Convergent finding:

- The 17–21s is `NSPersistentCloudKitContainer`'s post-`loadPersistentStores` mirror import.
- Apple's DTS engineer Ziqiao Chen, forum thread 817386 (2025): *"I don't really see anything to work around or mitigate the issue in this case... Make the app functional before the dataset is fully synchronized... Use direct CloudKit framework for better control."*
- Day One migrated off `NSPersistentCloudKitContainer` for exactly this reason; their published rationale cites duplicates, data loss, and the lack of robust APIs.
- Apple Notes uses raw `CKDatabase`, not `NSPersistentCloudKitContainer`. Apple's own team doesn't use the framework HiMem uses.
- `CKSyncEngine` (iOS 17+) is Apple's newer alternative — exposes the transport without the mirror-import opacity.

The agent recommendation was: don't panic-architect; ship masking; plan `CKSyncEngine` for v1.1. We pushed back: if we're going to migrate eventually, pre-launch (no user data to migrate) is the cheapest moment.

## The spike

Built `HimemSyncSpike` (`/Users/tom/dev/HimemSyncSpike/`, mirror source in `/Users/tom/dev/himem/HimemSyncSpike/` for posterity). 402 LOC, four Swift files plus entitlement / Info.plist / README. Read-only against the production iCloud container, signpost-instrumented for cold-launch timing.

Key spike facts:

- `NSPersistentCloudKitContainer` writes plain `CKRecord`s to the fixed zone `com.apple.coredata.cloudkit.zone` with type `CD_JournalEntry` and field keys `CD_*`. `CKSyncEngine` reads these directly with no schema work needed.
- Spike init is synchronous, returns immediately. No opaque setup phase.
- State persisted via `CKSyncEngine.State.Serialization` to `Documents/spike-cksync-state.json`.
- Apple's `sample-cloudkit-sync-engine` (cloned to `/tmp/` during research) was the canonical reference.

**Test matrix:**

| Container | Records | Cold launch to first-record-visible |
|---|---|---|
| `iCloud.com.himem.app` (HiMem's) | 34 | ~20s |
| `iCloud.com.himem.app` | ~14 (after deleting 20) | ~17s (same, confirming **O(1)** in record count) |
| `iCloud.com.himem.spike-empty` (fresh) | 0 | **~1.5s** ✓ |

Critical finding: the spike against an empty container completed in **~1.5 seconds** with 14ms total measured signpost work (`spike.app.init` 17µs + `spike.reader.init` 14ms). Against HiMem's container, both the spike and HiMem itself take ~17–21s.

**Conclusion:** the 17–21s is the cost of CloudKit's setup against HiMem's specific zone — change history, tombstones, schema iteration cost. Not `NSPersistentCloudKitContainer`'s mirror layer (the spike doesn't have one and still hit the same floor) and not `CKSyncEngine`'s anything (the spike doesn't even reach its own delegate methods until after the floor clears).

## Scaling test

`75d4cfe` added a DEBUG-only Settings → Debug → Scaling test panel with "Seed 100 / 1,000 / 10,000 entries" buttons and "Delete test entries." Each seeds minimal `JournalEntry` records on a background context with title prefix `Scale-test #` for clean delete.

Test methodology:
1. Seed 10,000 entries → wait for CloudKit to mirror → cold-launch HiMem.
2. `0c1bc76` (later reverted as `521c32c`) lifted `JournalViewModel`'s 500-record fetch limit to 100,000 so the test exercised the local fetch+map pipeline at full scale, not just the displayed 500.

**Result at >20,000 records: still 21 seconds cold launch.** Identical to the 34-record case. Streaming continued after launch at ~200 records/sec; full library populated in ~100 seconds total, but the launch wall clock itself was unchanged.

**Conclusion confirmed: O(1) at scale.** CloudKit's per-zone setup is the floor regardless of record count.

## Why migration is off the table

- **CKSyncEngine:** spike showed it has the same per-zone setup floor as `NSPersistentCloudKitContainer`. The opacity is in CloudKit's transport, not in the Core Data mirror layer. Migration cost (8–12 weeks) for zero perf benefit.
- **Custom backend (RDS + API):** would solve the floor by giving us control over the wire protocol. But (a) the ~21s only hits first-install populated-account users, (b) cost is 1–3 months plus ongoing infra plus auth-to-DB mapping plus watch-sync rewrite, (c) HiMem's pricing model (Plus $4.99/mo, Founders $99 cap 250) doesn't easily absorb per-user infra costs at low scale. Defer until cross-platform / web / server-side AI on user data become real requirements.

## What we shipped instead

- All six in-app launch-path commits listed above (steady-state ~1.1s).
- Onboarding permission wizard (in design, per `docs/design/Himem · Onboarding.html` + `screens-onboarding-wizard.jsx`, 2026-06-02). Seven permission-explanation pages plus three required-blocked screens. **The pacing IS the cover** — by the time the user has tapped through Sign in with Apple, microphone, speech, photos, camera, location, and notifications, CloudKit's ~21s setup has completed in the background. First-install perception: the wait is invisible. Implementation pending.
- `1f85bc0` — removed orphaned `SyncPing` entity from the Core Data model (0 records, 0 code references). Stops the type from appearing in CloudKit schema after the next production deploy.

## Schema findings (CloudKit Dashboard audit)

| Type | Records | Per-memory ratio | Verdict |
|---|---|---|---|
| `CD_JournalEntry` | 34 (14 active + 20 recycled) | 1.0 | Expected |
| `CD_ExtractedEntity` | 83 | 2.4 | Expected fan-out |
| `CD_ProcessingTask` | 31 | 0.9 | **Transient runtime state, shouldn't sync** |
| `CD_SyncPing` | 0 | — | Removed in `1f85bc0` |
| `CD_InferenceSummary` | 67 | 2.0 | **Legacy / pre-Organize** |
| `CDMR` | n/a | — | NSPCKC internal metadata, do not touch |
| `TestRecord` | n/a | — | Dev leftover; delete from CloudKit Dashboard Schema |

## What's deferred

- **`ProcessingTask` not-CloudKit-synced** (task #19). Requires splitting the Core Data model into two configurations — one CloudKit-backed, one local-only — and reconfiguring `StorageService` to load two persistent stores. Real architectural change, half-day estimate. Not on the v1 critical path.
- **`InferenceSummary` deprecation** (not yet ticketed). 28 references across `JournalViewModel.submitFeedback`, `DisplayModels`, multiple tests. Real deprecation project, multi-day estimate. Either migrate the feedback-on-AI-summary feature to `OrganizePass`'s already-present `feedbackState` field, or retire the feature entirely. Not on the v1 critical path.
- **Mass-sync visibility surface** (task #20). The 21s is masked by the onboarding wizard on first install, but real users with 20k+ memories restoring on a new device will see entries stream in over ~100s. Worth a quiet Today banner or nav-bar chip ("Syncing from iCloud · 4,200 so far"). Post-launch polish.
- **Dev-zone vacuum (Tom-specific).** Tom's dev environment carries months of accumulated change history. A one-time zone delete via CloudKit Dashboard would reset to a clean state. Walked back from recommending this because `NSPersistentCloudKitContainer`'s recovery behavior on zone deletion is ambiguous and the cost of being wrong is Tom's memories. Safe path is local SQLite backup first (Xcode → Devices → Download Container) then vacuum. Optional, low priority.

## References

- TN3164: Debugging the synchronization of NSPersistentCloudKitContainer
- Apple Forum 817386 — CloudKit sync stalls during initial large data hydration (DTS reply)
- Apple sample: `sample-cloudkit-sync-engine` (GitHub)
- Day One Sync FAQ — why they left CloudKit
- fatbobman — Core Data with CloudKit series
- Christian Selig — CKSyncEngine Q&A (christianselig.com)
- WWDC23 Session 10188 — Sync to iCloud with CKSyncEngine

## Commits in chronological order

```
ec72969  Cold-start instrumentation
ff73683  Cold-start fix 1: defer entitlement bootstrap, drop UX hold
8038ba8  Cold-start fix 2: splash dismisses immediately + JournalVM publish-then-populate
1890648  Cold-start fix 3: ProjectViewModel publish-then-populate + observer cleanup
6dcd579  Cold-start fix 4: remove permission pre-fetch
8b3eacd  Post-launch instrumentation
c78a90e  Spike: CKSyncEngine measurement app
60e0be1  Spike cleanup (drop NSObject + unused coreDataZoneID)
06db272  Spike: route App.init signpost through helper
1f85bc0  Remove orphaned SyncPing entity
75d4cfe  DEBUG: scaling-test seed/delete buttons in Settings
0c1bc76  TEMP: lift JournalViewModel fetch limit (reverted)
521c32c  Revert scaling-test fetch limit
```

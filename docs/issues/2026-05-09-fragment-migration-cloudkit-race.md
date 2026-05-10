# FragmentMigration ↔ CloudKit Sync Race at Launch

**Date:** 2026-05-09
**Status:** **Closed** — verified on iPhone + iPad, both at v4 with steady-state flag set, zero duplicates, 33 entries × clean fragment shape on both devices (verified 2026-05-10)
**Severity:** High — crashed the app on launch when the race triggered

## Problem

`FragmentMigration.runIfNeeded(in:)` runs ~100ms after launch from `LaunchScreenView.runChoreography()`, on the main thread. CloudKit's initial import is in flight at the same time. When the migration writes `ref.entry = entry` on a `MediaReference` it just created in the view context, Core Data raises an Objective-C `NSException` from `_PFManagedObject_coerceValueForKeyWithDescription` and the app aborts (`SIGABRT`).

Swift `do/catch` does **not** intercept ObjC `NSException`. Per-entry `try/catch` was added in this session and confirmed not to help.

## Reproduction

- Test runs are deterministic: each `xcodebuild test` invocation gets a fresh simulator clone with empty `UserDefaults`, so the migration always runs at host-app launch. CloudKit sync is also in flight (the host app is signed into the dev container). Out of 6 consecutive runs across two sessions: 4 crashed (with 3-28 cascade test failures depending on which suite was running when the host crashed), 2 completed clean.
- Real device: crash has not been reproduced in normal use because Tom's device already has `fragmentMigration.v2.completed` set, so the migration short-circuits. Reinstalling the app or clearing UserDefaults would re-arm the race.

## Crash signature

```
Exception Type:        EXC_CRASH (SIGABRT)
Termination Reason:    objc_exception_throw

_PFManagedObject_coerceValueForKeyWithDescription
_sharedIMPL_setvfk_core
FragmentMigration.swift:172 (ref.entry = entry)   ← v2 content-only branch
FragmentMigration.swift:80  (migrate loop)
LaunchScreenView.swift:173 (closure that calls runIfNeeded)
NSManagedObjectContext.performAndWait
```

The crash happens in the new content-only branch (line 172). The two v1 branches (audioFilePath, TextSegment) execute the same `ref.entry = entry` pattern but historically didn't crash — most likely because pure-content entries are the largest population and exercise the race surface.

## Root cause hypothesis

Two `NSManagedObjectModel` instances are loaded simultaneously: one from `MemoryStream.xcdatamodel` (our schema) and one from CloudKit's import operation (`NSCKImportOperation`). When CloudKit is mid-rematerialization of a `JournalEntry`, that entry's metadata describes the relationship via the import-operation model, not our model. Setting `ref.entry = entry` from our model triggers a coerce against a destination-entity description from the wrong model and Core Data throws `NSInvalidArgumentException`.

This matches the comment buried in the iPhone's existing CloudKit logs (see `2026-04-29-cloudkit-sync-asymmetry.md`):

```
CoreData: fault: Delete propagation prefetching failed with exception:
The fetch request's entity 0x106e8c3c0 'NSCKImportOperation' appears to be
from a different NSManagedObjectModel than this context's
```

Same family of error: two models active in one context.

## Current mitigations

- **Tests bypass the migration entirely.** `FragmentMigration.runIfNeeded` checks for `XCTestCase` / `Testing.Test` / `XCTestConfigurationFilePath` and early-returns. Test suites use `StorageService(inMemory: true)` per-suite and don't need migration. 3-for-3 clean test runs after this change.
- **Per-entry `try/catch` in `migrateOne`.** Doesn't catch the NSException, but does isolate per-entry Swift errors and saves per-row so a single bad entry doesn't roll back the whole batch.
- **`isLegacyEntry` removed.** EntryExpandedView still falls back to `Text(entry.content)` if `mediaItems.isEmpty` — covers any entry the migration skipped.

## Durable fix (landed 2026-05-09)

`LaunchScreenView` now defers `FragmentMigration.runIfNeeded` until one of three things happens:

1. `NSPersistentCloudKitContainer.eventChangedNotification` reports `.import` (`type.rawValue == 1`) `.succeeded` — the import has settled, only our model is live, the assignment is safe.
2. The 3-second safety net fires (covers no-iCloud account, no network, or empty store with nothing to import).
3. The "entries already exist" 0.3s check fires (covers the case where the import drained during store load and we missed the notification).

A `migrationStarted` flag in the launch view makes the call idempotent across all three paths. Migration runs on a background context (`StorageService.shared.backgroundContext()`) so the main thread isn't blocked; `viewContext.automaticallyMergesChangesFromParent` propagates the new `MediaReference`s to the UI.

`FragmentMigration.runIfNeeded` keeps an XCTest short-circuit because the test host app still launches `LaunchScreenView` and the 3s safety net would otherwise fire migration against the user's real store mid-test.

Test stability: 6-of-6 clean test runs (134/134 passing each) across two batches after the gate landed. Pre-fix runs were intermittent (4-of-6 crashed with cascading test failures).

## Verification (2026-05-10, real devices)

**iPhone first launch:**
```
[Migration] fetched=33 voice=0 note=1 entriesTouched=1 skipped=0 duplicatesRemoved=0
[Migration] starting v4
[Migration] steady state — flag set
[Migration] fetched=33 voice=0 note=0 entriesTouched=0 skipped=0 duplicatesRemoved=0
```
Migrated one lingering legacy entry on first pass; second pass confirmed steady state and set the flag.

**iPad first launch:**
```
[Migration] fetched=0   ← CloudKit hadn't synced yet
[Migration] starting v4
[Migration] steady state — flag set
[Migration] fetched=33 voice=0 note=0 entriesTouched=0 skipped=0 duplicatesRemoved=0
```
First pass walked an empty store (CloudKit not yet synced) — correctly *did not* set the flag. Second pass, after CloudKit had delivered the iPhone-migrated entries, found 0 work to do and 0 duplicates → steady state.

**No duplicates were ever created** because the iPhone migrated first, CloudKit delivered fully-formed `.note` MediaReferences to the iPad, and the iPad's migration was a clean no-op. The deterministic-UUID + dedup-pass belt-and-suspenders machinery was in place but didn't need to fire.

## Lessons

- v2 set the flag on a 0-entry fetch — bug. v3 fixed by requiring `entriesFetched > 0`.
- v3 didn't dedupe across multi-device race — anticipated risk. v4 added deterministic UUIDs + per-entry dedup pass; flag now also requires `duplicatesRemoved == 0`.
- The CloudKit-import gate (Apple `eventChangedNotification` `.import .succeeded`) is the dependable signal for "safe to write managed-object relationships." Don't write into the view context before that fires; the two-NSManagedObjectModel error from `_PFManagedObject_coerceValueForKeyWithDescription` raises an ObjC NSException Swift cannot catch.
- The `Already have a mirrored relationship` and `Delete propagation prefetching failed... NSCKImportOperation` log noise persists on both devices regardless of our setup. These are framework-side; non-fatal; Tier 4 (file Apple feedback).

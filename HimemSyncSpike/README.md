# HimemSyncSpike

A read-only iOS app that measures CKSyncEngine cold-launch time against the same iCloud container HiMem uses. Compares directly against HiMem's `NSPersistentCloudKitContainer` ~17s first-launch baseline.

## What it does

- Connects to `iCloud.com.himem.app` (same container as HiMem)
- Uses `CKSyncEngine` to fetch records from `com.apple.coredata.cloudkit.zone` (the zone `NSPersistentCloudKitContainer` writes to)
- Reads existing `CD_JournalEntry` records that HiMem has already synced
- Displays them in a list with title + date + content preview
- Emits `os_signpost` events for cold-launch phases

## Why it's safe

The spike is **read-only**. It implements `nextRecordZoneChangeBatch` returning `nil`, never enqueues pending changes, and only ever calls `fetchChanges`. There is no code path that writes a record to the container. Your HiMem production data is untouchable.

## Setup (~5 minutes in Xcode)

1. Open Xcode → **File → New → Project → iOS → App**.
2. Name it `HimemSyncSpike`. Bundle ID: `com.himem.app.syncspike` (anything works, but use a different bundle ID than HiMem's `Himem` / `com.himem.app` so they install side-by-side on the device).
3. Choose **SwiftUI** interface, **Swift** language. Use Storyboard for Launch Screen (or none — doesn't matter for measurement).
4. Save the project anywhere — Xcode will create a default project structure.
5. **Replace** the auto-generated files with the ones in this folder:
   - Delete the default `ContentView.swift` and `<ProjectName>App.swift`
   - Drag in: `HimemSyncSpikeApp.swift`, `SyncedReader.swift`, `EntryListView.swift`, `SpikeSignposter.swift`
   - Replace the default `Info.plist` with the one in this folder
   - Replace the default `.entitlements` with `HimemSyncSpike.entitlements` (or copy its keys into the existing one)
6. In project settings → **Signing & Capabilities**:
   - Sign with your personal team (same Apple ID you use for HiMem development)
   - Add the **iCloud** capability if not already there. Tick **CloudKit**. Select container `iCloud.com.himem.app` (you may need to click the refresh icon if it doesn't appear — Xcode reads it from the entitlement).
   - Add the **Push Notifications** capability.
   - Add the **Background Modes** capability and tick **Remote notifications**.
7. Set deployment target to **iOS 17.0** or higher.
8. Plug in your iPhone, set it as the run destination.
9. Cmd+R to build and run.

## Measurement (~10 minutes)

You need both apps installed on the same device for an apples-to-apples comparison.

### Run 1 — Baseline (HiMem cold launch)

1. Open Instruments → **App Launch** template.
2. Target: `HiMem` on your device.
3. Force-quit HiMem from the app switcher. Wait 10 seconds.
4. Hit Record in Instruments. Tap HiMem icon when prompted.
5. Stop when journal entries appear.
6. Note the time from launch to `journalVM.loadEntries` returning a non-empty result (or visually, when the journal stops being empty).

### Run 2 — Spike (CKSyncEngine cold launch)

1. New Instruments document → **App Launch** template.
2. Target: `HimemSyncSpike` on your device.
3. Force-quit HimemSyncSpike. Wait 10 seconds.
4. Hit Record. Tap the spike app icon.
5. Stop when the list populates with entries.
6. In Points of Interest, note the time from `spike.app.init` to `spike.firstRecordVisible` (or `spike.uiPainted` if you want pixel-on-screen).

### What success looks like

If `spike.firstRecordVisible` fires within **2 seconds** of `spike.app.init`, CKSyncEngine is meaningfully faster than NSPersistentCloudKitContainer and the migration is justified. The HiMem baseline is ~17s for the same data, so even 5s would be a 3× improvement.

If `spike.firstRecordVisible` is also in the 10-20s range, CKSyncEngine isn't going to save us — fall back to the masking approach.

## Signposts emitted

| Name | Type | What it marks |
|---|---|---|
| `spike.app.init` | interval | App struct init body (should be < 50ms) |
| `spike.reader.init` | interval | SyncedReader construction (engine config + state load) |
| `spike.engine.created` | event | CKSyncEngine instance exists |
| `spike.firstFetchKicked` | event | `engine.fetchChanges()` called |
| `spike.firstEventReceived` | event | First non-empty CKSyncEngine.Event delivered to delegate |
| `spike.firstRecordVisible` | event | First non-empty batch ingested into `entries` |
| `spike.uiPainted` | event | List view re-rendered with non-empty content |

All under subsystem `com.himem.spike`, category `PointsOfInterest`.

## Important caveats

- **Physical device only.** CKSyncEngine requires remote notifications which don't fire reliably in Simulator. Build to iPhone, not iPhone Simulator.
- **Use the same iCloud account.** The spike and HiMem must be signed into the same Apple ID for the spike to see HiMem's records.
- **Don't run side-by-side simultaneously.** Force-quit one before launching the other to keep CloudKit's resource attribution clean.
- **First launch matters most.** Subsequent launches of the spike will be fast because the persisted `CKSyncEngine.State.Serialization` skips re-fetching. The measurement is the first launch after install (or after deleting `Documents/spike-cksync-state.json` from the app container, which you can do via Xcode's device window).

## After measurement

Drop the Instruments screenshot back in the conversation. Two specific numbers:

1. Time from `spike.app.init` start to `spike.firstRecordVisible` event.
2. Compare to the HiMem run's equivalent (first non-empty `journalVM.loadEntries`).

If the spike is meaningfully faster, we proceed with the 8-12 week migration plan. If not, we fall back to masking + ship the onboarding wizard.

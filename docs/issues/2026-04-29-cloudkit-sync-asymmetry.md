# CloudKit Sync Asymmetry: iPad Does Not Receive Remote Changes

**Date:** 2026-04-29
**Status:** Open — unresolved
**Severity:** High — cross-device sync is a core feature

## Problem

Changes made on iPhone or in CloudKit Dashboard are not reflected on iPad until the iPad app is fully killed and relaunched. The reverse direction (iPad → iPhone) works reliably within seconds.

Both devices run the same build, same iCloud account, same network, same CloudKit container (`iCloud.com.himem.app`).

## Architecture

- **Persistence:** `NSPersistentCloudKitContainer` (Core Data + CloudKit)
- **CloudKit zone:** `com.apple.coredata.cloudkit.zone` (private database)
- **Context config:**
  ```swift
  container.viewContext.automaticallyMergesChangesFromParent = true
  container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
  ```
- **Store description options:**
  ```swift
  description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
  description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
  ```

## Observed Behavior

### iPhone (works)
1. App launches → initial sync → entries loaded
2. `Remote notification received` fires with CloudKit payload (`content-available: 1`)
3. `NSPersistentStoreRemoteChange` fires → container imports → `ObjectsDidChange` fires → UI updates
4. Changes from CloudKit Dashboard appear within seconds

### iPad (broken)
1. App launches → initial sync works perfectly (0 → 16 entries)
2. **`Remote notification received` NEVER fires** after launch
3. `NSPersistentStoreRemoteChange` fires only during initial sync burst, then stops
4. Poll timer fires every 15s, `reset()` + `loadEntries()` runs, but always reads stale data
5. Pull-to-refresh reads stale data
6. Only killing and relaunching the app triggers a fresh sync

### Key diagnostic output

**iPhone receives CloudKit push:**
```
🔄 [SYNC] Remote notification received: [AnyHashable("ck"): {
    cid = "iCloud.com.himem.app";
    met = { sid = "com.apple.coredata.cloudkit.private.subscription"; 
            zid = "com.apple.coredata.cloudkit.zone"; };
}, AnyHashable("aps"): { "content-available" = 1; }]
```

**iPad** — this line never appears. Zero `Remote notification received` entries in the entire session.

Both devices successfully registered for remote notifications:
```
🔄 [SYNC] Got APNs device token (32 bytes)
```

### Other errors observed

**iPhone (non-blocking):**
```
CoreData: fault: Delete propagation prefetching failed with exception: 
The fetch request's entity 0x106e8c3c0 'NSCKImportOperation' appears to be 
from a different NSManagedObjectModel than this context's
```

**Both devices:**
```
updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.[UUID]
Error Domain=BGSystemTaskSchedulerErrorDomain Code=3 "(null)"
```

## What We've Tried

### 1. Remote change observer with `refreshAllObjects()` (no effect)
```swift
NotificationCenter.default.addObserver(
    forName: .NSPersistentStoreRemoteChange,
    object: container.persistentStoreCoordinator,
    queue: .main
) { _ in
    self.viewContext.refreshAllObjects()
}
```
The notification fires during initial sync but never after. `refreshAllObjects()` re-faults cached objects but doesn't trigger CloudKit to import.

### 2. `viewContext.reset()` on poll timer (no effect)
```swift
Timer.publish(every: 15, on: .main, in: .common)
    .sink { _ in
        storage.viewContext.reset()  // drops all cached objects
        loadEntries()               // re-fetches from SQLite
    }
```
`reset()` forces a fresh read from the SQLite file, but `NSPersistentCloudKitContainer` hasn't written new data to SQLite because it never received the push trigger to import.

### 3. Foreground reload (partial — helps on app switch only)
```swift
NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
    .sink { _ in refresh() }
```
This catches changes that arrived while backgrounded, but doesn't help while the app is in the foreground.

### 4. `registerForRemoteNotifications()` (partial — token obtained, pushes still missing on iPad)
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
    application.registerForRemoteNotifications()
    return true
}
```
Both devices get APNs tokens. iPhone receives CloudKit silent pushes. iPad does not.

### 5. BGTaskScheduler permitted identifiers (no effect)
Added to Info.plist:
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.apple.coredata.cloudkit.activity.export</string>
    <string>com.apple.coredata.cloudkit.activity.import</string>
</array>
```
The `updateTaskRequest failed Code=3` error persists on iPhone. iPad shows `updateTaskRequest called for an already running/updated task` (different message).

### 6. `CKFetchRecordZoneChangesOperation` (no effect)
Tried manually fetching from `CKDatabase` to trigger the container's import pipeline:
```swift
let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone.zoneID], ...)
ckContainer.privateCloudDatabase.add(op)
```
This fetches records into our code but does NOT feed them into `NSPersistentCloudKitContainer`'s internal import pipeline. They're independent systems.

### 7. SyncPing nudge — force an export to trigger import (untested)
Latest approach: write a trivial `SyncPing` record every poll tick to force the container to do an export. During the export round-trip with CloudKit, the container may discover pending imports.
```swift
func nudgeCloudKitSync() {
    let context = backgroundContext()
    context.perform {
        let ping = SyncPing(context: context)
        ping.timestamp = Date()
        try? context.save()
    }
}
```
**Status: deployed, not yet verified.**

### 8. Delete and reinstall (partial)
Deleting the app from iPad and reinstalling clears the local SQLite store. On relaunch, the container does a full initial sync and all data appears. But ongoing sync still breaks after the initial burst.

## Current Code State

### StorageService.swift (relevant sections)
```swift
private init() {
    container = NSPersistentCloudKitContainer(name: "MemoryStream")
    let description = container.persistentStoreDescriptions.first!
    description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
        containerIdentifier: "iCloud.com.himem.app"
    )
    // ... load stores with CloudKit fallback to local-only ...
    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

    NotificationCenter.default.addObserver(
        forName: .NSPersistentStoreRemoteChange,
        object: container.persistentStoreCoordinator,
        queue: .main
    ) { [weak self] _ in
        self?.viewContext.perform { self?.viewContext.refreshAllObjects() }
    }
}
```

### JournalViewModel.swift (sync-related sections)
```swift
// Observes local Core Data changes (debounced 250ms)
private func observeStorageChanges() {
    contextObserver = NotificationCenter.default.publisher(
        for: .NSManagedObjectContextObjectsDidChange,
        object: storage.viewContext
    )
    .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
    .sink { [weak self] _ in self?.loadEntries() }
}

// Reloads on foreground entry
private func observeForeground() {
    foregroundObserver = NotificationCenter.default.publisher(
        for: UIApplication.willEnterForegroundNotification
    ).sink { [weak self] _ in self?.refresh(); self?.startSyncPoll() }
}

// 15-second poll with SyncPing nudge
private func startSyncPoll() {
    syncPollTimer = Timer.publish(every: 15, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            self?.storage.nudgeCloudKitSync()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.storage.viewContext.reset()
                self?.loadEntries()
            }
        }
}

func refresh() {
    storage.nudgeCloudKitSync()
    storage.viewContext.reset()
    loadEntries()
}
```

### MemoryStreamApp.swift (push registration)
```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: ...) {
        print("🔄 [SYNC] Remote notification received: \(userInfo)")
        completionHandler(.newData)
    }
}
```

### Info.plist
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.apple.coredata.cloudkit.activity.export</string>
    <string>com.apple.coredata.cloudkit.activity.import</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>fetch</string>
</array>
```

### Entitlements
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.himem.app</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>aps-environment</key>
<string>development</string>
<key>com.apple.developer.siri</key>
<true/>
```

## Core Question

Why does the iPad register for APNs successfully (gets a 32-byte device token) but never receive CloudKit silent push notifications (`content-available: 1`), while the iPhone with the identical build does?

Both devices:
- Same iCloud account
- Same network
- Same app build
- Same APNs registration code
- Both get device tokens
- Both show `NSPersistentStoreRemoteChange` during initial sync

Only iPhone:
- Receives `didReceiveRemoteNotification` with CloudKit payload
- Shows ongoing `NSPersistentStoreRemoteChange` after initial sync
- Imports changes within seconds

## Environment
- iPhone: Tom's iPhone (device ID: 00008130-000844990A43001C)
- iPad: Tom's iPad Pro (device ID: 00008103-001E390A0C23001E)
- Xcode: latest
- iOS/iPadOS: current
- CloudKit: development environment
- Bundle ID: com.himem.app

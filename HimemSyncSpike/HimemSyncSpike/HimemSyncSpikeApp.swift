import SwiftUI

/// CKSyncEngine spike — minimal iOS app that reads HiMem's existing
/// JournalEntry records from the shared iCloud container using
/// CKSyncEngine instead of NSPersistentCloudKitContainer. The single
/// purpose is to measure cold-launch time-to-first-record-visible and
/// compare against HiMem's ~17s NSPersistentCloudKitContainer baseline.
///
/// READ-ONLY. The spike never writes to CloudKit. Polluting HiMem's
/// production data is the only thing that could turn this experiment
/// into a regret.
@main
struct HimemSyncSpikeApp: App {
    @StateObject private var reader: SyncedReader

    init() {
        // Wrap SyncedReader construction in the spike.app.init signpost.
        // Using the SpikeSignposter.interval(...) helper instead of the
        // raw OSSignposter API so this file doesn't need to import `os`
        // — Swift 6's MemberImportVisibility upcoming feature requires
        // direct imports for APIs whose types are touched at call sites.
        _reader = SpikeSignposter.interval("spike.app.init") {
            StateObject(wrappedValue: SyncedReader())
        }
    }

    var body: some Scene {
        WindowGroup {
            EntryListView(reader: reader)
        }
    }
}

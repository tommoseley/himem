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
        let state = SpikeSignposter.signposter.beginInterval(
            "spike.app.init",
            id: SpikeSignposter.signposter.makeSignpostID()
        )
        defer { SpikeSignposter.signposter.endInterval("spike.app.init", state) }
        _reader = StateObject(wrappedValue: SyncedReader())
    }

    var body: some Scene {
        WindowGroup {
            EntryListView(reader: reader)
        }
    }
}

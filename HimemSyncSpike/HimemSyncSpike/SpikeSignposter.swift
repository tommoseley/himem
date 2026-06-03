import Foundation
import os.signpost

/// Cold-launch instrumentation for the CKSyncEngine spike. Uses the same
/// subsystem + "PointsOfInterest" category as HiMem's LaunchSignposter so
/// the spike's bars appear in Instruments' Points of Interest track exactly
/// like HiMem's do — direct apples-to-apples comparison.
///
/// Spike intervals:
///   spike.app.init                — App struct init body
///   spike.reader.init             — SyncedReader.init (synchronous setup)
///   spike.engine.created          — CKSyncEngine instance created
///   spike.firstFetchKicked        — engine.fetchChanges() called
///   spike.firstEventReceived      — first non-empty CKSyncEngine.Event
///   spike.firstRecordVisible      — first non-empty fetchedRecordZoneChanges
///   spike.uiPainted               — EntryListView.onAppear with non-empty list
enum SpikeSignposter {
    static let signposter = OSSignposter(
        subsystem: "com.himem.spike",
        category: "PointsOfInterest"
    )

    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

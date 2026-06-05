import Foundation
import CloudKit

/// Atomic Founders-purchase counter, backed by a single record in the
/// CloudKit *public* database.
///
/// Why public DB: every device must see the same `claimed` count so the
/// 250-seat cap is honest. The private DB is per-Apple-ID and can't
/// enforce a global cap. App Store Server Notifications would be more
/// robust but require backend infra HiMem doesn't have. CloudKit public
/// DB gets us atomic increment + reads from every device, no server.
///
/// Schema (deploy manually to Production via CloudKit Dashboard before
/// the first TestFlight build that surfaces Founders):
///   • RecordType: `FoundersCounter`
///   • Record name: `singleton` (always one record)
///   • Field: `claimed: Int`
///
/// Reads cache locally for the session (cap state changes slowly — at
/// most 250 times ever). Writes use a CloudKit `modifyRecords` against
/// the record's `recordChangeTag` to atomically resolve concurrent
/// purchases on the rare occasion two Founders buy at the same moment.
@MainActor
final class FoundersCounter: ObservableObject {
    static let shared = FoundersCounter()

    static let cap = 250
    private static let recordName = "singleton"
    private static let recordType = "FoundersCounter"
    private static let fieldClaimed = "claimed"

    @Published private(set) var claimed: Int = 0
    @Published private(set) var hasLoaded: Bool = false
    @Published private(set) var lastError: String?

    var remaining: Int { max(0, FoundersCounter.cap - claimed) }
    var capReached: Bool { remaining <= 0 }

    private var container: CKContainer {
        CKContainer(identifier: "iCloud.com.himem.app")
    }
    private var database: CKDatabase {
        container.publicCloudDatabase
    }
    private var recordID: CKRecord.ID {
        CKRecord.ID(recordName: FoundersCounter.recordName)
    }

    /// Reads the latest `claimed` count from CloudKit. Called at app
    /// launch and whenever Founders surfaces appear. Safe to call often
    /// — CloudKit handles its own caching.
    func refresh() async {
        do {
            let record = try await fetchOrCreateRecord()
            claimed = record[FoundersCounter.fieldClaimed] as? Int ?? 0
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("[HiMem][Founders] refresh failed: \(error.localizedDescription)")
        }
    }

    /// Atomically increments `claimed` after a verified Founders
    /// purchase. Retries once on `serverRecordChanged` to handle the
    /// concurrent-purchase race. Idempotent enough — if the user
    /// re-runs `Restore Purchases`, we don't double-increment because
    /// `StoreKitService.applyTransaction` only calls this from the new
    /// purchase path, not from `reconcileCurrentEntitlements`.
    func incrementClaimed(retries: Int = 1) async {
        do {
            let record = try await fetchOrCreateRecord()
            let current = record[FoundersCounter.fieldClaimed] as? Int ?? 0
            record[FoundersCounter.fieldClaimed] = current + 1
            _ = try await database.modifyRecords(saving: [record], deleting: [])
            claimed = current + 1
        } catch let error as CKError where error.code == .serverRecordChanged && retries > 0 {
            await incrementClaimed(retries: retries - 1)
        } catch {
            lastError = error.localizedDescription
            NSLog("[HiMem][Founders] increment failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// Overrides the local `claimed` count for testing — the upgrade
    /// hub tile and Founders detail screen render their cap states
    /// from this. Doesn't write to CloudKit, so a real refresh from
    /// the dashboard will clobber it.
    func debugSetClaimed(_ value: Int) {
        claimed = max(0, value)
        hasLoaded = true
    }
    #endif

    private func fetchOrCreateRecord() async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: FoundersCounter.recordType, recordID: recordID)
            record[FoundersCounter.fieldClaimed] = 0
            _ = try await database.modifyRecords(saving: [record], deleting: [])
            return record
        }
    }
}

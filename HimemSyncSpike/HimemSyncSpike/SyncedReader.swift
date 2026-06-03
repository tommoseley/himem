import Foundation
import CloudKit
import Combine

/// Snapshot of a CD_JournalEntry CKRecord. CKRecord itself isn't safe to
/// hold across actors, so we copy out the fields we display.
struct JournalEntrySnapshot: Identifiable, Hashable {
    let id: String          // recordName
    let title: String
    let createdAt: Date?
    let contentPreview: String
}

/// Reads JournalEntry records from HiMem's iCloud container via
/// CKSyncEngine. Single-purpose, read-only, instrumented.
///
/// CKSyncEngine state persistence: we serialize the engine's State.Serialization
/// blob to Documents/spike-cksync-state.json between launches so subsequent
/// launches don't re-fetch the full library. The cold-launch measurement we
/// care about is FIRST launch (no persisted state) — that's what's analogous
/// to HiMem's NSPersistentCloudKitContainer first-launch behavior.
@MainActor
final class SyncedReader: ObservableObject, CKSyncEngineDelegate {
    @Published private(set) var entries: [JournalEntrySnapshot] = []
    @Published private(set) var status: String = "Initializing…"

    private let containerID = "iCloud.com.himem.app"

    private let stateURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("spike-cksync-state.json")
    }()

    private var engine: CKSyncEngine!
    private var hasEmittedFirstRecordSignpost = false
    private var hasEmittedFirstEventSignpost = false

    init() {
        SpikeSignposter.interval("spike.reader.init") {
            createEngine()
        }
        Task { await kickInitialFetch() }
    }

    private func createEngine() {
        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase

        // Load any persisted state from a prior launch. nil first-time.
        let serialization: CKSyncEngine.State.Serialization? = {
            guard let data = try? Data(contentsOf: stateURL) else { return nil }
            return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }()

        var config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,
            delegate: self
        )
        config.automaticallySync = true
        engine = CKSyncEngine(config)
        SpikeSignposter.event("spike.engine.created")
    }

    private func kickInitialFetch() async {
        status = "Fetching…"
        SpikeSignposter.event("spike.firstFetchKicked")
        do {
            try await engine.fetchChanges()
            status = entries.isEmpty ? "Done · 0 records" : "Done · \(entries.count) records"
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        // Capture the first event signpost regardless of type — confirms
        // the engine has talked to the server at least once.
        await MainActor.run {
            if !hasEmittedFirstEventSignpost {
                SpikeSignposter.event("spike.firstEventReceived")
                hasEmittedFirstEventSignpost = true
            }
        }

        switch event {
        case .stateUpdate(let stateEvent):
            await persistState(stateEvent.stateSerialization)
        case .fetchedRecordZoneChanges(let zoneChanges):
            await ingest(zoneChanges)
        case .accountChange, .fetchedDatabaseChanges, .sentRecordZoneChanges,
             .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges, .didFetchChanges, .willSendChanges,
             .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    /// The spike never writes, so this always returns nil. CKSyncEngine
    /// calls this to drain pending changes; with none, it skips the
    /// network call.
    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        nil
    }

    // MARK: - Ingest

    private func ingest(_ zoneChanges: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        // We only care about the Core Data zone. CKSyncEngine surfaces
        // changes for ALL zones in the private DB; filter to ours.
        let entryRecords = zoneChanges.modifications
            .map(\.record)
            .filter { $0.recordType == "CD_JournalEntry" }

        guard !entryRecords.isEmpty else { return }

        let snapshots = entryRecords.map { record -> JournalEntrySnapshot in
            let title = (record["CD_title"] as? String) ?? ""
            let createdAt = record["CD_createdAt"] as? Date
            let content = (record["CD_content"] as? String) ?? ""
            let preview = String(content.prefix(120))
            return JournalEntrySnapshot(
                id: record.recordID.recordName,
                title: title,
                createdAt: createdAt,
                contentPreview: preview
            )
        }

        await MainActor.run {
            // Dedup by id (CKSyncEngine can re-deliver during recovery).
            var byId: [String: JournalEntrySnapshot] = [:]
            for existing in entries { byId[existing.id] = existing }
            for new in snapshots { byId[new.id] = new }
            entries = byId.values.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }

            if !hasEmittedFirstRecordSignpost {
                SpikeSignposter.event("spike.firstRecordVisible")
                hasEmittedFirstRecordSignpost = true
            }
        }
    }

    // MARK: - State persistence

    private func persistState(_ serialization: CKSyncEngine.State.Serialization) async {
        do {
            let data = try JSONEncoder().encode(serialization)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("[Spike] State persist failed: \(error.localizedDescription)")
        }
    }
}

import Foundation
import Photos
import CoreData

@MainActor
final class AlbumSyncService: ObservableObject {
    static let shared = AlbumSyncService()

    struct PendingProposal: Identifiable {
        let id = UUID()
        let topicName: String
    }

    @Published var pendingProposal: PendingProposal? = nil

    private var queue: [PendingProposal] = []

    // Topics where the user approved auto-sync to a Photos album
    private var syncedTopics: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "albumSyncedTopics") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "albumSyncedTopics") }
    }

    // Topics already offered (so we don't re-prompt)
    private var offeredTopics: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "albumOfferedTopics") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "albumOfferedTopics") }
    }

    func isAutoSyncEnabled(for topicName: String) -> Bool {
        syncedTopics.contains(topicName)
    }

    // MARK: - Propose / Approve / Reject

    func proposeIfNeeded(topicName: String) {
        guard !offeredTopics.contains(topicName) else { return }
        offeredTopics.insert(topicName)
        queue.append(PendingProposal(topicName: topicName))
        showNextIfNeeded()
    }

    func approve() {
        guard let proposal = pendingProposal else { return }
        syncedTopics.insert(proposal.topicName)
        Task {
            await syncAllMedia(for: proposal.topicName)
        }
        pendingProposal = nil
        showNextIfNeeded()
    }

    func reject() {
        pendingProposal = nil
        showNextIfNeeded()
    }

    /// Called from processing pipeline when a topic with auto-sync gets new media.
    func addNewMedia(topicName: String, identifiers: [String]) {
        guard isAutoSyncEnabled(for: topicName), !identifiers.isEmpty else { return }
        Task {
            try? await addAssetsToAlbum(named: topicName, assetIdentifiers: identifiers)
        }
    }

    // MARK: - Private

    private func showNextIfNeeded() {
        guard pendingProposal == nil, !queue.isEmpty else { return }
        pendingProposal = queue.removeFirst()
    }

    private func syncAllMedia(for topicName: String) async {
        let context = StorageService.shared.viewContext
        let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        request.predicate = NSPredicate(format: "ANY topics.name == %@", topicName)

        do {
            let entries = try context.fetch(request)
            var identifiers: [String] = []
            for entry in entries {
                for ref in entry.mediaReferencesArray {
                    identifiers.append(ref.osIdentifier)
                }
            }
            guard !identifiers.isEmpty else { return }
            try await addAssetsToAlbum(named: topicName, assetIdentifiers: identifiers)
        } catch {
            print("AlbumSync: failed to sync media for \(topicName): \(error)")
        }
    }

    // MARK: - Photos Library

    private func findOrCreateAlbum(named name: String) async throws -> PHAssetCollection {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let existing = collections.firstObject {
            return existing
        }

        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }

        guard let localIdentifier = placeholder?.localIdentifier else {
            throw AlbumSyncError.creationFailed
        }

        let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let album = created.firstObject else {
            throw AlbumSyncError.creationFailed
        }
        return album
    }

    private func addAssetsToAlbum(named name: String, assetIdentifiers: [String]) async throws {
        let album = try await findOrCreateAlbum(named: name)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        guard assets.count > 0 else { return }

        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets(assets)
        }
    }

    enum AlbumSyncError: LocalizedError {
        case creationFailed

        var errorDescription: String? {
            "Failed to create Photos album."
        }
    }
}

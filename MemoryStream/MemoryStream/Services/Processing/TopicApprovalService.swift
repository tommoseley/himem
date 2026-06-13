import Foundation

@MainActor
final class TopicApprovalService: ObservableObject {
    static let shared = TopicApprovalService()

    struct PendingTopic: Identifiable {
        let id = UUID()
        let name: String
        let entryObjectID: NSManagedObjectID
    }

    @Published var pendingTopic: PendingTopic? = nil

    private var queue: [PendingTopic] = []

    func suggest(name: String, entryObjectID: NSManagedObjectID) {
        let pending = PendingTopic(name: name, entryObjectID: entryObjectID)
        queue.append(pending)
        showNextIfNeeded()
    }

    func approve(paletteKey: String) {
        guard let current = pendingTopic else { return }
        let storage = StorageService.shared
        do {
            let topic = try storage.findOrCreateTopic(name: current.name, paletteKey: paletteKey)
            let entry = try storage.viewContext.existingObject(with: current.entryObjectID) as! JournalEntry
            entry.addToTopics(topic)
            try storage.save(context: storage.viewContext)

            // Update the in-memory palette cache
            TopicPaletteStore.shared.set(key: paletteKey, for: current.name)

            // Per-topic Photos-album sync was retired June 10 2026 —
            // captures now land in a single "HiMem" album (gated by
            // `CameraService.alsoSaveToPhotosLibrary`). Approving a
            // topic no longer touches the Photos library.
        } catch {
            ErrorState.shared.report(.topicError(error.localizedDescription))
        }
        pendingTopic = nil
        showNextIfNeeded()
    }

    func reject() {
        pendingTopic = nil
        showNextIfNeeded()
    }

    private func showNextIfNeeded() {
        guard pendingTopic == nil, !queue.isEmpty else { return }
        pendingTopic = queue.removeFirst()
    }
}

import CoreData

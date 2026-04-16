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

    func approve() {
        guard let current = pendingTopic else { return }
        let storage = StorageService.shared
        do {
            let topic = try storage.findOrCreateTopic(name: current.name)
            let entry = try storage.viewContext.existingObject(with: current.entryObjectID) as! JournalEntry
            entry.addToTopics(topic)
            try storage.save(context: storage.viewContext)
        } catch {
            print("Failed to approve topic: \(error)")
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

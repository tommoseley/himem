import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for delete-from-library (unified associations, 2026-07-17).
/// Deleting a topic from the library purges the vocabulary entry
/// everywhere — but the memories that used it must **survive**, simply
/// losing the assignment. That invariant rests entirely on the
/// `Topic.entries` relationship being `Nullify`, not `Cascade`; if a
/// model edit ever flips it, delete-from-library silently becomes
/// delete-the-memories. These tests are the guard.
@MainActor
@Suite(.serialized)
struct ManageTopicsLibraryDeleteTests {

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? storage.viewContext.fetch(req).first
    }

    private func fetchTopic(named name: String, in storage: StorageService) -> Topic? {
        let req = NSFetchRequest<Topic>(entityName: "Topic")
        req.predicate = NSPredicate(format: "name == %@", name)
        req.fetchLimit = 1
        return try? storage.viewContext.fetch(req).first
    }

    @Test func deleteFromLibrary_removesTopic_memoriesSurvive() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext

        // A topic shared by two memories.
        let topic = try storage.findOrCreateTopic(name: "Garden")
        let a = try storage.createEntry(content: "pear tree fruited", inputType: .typed)
        let b = try storage.createEntry(content: "planted tomatoes", inputType: .typed)
        a.addToTopics(topic)
        b.addToTopics(topic)
        try ctx.save()
        let aid = a.id, bid = b.id

        #expect(topic.entryCount == 2, "topic is used by both memories before delete")

        // Delete-from-library: destroy the Topic entity itself. This is
        // exactly what ManageTopicsSheet.performLibraryDelete does.
        ctx.delete(topic)
        try ctx.save()

        // Both memories survive — only the assignment is gone.
        let survivedA = fetchEntry(aid, in: storage)
        let survivedB = fetchEntry(bid, in: storage)
        #expect(survivedA != nil, "memory A survives delete-from-library")
        #expect(survivedB != nil, "memory B survives delete-from-library")
        #expect((survivedA?.topics as? Set<Topic>)?.isEmpty ?? true, "memory A lost the deleted topic")
        #expect((survivedB?.topics as? Set<Topic>)?.isEmpty ?? true, "memory B lost the deleted topic")
        #expect(fetchTopic(named: "Garden", in: storage) == nil, "topic is gone from the library")
    }

    @Test func topicEntries_deletionRule_isNullify() {
        // Schema invariant: the whole delete-from-library safety story
        // depends on Nullify. A refactor to Cascade would delete the
        // memories — this asserts it can't happen silently.
        let storage = StorageService(inMemory: true)
        let model = storage.viewContext.persistentStoreCoordinator?.managedObjectModel
        let entries = model?
            .entitiesByName["Topic"]?
            .relationshipsByName["entries"]
        #expect(entries != nil, "Topic.entries relationship exists")
        #expect(entries?.deleteRule == .nullifyDeleteRule,
                "Topic.entries MUST be Nullify — Cascade would delete memories on topic delete")
    }

    @Test func impactMessage_pluralizes() {
        let one = ManageTopicsSheet.impactMessage(count: 1)
        #expect(one.contains("1 memory"))
        #expect(!one.contains("1 memories"))

        let many = ManageTopicsSheet.impactMessage(count: 4)
        #expect(many.contains("4 memories"))

        // The reassurance copy is load-bearing (spec §3): the memories
        // themselves are never touched.
        #expect(many.contains("The memories themselves are untouched."))
    }
}

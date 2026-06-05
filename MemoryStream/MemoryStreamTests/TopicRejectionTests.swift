import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the per-topic reject pattern — line-through-to-
/// reject from the Mentions row extended to the Topics pills. The
/// visual half lived on the assist-quota-era AISuggestionsCard
/// (deleted in 8d); this test exercises the data half, now
/// `JournalEntry.applyTopicRejections(_:)`.
///
/// Contract:
///   • Rejected topics get their entry relationship removed.
///   • Topic entities themselves stay in the store (other entries
///     may still reference them).
///   • Non-rejected topics survive untouched.
///   • Empty rejection set is a no-op.
///   • Names that don't match any current topic are silently ignored
///     (the rejection set may include stale names if the data has
///     drifted between paint and commit).
@MainActor
@Suite(.serialized)
struct TopicRejectionTests {

    private func makeEntryWithTopics(
        in storage: StorageService,
        topicNames: [String]
    ) throws -> JournalEntry {
        let entry = try storage.createEntry(content: "x", inputType: .typed)
        for name in topicNames {
            let topic = try storage.findOrCreateTopic(name: name)
            entry.addToTopics(topic)
        }
        try storage.viewContext.save()
        return entry
    }

    @Test func applyTopicRejections_removesOnlyRejectedRelationships() throws {
        let storage = StorageService(inMemory: true)
        let entry = try makeEntryWithTopics(in: storage, topicNames: ["Cooking", "Garden", "How We Work"])
        #expect(entry.topicsArray.map(\.name).sorted() == ["Cooking", "Garden", "How We Work"])

        entry.applyTopicRejections(["Cooking"])

        let remaining = Set(entry.topicsArray.map(\.name))
        #expect(remaining == ["Garden", "How We Work"])
    }

    @Test func applyTopicRejections_emptySet_isNoOp() throws {
        let storage = StorageService(inMemory: true)
        let entry = try makeEntryWithTopics(in: storage, topicNames: ["Cooking", "Garden"])

        entry.applyTopicRejections([])

        let remaining = Set(entry.topicsArray.map(\.name))
        #expect(remaining == ["Cooking", "Garden"])
    }

    @Test func applyTopicRejections_unknownNames_silentlyIgnored() throws {
        let storage = StorageService(inMemory: true)
        let entry = try makeEntryWithTopics(in: storage, topicNames: ["Cooking"])

        // "Garden" isn't attached to this entry; rejection should not crash.
        entry.applyTopicRejections(["Garden"])

        let remaining = Set(entry.topicsArray.map(\.name))
        #expect(remaining == ["Cooking"])
    }

    @Test func applyTopicRejections_topicEntityNotDeleted_onlyRelationshipRemoved() throws {
        // Other entries can still reference a topic the current entry
        // rejects. Verify the Topic row survives in the store.
        let storage = StorageService(inMemory: true)
        let otherEntry = try makeEntryWithTopics(in: storage, topicNames: ["Garden"])
        let entry = try makeEntryWithTopics(in: storage, topicNames: ["Garden", "Cooking"])

        entry.applyTopicRejections(["Garden"])

        // The other entry still has Garden.
        #expect(otherEntry.topicsArray.map(\.name) == ["Garden"])
        // The current entry no longer has Garden.
        #expect(entry.topicsArray.map(\.name) == ["Cooking"])
        // The Topic itself is still in the store.
        let request = NSFetchRequest<Topic>(entityName: "Topic")
        request.predicate = NSPredicate(format: "name == %@", "Garden")
        let topics = try storage.viewContext.fetch(request)
        #expect(topics.count == 1)
    }

    @Test func applyTopicRejections_multipleRejected_allRemoved() throws {
        let storage = StorageService(inMemory: true)
        let entry = try makeEntryWithTopics(in: storage, topicNames: ["Cooking", "Garden", "How We Work", "Reading"])

        entry.applyTopicRejections(["Cooking", "Reading"])

        let remaining = Set(entry.topicsArray.map(\.name))
        #expect(remaining == ["Garden", "How We Work"])
    }
}

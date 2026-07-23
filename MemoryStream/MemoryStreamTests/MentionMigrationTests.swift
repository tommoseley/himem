import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the B4 schema batch (July 18 2026): the library-backed
/// `Mention` entity, `findOrCreateMention` dedup, and the
/// ExtractedEntity→Mention migration. The migration must (a) map the
/// legacy types correctly, (b) dedup on name+type across memories, (c) be
/// idempotent, and (d) never merge a person with a same-name org — the
/// dedup rule Tom locked. These are the guards that make the one-shot
/// Production deploy safe.
@MainActor
@Suite(.serialized)
struct MentionMigrationTests {

    private func makeEntry(_ storage: StorageService, _ content: String = "m") throws -> JournalEntry {
        try storage.createEntry(content: content, inputType: .typed)
    }

    private func mentions(of entry: JournalEntry) -> [Mention] {
        (entry.mentions as? Set<Mention> ?? []).sorted { $0.name < $1.name }
    }

    private func allMentions(_ storage: StorageService) -> [Mention] {
        (try? storage.viewContext.fetch(Mention.fetchAll())) ?? []
    }

    // MARK: - findOrCreateMention

    @Test func findOrCreateMention_dedupsOnNameAndType() throws {
        let storage = StorageService(inMemory: true)
        let a = try storage.findOrCreateMention(name: "Darlene", type: .person)
        let b = try storage.findOrCreateMention(name: "Darlene", type: .person)
        #expect(a.objectID == b.objectID, "same name+type resolves to one Mention")
        #expect(allMentions(storage).count == 1)
    }

    @Test func findOrCreateMention_sameNameDifferentType_staysDistinct() throws {
        let storage = StorageService(inMemory: true)
        // The locked rule: a person "Foodies" and an org "Foodies" must
        // NOT merge — dedup is name+type, not name alone.
        let person = try storage.findOrCreateMention(name: "Foodies", type: .person)
        let org = try storage.findOrCreateMention(name: "Foodies", type: .org)
        #expect(person.objectID != org.objectID)
        #expect(allMentions(storage).count == 2)
    }

    @Test func findOrCreateMention_normalizesNameForDedup() throws {
        let storage = StorageService(inMemory: true)
        let a = try storage.findOrCreateMention(name: "  Darlene   Graham ", type: .person)
        let b = try storage.findOrCreateMention(name: "darlene graham", type: .person)
        #expect(a.objectID == b.objectID, "case + whitespace fold to one entry")
        #expect(allMentions(storage).count == 1)
    }

    // MARK: - Type mapping

    @Test func mappedType_followsTheRuling() {
        #expect(MentionMigration.mappedType(for: .idea) == .idea)
        #expect(MentionMigration.mappedType(for: .person) == .person)
        #expect(MentionMigration.mappedType(for: .project) == .org)   // least-wrong bucket
        #expect(MentionMigration.mappedType(for: .issue) == .idea)
        #expect(MentionMigration.mappedType(for: .nextAction) == nil) // not a mention
    }

    // MARK: - Migration

    @Test func migration_mapsTypes_andSkipsNextAction() throws {
        let storage = StorageService(inMemory: true)
        let entry = try makeEntry(storage)
        try storage.createEntity(entryId: entry.id, type: .person, value: "Darlene", confidence: 1, method: "test", entry: entry)
        try storage.createEntity(entryId: entry.id, type: .idea, value: "Basque cheesecake", confidence: 1, method: "test", entry: entry)
        try storage.createEntity(entryId: entry.id, type: .project, value: "Kingfisher Studio", confidence: 1, method: "test", entry: entry)
        try storage.createEntity(entryId: entry.id, type: .nextAction, value: "call the plumber", confidence: 1, method: "test", entry: entry)

        MentionMigration.migrate(in: storage.viewContext, storage: storage)

        let m = mentions(of: entry)
        #expect(m.count == 3, "3 mentions migrated; next_action skipped")
        let byName = Dictionary(uniqueKeysWithValues: m.map { ($0.name, $0.mentionType) })
        #expect(byName["Darlene"] == .person)
        #expect(byName["Basque cheesecake"] == .idea)
        #expect(byName["Kingfisher Studio"] == .org)
        #expect(byName["call the plumber"] == nil, "next_action is not a mention")
    }

    @Test func migration_dedupsAcrossMemories() throws {
        let storage = StorageService(inMemory: true)
        let a = try makeEntry(storage, "one")
        let b = try makeEntry(storage, "two")
        try storage.createEntity(entryId: a.id, type: .person, value: "Darlene", confidence: 1, method: "test", entry: a)
        try storage.createEntity(entryId: b.id, type: .person, value: "Darlene", confidence: 1, method: "test", entry: b)

        MentionMigration.migrate(in: storage.viewContext, storage: storage)

        #expect(allMentions(storage).count == 1, "one shared Darlene, not two")
        let shared = allMentions(storage).first
        #expect(shared?.entryCount == 2, "linked to both memories")
    }

    @Test func migration_isIdempotent() throws {
        let storage = StorageService(inMemory: true)
        let entry = try makeEntry(storage)
        try storage.createEntity(entryId: entry.id, type: .person, value: "Darlene", confidence: 1, method: "test", entry: entry)

        let first = MentionMigration.migrate(in: storage.viewContext, storage: storage)
        let second = MentionMigration.migrate(in: storage.viewContext, storage: storage)
        #expect(first == 1, "one link created on first run")
        #expect(second == 0, "re-run creates nothing")
        #expect(allMentions(storage).count == 1)
        #expect(mentions(of: entry).count == 1, "no duplicate link on the memory")
    }
}

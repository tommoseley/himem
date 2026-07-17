import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for F1 (2026-07-17) — the project deletion lock's safety net.
/// `deleteProject` SOFT-deletes (routes to Recently Deleted, recoverable),
/// member memories survive (nullify edges), and Restore brings it back.
@MainActor
@Suite(.serialized)
struct ProjectSoftDeleteTests {

    private func make() -> (StorageService, ProjectViewModel) {
        let storage = StorageService(inMemory: true)
        return (storage, ProjectViewModel(storage: storage))
    }

    private func fetchEntry(_ id: UUID, in storage: StorageService) -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? storage.viewContext.fetch(req).first
    }

    @Test func deleteProject_softDeletes_memoryStaysAlive() throws {
        let (storage, vm) = make()
        let project = try storage.createProject(name: "Kingfisher Wharf", purpose: nil)
        let entry = try storage.createEntry(content: "a member memory", inputType: .typed)
        project.addToEntries(entry)
        try storage.viewContext.save()
        let pid = project.id, eid = entry.id

        vm.deleteProject(id: pid)

        // Soft-deleted: out of the active list, in Recently Deleted.
        vm.loadProjects()
        #expect(!vm.projects.contains { $0.id == pid }, "recycled project is hidden from the active list")
        #expect(vm.loadRecycledProjects().contains { $0.id == pid }, "recycled project appears in Recently Deleted")

        // The member memory survives — never deleted.
        #expect(fetchEntry(eid, in: storage) != nil, "member memory survives project deletion")
    }

    @Test func restoreProject_bringsItBack() throws {
        let (storage, vm) = make()
        let project = try storage.createProject(name: "M", purpose: nil)
        try storage.viewContext.save()
        let pid = project.id

        vm.deleteProject(id: pid)
        #expect(vm.loadRecycledProjects().contains { $0.id == pid })

        vm.restoreProject(id: pid)
        #expect(vm.loadRecycledProjects().isEmpty, "restore clears the recycled state")
        vm.loadProjects()
        #expect(vm.projects.contains { $0.id == pid }, "restored project is back in the active list")
    }

    @Test func purgeProject_hardDeletes_memoryStillSurvives() throws {
        let (storage, vm) = make()
        let project = try storage.createProject(name: "P", purpose: nil)
        let entry = try storage.createEntry(content: "member", inputType: .typed)
        project.addToEntries(entry)
        try storage.viewContext.save()
        let pid = project.id, eid = entry.id

        vm.deleteProject(id: pid)
        vm.purgeProject(id: pid)

        #expect(vm.loadRecycledProjects().isEmpty, "purged project is gone from the bin")
        vm.loadProjects()
        #expect(!vm.projects.contains { $0.id == pid }, "purged project is gone from the active list")
        #expect(fetchEntry(eid, in: storage) != nil, "member memory survives even a hard purge (nullify edges)")
    }
}

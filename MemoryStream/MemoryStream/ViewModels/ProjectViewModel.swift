import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class ProjectViewModel: ObservableObject {
    @Published var projects: [ProjectDisplayModel] = []

    private let storage: StorageService
    private var observer: AnyCancellable?

    init(storage: StorageService = .shared) {
        self.storage = storage
        observeChanges()
        // Cold-launch fix 2026-06-02: loadProjects() moved out of init.
        // JournalView fires loadInitial() in `.task` so the fetch runs
        // after the first frame is rendered. Same shape as the
        // JournalViewModel fix; see feedback_cold_launch_target memory.
    }

    /// First-paint load. Called by JournalView's `.task`. Idempotent.
    func loadInitial() async {
        loadProjects()
    }

    private func observeChanges() {
        observer = NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: storage.viewContext
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.loadProjects()
        }
    }

    func loadProjects() {
        let request = Project.fetchAll()
        // Recycled projects (F1 soft-delete) are hidden from the active list —
        // they live in Recently Deleted until restored or purged.
        request.predicate = NSPredicate(format: "recycledAt == nil")
        do {
            let fetched = try storage.viewContext.fetch(request)
            projects = fetched.map { mapToDisplayModel($0) }
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    func createProject(name: String, purpose: String?) {
        do {
            let _ = try storage.createProject(name: name, purpose: purpose)
            loadProjects()
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    /// F1 deletion lock (2026-07-17): SOFT-delete — routes the project to
    /// Recently Deleted (recoverable 30 days), the safety net that makes the
    /// no-confirm bottom Delete button safe. The membership edges are kept so
    /// Restore is faithful; a purge (or the 30-day sweep) hard-deletes, and
    /// the Nullify rule dissolves the edges then. Member memories survive
    /// throughout — they're never touched.
    func deleteProject(id: UUID) {
        withProject(id) { project in
            project.recycledAt = Date()
            project.updatedAt = Date()
        }
    }

    /// Recently-Deleted list — projects with a non-nil `recycledAt`,
    /// newest-deleted first.
    func loadRecycledProjects() -> [ProjectDisplayModel] {
        let request = Project.fetchAll()
        request.predicate = NSPredicate(format: "recycledAt != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "recycledAt", ascending: false)]
        do {
            return try storage.viewContext.fetch(request).map { mapToDisplayModel($0) }
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
            return []
        }
    }

    /// Restore from Recently Deleted — clears `recycledAt`; the kept edges
    /// bring back the memberships.
    func restoreProject(id: UUID) {
        withProject(id) { project in
            project.recycledAt = nil
            project.updatedAt = Date()
        }
    }

    /// Permanent delete (from the bin / 30-day purge). The Nullify edge rule
    /// dissolves membership here; member memories survive.
    func purgeProject(id: UUID) {
        withProject(id) { project in
            storage.viewContext.delete(project)
        }
    }

    /// 30-day sweep — hard-deletes recycled projects past their window.
    /// Matches the memory bin's retention.
    func purgeExpiredRecycledProjects() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let request = Project.fetchAll()
        request.predicate = NSPredicate(format: "recycledAt != nil AND recycledAt < %@", cutoff as CVarArg)
        do {
            let expired = try storage.viewContext.fetch(request)
            guard !expired.isEmpty else { return }
            expired.forEach { storage.viewContext.delete($0) }
            try storage.save(context: storage.viewContext)
            loadProjects()
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    private func withProject(_ id: UUID, _ mutate: (Project) -> Void) {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            if let project = try storage.viewContext.fetch(request).first {
                mutate(project)
                try storage.save(context: storage.viewContext)
                loadProjects()
            }
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    func updateProject(id: UUID, name: String, purpose: String?) {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            if let project = try storage.viewContext.fetch(request).first {
                project.name = name
                project.purpose = purpose
                project.updatedAt = Date()
                try storage.save(context: storage.viewContext)
                loadProjects()
            }
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    func addMemory(entryId: UUID, toProjectId projectId: UUID) {
        let entryReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        entryReq.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        entryReq.fetchLimit = 1
        let projReq = NSFetchRequest<Project>(entityName: "Project")
        projReq.predicate = NSPredicate(format: "id == %@", projectId as CVarArg)
        projReq.fetchLimit = 1
        do {
            guard let entry = try storage.viewContext.fetch(entryReq).first,
                  let project = try storage.viewContext.fetch(projReq).first else { return }
            project.addToEntries(entry)
            project.updatedAt = Date()
            try storage.save(context: storage.viewContext)
            loadProjects()
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    func removeMemory(entryId: UUID, fromProjectId projectId: UUID) {
        let entryReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        entryReq.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
        entryReq.fetchLimit = 1
        let projReq = NSFetchRequest<Project>(entityName: "Project")
        projReq.predicate = NSPredicate(format: "id == %@", projectId as CVarArg)
        projReq.fetchLimit = 1
        do {
            guard let entry = try storage.viewContext.fetch(entryReq).first,
                  let project = try storage.viewContext.fetch(projReq).first else { return }
            project.removeFromEntries(entry)
            project.updatedAt = Date()
            try storage.save(context: storage.viewContext)
            loadProjects()
        } catch {
            ErrorState.shared.report(.projectError(error.localizedDescription))
        }
    }

    private func mapToDisplayModel(_ project: Project) -> ProjectDisplayModel {
        ProjectDisplayModel(
            id: project.id,
            name: project.name,
            purpose: project.purpose,
            memoryCount: project.entryCount,
            topicNames: project.topicNames,
            updatedAt: project.updatedAt,
            previewText: project.entriesArray.first?.content
        )
    }
}

// MARK: - Display Model

struct ProjectDisplayModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let purpose: String?
    let memoryCount: Int
    let topicNames: [String]
    let updatedAt: Date
    let previewText: String?

    // Equatable/Hashable are SYNTHESIZED (all stored properties), not
    // id-only. An id-only `==` made SwiftUI treat a card whose goal (or
    // name / count / topics) changed as unchanged — same id → equal →
    // skip re-render — so an edited goal only appeared after a cold
    // relaunch (Tom, 2026-07-18). ForEach identity still comes from
    // `Identifiable.id`; this equality only governs whether the row's
    // body re-runs, which must react to every visible field.
    // Guarded by ProjectDisplayModelEqualityTests.

    var updatedLabel: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 3600 {
            let min = max(1, Int(interval / 60))
            return "\(min) min ago"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: updatedAt)
    }
}

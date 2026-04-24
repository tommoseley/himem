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
        do {
            let fetched = try storage.viewContext.fetch(request)
            projects = fetched.map { mapToDisplayModel($0) }
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    func createProject(name: String, purpose: String?) {
        do {
            let _ = try storage.createProject(name: name, purpose: purpose)
            loadProjects()
        } catch {
            print("Failed to create project: \(error)")
        }
    }

    func deleteProject(id: UUID) {
        let request = NSFetchRequest<Project>(entityName: "Project")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            if let project = try storage.viewContext.fetch(request).first {
                storage.viewContext.delete(project)
                try storage.save(context: storage.viewContext)
                loadProjects()
            }
        } catch {
            print("Failed to delete project: \(error)")
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
            print("Failed to update project: \(error)")
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
            print("Failed to add memory to project: \(error)")
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
            print("Failed to remove memory from project: \(error)")
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

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

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

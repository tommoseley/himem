import Testing
import Foundation
@testable import HiMem

/// Contract tests for the publish-then-populate refactor of
/// ProjectViewModel (cold-launch fix 2026-06-02). Mirrors the
/// JournalViewModel pattern. Same regression guard: init must not
/// run a synchronous Core Data fetch — that fetch lived under the
/// splash and blocked the main thread for seconds while the
/// JournalView @StateObject chain initialized.
@MainActor
struct ProjectViewModelLoadInitialTests {

    @Test func init_doesNotFetch_projectsStartEmpty() throws {
        let storage = StorageService(inMemory: true)

        // Seed a project directly via storage (bypasses the VM).
        _ = try storage.createProject(name: "Garden", purpose: "what's growing")

        let vm = ProjectViewModel(storage: storage)
        #expect(vm.projects.isEmpty, "init must not fetch — that's the cold-launch fix contract.")
    }

    @Test func loadInitial_populatesProjects() async throws {
        let storage = StorageService(inMemory: true)
        _ = try storage.createProject(name: "Garden", purpose: "what's growing")
        _ = try storage.createProject(name: "Studio", purpose: nil)

        let vm = ProjectViewModel(storage: storage)
        #expect(vm.projects.isEmpty)
        await vm.loadInitial()
        #expect(vm.projects.count == 2)
    }
}

import Testing
import Foundation
@testable import HiMem

/// Contract tests for the publish-then-populate refactor (cold-launch fix
/// 2026-06-02). `JournalViewModel.init` previously ran `loadEntries()`,
/// `mergeDuplicateTopics()`, and `mergeDuplicateEntities()` synchronously
/// on the main thread, blocking first paint by 1–3s on populated devices.
/// After the refactor, init only wires observers; the heavy fetches run
/// via `loadInitial()` which JournalView calls in `.task`.
///
/// These two tests pin the contract: empty entries after init, populated
/// after explicit loadInitial(). They guard against a future refactor
/// re-introducing the fetch into init (which would silently re-introduce
/// the cold-launch regression).
@MainActor
@Suite(.serialized)
struct JournalViewModelLoadInitialTests {

    /// Money test for the refactor. Before the fix, init would call
    /// `loadEntries()` synchronously, so this would see `vm.entries.count == 1`.
    /// After the fix, init returns with empty entries.
    @Test func init_doesNotFetch_entriesStartEmpty() {
        let storage = StorageService(inMemory: true)

        // Seed via a temporary VM (saveEntry still triggers its own
        // synchronous loadEntries — that path remains unchanged).
        let seeder = JournalViewModel(storage: storage, processingEngine: nil)
        seeder.saveEntry(content: "seed", inputType: .typed)
        #expect(seeder.entries.count == 1, "Seeding via saveEntry should populate the seeder VM.")

        // A fresh VM on the same storage — init must NOT fetch.
        let vm = JournalViewModel(storage: storage, processingEngine: nil)
        #expect(vm.entries.isEmpty, "init must not fetch — that's the cold-launch fix contract.")
    }

    /// Explicit loadInitial() populates entries. This is what JournalView's
    /// `.task` triggers on first appear.
    @Test func loadInitial_populatesEntries() async {
        let storage = StorageService(inMemory: true)
        let seeder = JournalViewModel(storage: storage, processingEngine: nil)
        seeder.saveEntry(content: "first", inputType: .typed)
        seeder.saveEntry(content: "second", inputType: .typed)

        let vm = JournalViewModel(storage: storage, processingEngine: nil)
        #expect(vm.entries.isEmpty)
        await vm.loadInitial()
        #expect(vm.entries.count == 2)
    }
}

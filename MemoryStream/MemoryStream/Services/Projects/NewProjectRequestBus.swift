import Foundation

/// One-shot signal from the tab-shell FAB to `ProjectListView`: the
/// user tapped + on the Projects tab at the list level, so present
/// the New Project sheet.
///
/// Introduced 2026-07-10 for the context-aware-FAB lock
/// (`CLAUDE.md:142`). The FAB lives at `HiMemTabView`; the New
/// Project sheet lives inside `ProjectListView`. This bus is the
/// seam — the FAB pokes `pending = true`, `ProjectListView` observes
/// and opens the sheet, then clears the flag.
///
/// Not persisted. Cleared on delivery.
@MainActor
final class NewProjectRequestBus: ObservableObject {
    static let shared = NewProjectRequestBus()

    /// Non-nil trigger token. `ProjectListView` observes and presents
    /// the sheet on any change from `nil` → non-`nil`; the token
    /// identity avoids conflating rapid taps.
    @Published var pendingToken: UUID? = nil

    private init() {}

    func request() {
        pendingToken = UUID()
    }

    func consume() {
        pendingToken = nil
    }
}

/// Sibling of `NewProjectRequestBus` for the in-project FAB's *second*
/// path (F7, 2026-07-17): the user, inside a project, chose "Add existing
/// memory," so `ProjectDetailView` should present the `AddMemoryToProject`
/// search-to-add sheet. Same seam shape — the FAB lives at `HiMemTabView`,
/// the sheet needs the project context that only `ProjectDetailView` has.
///
/// Co-located with `NewProjectRequestBus` because the two are the two
/// halves of the same context-aware-FAB contract (list → new project;
/// inside a project → new-memory *or* add-existing).
///
/// Not persisted. Cleared on delivery.
@MainActor
final class AddExistingMemoryRequestBus: ObservableObject {
    static let shared = AddExistingMemoryRequestBus()

    /// Non-nil trigger token. `ProjectDetailView` observes and presents
    /// the sheet on any change from `nil` → non-`nil`; the token identity
    /// avoids conflating rapid taps.
    @Published var pendingToken: UUID? = nil

    private init() {}

    func request() {
        pendingToken = UUID()
    }

    func consume() {
        pendingToken = nil
    }
}

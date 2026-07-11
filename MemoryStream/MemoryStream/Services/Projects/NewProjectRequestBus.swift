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

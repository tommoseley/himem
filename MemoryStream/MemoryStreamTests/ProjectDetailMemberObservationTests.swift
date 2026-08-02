import Testing
import Foundation
@testable import HiMem

/// **F25 (revised) — a correct write rendered from a frozen snapshot.**
///
/// Creating a memory from inside a project wrote the edge correctly and
/// associated it correctly. It just didn't *appear* until you left the
/// project and came back. `ProjectDetailView` held
/// `@State private var entries: [EntryDisplayModel]`, filled by
/// `loadProjectEntries()` from `.onAppear`. `EntryDisplayModel` is a
/// **struct**, so the view owned value copies mapped once at appear —
/// and a struct in `@State` cannot observe a Core Data insert. Leaving
/// and re-entering re-fired `onAppear`, which is why it looked
/// intermittent rather than broken.
///
/// **SECOND INSTANCE OF THIS CLASS IN ONE WEEK.** F24 Defect 2 was the
/// same mechanism one layer down: `InboxClip` — also a struct — captured
/// at `.sheet(item:)` presentation, so a correct transcript save
/// rendered as unchanged. Same shape both times:
///
///   > *a correct write, displayed from a frozen value snapshot.*
///
/// Two occurrences on two surfaces makes this demonstrated rather than
/// theoretical, which is the whole reason it gets a guard instead of a
/// comment. **This test exists to catch the third instance, not to
/// document the second.**
///
/// **The fix had to remove the snapshot, not refresh it.** Calling the
/// loader after creation would have papered over a missing observation
/// and fixed exactly one entry point — the next path that adds a memory
/// to a project would break identically. `@FetchRequest` observes
/// inserts and removals, so there is no cached copy to go stale and
/// nothing to remember to refresh.
///
/// **Why not `@ObservedObject` on the `Project`** (which would also
/// republish): F6g's off-main publishing investigation is unresolved and
/// already exposes `NSManagedObject` as an observed object at four
/// sites. Widening that surface to a fifth while the threading question
/// is open is the wrong trade, and this project's own evidence says so.
@Suite struct ProjectDetailMemberObservationTests {

    /// THE GUARD. The member list must be observed, never cached.
    @Test func theMemberListIsObservedNotSnapshotted() throws {
        let src = try Self.source()

        #expect(src.contains("@FetchRequest private var memberEntries"),
                "`ProjectDetailView` no longer observes its members — a cached array cannot see an insert.")

        let code = Self.executableLines(of: src)
        #expect(code.contains(where: { $0.contains("@State") && $0.contains("entries") }) == false,
                """
                `ProjectDetailView` holds its member memories in `@State` again. \
                That is the F25 defect verbatim: a struct array cannot observe a \
                Core Data insert, so a correctly-created memory renders only \
                after the view re-appears.
                """)
    }

    /// The imperative loader must stay gone. Re-introducing it — even
    /// called from the right places — restores the snapshot, and the
    /// next write path that forgets to call it breaks silently again.
    @Test func theImperativeLoaderIsNotReintroduced() throws {
        let code = Self.executableLines(of: try Self.source())
        #expect(code.contains(where: { $0.contains("loadProjectEntries") }) == false,
                "The imperative member loader is back — a refresh call papers over the missing observation.")
    }

    /// The fix must not have been made by widening the `NSManagedObject`
    /// observation surface F6g is still investigating.
    @Test func theProjectIsNotObservedAsAManagedObject() throws {
        let code = Self.executableLines(of: try Self.source())
        #expect(code.contains(where: { $0.contains("@ObservedObject") && $0.contains("Project") && !$0.contains("ProjectViewModel") }) == false,
                """
                A `Project` managed object is now observed directly. F6g's \
                off-main publishing question is unresolved with four such sites \
                already; this would be a fifth.
                """)
    }

    /// Ordering must not silently change with the mechanism. The retired
    /// `entriesArray` sorted by `createdAt` descending.
    @Test func theMemberOrderIsPreserved() throws {
        let src = try Self.source()
        #expect(src.contains("NSSortDescriptor(key: \"createdAt\", ascending: false)"),
                "The member list's sort order moved away from `createdAt` descending — the previous `entriesArray` behaviour.")
    }

    /// Self-test: the matcher must recognise the shape that shipped, or
    /// it passes forever by matching nothing.
    @Test func guardCanSeeTheSnapshotShape() {
        let shipped = """
                @State private var entries: [EntryDisplayModel] = []
                private func loadProjectEntries() {
                    entries = journalEntries.map(EntryMapper.mapToDisplayModel)
                }
        """
        let code = Self.executableLines(of: shipped)
        #expect(code.contains(where: { $0.contains("@State") && $0.contains("entries") }))
        #expect(code.contains(where: { $0.contains("loadProjectEntries") }))
    }

    /// …and must ignore the comments that explain the removal.
    @Test func guardIgnoresComments() {
        let documented = """
                /// This was `@State private var entries: [EntryDisplayModel] = []`,
                /// filled by `loadProjectEntries()` from `.onAppear`.
        """
        #expect(Self.executableLines(of: documented).isEmpty)
    }

    // MARK: - Helpers

    static func executableLines(of source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("///") }
    }

    static func source() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MemoryStream/Views/Projects/ProjectDetailView.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String) }
}

import Foundation
import Combine

/// Single-source-of-truth for "which text field on Memory Detail is
/// currently in edit mode" — load-bearing for two spec rules from
/// `docs/design/Memory Detail · unified editing model.md` §"Editing a
/// clip transcript — exact layout behavior" (Tom 2026-06-09):
///
/// - **The FAB hides during any active text edit.** The Memory Detail
///   FAB observes `isAnyEditing` and disappears the moment any title,
///   summary, or clip transcript flips to edit mode.
/// - **One edit at a time.** Beginning an edit on any field closes any
///   other currently-open editor. Each editor calls `begin(id:)` when
///   the user taps to edit; if `activeEditId` is already a different
///   id, the previously-open editor reacts to the id change and
///   commits-and-closes itself.
///
/// Per-Memory-Detail singleton (lives across `EntryExpandedView`s on
/// the navigation stack, but only one is on screen at a time so the
/// `activeEditId` value is unambiguous).
@MainActor
final class TextEditCoordinator: ObservableObject {
    static let shared = TextEditCoordinator()
    private init() {}

    /// Opaque id of the active editor (title, summary, or
    /// `transcript-<UUID>`). Nil when nothing is being edited.
    @Published private(set) var activeEditId: String? = nil

    var isAnyEditing: Bool { activeEditId != nil }

    /// Called when the user taps a text field to begin editing. The
    /// caller is responsible for setting their own local edit state
    /// to active and focusing the field.
    func begin(id: String) {
        activeEditId = id
    }

    /// Called by the editor when it commits/cancels. No-op if a
    /// different editor is now active (we don't want a stale commit
    /// to clobber another field's edit-active state).
    func end(id: String) {
        if activeEditId == id { activeEditId = nil }
    }
}

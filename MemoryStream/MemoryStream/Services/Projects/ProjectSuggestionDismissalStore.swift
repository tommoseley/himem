import Foundation

/// Persists per-project "I don't want this suggested again"
/// dismissals for the suggested-membership review sheet. v1 is
/// local-only — UserDefaults-backed, **not** CloudKit-synced. If
/// you dismiss on iPhone and re-suggest on iPad, that's annoying
/// but recoverable; cross-device dismissal is a v1.1 add (would
/// need a JSON field on `Project` and a schema deploy).
///
/// Storage shape: a single `[projectId: [entryId]]` dictionary
/// under one UserDefaults key. Two reasons over per-project keys:
/// fewer keys to walk on project deletion (one read + one write
/// vs. enumerating Defaults), and no per-key staleness when a
/// project is removed but UserDefaults still has its entries.
@MainActor
final class ProjectSuggestionDismissalStore: ObservableObject {

    static let shared = ProjectSuggestionDismissalStore(defaults: .standard)

    private static let storeKey = "himem.suggestedMembership.dismissed.v1"

    private let defaults: UserDefaults
    @Published private(set) var version: Int = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// All dismissed entry IDs for `projectId`. Empty when nothing
    /// has been dismissed (no error path — that's just the initial
    /// state).
    func dismissed(forProject projectId: UUID) -> Set<UUID> {
        let map = loadMap()
        let raw = map[projectId.uuidString] ?? []
        return Set(raw.compactMap(UUID.init))
    }

    /// Records that the user skipped `entryId` for this project.
    /// Idempotent — re-dismissing a row that's already in the set
    /// is a no-op (no UserDefaults write, no `version` bump).
    func dismiss(entryId: UUID, forProject projectId: UUID) {
        var map = loadMap()
        var ids = Set(map[projectId.uuidString]?.compactMap(UUID.init) ?? [])
        guard ids.insert(entryId).inserted else { return }
        map[projectId.uuidString] = ids.map(\.uuidString)
        saveMap(map)
        version &+= 1
    }

    /// Reverses a prior dismissal. Currently unused by the UI but
    /// available for "Undo" affordances and tests.
    func restore(entryId: UUID, forProject projectId: UUID) {
        var map = loadMap()
        var ids = Set(map[projectId.uuidString]?.compactMap(UUID.init) ?? [])
        guard ids.remove(entryId) != nil else { return }
        if ids.isEmpty {
            map.removeValue(forKey: projectId.uuidString)
        } else {
            map[projectId.uuidString] = ids.map(\.uuidString)
        }
        saveMap(map)
        version &+= 1
    }

    /// Clears every dismissal for a project. Call site: project
    /// deletion. No-op for an unknown project.
    func clearAll(forProject projectId: UUID) {
        var map = loadMap()
        guard map.removeValue(forKey: projectId.uuidString) != nil else { return }
        saveMap(map)
        version &+= 1
    }

    // MARK: - Backing store

    /// Reads the `[projectId: [entryId]]` map. Returns empty when
    /// the key has never been written or the stored payload is the
    /// wrong type (e.g., legacy schema). Wrong-type recovery is
    /// silent because UserDefaults shouldn't crash the app — the
    /// next write will overwrite cleanly.
    private func loadMap() -> [String: [String]] {
        (defaults.dictionary(forKey: Self.storeKey) as? [String: [String]]) ?? [:]
    }

    private func saveMap(_ map: [String: [String]]) {
        defaults.set(map, forKey: Self.storeKey)
    }
}

import Foundation
import Combine

/// Shared, tab-level signal: which unplaced `MediaReference` ids have
/// been absorbed into a voice session (by `SessionMediaAbsorber`).
///
/// SessionListView owns the write side — it runs the absorber every
/// time its `sessions` recompute. ClipsTabView reads the id set to
/// filter its own unplaced-refs list so a photo doesn't render both
/// inside a session card AND in the top day-grouped stack.
///
/// Introduced 2026-07-11 for the media-agnostic idle-gap fix
/// (`Captured Clips · session-first · spec.md` §Model, July 11 lock).
@MainActor
final class BenchAbsorbedMediaBus: ObservableObject {
    static let shared = BenchAbsorbedMediaBus()

    /// Ids of unplaced `MediaReference`s currently absorbed into a
    /// voice session's expanded body. Empty when the bench has no
    /// voice sessions or no unplaced media falls inside any window.
    @Published private(set) var absorbedRefIds: Set<UUID> = []

    private init() {}

    func setAbsorbed(_ ids: Set<UUID>) {
        // Guard against redundant publishes — avoids feedback loops
        // when SessionListView recomputes on an unrelated change.
        if ids != absorbedRefIds {
            absorbedRefIds = ids
        }
    }
}

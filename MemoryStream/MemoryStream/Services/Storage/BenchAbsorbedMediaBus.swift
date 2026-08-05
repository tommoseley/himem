import Foundation
import Combine

/// Shared, tab-level signal: which media `MediaReference` ids `SessionListView`
/// is currently drawing inside its session cards.
///
/// SessionListView owns the write side; ClipsTabView reads the id set to filter
/// its own unplaced-refs list so a photo doesn't render both inside a session
/// card AND in the top day-grouped stack.
///
/// Introduced 2026-07-11 for the media-agnostic idle-gap fix
/// (`Captured Clips · session-first · spec.md` §Model, July 11 lock), when the
/// set came from `SessionMediaAbsorber`.
///
/// **SCHEDULED FOR DELETION IN C2 STEP 3, and kept through step 2b on purpose**
/// (ruled 2026-08-03). The absorber is gone — media is now simply *in* its
/// session, so the published set is just "the non-voice items I drew". But the
/// sibling unplaced stack in `ClipsTabView` still renders until step 3 retires
/// it, and without this signal every photo would appear twice: reintroducing
/// the F35(b) duplication class in order to fix a structure problem. It dies
/// with the stack it exists for, not before.
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

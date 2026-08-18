import Foundation
import Combine
import CoreData

/// Shared, tab-level signal: the unplaced `MediaReference`s the **bench did not
/// draw**, which `ClipsTabView`'s day-grouped sibling stack is responsible for.
///
/// **C2 step 3, 2026-08-18 — this used to carry the opposite.** It published the
/// ids the bench HAD drawn, and the parent subtracted them from its own
/// `NSFetchRequest` over the same predicate. Two stores answering one question,
/// which is the class C2 exists to end: the parent's fetch was debounced at
/// 250ms, so it could hold a ref Core Data had already invalidated, and
/// `ClipsUnplacedFilter` existed to survive that window.
///
/// Now the composition names the complement once (`RenderedBench
/// .siblingStackSessions`) and publishes the refs themselves. There is one
/// fetch on the bench path and none in the parent.
///
/// **Direction, and why a bus at all:** `ClipsTabView` is the parent and
/// `SessionListView` the child, so this data travels upward. That was true
/// before this change and is unchanged by it.
///
/// **Filename note:** the type is `BenchSiblingStackBus`; the file is still
/// `BenchAbsorbedMediaBus.swift`. Renaming the file means editing four explicit
/// `project.pbxproj` references, and this project has already had `git mv`
/// orphan such references (F18). Deliberately deferred, recorded here so the
/// mismatch reads as a decision rather than an oversight.
///
/// Originally introduced 2026-07-11 for the media-agnostic idle-gap fix
/// (`Captured Clips · session-first · spec.md` §Model, July 11 lock).
@MainActor
final class BenchSiblingStackBus: ObservableObject {
    static let shared = BenchSiblingStackBus()

    /// Refs the sibling stack draws — the items of loose sessions with no
    /// voice. Empty when every unplaced media item grouped into a voice
    /// sitting, or when there is none.
    ///
    /// Order is the bench's (ascending by capture). The stack sorts for
    /// display; carrying data rather than presentation is what keeps the two
    /// concerns from drifting back together.
    @Published private(set) var stackMedia: [MediaReference] = []

    private init() {}

    func setStackMedia(_ refs: [MediaReference]) {
        // Guard against redundant publishes — avoids feedback loops when
        // `SessionListView` recomposes on an unrelated change. Compared by
        // identity, which is what `MediaReference` equality is.
        if refs != stackMedia {
            stackMedia = refs
        }
    }
}

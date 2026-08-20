import Testing
import Foundation
@testable import HiMem

/// **C2 step 3 — the bench and its sibling stack partition the media.**
///
/// `ClipsTabView` used to answer "what does the stack draw?" with its own
/// `NSFetchRequest` (same predicate as the bench's, opposite sort) minus an id
/// set the child published. Two stores answering one question — the class C2
/// exists to end, and the reason `ClipsUnplacedFilter` had to defend against
/// Core Data faults invalidated between a debounced fetch and a render.
///
/// The property that makes one source safe is a partition: every loose item is
/// drawn by exactly one of the two surfaces. **Never both** (a photo rendering
/// twice — the July 11 media-agnostic lock) and **never neither** (a clip
/// vanishing from the bench, which is F44's set-aside defect in a new place).
///
/// Contract tests (ADR-050): written with the accessor, green on first run, so
/// mutation-verified rather than red-first.
struct BenchStackPartitionTests {

    private func item(_ kind: BenchClipItem.Kind, at seconds: TimeInterval) -> BenchClipItem {
        BenchClipItem(
            id: UUID(),
            kind: kind,
            capturedAt: Date(timeIntervalSinceReferenceDate: seconds),
            rollGroupId: nil
        )
    }

    private func bench(_ items: [BenchClipItem]) -> RenderedBench {
        RenderedBench.compose(
            allItems: items,
            reviewedIds: [],
            hideReviewed: false,
            now: Date(timeIntervalSinceReferenceDate: 100_000),
            inFlightIds: [],
            reviewedAt: { _ in nil },
            soloIds: []
        )
    }

    @Test
    func everyLooseItemIsDrawnByExactlyOneSurface() {
        // A voice sitting with a photo folded in, and a photo far away that
        // groups alone — the two cases the split exists to separate.
        let voice = item(.voice, at: 0)
        let absorbed = item(.image, at: 60)
        let lonelyPhoto = item(.image, at: 50_000)

        let composed = bench([voice, absorbed, lonelyPhoto])
        let drawn = DrawnBench.from(composed, proposals: [])

        // **The CARD REGION, not `drawn.items`.** `drawn.items` used to mean
        // "what the session-card block draws" and was a fair proxy for it;
        // since the count fix (2026-08-19) it means "every item in every
        // region, including the stack", so using it here would compare the
        // stack against a set that now contains the stack. The invariant is
        // unchanged — an item is drawn by exactly one SURFACE — and it is now
        // expressed against the surfaces themselves.
        let drawnIds = Set(
            (drawn.loose.flatMap(\.items) + drawn.clusteredSessions.flatMap(\.items)).map(\.id)
        )
        let stackIds = Set(composed.siblingStackSessions.flatMap(\.items).map(\.id))
        let looseIds = Set(composed.loose.flatMap(\.items).map(\.id))

        // The stack the value reports and the stack the view is fed must be
        // the same stack — the two-stores-answering-one-question class C2
        // exists to end.
        #expect(
            Set(drawn.siblingStack.flatMap(\.items).map(\.id)) == stackIds,
            "DrawnBench.siblingStack diverged from RenderedBench.siblingStackSessions"
        )

        #expect(!looseIds.isEmpty, "self-test: the fixture must produce loose items, or this asserts nothing")
        #expect(
            drawnIds.intersection(stackIds).isEmpty,
            "An item drawn by the bench must not also be drawn by the stack — that is the photo-renders-twice defect the July 11 lock closed"
        )
        #expect(
            looseIds == drawnIds.union(stackIds),
            "Every loose item must be drawn by one surface or the other — an item in neither has vanished from the bench"
        )
        #expect(stackIds.contains(lonelyPhoto.id), "a photo grouping into no voice sitting belongs to the stack")
        #expect(drawnIds.contains(absorbed.id), "a photo inside a voice sitting is drawn by the bench")
    }

    /// The stack's set must be exactly "sessions with no voice" — not "all
    /// media", which would double-draw the absorbed photo.
    @Test
    func theStackTakesOnlyVoicelessSessions() {
        let composed = bench([item(.voice, at: 0), item(.image, at: 60), item(.note, at: 50_000)])
        for session in composed.siblingStackSessions {
            #expect(!session.hasVoice, "a session with voice belongs to the bench, not the sibling stack")
        }
    }

    /// **F35(b)'s promise, now structural.** A voice clip must never render in
    /// both the session cards and the sibling stack. That used to be a
    /// predicate on a second fetch (`loadUnplaced`, `mediaType != voice`),
    /// guarded by a source scan; the fetch is gone, and the stack takes only
    /// sessions where `!hasVoice`, so no voice item can reach it.
    ///
    /// Asserted on the items rather than on the sessions, because "no session
    /// has voice" and "no ITEM is voice" are the same statement only while
    /// `hasVoice` is defined as it is — and the promise is about the item.
    @Test
    func noVoiceItemReachesTheSiblingStack() {
        let composed = bench([
            item(.voice, at: 0),
            item(.image, at: 60),
            item(.voice, at: 50_000),
            item(.note, at: 90_000),
        ])
        let stackItems = composed.siblingStackSessions.flatMap(\.items)

        #expect(!stackItems.isEmpty, "self-test: the fixture must give the stack something to draw")
        #expect(
            stackItems.allSatisfy { $0.kind != .voice },
            "A voice clip reaching the sibling stack renders it twice — once as a session card, once here. That is F35(b)."
        )
    }
}

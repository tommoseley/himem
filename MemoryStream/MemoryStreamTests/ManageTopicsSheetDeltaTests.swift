import Testing
import Foundation
@testable import HiMem

/// Money tests for `ManageTopicsSheet.computeDelta(initial:selected:)`
/// — the pure set-diff the manage sheet runs before writing to Core
/// Data. The delta drives `entry.addToTopics(...)` and
/// `entry.removeFromTopics(...)`; getting it wrong silently
/// duplicates or drops user topics, so a money test on the pure
/// function is cheap insurance.
@Suite
struct ManageTopicsSheetDeltaTests {

    @Test func noChanges_emptyDelta() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: ["Garden", "Work"],
            selected: ["Garden", "Work"]
        )
        #expect(delta.toAdd.isEmpty)
        #expect(delta.toRemove.isEmpty)
    }

    @Test func addingOne_landsInToAdd_nothingInToRemove() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: ["Garden"],
            selected: ["Garden", "Travel"]
        )
        #expect(delta.toAdd == ["Travel"])
        #expect(delta.toRemove.isEmpty)
    }

    @Test func removingOne_landsInToRemove_nothingInToAdd() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: ["Garden", "Travel"],
            selected: ["Garden"]
        )
        #expect(delta.toAdd.isEmpty)
        #expect(delta.toRemove == ["Travel"])
    }

    @Test func swapOne_landsBothSides() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: ["Garden", "Travel"],
            selected: ["Garden", "Family"]
        )
        #expect(delta.toAdd == ["Family"])
        #expect(delta.toRemove == ["Travel"])
    }

    @Test func freshMemoryFirstSelection_allInToAdd() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: [],
            selected: ["Garden", "Travel"]
        )
        #expect(delta.toAdd == ["Garden", "Travel"])
        #expect(delta.toRemove.isEmpty)
    }

    @Test func clearingAll_allInToRemove() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: ["Garden", "Travel"],
            selected: []
        )
        #expect(delta.toAdd.isEmpty)
        #expect(delta.toRemove == ["Garden", "Travel"])
    }

    @Test func emptyBothSides_emptyDelta() {
        let delta = ManageTopicsSheet.computeDelta(initial: [], selected: [])
        #expect(delta.toAdd.isEmpty)
        #expect(delta.toRemove.isEmpty)
    }

    /// The delta is case-sensitive — palette canonicalization happens
    /// upstream (model output passes through `TopicPalette.partition`;
    /// "Add a new topic" field snaps to existing case). A case-only
    /// disagreement in `initial` vs `selected` would already mean a
    /// palette consistency bug elsewhere, and this test pins the
    /// contract so accidentally folding the case here would surface.
    @Test func caseSensitive_byDesign() {
        let delta = ManageTopicsSheet.computeDelta(
            initial: ["Garden"],
            selected: ["garden"]
        )
        // Both add and remove fire — this is the "treat as different"
        // behavior the contract requires. Catching case drift upstream
        // is the palette layer's job.
        #expect(delta.toAdd == ["garden"])
        #expect(delta.toRemove == ["Garden"])
    }
}

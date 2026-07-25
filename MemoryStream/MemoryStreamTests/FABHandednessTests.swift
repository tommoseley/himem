import Testing
import SwiftUI
@testable import HiMem

/// Money tests for the Left-Handed FAB bug (2026-07-24): the Settings toggle
/// wrote `fabHandednessLeft`, the FAB's *internal* layout honored it, but every
/// FAB *container* hardcoded `.bottomTrailing` — so the closed FAB stayed right
/// on every surface regardless of the preference. `FABHandedness` is the single
/// resolver both the containers and the internals now route through; these
/// assert flipping the preference flips the resolved layout on every axis.
struct FABHandednessTests {

    @Test func containerAlignment_followsPreference() {
        // The bug: this returned `.bottomTrailing` for both inputs.
        #expect(FABHandedness.containerAlignment(leftHanded: false) == .bottomTrailing)
        #expect(FABHandedness.containerAlignment(leftHanded: true) == .bottomLeading)
    }

    @Test func horizontalEdge_followsPreference() {
        #expect(FABHandedness.horizontalEdge(leftHanded: false) == .trailing)
        #expect(FABHandedness.horizontalEdge(leftHanded: true) == .leading)
    }

    @Test func paddingEdge_followsPreference() {
        #expect(FABHandedness.paddingEdge(leftHanded: false) == .trailing)
        #expect(FABHandedness.paddingEdge(leftHanded: true) == .leading)
    }

    /// The storage key is a cross-surface contract: Settings writes it, every
    /// FAB reads it. A rename that touched only one side would silently sever
    /// the toggle from the layout.
    @Test func storageKey_isStable() {
        #expect(FABHandedness.storageKey == "fabHandednessLeft")
    }
}

import Testing
import Foundation
@testable import HiMem

/// Money tests for the P7-4 general Clips-tab multi-select model
/// (`ClipsSelection`, July 2026). The model is clip-level; a session /
/// burst is a derived batch, Select-all spans merged sources, and
/// drag-to-select paints a run across registered row frames.
@MainActor
@Suite
struct ClipsSelectionTests {

    /// Selecting a session card batch-selects all its clip ids in one act;
    /// re-toggling clears the whole batch (session-level checkbox).
    @Test func toggleAll_sessionBatch_selectsThenClears() {
        let s = ClipsSelection()
        let a = UUID(), b = UUID(), other = UUID()
        s.toggleAll([a, b])
        #expect(s.isChecked(all: [a, b]))
        #expect(!s.selectedIds.contains(other))
        s.toggleAll([a, b])
        #expect(s.selectedIds.isEmpty)
    }

    /// A session reads "checked" only when EVERY clip is selected — so a
    /// partially-selected session card shows unchecked, and an empty set
    /// is never checked.
    @Test func isChecked_all_requiresEvery() {
        let s = ClipsSelection()
        let a = UUID(), b = UUID()
        s.set(a, selected: true)
        #expect(!s.isChecked(all: [a, b]))
        s.set(b, selected: true)
        #expect(s.isChecked(all: [a, b]))
        #expect(!s.isChecked(all: []))
    }

    /// Select-all spans the merged visible registry — New contributes two
    /// sources ("sessions" + "unplaced"); overlaps de-dup; resetVisible
    /// (filter switch) clears it so no stale id leaks into the next filter.
    @Test func registerVisible_mergesSources_selectAll() {
        let s = ClipsSelection()
        let a = UUID(), b = UUID(), c = UUID()
        s.registerVisible([a, b], source: "sessions")
        s.registerVisible([b, c], source: "unplaced")
        #expect(Set(s.visibleIds) == Set([a, b, c]))
        s.selectAll()
        #expect(s.selectedIds == Set([a, b, c]))
        s.resetVisible()
        #expect(s.visibleIds.isEmpty)
    }

    /// Drag-to-select: a drag beginning on a row paints that row's toggled
    /// state, then paints the same state across every row the finger passes.
    @Test func dragChanged_paintsRunAcrossRows() {
        let s = ClipsSelection()
        let a = UUID(), b = UUID(), c = UUID()
        s.enter()
        s.rowFrames = [
            ClipRowFrame(ids: [a], minY: 0,   maxY: 50),
            ClipRowFrame(ids: [b], minY: 50,  maxY: 100),
            ClipRowFrame(ids: [c], minY: 100, maxY: 150),
        ]
        s.dragChanged(to: 25)          // begins on row a (off → on)
        #expect(s.selectedIds.contains(a))
        s.dragChanged(to: 120)         // sweeps through b into c
        #expect(s.isChecked(all: [a, b, c]))
        s.dragEnded()
        // A fresh drag beginning on an already-selected row paints OFF.
        s.dragChanged(to: 25)
        s.dragEnded()
        #expect(!s.selectedIds.contains(a))
    }

    /// Cancel / filter-switch leaves the mode AND drops the selection.
    @Test func exit_dropsSelectionAndMode() {
        let s = ClipsSelection()
        s.enter()
        s.set(UUID(), selected: true)
        s.exit()
        #expect(!s.selecting)
        #expect(s.selectedIds.isEmpty)
    }
}

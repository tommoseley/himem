import Testing
import Foundation
import CoreGraphics
@testable import HiMem

/// P7-4 · drag-to-select must paint a contiguous run from the anchor in EITHER
/// direction — drag up selects the run above, drag down the run below. The
/// gesture-vs-scroll arbitration (the device bug, fixed with a high-priority
/// gesture) isn't unit-testable, but the paint math is: seed row frames, drive
/// `dragChanged`, assert the run. This is the regression guard that a future
/// change can't quietly make the paint one-directional again.
@MainActor
struct ClipsDragSelectTests {

    /// Five rows stacked top→bottom, 10pt tall each: a(0–10) … e(40–50).
    private func fiveRowSelection() -> (ClipsSelection, [UUID]) {
        let ids = (0..<5).map { _ in UUID() }
        let s = ClipsSelection()
        s.enter()  // selecting = true
        s.rowFrames = ids.enumerated().map { i, id in
            ClipRowFrame(ids: [id], minY: CGFloat(i) * 10, maxY: CGFloat(i) * 10 + 10)
        }
        return (s, ids)
    }

    @Test func dragUpFromMidAnchorSelectsTheRun() {
        let (s, ids) = fiveRowSelection()   // ids[0]=a … ids[4]=e
        s.dragChanged(to: 25)               // anchor on c (20–30) → paint = select
        s.dragChanged(to: 15)               // cross b
        s.dragChanged(to: 5)                // cross a
        s.dragEnded()
        #expect(s.selectedIds == Set([ids[0], ids[1], ids[2]]),
                "dragging up paints the contiguous run c→a")
    }

    @Test func dragDownFromMidAnchorSelectsTheRun() {
        let (s, ids) = fiveRowSelection()
        s.dragChanged(to: 25)               // anchor on c
        s.dragChanged(to: 35)               // cross d
        s.dragChanged(to: 45)               // cross e
        s.dragEnded()
        #expect(s.selectedIds == Set([ids[2], ids[3], ids[4]]),
                "dragging down paints the contiguous run c→e")
    }

    /// The anchor row sets the paint state to the opposite of its current
    /// state — so a drag that starts on an already-selected row de-selects the
    /// run.
    @Test func anchorOnSelectedRowPaintsDeselect() {
        let (s, ids) = fiveRowSelection()
        s.set(ids[2], selected: true)       // c already selected
        s.set(ids[3], selected: true)       // d already selected
        s.dragChanged(to: 25)               // anchor on c → paint = DEselect
        s.dragChanged(to: 35)               // cross d
        s.dragEnded()
        #expect(!s.selectedIds.contains(ids[2]) && !s.selectedIds.contains(ids[3]),
                "dragging from a selected row clears the run")
    }
}

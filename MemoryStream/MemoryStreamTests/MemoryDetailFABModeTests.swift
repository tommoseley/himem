import Testing
import Foundation
@testable import HiMem

/// **The paperclip was unreachable on exactly the memories that need it.**
///
/// Found on device, 2026-09-17 (Tom, device-pass check 5): a memory created
/// seconds earlier had no paperclip — no `+` at all. Root cause was not a
/// missing affordance. `AddExistingClipsSheet` is presented from
/// `EntryExpandedView`, its `leadingAction` exists, and the flag that opens it
/// is wired. Two gates stacked:
///
/// 1. the paperclip lives inside the FAB's **expanded** stack, so it is never
///    visible at rest — only after tapping `+`; and
/// 2. the whole FAB was removed whenever `organizeOnScreen` was true (F33,
///    which suppressed it so the 60pt button would stop covering the Organize
///    card). A **new** memory is short, so that card is on screen at rest.
///
/// So on a fresh memory there was no `+` to tap, therefore no stack to open,
/// therefore no paperclip.
///
/// **F33's rule was right when written and became wrong when the paperclip
/// became load-bearing.** After the vocabulary retirement it is the only route
/// by which a photo or video enters a memory (a recording transcribes on
/// arrival and becomes a memory of its own — §1). Ruled (Tom, 2026-09-17): the
/// Organize card **demotes** the FAB to the paperclip alone rather than hiding
/// it.
@Suite struct MemoryDetailFABModeTests {

    private func mode(
        editing: Bool = false,
        organize: Bool = false,
        letGo: Bool = false,
        topAnchor: Bool = false
    ) -> MemoryDetailFAB.Mode {
        MemoryDetailFAB.mode(
            isEditing: editing,
            organizeOnScreen: organize,
            letGoOnScreen: letGo,
            topAnchorVisible: topAnchor
        )
    }

    // MARK: - The defect

    /// **THE MONEY TEST.** This returned `.hidden` — the shipped defect.
    @Test("the Organize card demotes the FAB, it does not hide it")
    func organizeCardLeavesThePaperclipReachable() {
        #expect(mode(organize: true) == .paperclipOnly,
                "a new memory shows the Organize card at rest; hiding the FAB here removes the only way to add an existing part")
    }

    /// The state she is actually in after a capture: brand-new memory, card on
    /// screen, top anchor visible because the memory is short.
    @Test("a freshly-created memory can still reach the paperclip")
    func freshMemoryCanReachThePaperclip() {
        #expect(mode(organize: true, topAnchor: true) == .paperclipOnly)
    }

    // MARK: - What must not regress

    /// F33's actual concern: the capture stack must stop covering the card.
    /// Demoting satisfies it — `.paperclipOnly` is not `.full`.
    @Test("the capture stack still steps aside for the Organize card")
    func captureStackStillStepsAside() {
        #expect(mode(organize: true) != .full)
    }

    /// The FAB must never sit over the caret line — this outranks everything.
    @Test("an active edit hides it outright, whatever else is true")
    func editingWinsOutright() {
        #expect(mode(editing: true) == .hidden)
        #expect(mode(editing: true, organize: true) == .hidden)
        #expect(mode(editing: true, letGo: true) == .hidden)
        #expect(mode(editing: true, organize: true, letGo: true, topAnchor: true) == .hidden)
    }

    /// Let Go owns the full width, but only once she has scrolled to it —
    /// `topAnchorVisible` is what distinguishes "scrolled to the footer" from
    /// "short memory showing everything at once".
    @Test("the Let Go footer hides it only after a deliberate scroll")
    func letGoNeedsTheScroll() {
        #expect(mode(letGo: true, topAnchor: false) == .hidden, "scrolled to the destructive footer")
        #expect(mode(letGo: true, topAnchor: true) == .full,
                "a short memory showing both is not a scroll — the FAB stays")
    }

    /// Editing outranks Let Go, and Let Go outranks the Organize demotion.
    /// Pinned because the precedence is the rule, not an implementation detail.
    @Test("precedence holds when the gates collide")
    func precedenceIsOrdered() {
        #expect(mode(organize: true, letGo: true, topAnchor: false) == .hidden,
                "the destructive footer outranks the demotion")
        #expect(mode(organize: true, letGo: true, topAnchor: true) == .paperclipOnly,
                "an unscrolled Let Go does not hide; the card still demotes")
    }

    // MARK: - The ordinary case

    @Test("nothing in the way shows the whole FAB")
    func defaultIsFull() {
        #expect(mode() == .full)
        #expect(mode(topAnchor: true) == .full)
    }
}

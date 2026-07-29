import Testing
@testable import HiMem

/// Copy guards for `BottomDeleteButton.Kind` — the label tells the
/// truth about what's destroyed (July 13 lock) and the projects
/// footnote reassures that member memories survive (A1, 2026-07-17).
@Suite
struct BottomDeleteButtonKindTests {

    @Test func projectDelete_isTitleCased_andFootnoteReassuresMemoriesSurvive() {
        let kind = BottomDeleteButton.Kind.delete(noun: "project")
        #expect(kind.label == "Delete Project", "spec §Deleting wants title-case")
        #expect(kind.footnote.contains("The memories stay in your library"),
                "deleting the container never deletes the memories — say so")
    }

    @Test func memoryAndClipLabels_areLiteralNotMetaphor() {
        // The memory label is the literal "Delete this Memory" — the old "Let Go"
        // metaphor read as ambiguity about whether the memory survives, exactly
        // when certainty is owed (locked Voice principle, 2026-07-28). The
        // footnote carries the nuance (the clips stay).
        #expect(BottomDeleteButton.Kind.delete(noun: "memory").label == "Delete this Memory")
        #expect(BottomDeleteButton.Kind.delete(noun: "clip").label == "Delete this Clip")
        #expect(BottomDeleteButton.Kind.delete(noun: "memory").footnote.contains("The parts stay"),
                "the delete-moment disclosure uses the user-facing noun 'parts' (F7g)")
        // No metaphor survives on the destructive label.
        #expect(!BottomDeleteButton.Kind.delete(noun: "memory").label.contains("Let Go"))
    }

    @Test func removeFromProject_namesTheProject() {
        #expect(BottomDeleteButton.Kind.removeFromProject(name: "Kingfisher").label == "Remove from Kingfisher")
        // Falls back gracefully when the name is missing.
        #expect(BottomDeleteButton.Kind.removeFromProject(name: nil).label == "Remove from Project")
    }
}

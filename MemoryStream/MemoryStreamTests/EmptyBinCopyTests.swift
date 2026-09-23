import Testing
import Foundation
@testable import HiMem

/// **What emptying Recently Deleted says it will do** — ruled by Tom
/// 2026-09-23, after *Delete All Forever* destroyed 184 recordings on the 22nd
/// while the sheet read only *"N items will be permanently deleted."*
///
/// That sentence failed in three ways at once: a **lumped count** across four
/// different kinds of thing, the **passive voice** ("will be deleted" — by
/// whom?), and **no statement of what survives**. It is the Let Go rule
/// unapplied: when a label names something precious it must leave zero doubt
/// about what lives through the action.
@Suite struct EmptyBinCopyTests {

    // MARK: - The ruled sentence

    @Test("the ruled shape, exactly")
    func theRuledSentence() {
        #expect(RecycleBinView.emptyBinMessage(memories: 12, projects: 0, parts: 0, spared: 3)
                == "Permanently delete 12 memories. Photos and recordings used in other memories stay where they are.")
    }

    /// **The verb states the change and uses no metaphor.** Not "empty", not
    /// "clear", not "clean up" — she is destroying things, and the sheet says
    /// so in the active voice.
    @Test("the copy never softens what it does")
    func noMetaphor() {
        for (m, p, c, s) in [(12, 0, 0, 3), (1, 1, 1, 0), (0, 4, 0, 0), (7, 0, 2, 1)] {
            let msg = RecycleBinView.emptyBinMessage(memories: m, projects: p, parts: c, spared: s)
            #expect(msg.hasPrefix("Permanently delete "), "not an active statement of the change: \(msg)")
            let lower = msg.lowercased()
            for soft in ["empty", "clear out", "clean up", "tidy", "remove all", "will be deleted"] {
                #expect(!lower.contains(soft), "softened or passive: \(msg)")
            }
        }
    }

    // MARK: - The second sentence is conditional, and that is the point

    /// **"0 are shared" is noise that teaches her to skip the sentence on the
    /// day it matters.** When nothing is shared the promise is dropped, not
    /// zeroed.
    @Test("nothing shared drops the second sentence rather than zeroing it")
    func noSpareNoSentence() {
        let msg = RecycleBinView.emptyBinMessage(memories: 12, projects: 0, parts: 0, spared: 0)
        #expect(msg == "Permanently delete 12 memories.")
        #expect(!msg.contains("stay where they are"))
        #expect(!msg.contains("0"))
    }

    @Test("anything shared states the spare")
    func aSpareIsStated() {
        for spared in [1, 2, 99] {
            let msg = RecycleBinView.emptyBinMessage(memories: 3, projects: 0, parts: 0, spared: spared)
            #expect(msg.contains("Photos and recordings used in other memories stay where they are."),
                    "spared=\(spared): the promise the guard enforces must be stated")
        }
    }

    /// **The spare is never quantified.** Only the count of things being
    /// destroyed is a number; the survivors are a fact about behaviour, and a
    /// second number invites arithmetic at the worst possible moment.
    @Test("only the destroyed count is a number")
    func theSpareIsNotCounted() {
        let msg = RecycleBinView.emptyBinMessage(memories: 12, projects: 0, parts: 0, spared: 7)
        #expect(msg.filter(\.isNumber) == "12", "a second number appeared: \(msg)")
    }

    // MARK: - Counts

    @Test("singulars are not pluralised")
    func singulars() {
        #expect(RecycleBinView.emptyBinMessage(memories: 1, projects: 0, parts: 0, spared: 0)
                == "Permanently delete 1 memory.")
        #expect(RecycleBinView.emptyBinMessage(memories: 0, projects: 1, parts: 0, spared: 0)
                == "Permanently delete 1 project.")
        #expect(RecycleBinView.emptyBinMessage(memories: 0, projects: 0, parts: 1, spared: 0)
                == "Permanently delete 1 part.")
    }

    /// The bin holds four kinds of thing and the sheet destroys all of them,
    /// so a message naming only memories would be false whenever a project is
    /// in there too. Absent kinds are omitted rather than reported as zero.
    @Test("every kind present is named, and absent kinds are omitted")
    func mixedContents() {
        #expect(RecycleBinView.emptyBinMessage(memories: 12, projects: 2, parts: 0, spared: 0)
                == "Permanently delete 12 memories and 2 projects.")
        #expect(RecycleBinView.emptyBinMessage(memories: 12, projects: 2, parts: 5, spared: 0)
                == "Permanently delete 12 memories, 2 projects, and 5 parts.")
        #expect(!RecycleBinView.emptyBinMessage(memories: 12, projects: 0, parts: 3, spared: 0)
                    .contains("project"))
    }

    @Test("an empty bin says so rather than claiming a deletion")
    func emptyBin() {
        #expect(RecycleBinView.emptyBinMessage(memories: 0, projects: 0, parts: 0, spared: 0)
                == "There is nothing in Recently Deleted.")
    }
}

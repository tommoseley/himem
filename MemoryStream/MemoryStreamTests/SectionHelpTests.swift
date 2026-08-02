import Testing
import Foundation
@testable import HiMem

/// F7c · the per-section help must hold the locked three-clause shape for every
/// topic: what it is → what you can do → **where it's maintained**. The third
/// clause is load-bearing (the part nothing else in the app says), so a topic
/// missing it is a defect, not a stylistic gap. Copy itself is F7e-drafted for
/// cold validation; these tests pin structure, not wording.
struct SectionHelpTests {

    @Test func everyTopicHasAllThreeClauses() {
        for topic in HelpTopic.allCases {
            #expect(!topic.title.isEmpty, "\(topic) has a title")
            #expect(!topic.whatItIs.isEmpty, "\(topic) has a 'what it is' clause")
            #expect(!topic.whatYouCanDo.isEmpty, "\(topic) has a 'what you can do' clause")
            #expect(!topic.whereItsMaintained.isEmpty,
                    "\(topic) has a 'where it's maintained' clause — the load-bearing one")
        }
    }

    /// All six sections Tom named are covered.
    @Test func coversEverySection() {
        let ids = Set(HelpTopic.allCases.map(\.id))
        for expected in ["memoryTopics", "memoryProjects", "memoryMentions",
                         "memoryClip", "memoryOrganize", "editClip",
                         "projectGoal", "projectMemories", "projectFindThread"] {
            #expect(ids.contains(expected), "missing help topic: \(expected)")
        }
    }

    @Test func findThreadIsHonestAboutWhatItReads() {
        // The AI action must name that it never reads the raw transcripts, and
        // that nothing auto-adds — the honest beats that make the panel worth it.
        #expect(HelpTopic.projectFindThread.whereItsMaintained.contains("never the raw transcripts"))
        #expect(HelpTopic.projectFindThread.whatYouCanDo.contains("Nothing auto-adds"))
        #expect(HelpTopic.projectFindThread.clause3Label == "HOW IT RUNS", "an AI action runs, it doesn't 'live' somewhere")
    }

    /// Ontology stays accurate where it's easy to regress: a clip is stored once
    /// and shared — the clip/edit topics must carry that, since it's the fact
    /// that makes "delete removes it everywhere" honest.
    @Test func clipTopicsStateTheSharedAtomModel() {
        #expect(HelpTopic.memoryClip.whereItsMaintained.lowercased().contains("stored once"))
        #expect(HelpTopic.editClip.whereItsMaintained.lowercased().contains("stored once"))
    }
}

/// D4 · the single section-`?` coachmark: fires once, only after the
/// walkthrough, never during it; "Show me around" re-arms it. `.serialized` —
/// both are UserDefaults-backed shared singletons.
@MainActor
@Suite(.serialized)
struct SectionHelpCoachmarkTests {
    private var c: OneShotCoachmark { .sectionHelp }
    private var w: WalkthroughOrchestrator { .shared }

    private func reset() {
        UserDefaults.standard.removeObject(forKey: "himem.sectionHelpCoachmark.seen")
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
        c.visible = false
        w.activeBeat = nil
    }

    @Test func neverFiresWhileTheWalkthroughRuns() {
        reset()
        w.start()                       // isRunning = true, not completed
        c.armIfEligible()
        #expect(c.visible == false, "the walkthrough is teaching; the coachmark stands down")
        reset()
    }

    @Test func firesOnceAfterTheWalkthrough() {
        reset()
        w.skip()                        // completed + not running
        c.armIfEligible()
        #expect(c.visible == true, "first Memory Detail arrival post-walkthrough")
        c.dismiss()
        c.armIfEligible()
        #expect(c.visible == false, "seen — never fires twice")
        reset()
    }

    @Test func showMeAroundRearmsIt() {
        reset()
        w.skip()
        c.armIfEligible(); c.dismiss()
        #expect(c.hasSeen)
        c.rearm()                       // "? → Show me around"
        #expect(!c.hasSeen)
        c.armIfEligible()
        #expect(c.visible == true, "re-teaches alongside the relaunched walkthrough")
        reset()
    }

    /// The Projects coachmark is independent of the walkthrough (it teaches a
    /// concept the walkthrough doesn't) — it fires on first Projects arrival
    /// whether or not the walkthrough was done, but still stands down while it's
    /// running.
    @Test func projectsCoachmarkIsWalkthroughIndependent() {
        let p = OneShotCoachmark.projectsConcept
        UserDefaults.standard.removeObject(forKey: "himem.projectsCoachmark.seen")
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
        p.visible = false; w.activeBeat = nil

        w.start()                       // walkthrough running
        p.armIfEligible()
        #expect(p.visible == false, "stands down while the walkthrough runs")

        w.activeBeat = nil              // not running, and NOT completed
        p.armIfEligible()
        #expect(p.visible == true, "fires on first Projects arrival, walkthrough done or not")

        p.dismiss()
        UserDefaults.standard.removeObject(forKey: "himem.projectsCoachmark.seen")
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
    }
}

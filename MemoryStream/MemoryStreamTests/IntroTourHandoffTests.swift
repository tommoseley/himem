import Testing
import Foundation
@testable import HiMem

/// The seam between the intro tour and the F8 walkthrough — **the two defects
/// found on device, 2026-08-23**.
///
/// Both were invisible to the existing suites because **each piece was correct
/// in isolation.** `startAtFirstBeat()` sets `.record`. `offerIfFirstRun()`
/// arms `.offer` on a first run. Neither is wrong on its own; the defect is
/// entirely in WHEN the caller reaches them relative to the tour, which is why
/// these assert the ordering rather than the primitives.
@MainActor
@Suite(.serialized)
struct IntroTourHandoffTests {

    private var o: WalkthroughOrchestrator { .shared }

    private func reset() {
        o.skip()
        UserDefaults.standard.removeObject(forKey: "himem.walkthrough.completed")
        UserDefaults.standard.removeObject(forKey: "himem.introTour.hasSeen")
        o.activeBeat = nil
    }

    /// **THE DOUBLE OFFER.** Page 7's primary must land on beat 1 even when
    /// `.offer` is already armed.
    ///
    /// On device the tab shell mounts BEHIND the tour and its `.onAppear` armed
    /// `.offer` while the tour was still on screen — at which point
    /// `IntroTourStore.hasSeen` is false, so the suppression guard passed. Page
    /// 7 then called `startAtFirstBeat()`, which was guarded on
    /// `activeBeat == nil` and silently no-opped, and dismissing the tour
    /// revealed the offer card underneath: *"Walk through it together?"*, the
    /// question she had just answered by tapping the button.
    @Test func page7_landsOnBeatOne_evenWhenOfferIsAlreadyArmed() {
        reset()
        o.start()                                   // the state the tab shell left behind
        #expect(o.activeBeat == .offer)

        o.startAtFirstBeat()

        #expect(o.activeBeat == .record,
                "Page 7 must enter the walkthrough at beat 1. Landing on .offer asks her the question she just answered.")
        reset()
    }

    /// The walkthrough must still be relaunchable from "Show me around", which
    /// is `.offer`'s remaining honest use — so retiring the first-run offer
    /// must not retire the beat.
    @Test func showMeAround_stillArmsTheOfferBeat() {
        reset()
        o.start()
        #expect(o.activeBeat == .offer)
        reset()
    }

    /// **THE CALLER, NOT THE OWNER.** `offerIfFirstRun()` must have no call
    /// sites: under the tour ruling it can never legitimately fire — if the
    /// tour is unseen it is about to invite her, and if it has been seen the
    /// offer is suppressed. A source-level assertion because the defect is the
    /// EXISTENCE of a call, which no runtime test can observe.
    @Test func offerIfFirstRun_hasNoCallSites() throws {
        let root = try Self.appSourceRoot()
        var sites: [String] = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var scanned = 0
        for case let url as URL in walker! where url.pathExtension == "swift" {
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (i, line) in src.components(separatedBy: "\n").enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.contains("offerIfFirstRun"), !t.hasPrefix("//"), !t.hasPrefix("///") else { continue }
                guard !t.contains("func offerIfFirstRun") else { continue }
                sites.append("\(url.lastPathComponent):\(i + 1)")
            }
        }
        // The walk must not pass by matching nothing.
        #expect(scanned > 50, "source walk reached \(scanned) files — it is not scanning the app")
        #expect(sites.isEmpty,
                """
                `offerIfFirstRun` is still called: \(sites.joined(separator: ", ")).
                The intro tour is the invitation now. A first-run offer either duplicates \
                page 7's question or fires while the tour is still on screen.
                """)
    }

    static func appSourceRoot() throws -> URL {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectRoot.appendingPathComponent("MemoryStream")
    }
}

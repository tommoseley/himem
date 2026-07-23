import Testing
import Foundation
@testable import HiMem

/// **Calibration harness** for the on-device (Foundation Models) organize
/// prompt — companion to `docs/design/AI Organize · QA calibration set.md`
/// and `AI Organize · spec.md §11` + the July 18 cadence rule.
///
/// This is NOT a deterministic unit test — it runs the on-device LLM,
/// whose output varies run to run and which only exists on a capable
/// device (iPhone 15 Pro+/iOS 26 with Apple Intelligence). Per CLAUDE.md
/// the standing test suite must stay deterministic, so this harness is
/// **gated off by default** and only runs when the env flag is set:
///
///     TEST_RUNNER_RUN_ODO_CALIBRATION=1 xcodebuild test \
///       -only-testing:MemoryStreamTests/OnDeviceOrganizerCalibrationTests \
///       -destination 'platform=iOS,id=<device>'
///
/// (xcodebuild forwards `TEST_RUNNER_*` env vars to the test process with
/// the prefix stripped.) In a normal sim/CI run the flag is absent and
/// the harness is skipped.
///
/// It feeds each fixture's clips through the real prompt, applies the
/// **mechanical** rubric checks it can decide deterministically (POV,
/// length ceiling, banned anti-target phrases, cadence heuristic,
/// topic/mention reuse), and prints every output + a `[GRID]` line so the
/// **judgment** items (recognizable-in-6-months, descriptive-not-
/// interpretive) can be graded by reading. The mechanical anti-target
/// checks hard-fail — those are the failures we've actually seen.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUN_ODO_CALIBRATION"] != nil))
struct OnDeviceOrganizerCalibrationTests {

    // MARK: - Fixture model

    struct Fixture {
        let n: Int
        let name: String
        let clips: String
        let existingTopics: [String]
        let existingMentions: [String]
        /// Substrings that MUST NOT appear (case-insensitive) — the
        /// specific fluff/interpretation/fabrication each anti-target hit.
        let bannedPhrases: [String]
        /// Topic/mention names from the palette the output SHOULD reuse
        /// (at least one), proving palette discipline.
        let expectReuseTopics: [String]
        let expectReuseMentions: [String]
        /// Soft word-count ceiling for the summary (proportional length).
        let summaryWordCeiling: Int
        /// Owner POV: `.secondPerson` expects "you"; `.subjectOut`
        /// (pure-observation) expects NO "you".
        let pov: POV

        enum POV { case secondPerson, subjectOut }
    }

    private static let library = ["Gardening", "Retirement", "Cooking", "Onboarding", "Product", "Travel", "Health"]
    private static let people = ["Darlene", "Ben", "Mom", "Sarah"]

    static let fixtures: [Fixture] = [
        Fixture(
            n: 1, name: "Gardening — cadence exemplar",
            clips: "Out in the garden this morning before it got too hot. The peppers are doing well, tomatoes need more water than I expected in this humidity, and the eggplants are finally coming in. It's strange — since I retired I'm out here at seven instead of after work, and the whole rhythm of the day is different. South Carolina summer is brutal on everything by noon.",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["reflections", "challenges and reflections"],
            expectReuseTopics: ["Gardening", "Retirement"], expectReuseMentions: [],
            summaryWordCeiling: 55, pov: .secondPerson
        ),
        Fixture(
            n: 2, name: "Thin clip — length floor",
            clips: "Mmmm, pears.",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["savoring", "simple pleasures", "sensory", "reflecting"],
            expectReuseTopics: [], expectReuseMentions: [],
            summaryWordCeiling: 14, pov: .secondPerson
        ),
        Fixture(
            n: 3, name: "Multi-person mixed media — POV/pronouns",
            clips: "[audio] Walked the market with Darlene. She wanted to find the Basque cheesecake place Ben kept talking about — we did, finally, and it lived up to it.\n[photo] (no description)",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["bonding", "joy of the hunt", "explored the market"],
            expectReuseTopics: [], expectReuseMentions: ["Darlene", "Ben"],
            summaryWordCeiling: 55, pov: .secondPerson
        ),
        Fixture(
            n: 4, name: "Idea capture — no fabricated nextSteps",
            clips: "Thinking about the onboarding — the problem isn't the permissions screens, it's that we throw people into an empty app. Maybe the coach marks should fire on first real use, not up front. Also we still haven't decided the free project cap.",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["next step", "next steps", "reflecting on onboarding challenges"],
            expectReuseTopics: ["Onboarding", "Product"], expectReuseMentions: [],
            summaryWordCeiling: 60, pov: .secondPerson
        ),
        Fixture(
            n: 5, name: "Pure-observation — subject-out",
            clips: "[photo] description: Sunset over the ridge behind the house, sky went deep orange.\n[no audio]",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["breathtaking", "peaceful", "appreciate", "beauty of the evening"],
            expectReuseTopics: [], expectReuseMentions: [],
            summaryWordCeiling: 18, pov: .subjectOut
        ),
        // Example-bleed regression (2026-07-23): a quote + photo memory that
        // shares NOTHING with the (former) concrete cadence example. The
        // prior prompt bled "peppers, tomatoes, and eggplants … garden …
        // retirement … South Carolina" verbatim into exactly this kind of
        // unrelated memory (the Lincoln-quote data-integrity bug). With the
        // cadence example de-lexicalized, none of those nouns may appear.
        Fixture(
            n: 6, name: "Quote + photo — example-bleed guard (Lincoln)",
            clips: "[audio] \"I am not bound to win, but I am bound to be true. I am not bound to succeed, but I'm bound to live up to what light I have.\"\n[photo] (no description)",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["pepper", "tomato", "eggplant", "garden", "retire", "south carolina"],
            expectReuseTopics: [], expectReuseMentions: [],
            summaryWordCeiling: 45, pov: .secondPerson
        ),
    ]

    // MARK: - Runner

    @Test func runCalibrationSet() async throws {
        if let reason = OnDeviceOrganizer.availabilityError() {
            print("[CALIB] Foundation Models unavailable (\(reason)). Run on a capable device with Apple Intelligence enabled. Harness skipped.")
            return
        }

        var hardFailures: [String] = []
        print("[CALIB] === On-device organize calibration · \(Self.fixtures.count) fixtures ===")

        for f in Self.fixtures {
            let result = try await OnDeviceOrganizer().organize(
                content: f.clips,
                existingTopics: f.existingTopics,
                existingMentions: f.existingMentions
            )
            let summary = result.summary
            let title = result.title ?? ""
            let topics = result.topics
            let mentions = result.entities.map { $0.value }

            // Mechanical rubric
            let povOK = Self.povOK(summary, f.pov)
            let lengthOK = Self.wordCount(summary) <= f.summaryWordCeiling
            let cadenceOK = !Self.readsAsStaccato(summary)
            let bannedHit = f.bannedPhrases.first { summary.lowercased().contains($0.lowercased()) || title.lowercased().contains($0.lowercased()) }
            let antiTargetOK = bannedHit == nil
            let reuseOK = Self.reuseOK(topics: topics, mentions: mentions, f: f)

            print("""
            [CALIB] --- Fixture \(f.n) · \(f.name) ---
            [CALIB]   title:   \(title)
            [CALIB]   summary: \(summary)
            [CALIB]   topics:  \(topics)   mentions: \(mentions)
            [GRID]  F\(f.n) | POV:\(mark(povOK)) length(\(Self.wordCount(summary))≤\(f.summaryWordCeiling)):\(mark(lengthOK)) cadence:\(mark(cadenceOK)) antiTarget:\(mark(antiTargetOK))\(bannedHit.map { " (hit: \($0))" } ?? "") reuse:\(mark(reuseOK)) | claims/recognizable/descriptive = READ ABOVE
            """)

            // Hard-fail only the unambiguous mechanical violations — the
            // exact failure classes the anti-targets encode.
            if !antiTargetOK { hardFailures.append("F\(f.n): banned phrase '\(bannedHit ?? "")'") }
            if !povOK { hardFailures.append("F\(f.n): POV wrong for \(f.pov)") }
            if !lengthOK { hardFailures.append("F\(f.n): summary \(Self.wordCount(summary))w > ceiling \(f.summaryWordCeiling)") }
        }

        print("[CALIB] === hard mechanical failures: \(hardFailures.count) ===")
        hardFailures.forEach { print("[CALIB]   ✘ \($0)") }
        #expect(hardFailures.isEmpty, "Mechanical rubric violations: \(hardFailures.joined(separator: "; "))")
    }

    // MARK: - Rubric evaluators

    private func mark(_ ok: Bool) -> String { ok ? "PASS" : "FAIL" }

    static func wordCount(_ s: String) -> Int {
        s.split { $0 == " " || $0 == "\n" }.count
    }

    /// POV: owner rendered second-person ("you"), or — for pure
    /// observation — the subject left out entirely (no "you").
    static func povOK(_ summary: String, _ pov: Fixture.POV) -> Bool {
        let hasYou = summary.range(of: #"\byou\b|\byou're\b|\byou've\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        switch pov {
        case .secondPerson: return hasYou
        case .subjectOut:   return !hasYou
        }
    }

    /// Cadence proxy for "reads as one connected thought" (§ Voice, July
    /// 18): flags a run of short subject-verb declaratives with no
    /// connective glue. ≥3 sentences AND fewer than half carry a
    /// subordinator/coordinator → likely staccato. A heuristic, not a
    /// judge — the real read is done by eye on the printed summary.
    static func readsAsStaccato(_ summary: String) -> Bool {
        let sentences = summary
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard sentences.count >= 3 else { return false }
        let connectives = [" and ", " but ", " since ", " while ", " as ", " because ", " so ", " when ", " through ", ", "]
        let connected = sentences.filter { s in
            let lower = " " + s.lowercased() + " "
            return connectives.contains { lower.contains($0) }
        }.count
        return connected < sentences.count / 2 + 1
    }

    static func reuseOK(topics: [String], mentions: [String], f: Fixture) -> Bool {
        let topicsLower = Set(topics.map { $0.lowercased() })
        let mentionsLower = Set(mentions.map { $0.lowercased() })
        let topicReuse = f.expectReuseTopics.isEmpty
            || f.expectReuseTopics.contains { topicsLower.contains($0.lowercased()) }
        let mentionReuse = f.expectReuseMentions.isEmpty
            || f.expectReuseMentions.contains { mentionsLower.contains($0.lowercased()) }
        return topicReuse && mentionReuse
    }
}

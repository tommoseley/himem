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
            bannedPhrases: ["next step", "next steps", "reflecting on onboarding challenges", "Darlene"],
            expectReuseTopics: ["Onboarding", "Product"], expectReuseMentions: [],
            summaryWordCeiling: 60, pov: .secondPerson
        ),
        Fixture(
            n: 5, name: "Pure-observation — subject-out",
            clips: "[photo] description: Sunset over the ridge behind the house, sky went deep orange.\n[no audio]",
            existingTopics: library, existingMentions: people,
            bannedPhrases: ["breathtaking", "peaceful", "appreciate", "beauty of the evening", "Darlene", "Ben"],
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
            bannedPhrases: ["pepper", "tomato", "eggplant", "garden", "retire", "south carolina", "Darlene"],
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
            // Mirror production END-TO-END (2026-07-23): palette removed from
            // the prompt (fix #2), then the Honest-Label gate — verify the
            // summary → retry once → constrained extractive fallback. The
            // GATED summary is what ships, so that is what the rubric grades.
            let raw = try await OnDeviceOrganizer().organize(
                content: f.clips, existingTopics: f.existingTopics, existingMentions: []
            )
            let rawFabricated = HonestLabelGate.fabricatedProperNouns(in: raw.summary, sourceText: f.clips)

            var summary = raw.summary
            var title = raw.title ?? ""
            var usedFallback = false
            if HonestLabelGate.violates(summary: summary, sourceText: f.clips) {
                let retry = try await OnDeviceOrganizer().organize(
                    content: f.clips, existingTopics: f.existingTopics, existingMentions: []
                )
                if !HonestLabelGate.violates(summary: retry.summary, sourceText: f.clips) {
                    summary = retry.summary; title = retry.title ?? ""
                } else {
                    summary = HonestLabelGate.extractiveSummary(fromClipText: f.clips)
                    title = HonestLabelGate.extractiveTitle(fromClipText: f.clips)
                    usedFallback = true
                }
            }
            let topics = raw.topics
            let mentions = MentionReconciler.reconcile(
                extracted: raw.entities.map { $0.value }.filter { HonestLabelGate.isGrounded($0, in: f.clips) },
                library: f.existingMentions
            )

            // HONESTY (hard): the shipped summary must name no proper noun
            // absent from the clips — the gate's contract, catching ANY
            // invented name, not a banned list (the check the old fixed-
            // string antiTarget missed on "Albert").
            let gatedFabricated = HonestLabelGate.fabricatedProperNouns(in: summary, sourceText: f.clips)
            let fabricationOK = gatedFabricated.isEmpty
            let bannedHit = f.bannedPhrases.first { summary.lowercased().contains($0.lowercased()) || title.lowercased().contains($0.lowercased()) }
            let antiTargetOK = bannedHit == nil
            // QUALITY (soft — logged 3B ceilings; the extractive fallback
            // reshapes POV/length by design). Reported, never hard-failed.
            let povOK = Self.povOK(summary, f.pov)
            let lengthOK = Self.wordCount(summary) <= f.summaryWordCeiling
            let cadenceOK = !Self.readsAsStaccato(summary)
            let reuseOK = Self.reuseOK(topics: topics, mentions: mentions, f: f)

            print("""
            [CALIB] --- Fixture \(f.n) · \(f.name)\(usedFallback ? " [extractive fallback]" : "") ---
            [CALIB]   raw fabrication (pre-gate): \(rawFabricated.isEmpty ? "none" : rawFabricated.description)
            [CALIB]   title:   \(title)
            [CALIB]   summary: \(summary)
            [CALIB]   topics:  \(topics)   mentions: \(mentions)
            [GRID]  F\(f.n) | FABRICATION:\(mark(fabricationOK)) antiTarget:\(mark(antiTargetOK))\(bannedHit.map { " (hit: \($0))" } ?? "") | soft POV:\(mark(povOK)) length(\(Self.wordCount(summary))≤\(f.summaryWordCeiling)):\(mark(lengthOK)) cadence:\(mark(cadenceOK)) reuse:\(mark(reuseOK))
            """)

            // HARD-fail on honesty only. Quality items are reported above.
            if !fabricationOK { hardFailures.append("F\(f.n): fabricated proper noun(s) after gate: \(gatedFabricated)") }
            if !antiTargetOK { hardFailures.append("F\(f.n): banned phrase '\(bannedHit ?? "")'") }
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

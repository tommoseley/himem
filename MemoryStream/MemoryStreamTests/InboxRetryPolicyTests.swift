import Testing
import Foundation
@testable import HiMem

/// **B15 · the stranded-clip retry is unbounded, and the user watches it.**
///
/// Device, 2026-08-10. `WatchSessionDelegate.scheduleRetryIfStillPending`
/// re-arms a **fixed 30-second** sweep while `transcript.isEmpty &&
/// !transcriptionAttempted`, with no backoff, no cap and no terminal state.
/// Clips `DDA80712` / `48D2EF6E` (`exists=false ubiquitous=false`) retried
/// **twelve times in four minutes** and would have done so indefinitely.
///
/// **The `fileUnreadable` path deliberately leaves `transcriptionAttempted`
/// false, and that intent is correct** — *deferred* means "never really
/// attempted, the bytes weren't there." The defect is the retry policy layered
/// on top of it.
///
/// **Raised from logged to scheduled (Tom) because it is a visible UX defect,
/// not a battery one.** The Clips screen empties and rebuilds every ~15s. Each
/// sweep calls `recordTranscribingStarted` and then `clear` for *every* pending
/// clip, so it publishes two arrival-tracker changes per clip per sweep, each
/// driving a full bench regroup and re-render. The user watches her bench
/// blink. It also inflated two diagnostic signals — most `body` passes and most
/// of the `Publishing changes from background threads` noise — and it is what
/// made the `bench DIFFER` window periodic during 2b-ii-c1.
///
/// **Ruled fix shape: a file's arrival is an EVENT, not a poll.** Gate on the
/// ubiquity download state (already visible in the preflight log as `dlStatus`)
/// and resume on a ubiquity change notification. *Backoff alone only slows the
/// bleeding* — a clip whose bytes are not on the device will never succeed
/// because time passed, so any timer for it is a wrong answer at every
/// interval.
///
/// This suite owns the decision. The two pending causes are genuinely
/// different animals and the shipped code treated them as one:
///
///  - **the model is still installing** — time *is* the fix; retry, with
///    backoff and a cap.
///  - **the bytes are not here** — time is never the fix; request the download
///    and wait to be told.
@Suite struct InboxRetryPolicyTests {

    // MARK: - The defect

    /// **THE assertion.** Every pending clip is waiting on bytes, so there is
    /// nothing a timer can do — and arming one is what made the bench blink
    /// every fifteen seconds for four minutes.
    @Test func nothingIsArmedWhenEveryPendingClipIsWaitingOnBytes() {
        let a = UUID(), b = UUID()
        let decision = InboxRetryPolicy.decide(
            pending: [
                .init(clipId: a, fileIsReadyLocally: false),
                .init(clipId: b, fileIsReadyLocally: false),
            ],
            consecutiveAttempts: 0
        )
        #expect(decision.retryAfter == nil,
                """
                A timer was armed for clips whose audio is not on the device. No amount of \
                waiting makes those readable — the file has to ARRIVE — so every firing is \
                a guaranteed-failing sweep that republishes the arrival tracker twice per \
                clip and re-renders the whole bench.
                """)
        #expect(Set(decision.awaitingDownload) == [a, b])
        #expect(decision.retryable.isEmpty)
    }

    /// The converse, so the fix cannot degrade into "never retry anything".
    /// A clip whose file is present and is merely waiting for the speech model
    /// is exactly the case the 30s retry was added for (money 2026-06-17), and
    /// it must still be served.
    @Test func aClipWhoseFileIsPresentStillGetsARetry() {
        let ready = UUID()
        let decision = InboxRetryPolicy.decide(
            pending: [.init(clipId: ready, fileIsReadyLocally: true)],
            consecutiveAttempts: 0
        )
        #expect(decision.retryAfter == InboxRetryPolicy.backoff.first)
        #expect(decision.retryable == [ready])
        #expect(decision.awaitingDownload.isEmpty)
    }

    /// Mixed is the real device state: one clip installing, two stranded. The
    /// timer exists for the first and must not cover the other two, or the
    /// stranded pair rides the retry forever exactly as before.
    @Test func aMixedQueueArmsOnlyForTheClipsATimerCanHelp() {
        let ready = UUID(), stranded1 = UUID(), stranded2 = UUID()
        let decision = InboxRetryPolicy.decide(
            pending: [
                .init(clipId: ready, fileIsReadyLocally: true),
                .init(clipId: stranded1, fileIsReadyLocally: false),
                .init(clipId: stranded2, fileIsReadyLocally: false),
            ],
            consecutiveAttempts: 0
        )
        #expect(decision.retryable == [ready])
        #expect(Set(decision.awaitingDownload) == [stranded1, stranded2])
        #expect(decision.retryAfter != nil)
    }

    // MARK: - Bounds on both sides

    /// Backoff, not a fixed interval — the shipped policy asked again every
    /// 30 seconds forever.
    @Test func theIntervalGrowsWithConsecutiveFailures() {
        let id = UUID()
        let intervals = (0..<InboxRetryPolicy.backoff.count).map { attempt in
            InboxRetryPolicy.decide(
                pending: [.init(clipId: id, fileIsReadyLocally: true)],
                consecutiveAttempts: attempt
            ).retryAfter
        }
        #expect(intervals == InboxRetryPolicy.backoff.map { Optional($0) })
        #expect(intervals == intervals.sorted { ($0 ?? 0) < ($1 ?? 0) },
                "the backoff is not monotonic, so a later attempt asks sooner than an earlier one")
    }

    /// **The ceiling** (`CLAUDE.md` § Assertions Need a Ceiling). A policy that
    /// only ever grew the interval would pass every test above while still
    /// never stopping — the unbounded half of the defect, slowed rather than
    /// closed.
    @Test func thereIsATerminalStateRatherThanAnEverGrowingInterval() {
        let id = UUID()
        let decision = InboxRetryPolicy.decide(
            pending: [.init(clipId: id, fileIsReadyLocally: true)],
            consecutiveAttempts: InboxRetryPolicy.backoff.count
        )
        #expect(decision.retryAfter == nil,
                "the retry never reaches a terminal state — it is bounded in interval but not in count")
        #expect(decision.exhausted == [id],
                "a clip that ran out of attempts is not reported, so nothing can surface it")
    }

    /// **The interval lookup must never trap** (ruled by Tom, 2026-08-10).
    ///
    /// The first version bounded the subscript with a separate
    /// `guard consecutiveAttempts < backoff.count`. That is two things which
    /// must agree, kept in agreement by nobody — and during mutation
    /// verification a one-token edit to the guard turned the miss into an
    /// out-of-bounds **crash** that killed the test process and failed tests
    /// which do not touch this type. A wrong interval is diagnosable; a trap
    /// in a shared runner is the exit-65 overload again.
    ///
    /// Far past the end is the case that trapped. It must resolve to the
    /// terminal state, like any other overrun.
    @Test func anAttemptCountFarPastTheEndIsTerminalRatherThanATrap() {
        let id = UUID()
        for attempts in [InboxRetryPolicy.backoff.count, 99, Int.max] {
            let decision = InboxRetryPolicy.decide(
                pending: [.init(clipId: id, fileIsReadyLocally: true)],
                consecutiveAttempts: attempts
            )
            #expect(decision.retryAfter == nil, "attempts=\(attempts) armed a timer past the cap")
            #expect(decision.exhausted == [id], "attempts=\(attempts) did not report the clip exhausted")
        }
    }

    /// The other end. A negative count cannot arise from the delegate's
    /// counter today, which is exactly why nothing would catch it if that
    /// ever changed — and it would trap rather than misbehave.
    @Test func aNegativeAttemptCountIsTerminalRatherThanATrap() {
        let id = UUID()
        let decision = InboxRetryPolicy.decide(
            pending: [.init(clipId: id, fileIsReadyLocally: true)],
            consecutiveAttempts: -1
        )
        #expect(decision.retryAfter == nil)
        #expect(decision.exhausted == [id])
    }

    /// An empty queue arms nothing and reports nothing — the drained case,
    /// which the shipped code did get right and which must survive the fix.
    @Test func anEmptyQueueArmsNothing() {
        let decision = InboxRetryPolicy.decide(pending: [], consecutiveAttempts: 0)
        #expect(decision.retryAfter == nil)
        #expect(decision.awaitingDownload.isEmpty)
        #expect(decision.retryable.isEmpty)
        #expect(decision.exhausted.isEmpty)
    }

    /// A stranded clip must never count against the attempt budget: it is not
    /// failing, it is waiting. Otherwise a slow iCloud download quietly burns
    /// the retries belonging to a clip that a timer really could have helped.
    @Test func waitingOnBytesDoesNotConsumeTheAttemptBudget() {
        let stranded = UUID()
        let decision = InboxRetryPolicy.decide(
            pending: [.init(clipId: stranded, fileIsReadyLocally: false)],
            consecutiveAttempts: InboxRetryPolicy.backoff.count + 5
        )
        #expect(decision.exhausted.isEmpty,
                "a clip waiting on bytes was declared exhausted; it never had an attempt to spend")
        #expect(decision.awaitingDownload == [stranded])
    }

    // MARK: - Caller guard

    /// **The policy being right says nothing about whether the delegate asks
    /// it.** F18's lesson, and the one this project keeps re-learning: the
    /// shipped `WatchTransferAudioTranscoderTests` proved a transcoder correct
    /// while nothing asserted the transfer path still called it.
    @Test func theSweepAsksThePolicyRatherThanArmingItsOwnTimer() throws {
        let src = try Self.source("MemoryStream/Services/Watch/WatchSessionDelegate.swift")
        let body = try Self.blockBody(
            startingAtLineContaining: "private static func scheduleRetryIfStillPending()", in: src
        )
        let code = Self.codeOnly(body)
        #expect(code.contains("InboxRetryPolicy.decide"),
                """
                `scheduleRetryIfStillPending` decides its own schedule instead of asking the \
                policy, so the download gate and the cap can be correct and unreached. \
                Body was:
                \(body)
                """)
        #expect(code.contains("30_000_000_000") == false,
                """
                The fixed 30-second sleep is still present. That literal IS the defect: it \
                fires for clips whose bytes are not on the device, and every firing \
                republishes the arrival tracker and re-renders the bench.
                """)
    }

    // MARK: - Scanner self-tests
    //
    // Proving the matcher recognizes the defect, per Guard-the-Caller: a
    // mechanical guard that has never been shown to fire is a guard nobody
    // has tested.

    @Test func scanner_flagsAHandRolledFixedTimer() {
        let offending = """
        private static func scheduleRetryIfStillPending() {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
        """
        #expect(Self.codeOnly(offending).contains("30_000_000_000"))
        #expect(Self.codeOnly(offending).contains("InboxRetryPolicy.decide") == false)
    }

    @Test func scanner_acceptsASweepThatAsksThePolicy() {
        let fixed = """
        private static func scheduleRetryIfStillPending() {
            let decision = InboxRetryPolicy.decide(pending: p, consecutiveAttempts: n)
        }
        """
        #expect(Self.codeOnly(fixed).contains("InboxRetryPolicy.decide"))
        #expect(Self.codeOnly(fixed).contains("30_000_000_000") == false)
    }

    // MARK: - Source access

    static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let marker = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<marker.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// Throws on a missing anchor, so a rename fails loudly rather than
    /// letting this pass by matching nothing.
    static func blockBody(startingAtLineContaining needle: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            throw Failure.blockNotFound(needle)
        }
        var depth = 0, started = false
        var out: [String] = []
        for line in lines[start...] {
            for ch in line {
                if ch == "{" { depth += 1; started = true }
                if ch == "}" { depth -= 1 }
            }
            if started { out.append(line) }
            if started && depth == 0 { return out.joined(separator: "\n") }
        }
        throw Failure.blockNotFound(needle)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String), blockNotFound(String) }
}

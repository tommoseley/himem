import Foundation

/// **When may the inbox sweep ask again — and for which clips?** (B15, ruled
/// 2026-08-10.)
///
/// The shipped policy was one line inside `WatchSessionDelegate`: if anything
/// is still pending, sleep 30 seconds and sweep again. No backoff, no cap, no
/// terminal state, and — the part that made it a **visible UX defect rather
/// than a battery one** — no distinction between the two reasons a clip is
/// pending.
///
/// **Those two reasons are different animals, and conflating them is the
/// defect.**
///
///  - **The speech model is still installing.** Time really is the fix. This
///    is the case the 30-second retry was added for (money 2026-06-17): a user
///    sitting on Clips while Apple's model downloads would otherwise see
///    "Transcribing…" until she backgrounded and foregrounded the app.
///  - **The bytes are not on this device.** Time is *never* the fix. The file
///    has to arrive. Every firing is a guaranteed-failing sweep, and each one
///    calls `recordTranscribingStarted` and then `clear` for the clip — two
///    arrival-tracker publishes per clip per sweep, each driving a full bench
///    regroup and re-render. On device that is the Clips screen **emptying and
///    rebuilding every ~15 seconds** while two clips
///    (`exists=false ubiquitous=false`) retried twelve times in four minutes.
///
/// So: **a file's arrival is an EVENT, not a poll.** Clips waiting on bytes are
/// reported as `awaitingDownload`; the caller requests the download and resumes
/// when iCloud says so. No timer is armed on their behalf, at any interval —
/// *"backoff alone only slows the bleeding."*
///
/// Note what is NOT changed here. The `fileUnreadable` path deliberately leaves
/// `transcriptionAttempted` false, because *deferred* means "never really
/// attempted, the bytes weren't there," and that intent is correct. This is the
/// policy layered on top of it.
enum InboxRetryPolicy {

    /// One pending clip, reduced to the only thing the decision turns on.
    /// Value-typed so the policy is testable without a filesystem — the
    /// caller resolves readiness from `UbiquityStore.downloadStatus`.
    struct Pending: Equatable {
        let clipId: UUID
        /// True when the audio is readable on THIS device right now.
        /// Not "the file exists": a ubiquitous placeholder exists and is not
        /// readable, which is exactly the state that produced the loop.
        let fileIsReadyLocally: Bool
    }

    struct Decision: Equatable {
        /// Clips whose bytes are missing. The caller requests a download and
        /// waits for a ubiquity event. **Never scheduled.**
        let awaitingDownload: [UUID]
        /// Clips a later sweep could genuinely help.
        let retryable: [UUID]
        /// When to sweep again; `nil` means arm nothing at all.
        let retryAfter: TimeInterval?
        /// Clips that have spent the whole budget without succeeding. Reported
        /// rather than dropped: a policy that simply stopped would be a silent
        /// no-op, and the caller needs something to log or surface.
        let exhausted: [UUID]
    }

    /// Growing intervals rather than a fixed 30s. The first entry preserves
    /// the shipped behaviour for the model-installing case, which is the one
    /// the original retry was written to serve.
    static let backoff: [TimeInterval] = [30, 60, 120, 300, 600]

    /// - Parameter consecutiveAttempts: how many times the sweep has already
    ///   re-armed without the queue draining. Indexes `backoff`; at or past
    ///   its end the retry is terminal.
    static func decide(pending: [Pending], consecutiveAttempts: Int) -> Decision {
        let awaiting = pending.filter { !$0.fileIsReadyLocally }.map(\.clipId)
        let retryable = pending.filter(\.fileIsReadyLocally).map(\.clipId)

        // A clip waiting on bytes never spends an attempt — it is not failing,
        // it is waiting. Charging it would let a slow iCloud download quietly
        // burn the budget belonging to a clip a timer really could have helped.
        guard !retryable.isEmpty else {
            return Decision(
                awaitingDownload: awaiting, retryable: [], retryAfter: nil, exhausted: []
            )
        }

        // **The bound and the subscript are ONE expression, deliberately.**
        //
        // This was a `guard consecutiveAttempts < backoff.count` followed by
        // `backoff[consecutiveAttempts]` — two things that have to agree, kept
        // in agreement by nobody. That is the invariant-without-an-owner shape,
        // and it is not theoretical here: mutating the guard by a single token
        // during verification turned the miss into an out-of-bounds **crash**,
        // which took down the whole test process and failed tests that do not
        // touch this type at all. A wrong answer is diagnosable; a crash in a
        // shared runner is the `exit 65` overload again.
        //
        // `indices.contains` cannot disagree with the subscript it guards, and
        // it is total: past the end, negative, or an emptied `backoff` all
        // resolve to the terminal state rather than to a trap.
        guard backoff.indices.contains(consecutiveAttempts) else {
            // Terminal. The bench already offers a per-clip Retry affordance,
            // so stopping leaves the user a way forward rather than a dead end.
            return Decision(
                awaitingDownload: awaiting, retryable: retryable,
                retryAfter: nil, exhausted: retryable
            )
        }

        return Decision(
            awaitingDownload: awaiting,
            retryable: retryable,
            retryAfter: backoff[consecutiveAttempts],
            exhausted: []
        )
    }
}

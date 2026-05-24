import Foundation
import Combine

/// Cross-platform coordinator for the "Next" gesture during voice
/// recording. Owns the state machine (clip index, last-Next time,
/// rollGroupId) and the decision policy (debounce). Delegates the
/// actual audio handoff and haptic to platform-specific
/// implementations of `RecordingHandoff`.
///
/// Per spec (`docs/design/on-a-roll-spec.md`), this is the
/// "shared `NextClipController` that owns the gesture-to-action
/// mapping, debounce, haptic call, and recorder swap" — the
/// platform views wrap this controller and provide a
/// `RecordingHandoff` implementation matching their audio stack.
@MainActor
final class NextClipController: ObservableObject {
    /// 1-indexed clip counter for the current recording session.
    /// Clip 1 = the initial clip from session start; clip 2 starts
    /// at the first Next tap. UI reads this to drive the
    /// `CLIP N · ROLLING` eyebrow.
    @Published private(set) var currentClipIndex: Int = 1

    /// True for ~1.5 seconds after each Next tap. Drives the
    /// post-tap eyebrow animation.
    @Published private(set) var rollingEyebrowVisible: Bool = false

    /// Recording session start time. The first clip's start time
    /// is this; subsequent clips start at `lastNextAt`.
    private var sessionStart: Date?

    /// Most recent Next tap timestamp, or nil if no Next has fired
    /// in this session. Consumed by the debouncer and by the
    /// counter (the in-disc / under-Stop counter ticks from
    /// `lastNextAt ?? sessionStart`).
    private(set) var lastNextAt: Date?

    /// All Next tap offsets from session start, in tap order.
    /// Phone's master-file-then-split path reads this at Save time
    /// to slice the continuous master audio file into N per-clip
    /// segments (clip 1 = `0...offsets[0]`, clip 2 =
    /// `offsets[0]...offsets[1]`, …, clip N+1 =
    /// `offsets[N-1]...totalDuration`). Watch ignores this — its
    /// handoff path commits each clip at tap time.
    @Published private(set) var nextTapOffsets: [TimeInterval] = []

    /// Stamped at recording-session start; preserved across Next
    /// taps. Phone-side session-grouper consults this as a
    /// deterministic override over time+location heuristics. Same
    /// rollGroupId on every clip in the session means they always
    /// land in one Memory even if location drifts during a long
    /// walk.
    private(set) var rollGroupId: UUID?

    private let handoff: RecordingHandoff
    private var eyebrowDismissTask: Task<Void, Never>?

    init(handoff: RecordingHandoff) {
        self.handoff = handoff
    }

    /// Called by the recording UI when the user taps Record (the
    /// session begins). Resets all state to "clip 1 just started."
    func sessionDidStart(at start: Date = Date()) {
        sessionStart = start
        lastNextAt = nil
        nextTapOffsets = []
        currentClipIndex = 1
        rollGroupId = UUID()
        rollingEyebrowVisible = false
        eyebrowDismissTask?.cancel()
        eyebrowDismissTask = nil
    }

    /// Called by the recording UI when the user taps Stop & save
    /// (or wrist-off auto-saves). Clears state so a follow-up
    /// recording starts clean.
    func sessionDidEnd() {
        sessionStart = nil
        lastNextAt = nil
        nextTapOffsets = []
        currentClipIndex = 1
        rollGroupId = nil
        rollingEyebrowVisible = false
        eyebrowDismissTask?.cancel()
        eyebrowDismissTask = nil
    }

    /// Called by the Next button tap handler. Returns true if the
    /// tap fired (handoff invoked, counter incremented, eyebrow
    /// shown); false if the tap was silently debounced.
    ///
    /// The view layer uses the return value only to decide whether
    /// to fire the visual confirmation animation — the counter
    /// reset and eyebrow are observable via `@Published` and update
    /// automatically. Debounced taps emit no haptic, no save, no
    /// counter change.
    @discardableResult
    func handleNextTap(now: Date = Date()) -> Bool {
        guard let start = sessionStart else { return false }
        guard MinClipDebouncer.shouldFire(
            sessionStart: start,
            lastNextAt: lastNextAt,
            now: now
        ) else {
            return false
        }
        // The handoff is the platform's job — close current clip,
        // start new clip. It's expected to be near-instantaneous
        // (sub-100ms gap per spec). Errors are platform-specific
        // and surface there.
        handoff.handoffToNewClip(rollGroupId: rollGroupId ?? UUID(), newClipIndex: currentClipIndex + 1)
        lastNextAt = now
        nextTapOffsets.append(now.timeIntervalSince(start))
        currentClipIndex += 1
        showRollingEyebrow()
        return true
    }

    /// 5-minute hard cap (watch) interaction. Spec: "Next works
    /// with the cap. A user genuinely on a roll can chain seven
    /// 4-minute Next taps." When the cap fires and the current
    /// clip ends, the platform calls this to do the implicit Next
    /// — same handoff, but unconditional (the cap itself is the
    /// validation).
    func handleCapTriggeredHandoff(now: Date = Date()) {
        guard let start = sessionStart else { return }
        handoff.handoffToNewClip(rollGroupId: rollGroupId ?? UUID(), newClipIndex: currentClipIndex + 1)
        lastNextAt = now
        nextTapOffsets.append(now.timeIntervalSince(start))
        currentClipIndex += 1
        showRollingEyebrow()
    }

    /// Drives the `CLIP N · ROLLING` eyebrow that fades after ~1.5s.
    /// Re-tap behavior: hard replace (cancel the previous fade,
    /// show the new state immediately). The eyebrow is an
    /// acknowledgment of the most recent tap, not a queue.
    private func showRollingEyebrow() {
        eyebrowDismissTask?.cancel()
        rollingEyebrowVisible = true
        eyebrowDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.rollingEyebrowVisible = false
        }
    }
}

/// Platform-specific audio handoff contract. Each platform
/// implements this with its native audio stack:
///
///   • watchOS (AVAudioRecorder): close current file, swap target
///     URL, point recorder at new file. The session stays active.
///   • iOS (AVAudioEngine + SpeechAnalyzer): keep the engine
///     running; swap the AVAudioFile target; finalize the previous
///     transcript chunk and reset for the new clip. The mic tap
///     never pauses.
///
/// `rollGroupId` and `newClipIndex` are stamped on the new clip's
/// metadata so per-clip storage carries the grouping signal.
@MainActor
protocol RecordingHandoff {
    func handoffToNewClip(rollGroupId: UUID, newClipIndex: Int)
}

import Testing
import Foundation
@testable import HiMem

/// Money tests for `DebouncedTrigger` — the coalescing wrapper that
/// keeps `ClipsTabView.loadUnplaced()` from firing once per
/// `NSManagedObjectContextObjectsDidChange` during CloudKit import
/// bursts.
///
/// The tap-lockup report ("select a watch clip and it locks; then N
/// non-watch taps warm things up and the watch ones start opening")
/// traces to `ClipsTabView.onReceive(NSManagedObjectContextObjectsDidChange)`
/// running a MediaReference fetch with `edges.@count == 0` on the
/// main viewContext for every notification. Under CloudKit churn the
/// notification fires many times per second — main saturates, the
/// session-card tap gesture's animation is starved, and the card
/// looks "locked."
///
/// The fix's contract: many fires within a debounce window → one
/// action, always deferred to a later runloop tick so the current
/// stack frame (a notification callback) unwinds first.
@MainActor
@Suite(.serialized)
struct DebouncedTriggerTests {

    /// Burst of 20 fires within 5ms coalesces into exactly one
    /// action call inside the debounce window (100ms).
    @Test func burstFires_coalesceIntoOneAction() async throws {
        var callCount = 0
        let trigger = DebouncedTrigger(interval: .milliseconds(100))
        for _ in 0..<20 {
            trigger.fire { callCount += 1 }
        }
        // Deterministic wait, not a fixed sleep (2026-07-15): under a full
        // parallel test run the debounce's timer dispatch can be CPU-starved
        // well past a fixed 250ms window, which flaked `callCount` at 0. Poll
        // up to 3s — fires as soon as the coalesced action runs, tolerant of
        // the delay. `.serialized` on the suite can't fix this; the
        // contention is global CPU load, not intra-suite parallelism.
        let deadline = Date().addingTimeInterval(3.0)
        while callCount < 1 && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        // Then confirm NO second action fires — the coalescing guarantee.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(callCount == 1)
    }

    /// Fires spaced out by MORE than the debounce window each
    /// produce their own action call — proves the debounce doesn't
    /// swallow legitimate signals that arrive after the window
    /// closes.
    @Test func spacedFires_produceIndividualActions() async throws {
        var callCount = 0
        let trigger = DebouncedTrigger(interval: .milliseconds(80))
        // Deterministic wait per fire, same reason as the burst test above:
        // a fixed 200ms sleep is a wall-clock race under full-suite load.
        // Waiting for each action to land also GUARANTEES the spacing this
        // test is about, rather than assuming the clock provided it.
        for expected in 1...3 {
            await Self.awaitingAction("spaced fire #\(expected)") { done in
                trigger.fire { callCount += 1; done() }
            }
        }
        #expect(callCount == 3)
    }

    /// The action runs on a later runloop tick, not inside the
    /// `fire(_:)` call. This matters because the fire is called
    /// from inside an `.onReceive` closure holding the observation-
    /// change stack; running the fetch synchronously there is what
    /// the fix retires.
    @Test func actionDoesNotRunInsideFireCall() async throws {
        var callCount = 0
        let trigger = DebouncedTrigger(interval: .milliseconds(50))
        trigger.fire { callCount += 1 }
        // THE invariant: not synchronous inside `fire`. Deterministic — no
        // clock involved.
        #expect(callCount == 0)
        // That it eventually runs is a separate, weaker claim, and a fixed
        // 150ms sleep made it a wall-clock race: this failed at 1195 tests
        // and passed the same commit in isolation (F23, 2026-07-31). Same
        // deterministic wait the burst test adopted on 2026-07-15 — the fix
        // was applied to one instance then, not to the class.
        try await Self.waitUntil("the coalesced action ran") { callCount >= 1 }
        #expect(callCount == 1)
    }

    /// Polls until `condition` holds or `timeout` elapses. Returns as soon as
    /// it's true, so a healthy run costs ~one poll interval; a CPU-starved one
    /// gets the slack it needs instead of failing.
    ///
    /// A fixed sleep asserts "the scheduler got to it within N ms," which is
    /// not what any of these tests mean and is not something a parallel test
    /// run can promise. `.serialized` on the suite doesn't help — the
    /// contention is global CPU load, not intra-suite parallelism.

    /// A one-shot latch the debounce's action resolves. **This is the
    /// deterministic half** (2026-08-23).
    ///
    /// The tests used to poll `callCount` against a 3-second wall clock. The
    /// action is scheduled on a `Task` that sleeps for the interval, so under a
    /// full parallel run its dispatch can be starved well past any bound — the
    /// file already said so in 2026-07-15 — and the test then failed on a
    /// property that was never in question. Waiting on the ACTION ITSELF is
    /// correct whether or not the machine is loaded: the test completes when
    /// the thing it is about actually happens.
    ///
    /// The watchdog resolves the SAME latch, so the continuation is resumed
    /// exactly once on either path — no leak, and no second waiter.
    @MainActor
    final class ActionLatch {
        private(set) var ranForReal = false
        private var finished = false
        private var waiter: CheckedContinuation<Void, Never>?

        func resolve(ranForReal: Bool) {
            guard !finished else { return }
            finished = true
            if ranForReal { self.ranForReal = true }
            waiter?.resume()
            waiter = nil
        }

        func wait() async {
            if finished { return }
            await withCheckedContinuation { waiter = $0 }
        }
    }

    /// Fire `body`, then wait for its action to run. Fails loudly, naming the
    /// leg, only if the watchdog wins — which means starvation, never a
    /// swallowed signal.
    static func awaitingAction(
        _ leg: String,
        watchdog: Duration = .seconds(30),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: (@escaping () -> Void) -> Void
    ) async {
        let latch = ActionLatch()
        body { latch.resolve(ranForReal: true) }
        let guardTask = Task { @MainActor in
            try? await Task.sleep(for: watchdog)
            latch.resolve(ranForReal: false)
        }
        await latch.wait()
        guardTask.cancel()
        if !latch.ranForReal {
            Issue.record(
                """
                WAIT EXPIRED after \(watchdog) — "\(leg)" never ran.

                This is NOT evidence that the debounce swallowed a signal. The
                action is scheduled on a Task that sleeps for the interval; \
                under a full parallel run that dispatch can be CPU-starved. \
                Read THIS line before any count mismatch below it.
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    /// Poll until `condition` holds, and **fail loudly naming the expiry** if
    /// it doesn't.
    ///
    /// **The silent return was the diagnostic weakness** (2026-08-23). This
    /// used to return normally on timeout, leaving the caller's
    /// `#expect(callCount == 3)` to report the failure — which says *what* was
    /// wrong and hides *why*. A reader saw a bare count mismatch and had no
    /// signal that a wait had expired, so the obvious reading was "the debounce
    /// swallowed a signal", i.e. a production bug that isn't there. The next
    /// unrelated diff that tips this test should get a message naming the
    /// cause, not a number someone will misdiagnose.
    static func waitUntil(
        _ leg: String,
        timeout: TimeInterval = 3.0,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        if !condition() {
            Issue.record(
                """
                WAIT EXPIRED after \(timeout)s — "\(leg)" never happened.

                This is NOT evidence that the debounce swallowed a signal. The
                action is scheduled on a Task that sleeps for the interval;                 under a full parallel run that dispatch can be CPU-starved well                 past any wall-clock bound. The assertion that follows will                 report a count mismatch — read THIS line first.
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    /// `cancel()` between fire and window-close swallows the pending
    /// action. Needed so the trigger releases cleanly on view
    /// teardown without leaking a fetch onto a dead context.
    @Test func cancel_dropsPendingAction() async throws {
        var callCount = 0
        let trigger = DebouncedTrigger(interval: .milliseconds(80))
        trigger.fire { callCount += 1 }
        trigger.cancel()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(callCount == 0)
    }
}

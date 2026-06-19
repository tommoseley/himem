import Foundation

/// Process-wide async semaphore for tests that mutate
/// `InboxManifest.shared`. Swift Testing's `@Suite(.serialized)`
/// trait only serializes tests **within** a suite — different
/// suites run in parallel by default. The shared singleton can race
/// across suites when one suite seeds clips via `acceptClip(…)` and
/// another snapshot-replaces them via
/// `debugReplaceClipsForTesting(…)`. Concretely (observed 2026-06-19
/// on the full-suite run): `InboxArrivalTrackerTests` captured an
/// empty `priorClips` *before* `ColdLaunchTranscriptionRaceTests`'
/// `acceptClip` ran, then wiped the manifest to its empty snapshot,
/// nuking the planted clip mid-test.
///
/// Tests touching `InboxManifest.shared` must `await acquire()` at
/// entry and `release()` at exit (defer). The lock is not enforced
/// — it's a discipline. Both polluting and polluted suites have to
/// participate.
@MainActor
final class ManifestTestLock {
    static let shared = ManifestTestLock()
    private init() {}

    private var locked = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    /// Acquires the lock, suspending until any prior holder releases.
    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.append(cont)
        }
        // When resumed, `locked` stays true — handover from the
        // releasing holder. `release()` does not toggle `locked`
        // when there's a waiter.
    }

    /// Releases the lock. Handover semantics: if a waiter exists,
    /// resume the next one without flipping `locked`. Otherwise
    /// drop the flag so the next `acquire()` succeeds fast.
    func release() {
        if let next = queue.first {
            queue.removeFirst()
            next.resume()
        } else {
            locked = false
        }
    }
}

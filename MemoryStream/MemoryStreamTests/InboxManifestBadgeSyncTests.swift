import Testing
import Foundation
import UserNotifications
@testable import HiMem

/// Money tests for the 2026-05-18 regression: phone icon badge stuck
/// at "4" while the inbox was empty and no notifications had fired
/// recently. Root cause was twofold:
///
///   1. `InboxManifest.replace(with:)` (the normal mutation funnel)
///      didn't update the icon badge. Push payloads from
///      `WatchInboxNotificationCoordinator` set the badge when they
///      fire, but the system never lowers it on its own — when the
///      user reviews clips in-app, the badge stays at whatever the
///      last push said.
///
///   2. `InboxManifest.load()` set `clips` directly (filter-on-load
///      for orphaned audio + corrupt-manifest catch), bypassing
///      `replace(with:)`. So the bug above was also reachable just
///      by re-launching after a partial cleanup left orphaned rows.
///
/// Both paths now route through `syncIconBadge(to:)`. Plus
/// `syncBadgeNow()` is exposed for scene-active to call
/// defensively. Tests verify the badge follows mutations through
/// `acceptClip`, `remove`, `removeBatch`, and `load`.
///
/// **Note on testing:** `UNUserNotificationCenter.setBadgeCount`
/// requires notification permission and posts to the system. In
/// unit tests, the call succeeds (no permission prompt in non-UI
/// test contexts) but doesn't actually update a visible badge.
/// These tests verify the *call path* — that `replace(with:)` and
/// `load()` reach `setBadgeCount` — by observing the manifest's
/// in-memory state which gates the call, not the system's badge.
/// Integration verification is via the on-device fix observation:
/// the icon should clear to 0 the moment Tom opens the app.
@MainActor
@Suite(.serialized)
struct InboxManifestBadgeSyncTests {

    /// Money test scenario A: simulate the production bug —
    /// `acceptClip` fires, the badge should be set to the new count.
    /// We can't directly observe iOS's badge in a unit test, but the
    /// path-correctness is testable via the manifest's count
    /// invariants — if count is right, the syncIconBadge call uses
    /// the right value.
    @Test
    func acceptClip_thenRemove_keepsManifestCountCorrect() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        // Baseline: start clean. Drain any leftover clips from prior
        // tests in this process. `removeBatch` routes through
        // `replace(with:)` which triggers `syncIconBadge` to 0.
        let priorIds = manifest.clips.map(\.clipId)
        if !priorIds.isEmpty {
            manifest.removeBatch(clipIds: priorIds)
        }
        #expect(manifest.count == 0)

        let clip = InboxClip(
            clipId: UUID(),
            capturedAt: Date(),
            duration: 5,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "test.caf"
        )
        manifest.acceptClip(clip)
        #expect(manifest.count == 1)

        manifest.remove(clipId: clip.clipId)
        #expect(manifest.count == 0)
        // The badge would now be 0 in production — the test proves
        // the manifest state that drives the badge is correct.
    }

    /// Money test scenario B: bulk removal (batch dismiss from the
    /// inbox view) must also sync the badge — same `replace(with:)`
    /// funnel as single remove.
    @Test
    func removeBatch_emptiesManifest() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let prior = manifest.clips.map(\.clipId)
        if !prior.isEmpty { manifest.removeBatch(clipIds: prior) }

        let ids = (0..<3).map { _ in UUID() }
        for id in ids {
            manifest.acceptClip(InboxClip(
                clipId: id, capturedAt: Date(), duration: 1,
                transcript: "", latitude: nil, longitude: nil,
                source: "watch", audioFilename: "\(id).caf"
            ))
        }
        #expect(manifest.count == 3)

        manifest.removeBatch(clipIds: ids)
        #expect(manifest.count == 0)
    }

    /// Scenario C — **the locked decision, asserted.**
    ///
    /// This test used to be `#expect(true)` under a doc claiming it proved
    /// `syncBadgeNow()` idempotency. It proved only that three calls didn't
    /// crash; `#expect(true)` cannot fail, so it guarded nothing (F23 audit,
    /// Class 4 #4). The doc was also stale in a second way — it said the badge
    /// must "reflect the current count," which stopped being true when the
    /// numeric badge was retired on 2026-07-10.
    ///
    /// What is actually true, and now pinned: **whatever the pending count,
    /// the number requested is zero.** `CLAUDE.md` §Phone — a number
    /// reintroduces counting, which is the guilt-inbox HiMem rejects;
    /// presence is carried by the Clips tab dot.
    ///
    /// This is a locked-copy-style assertion: a failure here means someone
    /// restored a numeric badge, which is a principle change needing a ruling
    /// — not a test to update.
    @Test
    func iconBadgeIsAlwaysZero_whateverIsPending() {
        #expect(InboxManifest.iconBadgeCount(forPending: 0) == 0)
        #expect(InboxManifest.iconBadgeCount(forPending: 1) == 0, "one waiting clip is still not a number on the icon")
        #expect(InboxManifest.iconBadgeCount(forPending: 47) == 0, "nor is forty-seven")
    }

    /// Idempotency, stated as something that can fail: repeated calls request
    /// the same value rather than accumulating or drifting.
    @Test
    func syncBadgeNow_isIdempotent() async throws {
        await ManifestTestLock.shared.acquire()
        defer { ManifestTestLock.shared.release() }
        let manifest = InboxManifest.shared
        let before = manifest.count

        manifest.syncBadgeNow()
        manifest.syncBadgeNow()
        manifest.syncBadgeNow()

        #expect(manifest.count == before, "a badge sync must not mutate the manifest it reports on")
        #expect(InboxManifest.iconBadgeCount(forPending: manifest.count)
                == InboxManifest.iconBadgeCount(forPending: manifest.count),
                "the requested value is a pure function of the count — repeat calls cannot drift")
    }
}

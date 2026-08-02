import Foundation
import UIKit

/// Refcounted holder for `UIApplication.shared.isIdleTimerDisabled`.
/// Per CLAUDE.md's "Wake Lock (Idle Timer)" rule, HiMem holds the
/// system wake lock only during active capture — recording, photo
/// composer, video composer — and never for reading, editing, or
/// playback.
///
/// Multiple capture surfaces could theoretically overlap (a future
/// path could open the photo composer while a recording is winding
/// down). The refcount lets each surface acquire/release
/// independently without stepping on the others: the wake lock stays
/// held while the count is positive and lifts the moment it hits zero.
///
/// Watch surfaces don't use this — watchOS has no `isIdleTimerDisabled`
/// equivalent. The watch's recording UI keeps the screen alive via
/// wrist-up + foreground state, and the wrist-off auto-stop already
/// preserves the recording when the user disengages.
@MainActor
final class WakeLock {
    static let shared = WakeLock()

    private(set) var refCount: Int = 0

    /// True while the wake lock is held. Useful for tests and the
    /// debug panel.
    var isHeld: Bool { refCount > 0 }

    /// Increments the refcount and disables the idle timer when the
    /// count goes 0 → 1.
    func acquire() {
        refCount += 1
        if refCount == 1 {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    /// Decrements the refcount and re-enables the idle timer when
    /// the count goes 1 → 0. Calling release without a matching
    /// acquire is a no-op — by design, so views with conditional
    /// acquire paths can call release on dismiss unconditionally without
    /// churning. (The example named `MediaViewerView`, a type that exists
    /// nowhere in this codebase — removed 2026-07-31 rather than replaced:
    /// the rule stands on its own without an example to go stale.)
    func release() {
        guard refCount > 0 else { return }
        refCount -= 1
        if refCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    #if DEBUG
    /// Test-only reset. Clears the counter and forces the idle
    /// timer back on. Used by money tests for the wake-lock contract
    /// to start each test from a known state.
    func debugReset() {
        refCount = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }
    #endif
}

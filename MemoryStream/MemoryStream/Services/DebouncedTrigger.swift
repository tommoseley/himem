import Foundation

/// Coalesces a burst of `fire(_:)` calls into a single action call
/// after the interval elapses without any further fires. Each fire
/// cancels the pending schedule and starts a fresh one.
///
/// Introduced 2026-07-10 for `ClipsTabView`, whose
/// `.onReceive(NSManagedObjectContextObjectsDidChange)` handler ran
/// a `MediaReference` fetch with `edges.@count == 0` on the main
/// viewContext per notification. During CloudKit import bursts —
/// especially around freshly-arrived watch clips — that notification
/// fires many times per second, saturating main and starving the
/// session-card tap gesture's animation. Symptom Tom reported:
/// "select a watch clip and it locks; open a few non-watch first
/// and the watch ones start opening."
///
/// Action is passed per-`fire(_:)` so a SwiftUI View can initialize
/// the trigger as `@State` (no `self` capture at struct-init time)
/// and thread the reload closure at the notification site.
///
/// @MainActor because the driving use case is a SwiftUI `.onReceive`
/// — the notification lands on main and the action (a Core Data
/// viewContext fetch) has to run on main too.
@MainActor
final class DebouncedTrigger {

    private var pendingTask: Task<Void, Never>?
    private let interval: Duration

    nonisolated init(interval: Duration) {
        self.interval = interval
    }

    /// Schedule `action` to run after `interval` — cancels any prior
    /// pending schedule so a burst of fires collapses to one action.
    func fire(_ action: @escaping () -> Void) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.interval)
            if Task.isCancelled { return }
            action()
        }
    }

    /// Drop any pending schedule without firing. Call on view
    /// teardown to release cleanly.
    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

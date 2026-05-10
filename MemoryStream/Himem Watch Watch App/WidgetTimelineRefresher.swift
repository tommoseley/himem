import Foundation
import WidgetKit

/// Tells WidgetKit to recompute the complication timeline now, rather
/// than waiting for the next periodic refresh window. Called from any
/// watch-app code path that writes to the shared state (pending count
/// changes, recording flag flips).
///
/// Lives in its own file so the imports stay light — `WidgetKit` is a
/// system framework already linked by the watch target.
enum WidgetTimelineRefresher {
    static func refresh() async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation

/// State the watch app surfaces to its complication widget. Lives in the
/// App Group's shared UserDefaults so the widget extension (a separate
/// process) can read it without IPC.
///
/// Target membership: this file lives in the watch app target AND the
/// widget extension target. The iOS app does not consume it.
enum WatchSharedState {
    /// App Group identifier — must match the entitlement on both the watch
    /// app and the widget extension.
    static let appGroupId = "group.com.himem.app.shared"

    private static let pendingCountKey = "pendingCount"
    private static let isRecordingKey = "isRecording"
    private static let tapBehaviorKey = "complicationTapBehavior"

    /// Tap routing when the user taps the complication. Default is
    /// `.openReadyToRecord` per the design spec.
    enum TapBehavior: String {
        /// Open the watch app on the recording surface, ready to tap mic.
        case openReadyToRecord
        /// Press-and-hold to record immediately (walkie-talkie style).
        case pressAndHoldToRecord
    }

    /// The shared defaults instance, scoped to the App Group.
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Pending count

    static var pendingCount: Int {
        get { defaults?.integer(forKey: pendingCountKey) ?? 0 }
        set { defaults?.set(newValue, forKey: pendingCountKey) }
    }

    // MARK: - Recording flag

    static var isRecording: Bool {
        get { defaults?.bool(forKey: isRecordingKey) ?? false }
        set { defaults?.set(newValue, forKey: isRecordingKey) }
    }

    // MARK: - Tap behavior

    static var tapBehavior: TapBehavior {
        get {
            guard let raw = defaults?.string(forKey: tapBehaviorKey),
                  let value = TapBehavior(rawValue: raw)
            else { return .openReadyToRecord }
            return value
        }
        set { defaults?.set(newValue.rawValue, forKey: tapBehaviorKey) }
    }
}

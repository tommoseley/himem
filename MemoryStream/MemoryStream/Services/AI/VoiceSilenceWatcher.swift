import Foundation

/// Polls a text source on a background loop and fires `onSilence` once the
/// text has stopped changing for the user's configured silence interval.
/// Used by voice search and voice memory capture so both honour the same
/// "Voice search pace" setting in Settings.
@MainActor
final class VoiceSilenceWatcher {
    private var task: Task<Void, Never>?
    private var lastSnapshot: String = ""

    func start(textProvider: @escaping @MainActor () -> String,
               onSilence: @escaping @MainActor () -> Void) {
        cancel()
        lastSnapshot = textProvider()
        task = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await MainActor.run { Self.currentInterval() }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                let current = await MainActor.run { textProvider() }
                if !current.isEmpty && current == self?.lastSnapshot {
                    await MainActor.run { onSilence() }
                    return
                }
                await MainActor.run { self?.lastSnapshot = current }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func currentInterval() -> TimeInterval {
        let raw = UserDefaults.standard.string(forKey: "voiceSilenceMode") ?? VoiceSilenceMode.standard.rawValue
        return VoiceSilenceMode(rawValue: raw)?.seconds ?? VoiceSilenceMode.standard.seconds
    }
}

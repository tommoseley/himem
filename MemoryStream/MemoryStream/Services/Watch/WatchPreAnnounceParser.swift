import Foundation

/// Pure parser for the watch's pre-announce `sendMessage` payload.
/// Extracted from `WatchSessionDelegate` so the wire-format contract
/// is unit-testable without a real WCSession.
///
/// Payload shape (`WatchTransferService.send(clip:)` 2026-05-29+):
///
///   ```
///   [
///     "preAnnounce":     true,
///     "clipId":          "UUID-string",
///     "capturedAt":      Double  // unix epoch seconds
///     "duration":        Double  // seconds
///     "fileSizeBytes":   Int,
///     "latitude":        Double? // NSNull if absent
///     "longitude":       Double? // NSNull if absent
///   ]
///   ```
///
/// Any missing required field returns nil so the iPhone delegate
/// can ignore malformed payloads safely. The watch is the only
/// known producer; this is a defensive check, not a security
/// boundary.
enum WatchPreAnnounceParser {

    /// Parsed pre-announce payload, ready to feed into
    /// `InboxArrivalTracker.recordPreAnnounce(...)`. Returns nil
    /// when the payload doesn't carry a complete pre-announce.
    struct Parsed: Equatable {
        let clipId: UUID
        let capturedAt: Date
        let durationSeconds: TimeInterval
        let latitude: Double?
        let longitude: Double?
        let fileSizeBytes: Int64?
    }

    static func parse(_ payload: [String: Any]) -> Parsed? {
        guard payload["preAnnounce"] as? Bool == true else { return nil }
        guard let clipIdStr = payload["clipId"] as? String,
              let clipId = UUID(uuidString: clipIdStr) else { return nil }
        guard let capturedAtRaw = payload["capturedAt"] as? Double else { return nil }
        guard let durationRaw = payload["duration"] as? Double else { return nil }

        // Optional fields — latitude / longitude / fileSizeBytes may
        // arrive as NSNull or Double; treat anything non-numeric as
        // absent.
        let latitude = payload["latitude"] as? Double
        let longitude = payload["longitude"] as? Double
        let fileSize: Int64? = (payload["fileSizeBytes"] as? Int).map(Int64.init)

        return Parsed(
            clipId: clipId,
            capturedAt: Date(timeIntervalSince1970: capturedAtRaw),
            durationSeconds: durationRaw,
            latitude: latitude,
            longitude: longitude,
            fileSizeBytes: fileSize
        )
    }
}

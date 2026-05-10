import Foundation

/// Metadata payload that rides alongside each `WCSession.transferFile` call
/// when the watch ships a captured clip to the iPhone. Encoded as JSON in the
/// transfer's `metadata` dict; the iPhone decodes it on receive and uses the
/// fields to build the inbox manifest entry.
///
/// This file is a **member of both targets** (iOS app + watch app). The
/// shapes must stay in lockstep, so we keep one source of truth and let
/// Target Membership do the rest.
struct ClipMetadata: Codable, Equatable {
    /// Stable identifier for this clip. Watch generates it at recording-stop
    /// time. Used as:
    ///   - Idempotency key on the iPhone (a retried transfer with the same
    ///     id is a no-op).
    ///   - Handshake key in the WCSession reply ("got clipId X") so the
    ///     watch knows which row to remove from its pending list.
    let clipId: UUID

    /// Wall-clock time when recording stopped. ISO8601 in JSON.
    let capturedAt: Date

    /// Duration of the audio file, seconds. Stored on the watch so the
    /// inbox can render "0:14" without decoding the audio.
    let duration: TimeInterval

    /// Watch-side speech recognition transcript. Empty string if the user
    /// denied speech permission or the recognizer returned nothing.
    let transcript: String

    /// Capture location, if available. Nil when location permission is
    /// denied or no fix was obtained at recording-stop. Used by the iPhone
    /// inbox to suggest grouping clips captured at the same place.
    let latitude: Double?
    let longitude: Double?

    /// Capture source. Always "watch" for v1; future-proofs the manifest
    /// schema for other sources (Siri shortcut, AirPods voice memo, etc.).
    let source: String

    /// Convenience init for the watch side. The iPhone never constructs
    /// these; it only decodes them.
    init(
        clipId: UUID = UUID(),
        capturedAt: Date,
        duration: TimeInterval,
        transcript: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        source: String = "watch"
    ) {
        self.clipId = clipId
        self.capturedAt = capturedAt
        self.duration = duration
        self.transcript = transcript
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
    }

    // MARK: - Wire format

    /// Encoded as a flat string-keyed dict so it can ride in
    /// `WCSession.transferFile(_:metadata:)`. WatchConnectivity restricts
    /// metadata values to property-list types; we keep everything to
    /// strings/numbers and let the iPhone re-decode.
    func asWireDict() -> [String: Any] {
        var dict: [String: Any] = [
            "clipId": clipId.uuidString,
            "capturedAt": ISO8601DateFormatter().string(from: capturedAt),
            "duration": duration,
            "transcript": transcript,
            "source": source
        ]
        if let latitude { dict["latitude"] = latitude }
        if let longitude { dict["longitude"] = longitude }
        return dict
    }

    static func fromWireDict(_ dict: [String: Any]) -> ClipMetadata? {
        guard
            let clipIdStr = dict["clipId"] as? String,
            let clipId = UUID(uuidString: clipIdStr),
            let capturedAtStr = dict["capturedAt"] as? String,
            let capturedAt = ISO8601DateFormatter().date(from: capturedAtStr),
            let duration = dict["duration"] as? TimeInterval,
            let transcript = dict["transcript"] as? String,
            let source = dict["source"] as? String
        else { return nil }
        return ClipMetadata(
            clipId: clipId,
            capturedAt: capturedAt,
            duration: duration,
            transcript: transcript,
            latitude: dict["latitude"] as? Double,
            longitude: dict["longitude"] as? Double,
            source: source
        )
    }
}

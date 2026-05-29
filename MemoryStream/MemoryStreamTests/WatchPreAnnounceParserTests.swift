import Testing
import Foundation
@testable import HiMem

/// Money tests for the watch → iPhone pre-announce wire format
/// (`screens-captured-clips-sessions.jsx` § SYNC / INCOMING).
///
/// The parser is the contract boundary between the two apps; if the
/// shape drifts, the iPhone silently stops surfacing in-flight
/// clips. These tests lock the field names + types so a future
/// `WatchTransferService.send(clip:)` change can't silently break
/// pre-announce delivery.
struct WatchPreAnnounceParserTests {

    private func validPayload(
        clipId: UUID = UUID(),
        capturedAt: TimeInterval = 1_716_000_000,
        duration: TimeInterval = 12.5,
        fileSize: Int = 4096,
        latitude: Double? = 33.50,
        longitude: Double? = -80.50
    ) -> [String: Any] {
        return [
            "preAnnounce": true,
            "clipId": clipId.uuidString,
            "capturedAt": capturedAt,
            "duration": duration,
            "fileSizeBytes": fileSize,
            "latitude": latitude as Any,
            "longitude": longitude as Any
        ]
    }

    @Test func validPayload_parsesAllFields() {
        let id = UUID()
        let payload = validPayload(clipId: id)
        let parsed = WatchPreAnnounceParser.parse(payload)
        let unwrapped = parsed!
        #expect(unwrapped.clipId == id)
        #expect(unwrapped.capturedAt == Date(timeIntervalSince1970: 1_716_000_000))
        #expect(unwrapped.durationSeconds == 12.5)
        #expect(unwrapped.fileSizeBytes == 4096)
        #expect(unwrapped.latitude == 33.50)
        #expect(unwrapped.longitude == -80.50)
    }

    @Test func missingPreAnnounceFlag_returnsNil() {
        // A future watch message with a different shape (e.g., an
        // ack response, a flush command echo) must NOT be mistaken
        // for a pre-announce.
        var p = validPayload()
        p.removeValue(forKey: "preAnnounce")
        #expect(WatchPreAnnounceParser.parse(p) == nil)
    }

    @Test func preAnnounceFalse_returnsNil() {
        var p = validPayload()
        p["preAnnounce"] = false
        #expect(WatchPreAnnounceParser.parse(p) == nil)
    }

    @Test func missingClipId_returnsNil() {
        var p = validPayload()
        p.removeValue(forKey: "clipId")
        #expect(WatchPreAnnounceParser.parse(p) == nil)
    }

    @Test func malformedClipId_returnsNil() {
        var p = validPayload()
        p["clipId"] = "not-a-valid-uuid"
        #expect(WatchPreAnnounceParser.parse(p) == nil)
    }

    @Test func missingCapturedAt_returnsNil() {
        var p = validPayload()
        p.removeValue(forKey: "capturedAt")
        #expect(WatchPreAnnounceParser.parse(p) == nil)
    }

    @Test func missingDuration_returnsNil() {
        var p = validPayload()
        p.removeValue(forKey: "duration")
        #expect(WatchPreAnnounceParser.parse(p) == nil)
    }

    @Test func missingLatLong_parses_withNilCoordinates() {
        var p = validPayload()
        p["latitude"] = NSNull()
        p["longitude"] = NSNull()
        let parsed = WatchPreAnnounceParser.parse(p)
        let unwrapped = parsed!
        #expect(unwrapped.latitude == nil)
        #expect(unwrapped.longitude == nil)
    }

    @Test func missingFileSize_parses_withNilBytes() {
        var p = validPayload()
        p.removeValue(forKey: "fileSizeBytes")
        let parsed = WatchPreAnnounceParser.parse(p)
        let unwrapped = parsed!
        #expect(unwrapped.fileSizeBytes == nil)
    }
}

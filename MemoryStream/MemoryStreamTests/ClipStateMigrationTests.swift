import Testing
import Foundation
@testable import HiMem

/// Money tests for `InboxClip.Status` and the Codable migration that
/// upgrades legacy manifest rows in place.
///
/// Why this exists: the watch-sync rebuild consolidates three stores
/// (`InboxManifest` + `InboxProcessedClipIds` + `InboxArrivalTracker`)
/// into one source of truth — `InboxClip.status` is that source.
/// Existing devices have a `manifest.json` written under the old
/// schema (no `status` field). When the app launches on the new
/// build, those rows must load without data loss and infer the right
/// status from the fields they DO have.
///
/// Inference rule:
///   - `transcript.isEmpty == false` OR `transcriptionAttempted == true`
///     → `.transcribed` (the recognizer has run, even if it found
///     nothing usable)
///   - otherwise → `.received` (audio on disk, recognizer hasn't run yet)
///
/// The status field is the source of truth for *what's happening* with
/// a clip; the rebuild eliminates §§ 8.6 / 8.2 / 8.7 / 7.3 by reading
/// the manifest's row instead of consulting separate stores.
struct ClipStateMigrationTests {

    // MARK: - Legacy decode (no `status` field on the wire)

    @Test func legacyEntry_noTranscriptUntried_migratesToReceived() throws {
        let json = #"""
        {
          "clipId": "11111111-1111-1111-1111-111111111111",
          "capturedAt": "2026-05-15T10:00:00Z",
          "duration": 12.5,
          "transcript": "",
          "source": "watch",
          "audioFilename": "11111111-1111-1111-1111-111111111111.caf",
          "transcriptionAttempted": false
        }
        """#
        let clip = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: Data(json.utf8))
        #expect(clip.status == .received)
        #expect(clip.disposedAt == nil)
    }

    @Test func legacyEntry_withTranscript_migratesToTranscribed() throws {
        let json = #"""
        {
          "clipId": "22222222-2222-2222-2222-222222222222",
          "capturedAt": "2026-05-15T10:00:00Z",
          "duration": 18.2,
          "transcript": "hello world",
          "source": "watch",
          "audioFilename": "22222222-2222-2222-2222-222222222222.caf",
          "transcriptionAttempted": true
        }
        """#
        let clip = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: Data(json.utf8))
        #expect(clip.status == .transcribed)
    }

    /// Recognizer ran but found nothing — `transcriptionAttempted=true`
    /// + empty transcript. Still `.transcribed` because the attempt is
    /// what the status records, not the result.
    @Test func legacyEntry_attemptedNoText_migratesToTranscribed() throws {
        let json = #"""
        {
          "clipId": "33333333-3333-3333-3333-333333333333",
          "capturedAt": "2026-05-15T10:00:00Z",
          "duration": 6.0,
          "transcript": "",
          "source": "watch",
          "audioFilename": "33333333-3333-3333-3333-333333333333.caf",
          "transcriptionAttempted": true
        }
        """#
        let clip = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: Data(json.utf8))
        #expect(clip.status == .transcribed)
    }

    /// Even older entries with neither `transcriptionAttempted` NOR
    /// `rollGroupId` should still decode — both are optional in the
    /// pre-status schema. Defaults to `.received`.
    @Test func legacyEntry_minimalFields_migratesToReceived() throws {
        let json = #"""
        {
          "clipId": "44444444-4444-4444-4444-444444444444",
          "capturedAt": "2026-05-15T10:00:00Z",
          "duration": 3.5,
          "transcript": "",
          "source": "watch",
          "audioFilename": "44444444-4444-4444-4444-444444444444.caf"
        }
        """#
        let clip = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: Data(json.utf8))
        #expect(clip.status == .received)
        #expect(clip.transcriptionAttempted == false)
    }

    // MARK: - New schema round-trip

    @Test func newSchema_roundTrips_preservesStatus() throws {
        let clip = makeClip(clipId: UUID(), status: .transcribing)
        let data = try JSONEncoder.iso8601forTest.encode(clip)
        let decoded = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: data)
        #expect(decoded.status == .transcribing)
        #expect(decoded.clipId == clip.clipId)
    }

    @Test func newSchema_roundTrips_preservesDisposedAt() throws {
        let disposedAt = Date(timeIntervalSinceReferenceDate: 500_000)
        let clip = makeClip(clipId: UUID(), status: .disposed, disposedAt: disposedAt)
        let data = try JSONEncoder.iso8601forTest.encode(clip)
        let decoded = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: data)
        #expect(decoded.status == .disposed)
        #expect(decoded.disposedAt == disposedAt)
    }

    /// All five status values must round-trip cleanly — lock the
    /// enum's `rawValue` mapping.
    @Test func newSchema_allStatusValues_roundTrip() throws {
        let statuses: [InboxClip.Status] = [.announced, .received, .transcribing, .transcribed, .disposed]
        for status in statuses {
            let clip = makeClip(clipId: UUID(), status: status)
            let data = try JSONEncoder.iso8601forTest.encode(clip)
            let decoded = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: data)
            #expect(decoded.status == status, "status \(status) failed round-trip")
        }
    }

    // MARK: - Announce-time metadata (Step 12 — schema pre-position)

    /// Pre-position for the future `InboxArrivalTracker` full
    /// demotion: the announce-time metadata (`announcedAt`,
    /// `fileSizeBytes`) lives on `InboxClip` so a later post-launch
    /// commit can move `.announced` state from the tracker into the
    /// manifest without a second codable migration. Today the
    /// tracker still owns the in-memory queue; these fields land as
    /// nullable optionals so legacy rows decode unchanged.
    @Test func legacyEntry_withoutAnnouncedAt_decodesAsNil() throws {
        let json = #"""
        {
          "clipId": "55555555-5555-5555-5555-555555555555",
          "capturedAt": "2026-06-01T10:00:00Z",
          "duration": 4.0,
          "transcript": "",
          "source": "watch",
          "audioFilename": "55555555-5555-5555-5555-555555555555.caf"
        }
        """#
        let clip = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: Data(json.utf8))
        #expect(clip.announcedAt == nil)
    }

    @Test func legacyEntry_withoutFileSizeBytes_decodesAsNil() throws {
        let json = #"""
        {
          "clipId": "66666666-6666-6666-6666-666666666666",
          "capturedAt": "2026-06-01T10:00:00Z",
          "duration": 4.0,
          "transcript": "",
          "source": "watch",
          "audioFilename": "66666666-6666-6666-6666-666666666666.caf"
        }
        """#
        let clip = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: Data(json.utf8))
        #expect(clip.fileSizeBytes == nil)
    }

    @Test func newSchema_roundTrips_preservesAnnouncedAt() throws {
        let announcedAt = Date(timeIntervalSinceReferenceDate: 900_000)
        let clip = makeClipWithAnnounceMetadata(
            clipId: UUID(),
            status: .announced,
            announcedAt: announcedAt,
            fileSizeBytes: nil
        )
        let data = try JSONEncoder.iso8601forTest.encode(clip)
        let decoded = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: data)
        #expect(decoded.announcedAt == announcedAt)
    }

    @Test func newSchema_roundTrips_preservesFileSizeBytes() throws {
        let clip = makeClipWithAnnounceMetadata(
            clipId: UUID(),
            status: .announced,
            announcedAt: nil,
            fileSizeBytes: 192_456
        )
        let data = try JSONEncoder.iso8601forTest.encode(clip)
        let decoded = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: data)
        #expect(decoded.fileSizeBytes == 192_456)
    }

    /// Both fields are independently nullable; an entry can have
    /// one set without the other (e.g., a pre-announce that didn't
    /// carry size on the wire). Round-trip locks this.
    @Test func newSchema_roundTrips_bothAnnounceFieldsNil() throws {
        let clip = makeClipWithAnnounceMetadata(
            clipId: UUID(),
            status: .announced,
            announcedAt: nil,
            fileSizeBytes: nil
        )
        let data = try JSONEncoder.iso8601forTest.encode(clip)
        let decoded = try JSONDecoder.iso8601forTest.decode(InboxClip.self, from: data)
        #expect(decoded.announcedAt == nil)
        #expect(decoded.fileSizeBytes == nil)
    }

    // MARK: - Helpers

    private func makeClip(
        clipId: UUID,
        status: InboxClip.Status,
        disposedAt: Date? = nil
    ) -> InboxClip {
        InboxClip(
            clipId: clipId,
            capturedAt: Date(timeIntervalSinceReferenceDate: 100_000),
            duration: 10,
            transcript: status == .transcribed ? "test" : "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(clipId.uuidString).caf",
            transcriptionAttempted: status == .transcribed,
            rollGroupId: nil,
            status: status,
            disposedAt: disposedAt
        )
    }

    private func makeClipWithAnnounceMetadata(
        clipId: UUID,
        status: InboxClip.Status,
        announcedAt: Date?,
        fileSizeBytes: Int64?
    ) -> InboxClip {
        InboxClip(
            clipId: clipId,
            capturedAt: Date(timeIntervalSinceReferenceDate: 100_000),
            duration: 10,
            transcript: "",
            latitude: nil,
            longitude: nil,
            source: "watch",
            audioFilename: "\(clipId.uuidString).caf",
            transcriptionAttempted: false,
            rollGroupId: nil,
            status: status,
            disposedAt: nil,
            announcedAt: announcedAt,
            fileSizeBytes: fileSizeBytes
        )
    }
}

private extension JSONEncoder {
    static var iso8601forTest: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso8601forTest: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

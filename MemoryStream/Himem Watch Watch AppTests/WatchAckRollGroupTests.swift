import Testing
import Foundation
import Combine
@testable import Himem_Watch_Watch_App

/// Money tests for the watch-side rollGroup ack handler.
///
/// The bug context (Tom QA 2026-05-30): a phone-side delete of a clip
/// from a split-clip session re-acked using the child's clipId. The
/// watch row was keyed on the master's clipId (= the rollGroupId), so
/// the ack never matched. If the original arrival ack was lost, the
/// row stayed pending forever.
///
/// The fix: the iPhone sends one rollGroup ack per disposed roll
/// group; the watch removes every pending row whose `rollGroupId`
/// matches. `handleAckPayload` is the parser the tests can drive
/// without a real WCSession.
@MainActor
@Suite(.serialized)
struct WatchAckRollGroupTests {

    /// New wire format with `kind: "rollGroup"` publishes onto the
    /// rollGroup channel, leaving `lastAckedClipId` untouched. Drives
    /// the coordinator's separate sink.
    @Test func handleAck_newFormat_rollGroup_publishesRollGroupId() async throws {
        let service = WatchTransferService()
        let id = UUID()
        var received: UUID?
        let cancellable = service.$lastAckedRollGroupId
            .compactMap { $0 }
            .sink { received = $0 }
        defer { cancellable.cancel() }

        service.handleAckPayload(["confirmed": id.uuidString, "kind": "rollGroup"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(received == id)
        #expect(service.lastAckedClipId == nil, "rollGroup ack must not leak onto clipId channel")
    }

    /// New wire format with `kind: "clip"` still routes to the
    /// per-clipId channel — preserves the existing arrival ack path
    /// without changes at receiver sites.
    @Test func handleAck_newFormat_clip_publishesClipId() async throws {
        let service = WatchTransferService()
        let id = UUID()
        var received: UUID?
        let cancellable = service.$lastAckedClipId
            .compactMap { $0 }
            .sink { received = $0 }
        defer { cancellable.cancel() }

        service.handleAckPayload(["confirmed": id.uuidString, "kind": "clip"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(received == id)
        #expect(service.lastAckedRollGroupId == nil)
    }

    /// Legacy `confirmedClipId` payloads must still route to the
    /// clipId channel. iOS's transferUserInfo queue can hold acks
    /// emitted before the format change; the legacy branch keeps them
    /// flowing during the rollout window.
    @Test func handleAck_legacyFormat_clipId_publishesClipId() async throws {
        let service = WatchTransferService()
        let id = UUID()
        var received: UUID?
        let cancellable = service.$lastAckedClipId
            .compactMap { $0 }
            .sink { received = $0 }
        defer { cancellable.cancel() }

        service.handleAckPayload(["confirmedClipId": id.uuidString])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(received == id)
    }

    /// Payload with `kind` set to something nonsense neither
    /// publishes nor crashes. Mirrors the legacy ignore branch's
    /// safety — receiver is forgiving on the wire.
    @Test func handleAck_unknownKind_isIgnored() async throws {
        let service = WatchTransferService()
        service.handleAckPayload(["confirmed": UUID().uuidString, "kind": "bogus"])
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.lastAckedClipId == nil)
        #expect(service.lastAckedRollGroupId == nil)
    }

    /// `removeByRollGroup` clears every pending row whose
    /// `rollGroupId` matches and leaves unrelated rows alone. Three
    /// children of one roll session + one single-clip outside it →
    /// one rollGroup ack removes the three children and the single
    /// stays.
    @Test func removeByRollGroup_removesAllMatchingRows() async throws {
        let manifest = WatchPendingManifest.shared
        let priorClips = manifest.clips
        let priorReceipt = manifest.lastConfirmedReceiptAt
        defer {
            manifest.debugReplaceClipsForTesting(priorClips)
            manifest.debugSetLastConfirmedReceiptForTesting(priorReceipt)
        }

        let rollGroupId = UUID()
        let unrelatedRollGroupId = UUID()
        let childA = WatchPendingClip(
            clipId: UUID(), capturedAt: Date(), duration: 5, transcript: "",
            latitude: nil, longitude: nil,
            audioFilename: "a-\(UUID().uuidString).caf",
            rollGroupId: rollGroupId
        )
        let childB = WatchPendingClip(
            clipId: UUID(), capturedAt: Date(), duration: 5, transcript: "",
            latitude: nil, longitude: nil,
            audioFilename: "b-\(UUID().uuidString).caf",
            rollGroupId: rollGroupId
        )
        let childC = WatchPendingClip(
            clipId: UUID(), capturedAt: Date(), duration: 5, transcript: "",
            latitude: nil, longitude: nil,
            audioFilename: "c-\(UUID().uuidString).caf",
            rollGroupId: rollGroupId
        )
        let outsider = WatchPendingClip(
            clipId: UUID(), capturedAt: Date(), duration: 5, transcript: "",
            latitude: nil, longitude: nil,
            audioFilename: "x-\(UUID().uuidString).caf",
            rollGroupId: unrelatedRollGroupId
        )
        manifest.debugReplaceClipsForTesting([childA, childB, childC, outsider])

        manifest.removeByRollGroup(rollGroupId: rollGroupId)
        // remove(viaSync:true) defers the actual purge by
        // syncFlashDuration (1s). Wait it out plus a small buffer.
        try await Task.sleep(nanoseconds: 1_300_000_000)

        let remaining = Set(manifest.clips.map(\.clipId))
        #expect(remaining == [outsider.clipId], "rollGroup ack should remove all three matches and leave the outsider")
    }

    /// `removeByRollGroup` with a rollGroupId that doesn't match any
    /// rows is a no-op — same idempotency the per-clipId path has.
    @Test func removeByRollGroup_noMatch_isNoOp() {
        let manifest = WatchPendingManifest.shared
        let priorClips = manifest.clips
        let priorReceipt = manifest.lastConfirmedReceiptAt
        defer {
            manifest.debugReplaceClipsForTesting(priorClips)
            manifest.debugSetLastConfirmedReceiptForTesting(priorReceipt)
        }
        let single = WatchPendingClip(
            clipId: UUID(), capturedAt: Date(), duration: 5, transcript: "",
            latitude: nil, longitude: nil,
            audioFilename: "s-\(UUID().uuidString).caf",
            rollGroupId: UUID()
        )
        manifest.debugReplaceClipsForTesting([single])
        manifest.removeByRollGroup(rollGroupId: UUID())
        #expect(manifest.clips.count == 1)
    }
}

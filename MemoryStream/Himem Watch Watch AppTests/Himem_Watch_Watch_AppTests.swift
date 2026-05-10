import Testing
import Foundation
@testable import Himem_Watch_Watch_App

struct WatchTransferServiceTests {

    /// Guards the parsing logic that both delivery paths (sendMessage and
    /// transferUserInfo) feed into. Regression target: a typo in the payload
    /// key or UUID parsing change would break ack-driven manifest pruning.
    @Test
    func handleAckPayloadSetsLastAckedClipId() async throws {
        let service = await WatchTransferService()
        let clipId = UUID()

        service.handleAckPayload(["confirmedClipId": clipId.uuidString])

        // The handler hops to MainActor via Task; give it a tick to settle.
        try await Task.sleep(nanoseconds: 50_000_000)
        let acked = await service.lastAckedClipId
        #expect(acked == clipId)
    }

    @Test
    func handleAckPayloadIgnoresMissingKey() async throws {
        let service = await WatchTransferService()
        service.handleAckPayload(["someOtherKey": "value"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let acked = await service.lastAckedClipId
        #expect(acked == nil)
    }

    @Test
    func handleAckPayloadIgnoresMalformedUUID() async throws {
        let service = await WatchTransferService()
        service.handleAckPayload(["confirmedClipId": "not-a-uuid"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let acked = await service.lastAckedClipId
        #expect(acked == nil)
    }
}

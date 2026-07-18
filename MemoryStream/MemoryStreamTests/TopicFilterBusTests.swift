import Testing
import Foundation
@testable import HiMem

/// The topic read-chip navigation contract (unified associations,
/// 2026-07-17): tapping a topic on an opened memory sets
/// `pendingTopicFilter`, which HiMemTabView + the memories JournalView
/// observe to route to the Memories tab filtered by that topic.
@MainActor
@Suite(.serialized)
struct TopicFilterBusTests {

    @Test func request_setsPendingTopicFilter() {
        let bus = TopicFilterBus.shared
        bus.pendingTopicFilter = nil   // clean baseline (shared singleton)

        bus.request("Garden")
        #expect(bus.pendingTopicFilter == "Garden")

        // Consumers clear it after routing so an identical topic can
        // fire again later.
        bus.pendingTopicFilter = nil
        #expect(bus.pendingTopicFilter == nil)
    }
}

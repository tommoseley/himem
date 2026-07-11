import Testing
import Foundation
@testable import HiMem

/// Money tests for `MemoryDetailPresentationContext` — the July 11
/// 2026 signal that lets `HiMemTabView` hide its tab-shell FAB
/// while a Memory Detail is on screen. Prior to this, drilling into
/// a memory rendered two overlapping ochre `+` buttons ("two RABs")
/// — one from Memory Detail's own `AppendFAB`, one from the tab
/// shell. Both were operable and did different things.
///
/// Same shape as `ProjectsNavigationContextTests`.
@MainActor
@Suite(.serialized)
struct MemoryDetailPresentationContextTests {

    private func withFreshContext(_ body: () throws -> Void) rethrows {
        let ctx = MemoryDetailPresentationContext.shared
        ctx.debugReset()
        defer { ctx.debugReset() }
        try body()
    }

    @Test func enter_sets_currentMemoryId() throws {
        try withFreshContext {
            let id = UUID()
            let ctx = MemoryDetailPresentationContext.shared
            #expect(ctx.currentMemoryId == nil)
            ctx.enter(memoryId: id)
            #expect(ctx.currentMemoryId == id)
        }
    }

    @Test func exit_clears_matching_memoryId() throws {
        try withFreshContext {
            let id = UUID()
            let ctx = MemoryDetailPresentationContext.shared
            ctx.enter(memoryId: id)
            ctx.exit(memoryId: id)
            #expect(ctx.currentMemoryId == nil)
        }
    }

    @Test func exit_does_not_clear_when_id_differs() throws {
        try withFreshContext {
            let departing = UUID()
            let incoming = UUID()
            let ctx = MemoryDetailPresentationContext.shared
            ctx.enter(memoryId: incoming)
            ctx.exit(memoryId: departing)
            #expect(ctx.currentMemoryId == incoming,
                    "stale exit must not clear an incoming detail's context")
        }
    }
}

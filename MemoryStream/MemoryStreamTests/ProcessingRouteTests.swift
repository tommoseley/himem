import Testing
@testable import HiMem

/// The organize-routing seam extracted from `ProcessingEngine.processEntry`
/// (CRAP 2026-07-26). The tier × on-device × connectivity matrix changed four
/// times this month and had no test — and its inline comment had already
/// drifted from the code (it under-stated the Free-tier cloud fallback). This
/// pins the ACTUAL shipped routing for all eight combinations so the two can't
/// silently disagree again. `processLocally` (NLTagger) is the always-terminal
/// fallback and is intentionally NOT part of the plan.
struct ProcessingRouteTests {

    @Test func plusOnline_withAI_cloudPrimary_onDeviceFallback() {
        #expect(ProcessingEngine.organizeRoute(online: true, isPlus: true, hasAI: true) == [.cloud, .onDevice])
    }

    @Test func plusOnline_noAI_cloudOnly() {
        #expect(ProcessingEngine.organizeRoute(online: true, isPlus: true, hasAI: false) == [.cloud])
    }

    @Test func freeOnline_withAI_onDevicePrimary_cloudLastResort() {
        // The case the old comment got wrong: Free + AI + online still gets a
        // cloud last-resort BEFORE the local terminal.
        #expect(ProcessingEngine.organizeRoute(online: true, isPlus: false, hasAI: true) == [.onDevice, .cloud])
    }

    @Test func freeOnline_noAI_cloudIsOnlyAIPath() {
        #expect(ProcessingEngine.organizeRoute(online: true, isPlus: false, hasAI: false) == [.cloud])
    }

    @Test func offline_withAI_onDeviceOnly() {
        #expect(ProcessingEngine.organizeRoute(online: false, isPlus: true, hasAI: true) == [.onDevice])
        #expect(ProcessingEngine.organizeRoute(online: false, isPlus: false, hasAI: true) == [.onDevice])
    }

    @Test func offline_noAI_emptyPlan_goesStraightToLocalTerminal() {
        #expect(ProcessingEngine.organizeRoute(online: false, isPlus: true, hasAI: false) == [])
        #expect(ProcessingEngine.organizeRoute(online: false, isPlus: false, hasAI: false) == [])
    }

    /// A cloud step at index 0 is the primary; a cloud step later is the
    /// last-resort fallback (drives `processWithCloud(isFallback:)`).
    @Test func cloudFallbackIsNeverIndexZero_whenItFollowsOnDevice() {
        let plan = ProcessingEngine.organizeRoute(online: true, isPlus: false, hasAI: true)
        #expect(plan.firstIndex(of: .cloud) == 1, "Free-online cloud is the fallback, not the primary")
    }
}

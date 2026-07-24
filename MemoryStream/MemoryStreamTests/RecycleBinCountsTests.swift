import Testing
import Foundation
@testable import HiMem

/// Money tests for `RecycleBinCounts` — the single source of truth behind the
/// bin's per-tab count pills AND the Settings "Recently Deleted" badge
/// (2026-07-24). The badge bug: it showed memories-only, so a bin of 3 clips +
/// 1 memory read as "1".
@Suite
struct RecycleBinCountsTests {

    /// The exact reported bug: 3 clips + 1 memory must total 4, not 1.
    @Test func reportedBug_threeClipsOneMemory_unionIsFour() {
        let c = RecycleBinCounts(memories: 1, benchClips: 3, inboxClips: 0, projects: 0)
        #expect(c.all == 4)
        #expect(c.count(for: .all) == 4)
    }

    @Test func all_isUnionOfEveryType() {
        let c = RecycleBinCounts(memories: 2, benchClips: 3, inboxClips: 1, projects: 4)
        #expect(c.all == 10)
        #expect(c.count(for: .all) == 10)
    }

    /// "Clips" is bench + inbox recycled clips combined.
    @Test func clips_unionsBenchAndInbox() {
        let c = RecycleBinCounts(memories: 0, benchClips: 2, inboxClips: 5, projects: 0)
        #expect(c.clips == 7)
        #expect(c.count(for: .clips) == 7)
    }

    @Test func perType_countsMatchTheirTab() {
        let c = RecycleBinCounts(memories: 2, benchClips: 3, inboxClips: 1, projects: 4)
        #expect(c.count(for: .memories) == 2)
        #expect(c.count(for: .projects) == 4)
        #expect(c.count(for: .clips) == 4)   // 3 + 1
    }

    @Test func empty_isAllZero() {
        let c = RecycleBinCounts()
        #expect(c.all == 0)
        for f in RecycleBinFilter.allCases { #expect(c.count(for: f) == 0) }
    }
}

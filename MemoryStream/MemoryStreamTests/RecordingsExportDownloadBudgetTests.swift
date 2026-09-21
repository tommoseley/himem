import Testing
import Foundation
@testable import HiMem

/// **THE MONEY TEST for the device defect of 2026-09-21.**
///
/// Tom ran *Save a copy of your recordings* on a real library and got:
///
///     Saved 130 recordings. 108 couldn't be downloaded from iCloud
///     — try again when you're on Wi-Fi.
///
/// **He was on Wi-Fi, and iCloud was working.** The export had one shared
/// 90-second budget for the whole library; it expired while transfers were
/// still arriving, and the export reported the expiry as a result.
///
/// **A shared deadline does not scale with the thing it bounds.** The larger
/// the library, the smaller the fraction that can possibly arrive inside it —
/// so the defect grows with exactly the libraries most worth exporting, and
/// Judi's is the one this feature exists for. A per-file timeout scales with
/// the work instead, and the only global bound left is a ceiling large enough
/// that reaching it means something is genuinely wrong.
///
/// These run on an injected clock: no test sleeps, and `advance` makes the
/// passage of time the thing under test rather than a thing to wait out.
@Suite struct RecordingsExportDownloadBudgetTests {

    /// A library where file *i* finishes downloading at `i * step` seconds —
    /// iCloud delivering steadily, which is what was actually happening.
    private final class Cloud {
        private(set) var t: TimeInterval = 0
        private let step: TimeInterval
        private let arrival: [URL: TimeInterval]
        private(set) var requested: Set<URL> = []

        init(urls: [URL], step: TimeInterval) {
            self.step = step
            var a: [URL: TimeInterval] = [:]
            // `i + 1`, so nothing is already down at t=0 — otherwise the
            // first file is (correctly) never requested, and a test asserting
            // "every absent file is requested" fails on a file that was not
            // absent. That is what the first draft of this fixture did.
            for (i, u) in urls.enumerated() { a[u] = Double(i + 1) * step }
            self.arrival = a
        }
        func status(_ u: URL) -> UbiquityStore.DownloadStatus {
            guard let due = arrival[u] else { return .missing }
            return t >= due ? .downloaded : .notDownloaded
        }
        var io: RecordingsExport.IO {
            RecordingsExport.IO(
                status: { [unowned self] in self.status($0) },
                startDownload: { [unowned self] in self.requested.insert($0) },
                now: { [unowned self] in Date(timeIntervalSinceReferenceDate: self.t) },
                sleep: { [unowned self] d in self.t += d }
            )
        }
    }

    /// Real files on disk, so the copy the export performs is a real copy.
    private func library(_ n: Int) throws -> (dir: URL, recs: [RecordingsExport.Recording]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let recs = try (0..<n).map { i -> RecordingsExport.Recording in
            let url = dir.appendingPathComponent("clip-\(i).m4a")
            try Data("audio-\(i)".utf8).write(to: url)
            return RecordingsExport.Recording(
                id: UUID(), sourceURL: url, transcript: "thought number \(i)",
                capturedAt: base.addingTimeInterval(Double(i) * 60),
                placeName: nil, memoryIds: [])
        }
        return (dir, recs)
    }

    private func out() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("out-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - The money test

    /// Twenty recordings arriving ten seconds apart — 200 seconds of honest
    /// iCloud delivery. Under the old shared 90-second budget this saved nine.
    @Test("a steadily-delivering library exports completely, however long it takes")
    func steadyDeliveryExportsEverything() throws {
        let (dir, recs) = try library(20)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = Cloud(urls: recs.map(\.sourceURL), step: 10)
        let folder = out()
        defer { try? FileManager.default.removeItem(at: folder) }

        let outcome = try RecordingsExport.write(
            RecordingsExport.Snapshot(recordings: recs, memories: []),
            into: folder, perFileTimeout: 120, ceiling: 1800, io: cloud.io)

        #expect(outcome.savedCount == 20, """
            \(outcome.unavailableCount) of 20 recordings were reported as not \
            downloaded while iCloud was delivering every one of them. This is \
            the shared-budget defect: the export stopped waiting and called \
            that a result.
            """)
        #expect(outcome.unavailableCount == 0)
    }

    /// The whole library is requested before any copying begins, so iCloud can
    /// queue the set rather than being asked for one file at a time.
    @Test("every absent file is requested up front")
    func allDownloadsAreRequestedFirst() throws {
        let (dir, recs) = try library(8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = Cloud(urls: recs.map(\.sourceURL), step: 5)
        let folder = out()
        defer { try? FileManager.default.removeItem(at: folder) }

        _ = try RecordingsExport.write(
            RecordingsExport.Snapshot(recordings: recs, memories: []),
            into: folder, perFileTimeout: 120, ceiling: 1800, io: cloud.io)

        #expect(cloud.requested.count == 8, "a file nobody asked for will never arrive")
    }

    /// **The bound still exists.** One file that never arrives must cost its
    /// own timeout and no more — it must not consume the budget of the files
    /// after it, which is the failure mode in the other direction.
    @Test("one stuck file does not starve the rest")
    func aStuckFileDoesNotStarveTheOthers() throws {
        let (dir, recs) = try library(4)
        defer { try? FileManager.default.removeItem(at: dir) }
        // File 1 never arrives; the others are immediate.
        final class OneStuck {
            var t: TimeInterval = 0
            let stuck: URL
            init(stuck: URL) { self.stuck = stuck }
        }
        let box = OneStuck(stuck: recs[1].sourceURL)
        let io = RecordingsExport.IO(
            status: { $0 == box.stuck ? .notDownloaded : .downloaded },
            startDownload: { _ in },
            now: { Date(timeIntervalSinceReferenceDate: box.t) },
            sleep: { box.t += $0 })
        let folder = out()
        defer { try? FileManager.default.removeItem(at: folder) }

        let outcome = try RecordingsExport.write(
            RecordingsExport.Snapshot(recordings: recs, memories: []),
            into: folder, perFileTimeout: 30, ceiling: 1800, io: io)

        #expect(outcome.savedCount == 3, "the three readable files must all be copied")
        #expect(outcome.unavailableCount == 1)
        #expect(box.t >= 30, "the stuck file should have been waited for")
        #expect(box.t < 120, "…but only for its own timeout, not everyone's")
    }

    /// The ceiling is the one global bound, and it clamps a per-file wait
    /// rather than being ignored by it.
    @Test("the overall ceiling still stops a runaway export")
    func theCeilingClamps() throws {
        let (dir, recs) = try library(6)
        defer { try? FileManager.default.removeItem(at: dir) }
        final class Never { var t: TimeInterval = 0 }
        let box = Never()
        let io = RecordingsExport.IO(
            status: { _ in .notDownloaded },
            startDownload: { _ in },
            now: { Date(timeIntervalSinceReferenceDate: box.t) },
            sleep: { box.t += $0 })
        let folder = out()
        defer { try? FileManager.default.removeItem(at: folder) }

        let outcome = try RecordingsExport.write(
            RecordingsExport.Snapshot(recordings: recs, memories: []),
            into: folder, perFileTimeout: 60, ceiling: 100, io: io)

        #expect(outcome.savedCount == 0)
        #expect(outcome.unavailableCount == 6)
        #expect(box.t <= 110, "six files × 60s would be 360s; the ceiling must cut it short")
    }

    /// Progress is reported as it goes, because an export of a real library
    /// takes minutes and a bare spinner for minutes reads as a hang.
    @Test("progress is reported while it works")
    func progressIsReported() throws {
        let (dir, recs) = try library(5)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = Cloud(urls: recs.map(\.sourceURL), step: 0)
        let folder = out()
        defer { try? FileManager.default.removeItem(at: folder) }

        final class Seen { var ticks: [(Int, Int)] = [] }
        let seen = Seen()
        _ = try RecordingsExport.write(
            RecordingsExport.Snapshot(recordings: recs, memories: []),
            into: folder, perFileTimeout: 60, ceiling: 600, io: cloud.io,
            progress: { d, t in seen.ticks.append((d, t)) })

        #expect(seen.ticks.count >= 5)
        #expect(seen.ticks.allSatisfy { $0.1 == 5 }, "the total must be the library size throughout")
        #expect(seen.ticks.last?.0 == 5, "the last tick must report completion")
    }
}

import Testing
import Foundation
@testable import HiMem

/// **The no-clobber guarantee extends from summary to TITLE (ruled
/// 2026-08-01).**
///
/// F20 established for `entry.summary` that no automatic path writes it
/// — auto-organize creates an `OrganizePass` awaiting review, and every
/// actual write is user-driven. `SummaryAuthorshipTests` pins that,
/// deliberately, *because it is true by construction* and construction
/// is exactly what a future auto-accept would quietly change.
///
/// **The same holds for the title, and it is now pinned the same way.**
/// Verified 2026-08-01: every `entry.title = …` in production is
/// user-initiated —
///
///   • `OrganizePass.commitReorganize` under `titleChoice == .new`
///     (she chose the new title in the Reorganize review sheet)
///   • `DraftReviewSheet` acceptance (she accepted the draft)
///   • `EntryLifecycleService` (her own tap-to-edit)
///   • `CreateMemoryFromClipsSheet` / `PlaceClipSheet` (she named it at
///     creation)
///   • `SortBatchCommit` (she committed the batch)
///
/// **Difference from summary, stated rather than glossed:** there is no
/// `titleUserEdited` marker. Summary has one, so a future automatic path
/// *could* consult it; title has none, so this scanner is the only thing
/// standing between a user-authored title and an automatic overwrite.
/// That makes the guard load-bearing rather than belt-and-braces.
///
/// **Known, already-logged exception (C9):** `DraftReviewSheet` accepts
/// title + summary + topics + mentions in one action with no keep-mine
/// option, unlike `OrganizePass.accept`'s `.new`/`.current`. So a
/// user-authored title *can* be replaced by accepting a draft — but that
/// is user-initiated and under-informed, not an automatic overwrite. It
/// is deferred, not missed.
@Suite struct TitleAuthorshipTests {

    /// THE GUARD. Any `entry.title = …` outside a user-initiated file is
    /// an automatic path overwriting something she may have written.
    @Test func noAutomaticPathWritesTheTitle() throws {
        let offenders = try Self.titleWriteSites().filter { !Self.isUserInitiated($0.file) }
        #expect(
            offenders.isEmpty,
            """
            `entry.title` is written outside a user-initiated path:
            \(offenders.map { "  • \($0.file):\($0.line)" }.joined(separator: "\n"))

            Auto-organize must create an `OrganizePass` awaiting review, never \
            write the title. There is no `titleUserEdited` marker to fall back \
            on, so this scanner is the only guarantee.
            """
        )
    }

    /// Self-test — the scanner must SEE the known writers, or it is
    /// passing by matching nothing (the `loudPeakThenSilence` lesson).
    @Test func scannerSeesTheKnownWriteSites() throws {
        let files = Set(try Self.titleWriteSites().map(\.file))
        #expect(files.contains("OrganizePass.swift"),
                "The scanner cannot see `commitReorganize`'s title write — it would pass forever.")
        #expect(files.isEmpty == false)
    }

    // MARK: - Scanner

    struct WriteSite { let file: String; let line: Int }

    /// Files whose `entry.title` writes are user-initiated by definition.
    static func isUserInitiated(_ file: String) -> Bool {
        [
            "OrganizePass.swift",              // .new / .current review choice
            "DraftReviewSheet.swift",          // user accepts a draft
            "EntryLifecycleService.swift",     // her tap-to-edit
            "StorageService.swift",            // creation, with her input
            "CreateMemoryFromClipsSheet.swift",// she names it at creation
            "PlaceClipSheet.swift",            // she names it at placement
            "SortBatchCommit.swift"            // she commits the batch
        ].contains(file)
    }

    static func titleWriteSites() throws -> [WriteSite] {
        var out: [WriteSite] = []
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return out }
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard !url.path.contains("Tests") else { continue }
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (i, line) in src.components(separatedBy: "\n").enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), !t.hasPrefix("///") else { continue }
                // `entry.title = …`, but not the many unrelated `title`
                // properties (notifications, tutorial rows, nav titles).
                guard line.range(of: #"\bentry\.title\s*="#, options: .regularExpression) != nil
                else { continue }
                out.append(WriteSite(file: url.lastPathComponent, line: i + 1))
            }
        }
        return out
    }
}

import Testing
import Foundation
@testable import HiMem

/// F19b · **the user's summary is hers, and stays hers.**
///
/// Memory Detail now offers two doors to one field: she can write a summary, or
/// Organize can. The guarantee that makes that safe is that **no automatic path
/// writes `JournalEntry.summary`** — an organize pass produces an
/// `OrganizePass` awaiting review, and `renderedSummary` reads the stored
/// summary FIRST, so her words keep rendering while a draft sits unaccepted.
///
/// That guarantee is currently true **by construction** rather than by a check:
/// every write to `entry.summary` is user-initiated (accepting a review,
/// accepting a draft, or her own tap-to-edit). Construction is exactly what a
/// future auto-accept would quietly change, so it is pinned here.
///
/// *Provenance note (2026-07-31): an earlier report claimed the Plus
/// auto-organize path silently overwrote user summaries. It does not — that was
/// read off a stale doc comment ("gates the auto-pass-no-clobber rule") instead
/// of the call sites, and retracted. This suite pins what is actually true so
/// the next reader doesn't have to re-derive it from comments.*
@Suite
struct SummaryAuthorshipTests {

    /// THE STRUCTURAL GUARANTEE. Only user-initiated code paths may assign
    /// `entry.summary`. If a new automatic writer appears, this fails and the
    /// two-doors model needs a real no-clobber gate before it ships.
    @Test func noAutomaticPathWritesTheSummary() throws {
        let offenders = try Self.summaryWriteSites().filter { !Self.isUserInitiated($0.file) }
        #expect(
            offenders.isEmpty,
            """
            A non-user-initiated path assigns `entry.summary`:
            \(offenders.map { "  • \($0.file):\($0.line)" }.joined(separator: "\n"))

            Her summary must survive an organize pass. An organize pass produces a \
            draft for review; it does not overwrite. If this write is intended, it \
            needs a no-clobber gate keyed on `summaryUserEdited` first.
            """
        )
    }

    /// The known-good writers, so the guard proves it can see writes at all
    /// rather than silently matching nothing.
    @Test func scannerSeesTheKnownWriteSites() throws {
        let files = Set(try Self.summaryWriteSites().map(\.file))
        #expect(!files.isEmpty, "scanner found no summary writes — it is not scanning")
        #expect(files.contains("EntryLifecycleService.swift"),
                "the user's own tap-to-edit is a summary write and must be visible to this scan")
    }

    // MARK: - Scanner

    struct WriteSite { let file: String; let line: Int }

    /// Files whose `entry.summary` writes are user-initiated by definition:
    /// the review flow, the draft-accept sheet, the user's inline edit, and the
    /// one-time backfill (which only copies an already-ACCEPTED pass).
    static func isUserInitiated(_ file: String) -> Bool {
        [
            "OrganizePass.swift",            // .new / .current review choice
            "DraftReviewSheet.swift",        // user accepts a draft
            "EntryLifecycleService.swift",   // her tap-to-edit
            "SummaryFieldMigration.swift"    // backfill of already-accepted text
        ].contains(file)
    }

    static func summaryWriteSites() throws -> [WriteSite] {
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
                // `entry.summary = …` / `self.summary = …`, but not
                // `summaryUserEdited` or `inferenceSummary`.
                guard line.range(of: #"\.summary\s*="#, options: .regularExpression) != nil else { continue }
                guard !line.contains("summaryUserEdited"), !line.contains("inferenceSummary") else { continue }
                out.append(WriteSite(file: url.lastPathComponent, line: i + 1))
            }
        }
        return out
    }
}

import Testing
import Foundation
@testable import HiMem

/// **"Save a copy of your recordings"** — the export ruled 2026-09-21.
///
/// The pure halves: how a recording is named on disk, and what the completion
/// state says. Both are testable without a filesystem, which is why they were
/// written as pure functions rather than inline in the view.
@Suite struct RecordingsExportTests {

    /// **Local time, not UTC** — and the test says so because the first draft
    /// did not. A filename answers *when did I record this*, which is a local
    /// question; the exporter formats in the device's zone. Built from
    /// components here so the assertions hold wherever this runs, rather than
    /// passing only in the zone they were written in.
    ///
    /// The one fidelity limit, recorded rather than hidden: we do not store a
    /// capture timezone, so a recording made abroad is named in the zone the
    /// export runs in. Same behaviour as the stock photo apps, and the only
    /// option the schema allows.
    private static func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    private static var stampOf: (Date) -> String = { date in
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    private static let caf = URL(fileURLWithPath: "/x/abc.caf")

    // MARK: - Naming

    @Test("a recording is named so it means something in Finder")
    func nameCarriesTimeAndWords() {
        let name = RecordingsExport.exportName(
            capturedAt: Self.at(2026, 8, 14, 14, 32),
            transcript: "The pears were really good this year, better than last",
            sourceURL: Self.caf)
        #expect(name.hasSuffix(".caf"), "the source extension must survive — a .caf renamed .m4a will not open")
        #expect(name.contains("2026-08-14"))
        #expect(name.contains("The pears were really good"))
        #expect(!name.contains("better than last"), "six words, not the whole transcript")
    }

    /// A recording that transcribed to silence is still hers, and still gets
    /// copied — under its timestamp alone rather than being skipped.
    @Test("a silent recording still gets a name")
    func silenceStillExports() {
        let when = Self.at(2026, 8, 14, 14, 32)
        let name = RecordingsExport.exportName(capturedAt: when, transcript: "", sourceURL: Self.caf)
        #expect(name == "\(Self.stampOf(when)).caf")
        #expect(name == "2026-08-14 1432.caf", "local-time stamp — fails only if the machine's zone shifts the date")
    }

    @Test("path separators never reach a filename")
    func illegalCharactersAreStripped() {
        let words = RecordingsExport.firstWords("re/marks: on 9/11 and c:\\temp")
        #expect(!words.contains("/"))
        #expect(!words.contains(":"))
        #expect(!words.contains("\\"))
        #expect(!words.isEmpty, "stripping must not empty a transcript that had usable words")
    }

    @Test("a long opening word cannot blow the filename limit")
    func nameIsBounded() {
        let words = RecordingsExport.firstWords(String(repeating: "a", count: 500))
        #expect(words.count <= 60)
    }

    /// **Two recordings in the same minute with the same opening words would
    /// otherwise overwrite each other** — one file where there should be two,
    /// and no error to notice, which is the shape of silent data loss this
    /// whole export exists to prevent.
    @Test("colliding names disambiguate instead of overwriting")
    func collisionsAreDisambiguated() {
        let when = Self.at(2026, 8, 14, 14, 32)
        let recs = (0..<3).map { _ in
            RecordingsExport.Recording(id: UUID(), sourceURL: Self.caf, transcript: "same words here",
                                       capturedAt: when, placeName: nil, memoryIds: [])
        }
        let names = RecordingsExport.assignNames(recs)
        #expect(names.count == 3)
        #expect(Set(names.values).count == 3, "three recordings must produce three distinct files")
    }

    @Test("naming is deterministic across runs")
    func namingIsStable() {
        let recs = (0..<5).map { i in
            RecordingsExport.Recording(id: UUID(), sourceURL: Self.caf, transcript: "note \(i)",
                                       capturedAt: Self.at(2026, 8, 14, 14, 32), placeName: nil, memoryIds: [])
        }
        #expect(RecordingsExport.assignNames(recs) == RecordingsExport.assignNames(recs.reversed()))
    }

    // MARK: - The completion state

    @Test("a clean run reports the count")
    func cleanRunCopy() {
        #expect(RecordingsExport.completionMessage(savedCount: 84, unavailableCount: 0) == "Saved 84 recordings.")
        #expect(RecordingsExport.completionMessage(savedCount: 1, unavailableCount: 0) == "Saved 1 recording.")
    }

    /// **The ruled sentence.** Pinned close to the literal because here the
    /// wording *is* the promise (CLAUDE.md § Assert the Meaning, second
    /// bullet): it must name how many were missed, say why, and say what to do
    /// about it. A rewording that kept all three would pass; one that dropped
    /// the remedy would not.
    @Test("an incomplete run says what it missed and what to do")
    func incompleteRunCopy() {
        let msg = RecordingsExport.completionMessage(savedCount: 84, unavailableCount: 3)
        #expect(msg.contains("Saved 84 recordings."))
        #expect(msg.contains("3 couldn't be downloaded from iCloud"))
        #expect(msg.contains("try again when you're on Wi-Fi"), "the remedy is the point — never report the shortfall alone")
    }

    /// **Never "failed".** A recording iCloud has not brought down is a thing
    /// that needs Wi-Fi, not a fault, and the difference is whether she thinks
    /// her recordings are damaged. Tom, 2026-09-21.
    @Test("no outcome is ever described as a failure")
    func neverSaysFailed() {
        for (s, u) in [(84, 3), (0, 12), (5, 0), (0, 0), (1, 1)] {
            let msg = RecordingsExport.completionMessage(savedCount: s, unavailableCount: u).lowercased()
            #expect(!msg.contains("fail"), "\(s)/\(u) reported a failure: \(msg)")
            #expect(!msg.contains("error"), "\(s)/\(u) reported an error: \(msg)")
            #expect(!msg.contains("unable"), "\(s)/\(u) reported an inability: \(msg)")
        }
    }

    @Test("singulars are not pluralised")
    func singularCopy() {
        let msg = RecordingsExport.completionMessage(savedCount: 1, unavailableCount: 1)
        #expect(msg.contains("Saved 1 recording."))
        #expect(msg.contains("1 couldn't be downloaded"))
        #expect(!msg.contains("1 recordings"))
    }

    @Test("an empty library says so rather than claiming a save")
    func emptyCopy() {
        #expect(RecordingsExport.completionMessage(savedCount: 0, unavailableCount: 0)
                == "There are no recordings to save.")
    }
}

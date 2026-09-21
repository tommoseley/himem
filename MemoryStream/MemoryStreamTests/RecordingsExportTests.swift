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

    /// **The ruled sentence, corrected 2026-09-21 after it said something
    /// false on a device.** The first version reported *"108 couldn't be
    /// downloaded from iCloud — try again when you're on Wi-Fi"* to someone
    /// who was on Wi-Fi.
    @Test("an incomplete run says what happened and what to do")
    func incompleteRunCopy() {
        let msg = RecordingsExport.completionMessage(savedCount: 22, unavailableCount: 108)
        #expect(msg == "Saved 22 of 130 recordings. The rest are still in iCloud and haven't come down yet — run this again in a few minutes.")
    }

    /// **The count must be OF the total, not a bare saved figure.** The
    /// device report read *"Saved 130 recordings. 108 couldn't…"* — two
    /// numbers that do not obviously belong to one set, so it scans as
    /// 130 successes plus 108 problems rather than 130 of 238 done.
    @Test("the saved count is framed against the total")
    func savedIsFramedAgainstTheTotal() {
        let msg = RecordingsExport.completionMessage(savedCount: 130, unavailableCount: 108)
        #expect(msg.hasPrefix("Saved 130 of 238 recordings."))
    }

    /// **THE MONEY TEST for the copy defect.** A completion line may report
    /// what happened and what to do; it may not diagnose WHY. The app can see
    /// that a file has not arrived and nothing more — every cause it could
    /// name is a guess, and the guess it made was wrong.
    @Test("the copy never asserts a cause")
    func theCopyNeverAssertsACause() {
        for (s, u) in [(22, 108), (0, 130), (130, 108), (1, 1), (5, 0), (0, 0), (0, 1)] {
            let msg = RecordingsExport.completionMessage(savedCount: s, unavailableCount: u).lowercased()
            for banned in ["wi-fi", "wifi", "offline", "connection", "network", "signal"] {
                #expect(!msg.contains(banned),
                        "\(s)/\(u) diagnosed the cause with \"\(banned)\": \(msg)")
            }
        }
    }

    /// **Never "failed".** A recording iCloud has not handed over yet is not
    /// damaged, and the difference is whether she thinks her memories are
    /// gone. Tom, 2026-09-21.
    @Test("no outcome is ever described as a failure")
    func neverSaysFailed() {
        for (s, u) in [(84, 3), (0, 12), (5, 0), (0, 0), (1, 1), (22, 108)] {
            let msg = RecordingsExport.completionMessage(savedCount: s, unavailableCount: u).lowercased()
            #expect(!msg.contains("fail"), "\(s)/\(u) reported a failure: \(msg)")
            #expect(!msg.contains("error"), "\(s)/\(u) reported an error: \(msg)")
            #expect(!msg.contains("unable"), "\(s)/\(u) reported an inability: \(msg)")
        }
    }

    /// Every incomplete outcome must name the action that actually works.
    @Test("an incomplete run always offers the retry")
    func incompleteAlwaysOffersTheRetry() {
        for (s, u) in [(22, 108), (0, 130), (1, 1), (0, 1)] {
            let msg = RecordingsExport.completionMessage(savedCount: s, unavailableCount: u)
            #expect(msg.contains("run this again"),
                    "\(s)/\(u) reported a shortfall with no action: \(msg)")
        }
    }

    /// Nothing arrived at all: "the rest" has no referent, and "Saved 0 of
    /// 130" reads as a failure report rather than a wait.
    @Test("a run that got nothing still reads as waiting, not failing")
    func nothingArrivedCopy() {
        #expect(RecordingsExport.completionMessage(savedCount: 0, unavailableCount: 130)
                == "Your 130 recordings are still in iCloud and haven't come down yet — run this again in a few minutes.")
        #expect(RecordingsExport.completionMessage(savedCount: 0, unavailableCount: 1)
                == "Your recording is still in iCloud and hasn't come down yet — run this again in a few minutes.")
    }

    @Test("singulars are not pluralised")
    func singularCopy() {
        #expect(RecordingsExport.completionMessage(savedCount: 1, unavailableCount: 0) == "Saved 1 recording.")
        #expect(!RecordingsExport.completionMessage(savedCount: 1, unavailableCount: 1).contains("1 recordings"))
    }

    @Test("an empty library says so rather than claiming a save")
    func emptyCopy() {
        #expect(RecordingsExport.completionMessage(savedCount: 0, unavailableCount: 0)
                == "There are no recordings to save.")
    }
}

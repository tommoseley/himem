import Testing
import Foundation
@testable import HiMem

/// **B17 — the cluster card contradicted itself, and a placeholder was becoming
/// a memory's name.**
///
/// Ruled 2026-08-18 (Tom).
///
/// **(a) The title asserted what the card only proposes.** A time+place cluster
/// was named `"Together at Sun 5:44 PM"` and drawn in the card's largest type,
/// one line under the eyebrow `MIGHT GO TOGETHER` and just above an observation
/// ("3 clips from 3 sittings · 30 minutes apart"). J5's line — *observe, don't
/// conclude* — crossed by the surface's own chrome rather than by the AI, and
/// one line above where F42 had already softened "seem to belong together".
/// Now `"Sun 5:44 PM"`: the observation without the verdict.
///
/// **(b) A proposal must not name the memory it becomes.** Spec §74 had the
/// proposed name become the committed memory's title, so a placeholder the code
/// itself called neutral ("a later Plus pass can produce better names") would
/// have become what the user sees in their Memory Box forever. A memory made
/// from a proposal now **arrives untitled**, for Organize or the user to name.
///
/// Word-match clusters are covered by the same rule: "Sparrow Quarry" reads
/// like a fine title, which is precisely why the rule is about *provenance*
/// rather than about how good a given string looks.
struct ProposalNamingTests {

    private func clip(at time: Date, _ transcript: String, lat: Double?, lon: Double?) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: time,
            duration: 30,
            transcript: transcript,
            latitude: lat,
            longitude: lon,
            source: "watch",
            audioFilename: "\(UUID()).caf",
            transcriptionAttempted: true,
            rollGroupId: nil
        )
    }

    /// A time+place cluster names the window it observed — and nothing more.
    ///
    /// **Pinned as a literal absence**, per *Assert the Meaning, Not the
    /// Phrasing*: the retired word IS the subject of the rule, so a failure
    /// reads as "the verdict came back", not "someone reworded a label".
    @Test
    func aTimePlaceClusterNamesTheWindowWithoutAssertingTheGrouping() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let sessions = [
            ClipGroup(clips: [clip(at: base, "first", lat: 40.0, lon: -75.0)]),
            ClipGroup(clips: [clip(at: base.addingTimeInterval(600), "second", lat: 40.0001, lon: -75.0001)]),
        ]

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: sessions)

        #expect(proposals.count == 1, "self-test: the fixture must actually cluster, or this guard asserts nothing")
        let name = proposals[0].proposedName
        #expect(
            !name.lowercased().contains("together"),
            "The card's largest type must not assert the grouping its own eyebrow calls 'might go together' — got \"\(name)\""
        )
        #expect(
            name.contains("AM") || name.contains("PM"),
            "The observation itself must survive: the name states the capture window — got \"\(name)\""
        )
    }

    /// **(b) No path may name a memory from a proposal.**
    ///
    /// A behavioural test cannot reach this: the live path is a private method
    /// on `SessionListView` building a `BundleRequest`, and the other site is
    /// `SortBatchCommit`, which currently has **zero production callers**. A
    /// mechanical source assertion is the honest instrument here — anchored on
    /// the real files, self-tested against a known offending shape, and
    /// throwing if the walk reaches no source so it cannot pass by matching
    /// nothing.
    ///
    /// The dead path is guarded deliberately: `SortBatchCommit` is complete and
    /// tested with no caller (the `UnifiedBenchGrouper` / `MediaBlobOrphanSweep`
    /// shape), and an unreachable file that still assigns the title is exactly
    /// how a retired behaviour returns when someone revives it.
    @Test
    func noPathNamesAMemoryFromAProposal() throws {
        let files = try Self.sources(named: [
            "Views/Inbox/SessionListView.swift",
            "Services/Storage/SortBatchCommit.swift",
        ])

        // Self-test: the scanner must recognise the shape it is looking for, or
        // a clean report means nothing.
        let knownOffender = "entry.title = proposal.proposedName"
        #expect(Self.namesAMemory(knownOffender), "self-test: the matcher must flag the known offending shape")
        #expect(!Self.namesAMemory("let x = proposal.proposedName // rendered on the card"), "self-test: reading the name for display is not naming a memory")

        for (path, source) in files {
            let offenders = source
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .filter { Self.namesAMemory($0) }
            #expect(
                offenders.isEmpty,
                "\(path) names a memory from a proposal — a memory made from a proposal arrives untitled so Organize or the user names it: \(offenders.map { $0.trimmingCharacters(in: .whitespaces) })"
            )
        }
    }

    /// Title-assignment shapes: `entry.title = …proposedName` and
    /// `prefillTitle: …proposedName`. Reading `proposedName` for display is not
    /// one of them.
    private static func namesAMemory(_ line: String) -> Bool {
        guard line.contains("proposedName") else { return false }
        return line.contains("title =") || line.contains("prefillTitle:")
    }

    private static func sources(named relativePaths: [String]) throws -> [(String, String)] {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let root = dir.appendingPathComponent("MemoryStream")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePaths[0]).path) {
                return try relativePaths.map {
                    ($0, try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8))
                }
            }
            dir = dir.deletingLastPathComponent()
        }
        throw SourceNotFound()
    }

    private struct SourceNotFound: Error, CustomStringConvertible {
        var description: String {
            "The scanned sources were not found — this guard proves nothing when it cannot read them, so it fails rather than passing vacuously"
        }
    }
}

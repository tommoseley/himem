import Testing
import Foundation
@testable import HiMem

/// **Does the seed actually produce the shapes it claims?**
///
/// The fixtures exist to unblock F37/F41/F43/F44 on device, and every one of
/// them depends on `ClipClusterProposer` accepting the seeded transcripts. The
/// bigram rule rejects pairs made of common content words, so a plausible-
/// sounding place name can silently fail to cluster — and the failure surfaces
/// as "no Sort proposal appeared", which reads on device as *the bench being
/// broken* rather than as a bad fixture. That is a wrong diagnosis handed to
/// whoever runs the pass.
///
/// These are cheap and they run the **real** proposer over the **real** seed
/// text, so the seed cannot ship claiming a cluster it does not create.
/// **`.serialized` because `ClipClusterProposer` reaches
/// `LocalEntityExtractor.shared`**, which wraps a non-thread-safe `NLTagger`
/// (`CLAUDE.md` § Test Concurrency and Shared Singletons). Swift Testing runs
/// a suite's tests in parallel by default, and every test here calls the
/// proposer — the first run crashed **four of five with `signal segv`**, which
/// is that singleton, not the fixtures.
///
/// Recorded because it is also live evidence for **B14**, which flagged the
/// same singleton as reachable from a main-thread render path on
/// circumstantial grounds only. It is now demonstrated to crash under
/// concurrent entry.
@Suite(.serialized) struct QAFixtureSeederTests {

    /// Each cluster's three sittings must produce exactly one proposal, and it
    /// must claim all three.
    @Test func eachSeededClusterActuallyClusters() {
        for cluster in Self.seededClusters {
            let name = cluster.name
            let sessions = Self.sessions(Self.clips(for: cluster))
            let proposals = ClipClusterProposer.propose(sessions: sessions, dismissed: [])
            #expect(proposals.count == 1,
                    """
                    “\(name)” produced \(proposals.count) proposals, not 1. The seed would put \
                    clips on the bench with no Sort card, and the device pass would read that \
                    as the bench failing rather than as a fixture that never clustered.
                    """)
            #expect(proposals.first?.clipIds.count == 3,
                    "“\(name)” clustered \(proposals.first?.clipIds.count ?? 0) of 3 clips")
        }
    }

    /// **The clusters must not merge.** They are seeded together, so a bigram
    /// or proper noun shared across two of them would collapse them into one
    /// proposal — and F43's endpoint check and F44's mixed-kinds check would
    /// then be running against a shape nobody designed.
    ///
    /// This is the failure the marker text was written around: the natural
    /// temptation is to end every seeded transcript with the same phrase, which
    /// is exactly how a shared bigram gets introduced.
    @Test func theSeededClustersDoNotMergeIntoOne() {
        let all = Self.seededClusters.flatMap(Self.clips(for:))
        let proposals = ClipClusterProposer.propose(sessions: Self.sessions(all), dismissed: [])
        #expect(proposals.count == Self.seededClusters.count,
                """
                \(Self.seededClusters.count) seeded clusters collapsed into \(proposals.count). \
                Something is shared across their transcripts — a bigram or a proper noun — so \
                the fixtures are not the shapes the checks need.
                """)
    }

    /// The loose session's text must attract no proposal at all, or F37 has no
    /// loose session to check and the fully-clustered case is unreachable from
    /// the other direction.
    @Test func theLooseSessionStaysLoose() {
        // The loose fixture carries NO coordinate, so the time+place rule
        // cannot reach it however close in time it lands.
        let looseClip = Self.clip(
            text: Self.looseLine,
            at: Self.now.addingTimeInterval(-10 * 3600),
            coordinate: nil
        )
        let all = Self.seededClusters.flatMap(Self.clips(for:)) + [looseClip]
        let proposals = ClipClusterProposer.propose(sessions: Self.sessions(all), dismissed: [])
        let clustered = Set(proposals.flatMap(\.clipIds))
        #expect(clustered.contains(looseClip.clipId) == false,
                "the loose session was swept into a cluster, so F37 has nothing to check")
    }

    /// The QA marker must not itself become the clustering signal. `"QA"` is
    /// two characters so it cannot start a bigram, and the trailing digit is
    /// not alphabetic — but that is a property worth pinning rather than
    /// re-deriving, because the obvious edit (a wordier marker) breaks it.
    @Test func theMarkerTextIsNotWhatClusters() {
        // Same marker, deliberately unrelated subjects: nothing should cluster.
        // No coordinates, so only the word rules can fire — which is what
        // isolates the marker. With a shared place the time+place rule
        // clusters these regardless of their words, and this test would be
        // measuring that instead.
        let lines = [
            "Completely unrelated thought about breakfast — QA fixture 1",
            "Another separate idea about the garden hose — QA fixture 2",
            "A third unconnected remark on parking — QA fixture 3",
        ]
        let unrelated = lines.enumerated().map { i, text in
            Self.clip(text: text,
                      at: Self.now.addingTimeInterval(Double(-i) * 15 * 60),
                      coordinate: nil)
        }
        let proposals = ClipClusterProposer.propose(sessions: Self.sessions(unrelated), dismissed: [])
        #expect(proposals.isEmpty,
                """
                The QA marker is clustering these on its own, so every seeded cluster is \
                really one cluster wearing three names.
                """)
    }

    /// **The media must land in the sitting the seed intends**, or F43's photo
    /// check and F44's three-numbers check are aimed at the wrong card.
    ///
    /// This is arithmetic against `UnifiedBenchGrouper`'s ≤10-minute adjacency,
    /// and arithmetic I was confident about — which is the reason to check it.
    /// The offsets below mirror the seeder exactly.
    @Test func seededMediaLandsInTheIntendedSitting() {
        // Cluster B: photo 2 min after the OLDEST of three clips 15 min apart.
        let bBase = Self.now.addingTimeInterval(-3 * 3600)
        let bOldest = bBase.addingTimeInterval(-2 * 15 * 60)
        let bItems = [
            Self.item(.voice, bBase),
            Self.item(.voice, bBase.addingTimeInterval(-15 * 60)),
            Self.item(.voice, bOldest),
            Self.item(.image, bOldest.addingTimeInterval(120)),
        ]
        let bSessions = UnifiedBenchGrouper.group(bItems)
        let bPhotoSession = bSessions.first { $0.items.contains { $0.kind == .image } }
        #expect(bPhotoSession?.items.count == 2,
                "Cluster B's photo did not join the oldest sitting — F43's photo check would target the wrong card")

        // Cluster C: photo +3 min and note +5 min after the NEWEST clip.
        let cBase = Self.now.addingTimeInterval(-6 * 3600)
        let cItems = [
            Self.item(.voice, cBase),
            Self.item(.voice, cBase.addingTimeInterval(-15 * 60)),
            Self.item(.voice, cBase.addingTimeInterval(-30 * 60)),
            Self.item(.image, cBase.addingTimeInterval(180)),
            Self.item(.note, cBase.addingTimeInterval(300)),
        ]
        let cMixed = UnifiedBenchGrouper.group(cItems).first {
            $0.items.contains { $0.kind == .image }
        }
        #expect(cMixed?.items.count == 3,
                "Cluster C's photo and note did not join the newest sitting — F44 needs all three kinds on one card")
        #expect(cMixed?.hasVoice == true, "the mixed sitting has no voice, so this surface would not draw it at all")

        // Loose session: voice, photo +2 min, note +4 min — one sitting of 3.
        let lBase = Self.now.addingTimeInterval(-9 * 3600)
        let loose = UnifiedBenchGrouper.group([
            Self.item(.voice, lBase),
            Self.item(.image, lBase.addingTimeInterval(120)),
            Self.item(.note, lBase.addingTimeInterval(240)),
        ])
        #expect(loose.count == 1 && loose[0].items.count == 3,
                "the loose fixture is not one sitting of three — F37's 'every count says 3' has nothing to check")
    }

    static func item(_ kind: BenchClipItem.Kind, _ at: Date) -> BenchClipItem {
        BenchClipItem(id: UUID(), kind: kind, capturedAt: at, rollGroupId: nil)
    }

    /// **Why the fixtures carry no location — the mechanism, pinned.**
    ///
    /// Device 2026-08-12: Cluster A drew "2 clips from 2 sittings" over a
    /// 3-clip seed. Reproduced here. When the seed carried coordinates, one
    /// member whose session coordinate did not match its siblings dropped out
    /// of the timePlace cluster — and the word-match proposal covering all
    /// three was then discarded by the ≥50 % overlap dedup, because timePlace
    /// (Tier 2) had already claimed two of its members. **Word-match cannot
    /// rescue what timePlace has half-taken.**
    ///
    /// Kept as a guard rather than deleted with the fix: it documents *why*
    /// the fixtures are location-free, so restoring a coordinate "for realism"
    /// fails here instead of silently reshaping the fixtures on device.
    ///
    /// Deliberately `== 2`: this asserts the hazard is real, not that it is
    /// desired. `probe_seededTextClustersOnWordMatchAlone` asserts the escape.
    @Test func aMismatchedCoordinateHalfTakesTheClusterAndWordMatchCannotRescueIt() {
        let cluster = Self.seededClusters[0]
        // Re-apply coordinates to two of three, as the earlier seed did, then
        // leave the third without — the contaminated-session shape.
        var clips = Self.clips(for: cluster).map { c in
            InboxClip(clipId: c.clipId, capturedAt: c.capturedAt, duration: c.duration,
                      transcript: c.transcript, latitude: 32.2371, longitude: -80.8557,
                      source: c.source, audioFilename: c.audioFilename,
                      transcriptionAttempted: true, rollGroupId: nil, status: .transcribed)
        }
        let oldest = clips[2]
        clips[2] = InboxClip(
            clipId: oldest.clipId, capturedAt: oldest.capturedAt, duration: oldest.duration,
            transcript: oldest.transcript, latitude: nil, longitude: nil,
            source: oldest.source, audioFilename: oldest.audioFilename,
            transcriptionAttempted: true, rollGroupId: nil, status: .transcribed
        )
        let proposals = ClipClusterProposer.propose(sessions: Self.sessions(clips), dismissed: [])
        let claimed = proposals.first?.clipIds.count ?? 0
        #expect(claimed == 2 && proposals.first?.ruleTag == .timePlace,
                """
                The hazard this fixture design avoids has changed shape: \(claimed) of 3 \
                clustered under rule=\(proposals.first?.ruleTag.rawValue ?? "none"). If \
                mismatched coordinates no longer half-take a cluster, the location-free \
                fixtures may no longer be necessary — re-derive before changing them.
                """)
    }

    /// **The escape, and the property the fixtures now rely on.** With no
    /// location the timePlace rule cannot fire at all, so each cluster forms
    /// on its distinctive place name alone — deterministic, and immune to
    /// whatever the user happens to capture nearby.
    @Test func seededTextClustersOnWordMatchAlone() {
        for cluster in Self.seededClusters {
            let stripped = Self.clips(for: cluster).map { c in
                InboxClip(clipId: c.clipId, capturedAt: c.capturedAt, duration: c.duration,
                          transcript: c.transcript, latitude: nil, longitude: nil,
                          source: c.source, audioFilename: c.audioFilename,
                          transcriptionAttempted: true, rollGroupId: nil, status: .transcribed)
            }
            let proposals = ClipClusterProposer.propose(sessions: Self.sessions(stripped), dismissed: [])
            #expect(proposals.count == 1 && proposals[0].clipIds.count == 3,
                    "“\(cluster.name)” without coords: \(proposals.count) proposals, \(proposals.first?.clipIds.count ?? 0)/3 clips, rule=\(proposals.first?.ruleTag.rawValue ?? "none")")
        }
    }

    // MARK: - Fixtures mirrored from the seeder
    //
    // Duplicated deliberately: the seeder is `#if DEBUG` *and* `@MainActor`
    // and writes files and Core Data rows, none of which this needs. What
    // matters is that the TEXT is identical, so a drift here is a real risk —
    // `theSeedTextMatchesTheSeeder` pins it against the source.

    /// Mirrors the seeder's real layout — **including the hours between
    /// clusters and the per-cluster coordinate**, both of which are
    /// load-bearing. The first version of this suite flattened all nine lines
    /// to 15-minute spacing at one shared location, which made
    /// `proposeTimePlace` merge everything and reported a fixture defect that
    /// was really a harness defect. A harness that does not mirror the thing
    /// it verifies produces confident wrong answers.
    struct Cluster {
        let name: String
        /// Hours before "now" — clusters are far enough apart that the
        /// time+place rule cannot reach across them.
        let hoursAgo: Double
        let coordinate: (lat: Double, lon: Double)?
        let lines: [String]
    }

    static let seededClusters: [Cluster] = [
        Cluster(name: "Harbor Lantern", hoursAgo: 1, coordinate: nil, lines: [
            "Walking past Harbor Lantern before the tide turned — QA fixture 1",
            "Second pass by Harbor Lantern, quieter now — QA fixture 2",
            "Last look at Harbor Lantern on the way back — QA fixture 3",
        ]),
        Cluster(name: "Sparrow Quarry", hoursAgo: 4, coordinate: nil, lines: [
            "Notes from Sparrow Quarry, north face in shadow — QA fixture 4",
            "More from Sparrow Quarry after the climb — QA fixture 5",
            "Leaving Sparrow Quarry as the light went — QA fixture 6",
        ]),
        Cluster(name: "Thistle Beacon", hoursAgo: 7, coordinate: nil, lines: [
            "Thistle Beacon from the lower path — QA fixture 7",
            "Halfway up to Thistle Beacon now — QA fixture 8",
            "At Thistle Beacon, wind off the water — QA fixture 9",
        ]),
    ]

    static let looseLine = "Just thinking out loud about the week ahead — QA fixture 10"

    /// Every line above must appear verbatim in the seeder, or these tests
    /// bless text the device never sees.
    @Test func theSeedTextMatchesTheSeeder() throws {
        let src = try Self.source("MemoryStream/Services/Storage/QAFixtureSeeder.swift")
        for line in Self.seededClusters.flatMap(\.lines) + [Self.looseLine] {
            #expect(src.contains(line),
                    """
                    This suite verifies clustering for a line the seeder does not contain:
                    \(line)
                    The fixtures on device are therefore unverified.
                    """)
        }
    }

    static let now = Date(timeIntervalSince1970: 1_785_000_000)

    /// One cluster's clips, laid out exactly as the seeder lays them: 15
    /// minutes apart (past the 10-minute idle gap → one sitting each), at the
    /// cluster's own coordinate, `hoursAgo` before now.
    static func clips(for cluster: Cluster) -> [InboxClip] {
        let base = now.addingTimeInterval(-cluster.hoursAgo * 3600)
        return cluster.lines.enumerated().map { i, text in
            clip(text: text,
                 at: base.addingTimeInterval(Double(-i) * 15 * 60),
                 coordinate: cluster.coordinate)
        }
    }

    static func clip(text: String, at when: Date, coordinate: (lat: Double, lon: Double)?) -> InboxClip {
        InboxClip(
            clipId: UUID(),
            capturedAt: when,
            duration: 2,
            transcript: text,
            latitude: coordinate?.lat,
            longitude: coordinate?.lon,
            source: "phone",
            audioFilename: "seed-\(UUID().uuidString).caf",
            transcriptionAttempted: true,
            rollGroupId: nil,
            status: .transcribed
        )
    }

    static func sessions(_ clips: [InboxClip]) -> [ClipGroup] {
        ClipSessionGrouper.group(clips)
    }

    static func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        guard let src = try? String(contentsOf: url, encoding: .utf8), !src.isEmpty else {
            throw Failure.sourceNotFound(url.path)
        }
        return src
    }

    enum Failure: Error { case sourceNotFound(String) }
}

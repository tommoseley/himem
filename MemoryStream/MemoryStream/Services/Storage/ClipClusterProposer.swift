import Foundation

/// Pure/deterministic Sort proposer for the Captured Clips
/// workbench. Given the current loose sessions + the set of
/// dismissed fingerprints, emits confident cluster proposals per
/// `docs/design/Captured Clips · session-first · spec.md`
/// v3 § "Clustering is Honest-Label, and tiered."
///
/// **Rules (v1, Free / on-device):**
///  * **Time+place** — sessions within `timeWindowSeconds`
///    AND within `proximityMeters`. Location is a **hard
///    requirement** (spec § 81) — no clustering on time alone.
///    Any session without coords is skipped for this rule.
///  * **Word-match** — distinctive-token rule (spec § 82).
///    Landing in a later slice (`Phase 2C`).
///
/// **Honest-Label discipline:** only clusters we're confident about.
/// A blank suggestions area is honest; a confident wrong grouping
/// erodes trust in every card. Under-suggest.
///
/// **Idempotent + stateless.** Same input always produces the same
/// output. Dismissed fingerprints are filtered out — the caller
/// owns that store (see `InboxManifest.dismissedClusterFingerprints`
/// in Phase 2D).
enum ClipClusterProposer {

    // MARK: - Tunable gates (v1 first-cut, dogfood-tunable)

    /// Time window for the time+place rule. Two sessions must
    /// start within this of each other to cluster. Spec § 81
    /// first-cut: ~90 min. Bigger risks blobbing into "all-day
    /// clusters"; smaller misses two-course dinners with a
    /// mid-meal break.
    static let timePlaceWindowSeconds: TimeInterval = 90 * 60

    /// Coord-proximity threshold for the time+place rule. Two
    /// sessions must be within this many meters. Spec § 81
    /// first-cut: ~200m. Tight enough that "same restaurant"
    /// matches; loose enough that "walking around a market" does.
    static let timePlaceProximityMeters: Double = 200

    // MARK: - Entry point

    /// Emits ordered cluster proposals for the current inbox.
    /// Ordered newest-first by their earliest-clip capture time
    /// (matches the workbench visual: recent stands out first).
    ///
    /// - Parameters:
    ///   - sessions: the current session list (post-idle-gap
    ///     grouping) — the loose bench. Newest-first.
    ///   - dismissed: fingerprints the user already declined via
    ///     "Not together." These are filtered out silently.
    static func propose(
        sessions: [ClipGroup],
        dismissed: Set<ClusterFingerprint>
    ) -> [ClusterProposal] {
        // Only run Sort when there's material to sort — a single
        // session on the bench can never cluster with anything.
        guard sessions.count >= 2 else { return [] }

        var proposals: [ClusterProposal] = []
        proposals.append(contentsOf: proposeTimePlace(sessions: sessions))

        // Filter dismissed. Exact-set suppression only per spec.
        proposals = proposals.filter { !dismissed.contains($0.fingerprint) }

        // No cluster should propose fewer than 2 sessions — that's
        // the loose clip itself. Belt against a rule bug.
        proposals = proposals.filter { $0.clipIds.count >= 2 }

        // Order by the cluster's earliest clip's capturedAt
        // descending (newest cluster first). Stable tiebreak on
        // fingerprint to avoid render flip-flop.
        proposals.sort { a, b in
            let aStart = earliestCapturedAt(clipIds: a.clipIds, in: sessions) ?? .distantPast
            let bStart = earliestCapturedAt(clipIds: b.clipIds, in: sessions) ?? .distantPast
            if aStart != bStart { return aStart > bStart }
            return a.fingerprint.rawValue < b.fingerprint.rawValue
        }

        return proposals
    }

    // MARK: - Time + place rule

    /// Groups sessions whose coordinate + time proximity meet the
    /// gates. A session **must** have both `latitude` and
    /// `longitude` on at least one of its clips to participate —
    /// location is a hard requirement per spec § 81.
    ///
    /// Uses single-link clustering (a chain of overlapping pairs
    /// forms one cluster), which is why the location gate matters
    /// so much: without it, single-link on time alone can chain
    /// into an all-day blob. With location, the chain requires
    /// spatial continuity, which is much harder to hit
    /// accidentally.
    static func proposeTimePlace(sessions: [ClipGroup]) -> [ClusterProposal] {
        // Only sessions with usable coords participate.
        let located: [(session: ClipGroup, coord: (Double, Double))] =
            sessions.compactMap { session in
                guard let coord = coordinate(for: session) else { return nil }
                return (session, coord)
            }
        guard located.count >= 2 else { return [] }

        // Build adjacency: two sessions are adjacent if they're
        // within the time AND proximity gates.
        let n = located.count
        var adj: [[Int]] = Array(repeating: [], count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let a = located[i].session
                let b = located[j].session
                let timeGap = abs(a.capturedAt.timeIntervalSince(b.capturedAt))
                guard timeGap <= timePlaceWindowSeconds else { continue }
                let (aLat, aLon) = located[i].coord
                let (bLat, bLon) = located[j].coord
                let meters = haversineMeters(lat1: aLat, lon1: aLon, lat2: bLat, lon2: bLon)
                guard meters <= timePlaceProximityMeters else { continue }
                adj[i].append(j)
                adj[j].append(i)
            }
        }

        // Union-find via BFS to collect connected components.
        var visited = Array(repeating: false, count: n)
        var components: [[Int]] = []
        for start in 0..<n where !visited[start] {
            var stack = [start]
            var comp: [Int] = []
            while let cur = stack.popLast() {
                if visited[cur] { continue }
                visited[cur] = true
                comp.append(cur)
                stack.append(contentsOf: adj[cur].filter { !visited[$0] })
            }
            if comp.count >= 2 { components.append(comp) }
        }

        return components.map { component in
            let sessionsInCluster = component.map { located[$0].session }
                .sorted { $0.capturedAt < $1.capturedAt }
            return makeTimePlaceProposal(sessions: sessionsInCluster)
        }
    }

    // MARK: - Proposal construction

    /// Builds a `ClusterProposal` from a time+place cluster's
    /// sessions. Fills `whyText` from the signals per spec § 80
    /// ("5 clips · one 18-minute stretch, same place") — templated,
    /// never LLM prose.
    private static func makeTimePlaceProposal(sessions: [ClipGroup]) -> ClusterProposal {
        let allClips = sessions.flatMap(\.clips)
        let clipIds = allClips.map(\.clipId)
        let stretchMinutes: Int = {
            let earliest = sessions.first?.capturedAt ?? Date()
            // Last clip's capturedAt in the last session is the
            // cluster's true end; use it for the stretch label.
            let latest = sessions.last?.clips
                .map(\.capturedAt)
                .max() ?? earliest
            let minutes = Int((latest.timeIntervalSince(earliest) / 60).rounded())
            return max(1, minutes)
        }()
        let whyText: String = {
            let clipsWord = allClips.count == 1 ? "clip" : "clips"
            return "\(allClips.count) \(clipsWord) · \(stretchMinutes)-minute stretch, same place"
        }()
        // Provisional cluster name — spec § 74 says the cluster's
        // proposed name becomes the draft-Memory title. For the
        // time+place rule with no NLP naming yet, use a friendly
        // window label: "Dinner at Culinary Institute" would need
        // a placeName resolver we don't have on `InboxClip` yet.
        // First cut uses a neutral capture window; a later Plus
        // pass can produce better names.
        let proposedName: String = {
            let f = DateFormatter()
            f.dateFormat = "EEE h:mm a"
            return "Together at " + f.string(from: sessions.first?.capturedAt ?? Date())
        }()
        let previewLines: [ClusterProposal.PreviewLine] = allClips
            .sorted { $0.capturedAt < $1.capturedAt }
            .prefix(3)
            .map { clip in
                let timeF = DateFormatter()
                timeF.dateFormat = "h:mm"
                let snippet = clip.transcript
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? "(transcribing)" : String(clip.transcript.prefix(72))
                return ClusterProposal.PreviewLine(
                    timeLabel: timeF.string(from: clip.capturedAt),
                    transcriptSnippet: snippet
                )
            }
        return ClusterProposal(
            clipIds: clipIds,
            ruleTag: .timePlace,
            whyText: whyText,
            proposedName: proposedName,
            previewLines: previewLines
        )
    }

    // MARK: - Coordinate helpers

    /// Returns the first (lat, lon) pair found on a session's
    /// clips, or nil if none carry coords. Sessions without any
    /// located clip are excluded from the time+place rule per
    /// spec § 81 (never invent a "same place" you can't confirm).
    private static func coordinate(for session: ClipGroup) -> (Double, Double)? {
        for clip in session.clips {
            if let lat = clip.latitude, let lon = clip.longitude {
                return (lat, lon)
            }
        }
        return nil
    }

    private static func earliestCapturedAt(
        clipIds: [UUID],
        in sessions: [ClipGroup]
    ) -> Date? {
        let idSet = Set(clipIds)
        let clips = sessions.flatMap(\.clips).filter { idSet.contains($0.clipId) }
        return clips.map(\.capturedAt).min()
    }

    /// Great-circle distance via the haversine formula. Same
    /// helper the legacy grouper used, kept here so this file is
    /// self-contained. Sufficient precision for the 200m gate.
    private static func haversineMeters(
        lat1: Double, lon1: Double, lat2: Double, lon2: Double
    ) -> Double {
        let earthR = 6_371_000.0
        let toRad = Double.pi / 180
        let dLat = (lat2 - lat1) * toRad
        let dLon = (lon2 - lon1) * toRad
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * toRad) * cos(lat2 * toRad)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthR * c
    }
}

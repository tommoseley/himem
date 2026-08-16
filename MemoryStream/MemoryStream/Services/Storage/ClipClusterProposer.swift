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

    /// Minimum length of an "interesting" token for the word-match
    /// rule. Below this and we're into function-word territory
    /// where stopwords + short function words dominate.
    static let wordMatchMinTokenLength: Int = 4

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
    ///   - trace: optional recorder for `[ClusterTrace]`. Nil in every
    ///     production path that does not want it and in every test that does
    ///     not assert on it, so the proposer's behaviour is identical with and
    ///     without one. **It is a per-call collector, never shared** — which is
    ///     why it needs no lock, unlike `LocalEntityExtractor.shared` below it.
    static func propose(
        sessions: [ClipGroup],
        dismissed: Set<ClusterFingerprint>,
        entityExtractor: EntityExtractor = LocalEntityExtractor.shared,
        trace: ClusterProposalTrace? = nil
    ) -> [ClusterProposal] {
        trace?.recordInput(sessions: sessions)
        // Only run Sort when there's material to sort — a single
        // session on the bench can never cluster with anything.
        guard sessions.count >= 2 else {
            trace?.recordTooFewSessions(sessions.count)
            return []
        }

        var proposals: [ClusterProposal] = []
        proposals.append(contentsOf: proposeTimePlace(sessions: sessions))
        proposals.append(contentsOf: proposeWordMatch(
            sessions: sessions,
            entityExtractor: entityExtractor,
            trace: trace
        ))
        trace?.recordFormed(proposals)
        // Overlap dedup per spec § "Clustering is Honest-Label" —
        // locked July 4 2026: a clip may appear in at most one
        // rendered candidate. Order by signal strength and greedily
        // drop any proposal whose clipIds are ≥ 50% already claimed
        // by a stronger one. This subsumes exact-set, subset, and
        // substantial-overlap cases in one pass.
        proposals = dedupByOverlap(proposals, trace: trace)

        // Filter dismissed. Exact-set suppression only per spec.
        let beforeDismissal = proposals
        proposals = proposals.filter { !dismissed.contains($0.fingerprint) }
        trace?.recordDismissed(removed: beforeDismissal.filter { dismissed.contains($0.fingerprint) })

        // No cluster should propose fewer than 2 sessions — that's
        // the loose clip itself. Belt against a rule bug.
        let beforeMinimum = proposals
        proposals = proposals.filter { $0.clipIds.count >= 2 }
        trace?.recordBelowMinimum(removed: beforeMinimum.filter { $0.clipIds.count < 2 })
        trace?.recordSurvivors(proposals)

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

    // MARK: - Overlap dedup

    /// Spec § "One clip set = one candidate" (locked July 4 2026).
    /// A clip may appear in at most one rendered candidate. Multiple
    /// signals routinely point at the same clips (Pennsylvania
    /// clips also share "little town"; a dinner matches on both
    /// time+place *and* a shared word). Rendering both is
    /// double-filing — the exact mess Sort exists to prevent.
    ///
    /// Greedy claim in signal-strength order: strongest first
    /// claims its clipIds; each subsequent proposal is dropped if
    /// ≥ 50% of its clipIds are already claimed. This subsumes
    /// exact-set duplicates, subset/superset relations, and
    /// substantial-overlap cases in one pass. Minor-overlap-per-
    /// clip reassignment (< 50%) preserves both candidates as-is;
    /// a full per-clip reassignment is post-v1.
    ///
    /// Signal strength (spec § 86):
    /// - **Tier 2 (strongest):** proper-noun word-match, time+place
    /// - **Tier 1 (weaker):** distinctive bigram word-match
    /// Bigrams are identified by a space in the proposedName
    /// (which is the shared token itself for word-match clusters).
    static func dedupByOverlap(
        _ proposals: [ClusterProposal],
        trace: ClusterProposalTrace? = nil
    ) -> [ClusterProposal] {
        let sorted = proposals.sorted { a, b in
            let sa = signalStrength(a)
            let sb = signalStrength(b)
            if sa != sb { return sa > sb }
            // Stable tiebreak on fingerprint so ordering is
            // deterministic across runs.
            return a.fingerprint.rawValue < b.fingerprint.rawValue
        }
        var kept: [ClusterProposal] = []
        var claimedClipIds: Set<UUID> = []
        // Only built when someone is tracing: naming the *eater* is the whole
        // question the instrument was written for, and a flat claimed-set
        // cannot answer it. Nil trace leaves the production path unchanged.
        var claimedBy: [UUID: ClusterProposal] = [:]
        for proposal in sorted {
            let clipIdSet = Set(proposal.clipIds)
            let intersection = clipIdSet.intersection(claimedClipIds)
            // Overlap ratio against THIS proposal's clipIds so a
            // small proposal fully-inside a big one (subset) is
            // dropped, and a small proposal with modest overlap of
            // its own clipIds stays.
            let overlapRatio = clipIdSet.isEmpty ? 0 :
                Double(intersection.count) / Double(clipIdSet.count)
            if overlapRatio >= 0.5 {
                trace?.recordEatenByOverlap(
                    proposal,
                    ratio: overlapRatio,
                    claimedBy: intersection.compactMap { claimedBy[$0] }
                )
                continue
            }
            kept.append(proposal)
            claimedClipIds.formUnion(clipIdSet)
            if trace != nil {
                for id in clipIdSet { claimedBy[id] = proposal }
            }
        }
        return kept
    }

    private static func signalStrength(_ proposal: ClusterProposal) -> Int {
        switch proposal.ruleTag {
        case .timePlace: return 2
        case .wordMatch:
            // Bigrams have a space in the proposedName (which is
            // the shared token). Proper-noun single tokens don't.
            return proposal.proposedName.contains(" ") ? 1 : 2
        }
    }

    // MARK: - Word-match rule

    /// Distinctive-token clustering per spec § 82. Under-suggest
    /// discipline: the shared token must be **either** a proper
    /// noun (NLTagger-detected personalName / placeName /
    /// organizationName) **or** a bigram (inherently distinctive)
    /// **or** a single content word that is TF-rare across the
    /// user's own inbox corpus. Common content words like
    /// "restaurant" / "town" / "lovely" — the spec's named
    /// failure mode — are explicitly excluded.
    ///
    /// The gate is deliberately conservative: a missed match is
    /// invisible, a false one erodes trust in every card. Prefer
    /// silence.
    static func proposeWordMatch(
        sessions: [ClipGroup],
        entityExtractor: EntityExtractor,
        trace: ClusterProposalTrace? = nil
    ) -> [ClusterProposal] {
        // Extract candidate tokens per session and build inverse
        // indexes: token → session indices it appears in.
        var tokenToSessions: [String: Set<Int>] = [:]
        // For "why" line and cluster naming: original casing per token.
        var tokenDisplay: [String: String] = [:]

        // Corpus-wide TF map: token → number of DISTINCT sessions
        // it appears in. Content words above the rarity ceiling
        // don't cluster.
        var sessionAppearances: [String: Int] = [:]

        // Set of tokens known to be proper nouns (NLTagger flagged
        // them). Two-session appearance is enough; TF ceiling is
        // waived for proper nouns.
        var properNouns: Set<String> = []

        // Bigrams get their own set (always distinctive; no TF gate).
        var bigrams: Set<String> = []

        for (idx, session) in sessions.enumerated() {
            let joinedTranscript = session.clips
                .map(\.transcript)
                .joined(separator: " ")
            let tokens = distinctiveTokens(
                from: joinedTranscript,
                entityExtractor: entityExtractor,
                properNouns: &properNouns,
                bigrams: &bigrams,
                displayForms: &tokenDisplay
            )
            for token in tokens {
                tokenToSessions[token, default: []].insert(idx)
                sessionAppearances[token, default: 0] += 1
            }
        }

        // For each token appearing in ≥2 sessions, decide whether
        // it's distinctive enough to propose. **Under-suggest**
        // discipline per spec § 82 + Tom's July 4 watch item: only
        // proper nouns and bigrams qualify. A single content word,
        // even if TF-rare across the current inbox, is not a
        // strong enough signal to cluster on its own — "restaurant"
        // appearing in 2 of 5 sessions is 40% of the corpus, not
        // "rare user jargon," and clustering on it would be
        // exactly the failure mode the spec names. Truly rare
        // user-specific single words are the edge case; bigrams
        // + proper nouns cover the common cases (Hosta Hideaway,
        // Machu Picchu, farm-to-table) without the false-positive
        // risk. If dogfood shows we're missing important cases,
        // reintroduce a TF-rarity gate with proper corpus-size
        // gating.
        _ = sessionAppearances  // Kept in case a later TF-rarity gate wants it.
        var clustersByTokenKey: [String: (sessionIndices: Set<Int>, token: String)] = [:]
        for (token, indices) in tokenToSessions where indices.count >= 2 {
            let isProperNoun = properNouns.contains(token)
            let isBigram = bigrams.contains(token)
            let distinctive = isProperNoun || isBigram
            guard distinctive else {
                trace?.recordToken(
                    token,
                    sessionIndices: indices,
                    isProperNoun: isProperNoun,
                    isBigram: isBigram,
                    fate: .notDistinctive
                )
                continue
            }
            // Group cluster proposals by their session index set —
            // "Hosta Hideaway" (bigram) and "Hideaway" (proper noun)
            // both surfacing the same session pair should not double.
            let key = indices.sorted().map(String.init).joined(separator: ",")
            // First-writer wins. Proper-noun match beats bigram
            // beats rare content word for the "why" text, since
            // proper nouns produce the clearest reason string.
            if clustersByTokenKey[key] == nil ||
                (isProperNoun && !properNouns.contains(clustersByTokenKey[key]!.token)) {
                let displaced = clustersByTokenKey[key]?.token
                clustersByTokenKey[key] = (indices, token)
                trace?.recordToken(
                    token,
                    sessionIndices: indices,
                    isProperNoun: isProperNoun,
                    isBigram: isBigram,
                    fate: .namesTheCluster(displacing: displaced)
                )
            } else {
                // Qualified, and still produced no proposal of its own: another
                // token already speaks for this exact set of sessions. The
                // cluster is not lost — it is named by the other token — but a
                // reader looking for THIS token in the formed list would
                // otherwise read its absence as "never qualified".
                trace?.recordToken(
                    token,
                    sessionIndices: indices,
                    isProperNoun: isProperNoun,
                    isBigram: isBigram,
                    fate: .sessionSetNamedByAnotherToken(clustersByTokenKey[key]?.token ?? "?")
                )
            }
        }

        trace?.recordSingleSessionTokens(
            tokenToSessions
                .filter { $0.value.count == 1 }
                .filter { properNouns.contains($0.key) || bigrams.contains($0.key) }
                .map(\.key)
        )

        return clustersByTokenKey.values.map { entry in
            let sessionsInCluster = entry.sessionIndices
                .sorted()
                .map { sessions[$0] }
            let display = tokenDisplay[entry.token] ?? entry.token
            return makeWordMatchProposal(
                sessions: sessionsInCluster,
                sharedToken: display
            )
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
        // F39 · "51-minute stretch" read as ONE CONTINUOUS THING, which is
        // precisely what made a cross-session proposal look like a broken
        // session. A cluster spans sittings, and the gap between them is the
        // reason a human might disagree — so name the sittings and call the
        // number a gap ("apart"), not a duration ("stretch").
        //
        // Still an observation, never a conclusion (J5): it reports how many
        // clips, how many sittings, and how far apart. It does not say they
        // belong together.
        // F43 · ONE definition, shared with the card. The proposal's own
        // `whyText` describes its original membership; the card recomputes
        // the same sentence from the KEPT set. Same string builder both
        // times, so the two can never disagree about phrasing — only about
        // the set, which is the point.
        let whyText = ClusterSubtitleBuilder.subtitle(
            clipCount: allClips.count,
            sittingCount: sessions.count,
            capturedAts: allClips.map(\.capturedAt)
        )
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

    /// Word-match proposal construction. Templated per spec § 80.
    private static func makeWordMatchProposal(
        sessions: [ClipGroup],
        sharedToken: String
    ) -> ClusterProposal {
        let allClips = sessions.flatMap(\.clips)
        let clipIds = allClips.map(\.clipId)
        let sessionsWord = sessions.count == 1 ? "clip" : "clips"
        // Preserve casing of the surface form the corpus produced.
        let whyText = "\(sessions.count) \(sessionsWord) mention \"\(sharedToken)\""
        // Proposed cluster name uses the shared token — cheap and
        // honest. A later Plus semantic pass can produce better
        // names.
        let proposedName = sharedToken
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
            ruleTag: .wordMatch,
            whyText: whyText,
            proposedName: proposedName,
            previewLines: previewLines
        )
    }

    // MARK: - Token extraction

    /// Extracts distinctive candidate tokens from one session's
    /// transcript. Returns a set of **lowercased** tokens for
    /// TF/inverse-index comparison; the `displayForms` out-parameter
    /// captures the original casing so the "why" string can quote
    /// the actual word the user said. Also populates `properNouns`
    /// (NLTagger-detected personalName / placeName / organizationName)
    /// and `bigrams` (adjacent ≥4-char alphabetic pairs).
    private static func distinctiveTokens(
        from text: String,
        entityExtractor: EntityExtractor,
        properNouns: inout Set<String>,
        bigrams: inout Set<String>,
        displayForms: inout [String: String]
    ) -> Set<String> {
        var candidates: Set<String> = []

        // Proper nouns via the entity extractor. NLTagger's
        // unreliable on the iOS 26 simulator (per memory), so
        // real device coverage is the source of truth; simulator
        // tests should inject a stub extractor.
        let result = entityExtractor.extractEntities(from: text)
        for entity in result.entities {
            let key = entity.value.lowercased()
            if displayForms[key] == nil {
                displayForms[key] = entity.value
            }
            candidates.insert(key)
            properNouns.insert(key)
        }

        // Simple word tokenization for bigrams + rare-content-word
        // candidates. Split on whitespace + punctuation; keep
        // alphabetic tokens of `wordMatchMinTokenLength` or longer;
        // filter stopwords.
        let words = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let originalWords = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        // Track (index → original-cased word) for display recovery.
        var display: [String: String] = [:]
        for (i, w) in words.enumerated() where i < originalWords.count {
            if display[w] == nil { display[w] = originalWords[i] }
        }

        // Rare content words: keep tokens that survive the length
        // + stopword filter. TF ceiling is applied at the corpus
        // level in `proposeWordMatch`.
        for w in words where w.count >= Self.wordMatchMinTokenLength && !Self.stopwords.contains(w) {
            candidates.insert(w)
            if displayForms[w] == nil, let d = display[w] {
                displayForms[w] = d
            }
        }

        // Bigrams: adjacent word pairs, both ≥4 chars, both non-
        // stopword. Bigrams are a stronger signal than single
        // content words — but ONLY when both components are
        // distinctive.
        //
        // Spec § "Clustering is Honest-Label" (July 4 revision):
        // reject bigrams composed of common content words. "little
        // town," "great restaurant," "quiet morning" all read as
        // random — they're the exact false-positive pattern the
        // distinctness gate must reject. If EITHER component is
        // in `commonContentWordsForBigrams`, the bigram is skipped.
        //
        // Escape hatch: if either component was independently
        // detected as a proper noun by the entity extractor
        // (already in `properNouns`), the bigram passes — that's
        // the "Hosta Hideaway" / "Machu Picchu" case where the
        // proper-noun component confers distinctness on the pair.
        for i in 0..<max(0, words.count - 1) {
            let a = words[i]
            let b = words[i + 1]
            guard a.count >= Self.wordMatchMinTokenLength,
                  b.count >= Self.wordMatchMinTokenLength,
                  !Self.stopwords.contains(a),
                  !Self.stopwords.contains(b) else { continue }
            let aIsCommon = Self.commonContentWordsForBigrams.contains(a)
            let bIsCommon = Self.commonContentWordsForBigrams.contains(b)
            let hasProperNounComponent = properNouns.contains(a) || properNouns.contains(b)
            if (aIsCommon || bIsCommon) && !hasProperNounComponent {
                continue
            }
            let bigram = "\(a) \(b)"
            candidates.insert(bigram)
            bigrams.insert(bigram)
            if displayForms[bigram] == nil,
               i < originalWords.count - 1 {
                displayForms[bigram] = "\(originalWords[i]) \(originalWords[i + 1])"
            }
        }

        return candidates
    }

    /// Minimal English stopword list for the ≥4-char band. Adding
    /// only stopwords the ≥4-char filter doesn't already remove —
    /// no "the"/"and" here because those are already too short.
    /// Kept small on purpose; over-filtering common phrases
    /// weakens the bigram signal (a bigram of "still lovely" is
    /// weak, but the pair-level filter is enforced elsewhere).
    private static let stopwords: Set<String> = [
        "this", "that", "with", "from", "your", "have", "were",
        "there", "their", "which", "would", "could", "should",
        "about", "into", "over", "under", "again", "just", "some",
        "like", "when", "then", "them", "than", "what", "where",
        "yeah", "okay", "gonna", "wanna", "kinda", "sort", "kind",
        "very", "really", "actually", "basically", "pretty",
        "well", "still", "even", "also", "only", "such", "much",
        "many", "most", "each", "every", "these", "those",
        "being", "does", "doing", "done", "going", "make", "made",
        "know", "knew", "think", "thought", "say", "said", "here",
        "back", "come", "came", "want", "wanted",
    ]

    /// Common content words that must NOT appear in a bigram
    /// (unless the bigram's other component is a proper noun).
    /// Spec § "Clustering is Honest-Label" July 4 revision
    /// explicitly names "restaurant," "town," "lovely" as the
    /// generic-bigram false-positive class ("little town" from
    /// Tom's July 4 dogfood surfaced as a cluster — exactly this
    /// gate's target). Kept moderate — over-filtering starves
    /// the bigram signal.
    ///
    /// Distinct from `stopwords` because these are content words
    /// (nouns/adjectives with real meaning), not function words.
    /// Bigrams *composed of* these are the failure mode; bigrams
    /// that just contain one alongside a proper noun still pass.
    private static let commonContentWordsForBigrams: Set<String> = [
        // Places / generic locations
        "town", "city", "place", "area", "spot", "part", "side",
        "home", "house", "room", "street", "road", "building",
        // Meals / establishments
        "restaurant", "meal", "dinner", "lunch", "breakfast",
        "coffee", "food", "menu", "table", "drink",
        // Common qualifiers
        "little", "great", "good", "nice", "lovely", "beautiful",
        "quiet", "small", "large", "tiny", "huge", "long", "short",
        // Time-of-day / duration
        "morning", "afternoon", "evening", "night", "today",
        "yesterday", "tomorrow", "moment", "minute", "hour", "week",
        // Generic nouns
        "thing", "stuff", "kind", "type", "sort", "part", "piece",
        "way", "point", "case", "time", "year", "day",
        "people", "person", "someone", "everyone",
    ]

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

// MARK: - `[ClusterTrace]` · the proposal instrument

/// **What the proposer decided, as a value.**
///
/// Written 2026-08-15 for one question that cannot be answered from outside
/// `propose`: Sparrow Quarry did not cluster on a real bench while Harbor
/// Lantern (3/3) and Thistle Beacon (5/3) did, and the two candidate causes —
/// *a formed proposal was discarded* versus *the token never qualified* —
/// produce an identical observation (no card). Four wrong theories were spent
/// on the adjacent clip before a two-tap fixture check ended it; this exists so
/// the fifth is a reading rather than a guess.
///
/// **Presence in `formed` names what ate it. Absence points at the token**, and
/// the token verdicts say which gate it failed rather than leaving the reader
/// to infer it from silence.
///
/// Same posture as `[BenchPerf]`, `[Amp]` and `[Meter]`: read-only, changes no
/// behaviour, and answers a question three of this project's hardest defects
/// needed a log rather than more reasoning to settle.
///
/// **It is built to be falsifiable.** The 2026-08-09 lesson is that a
/// diagnostic written specifically to be falsifiable *passed by matching
/// nothing* — `synthesizedRows` and `emptyGroups` were both reductions over an
/// empty set, so both printed 0 regardless of the truth. So this is a value
/// with tests over it (`ClusterProposalTraceTests`), not a `print` statement:
/// one test proves it distinguishes eaten-by-dedup from never-formed, which is
/// exactly the discrimination it was built to make. A trace that recorded
/// nothing fails those tests.
final class ClusterProposalTrace {

    /// A proposal as the rules formed it, before anything downstream could
    /// discard it.
    struct Formed: Equatable {
        let fingerprint: String
        let ruleTag: ClusterProposal.RuleTag
        let proposedName: String
        let clipIds: [UUID]
    }

    /// What became of a formed proposal. Four fates, because there are four
    /// places one can die — the overlap dedup is only the loudest.
    enum Fate: Equatable {
        /// Survived every filter and reached the caller.
        case survived
        /// The ≥50% overlap dedup dropped it; a stronger proposal had already
        /// claimed its clips.
        case eatenByOverlap(ratio: Double, claimedBy: [String])
        /// The user's own "Not together" suppressed it.
        case dismissedByUser
        /// The belt-and-braces `clipIds.count >= 2` filter dropped it.
        case belowMinimumSize(Int)
    }

    /// Why a shared token did or did not become a cluster. `notDistinctive` is
    /// the one that answers "the token never qualified" — the branch the device
    /// cannot show.
    enum TokenFate: Equatable {
        case namesTheCluster(displacing: String?)
        case notDistinctive
        case sessionSetNamedByAnotherToken(String)
    }

    struct TokenVerdict: Equatable {
        let token: String
        let sessionIndices: [Int]
        let isProperNoun: Bool
        let isBigram: Bool
        let fate: TokenFate
    }

    /// One drawn session as the proposer received it. Carries a transcript
    /// snippet per clip because "did these three land in one sitting or three"
    /// is the first question a missing token raises, and it is unanswerable
    /// from counts alone.
    struct SessionInput: Equatable {
        let index: Int
        let clipCount: Int
        let hasCoordinate: Bool
        let snippets: [String]
    }

    private(set) var sessionInputs: [SessionInput] = []
    private(set) var formed: [Formed] = []
    private(set) var fates: [String: Fate] = [:]
    private(set) var tokenVerdicts: [TokenVerdict] = []
    private(set) var singleSessionDistinctiveTokens: [String] = []
    private(set) var tooFewSessions: Int?

    init() {}

    // MARK: Recording

    func recordInput(sessions: [ClipGroup]) {
        sessionInputs = sessions.enumerated().map { index, session in
            SessionInput(
                index: index,
                clipCount: session.clips.count,
                hasCoordinate: session.clips.contains { $0.latitude != nil && $0.longitude != nil },
                snippets: session.clips.map {
                    String($0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
                }
            )
        }
    }

    func recordTooFewSessions(_ count: Int) { tooFewSessions = count }

    func recordFormed(_ proposals: [ClusterProposal]) {
        formed = proposals.map {
            Formed(
                fingerprint: $0.fingerprint.rawValue,
                ruleTag: $0.ruleTag,
                proposedName: $0.proposedName,
                clipIds: $0.clipIds
            )
        }
    }

    func recordEatenByOverlap(_ proposal: ClusterProposal, ratio: Double, claimedBy: [ClusterProposal]) {
        // Distinct eaters, in a stable order, so the same run reads the same
        // way twice.
        var seen: Set<String> = []
        let names = claimedBy.compactMap { eater -> String? in
            let label = "\(eater.proposedName)#\(String(eater.fingerprint.rawValue.prefix(8)))"
            return seen.insert(label).inserted ? label : nil
        }.sorted()
        fates[proposal.fingerprint.rawValue] = .eatenByOverlap(ratio: ratio, claimedBy: names)
    }

    func recordDismissed(removed: [ClusterProposal]) {
        for proposal in removed { fates[proposal.fingerprint.rawValue] = .dismissedByUser }
    }

    func recordBelowMinimum(removed: [ClusterProposal]) {
        for proposal in removed {
            fates[proposal.fingerprint.rawValue] = .belowMinimumSize(proposal.clipIds.count)
        }
    }

    func recordSurvivors(_ proposals: [ClusterProposal]) {
        for proposal in proposals { fates[proposal.fingerprint.rawValue] = .survived }
    }

    func recordToken(
        _ token: String,
        sessionIndices: Set<Int>,
        isProperNoun: Bool,
        isBigram: Bool,
        fate: TokenFate
    ) {
        tokenVerdicts.append(
            TokenVerdict(
                token: token,
                sessionIndices: sessionIndices.sorted(),
                isProperNoun: isProperNoun,
                isBigram: isBigram,
                fate: fate
            )
        )
    }

    func recordSingleSessionTokens(_ tokens: [String]) {
        singleSessionDistinctiveTokens = tokens.sorted()
    }

    // MARK: Reading

    /// The fate of a proposal by fingerprint — `nil` when no proposal with that
    /// fingerprint was ever formed. **That nil is the discrimination the
    /// instrument exists to make:** a proposal that was eaten has a fate, a
    /// proposal that never formed has none.
    func fate(ofFingerprint fingerprint: String) -> Fate? { fates[fingerprint] }

    /// Whether any formed proposal claimed this clip, regardless of what
    /// happened to it afterwards.
    func formedProposalsClaiming(_ clipId: UUID) -> [Formed] {
        formed.filter { $0.clipIds.contains(clipId) }
    }

    /// A stable digest of everything recorded. The call site emits only when
    /// this changes, so a retry sweep republishing the same bench does not
    /// reprint the same trace — and a bench that genuinely changed always
    /// prints.
    var signature: String { lines.joined(separator: "\n") }

    /// The log form. Deliberately several short lines naming each decision
    /// rather than one paragraph: a paragraph tells you *that* something
    /// changed, never *what*.
    var lines: [String] {
        var out: [String] = []
        if let tooFew = tooFewSessions {
            out.append("sessions=\(tooFew) · SKIPPED (needs ≥2)")
            return out
        }
        out.append("sessions=\(sessionInputs.count) · formed=\(formed.count) · survived=\(fates.values.filter { $0 == .survived }.count)")
        for input in sessionInputs {
            let snippets = input.snippets.map { "“\($0)”" }.joined(separator: " | ")
            out.append("  s\(input.index) · clips=\(input.clipCount) · coord=\(input.hasCoordinate ? "yes" : "no") · \(snippets)")
        }
        for proposal in formed {
            let fate = fates[proposal.fingerprint] ?? .survived
            out.append("  FORMED \(proposal.ruleTag) “\(proposal.proposedName)” · ids=\(proposal.clipIds.count) [\(shortIds(proposal.clipIds))] → \(describe(fate))")
        }
        for verdict in tokenVerdicts {
            let kind = [verdict.isProperNoun ? "properNoun" : nil, verdict.isBigram ? "bigram" : nil]
                .compactMap { $0 }
                .joined(separator: "+")
            out.append("  TOKEN “\(verdict.token)” · sessions=\(verdict.sessionIndices) · \(kind.isEmpty ? "neither" : kind) → \(describe(verdict.fate))")
        }
        out.append(contentsOf: singleSessionTokenLines())
        return out
    }

    /// **The cap is stated in the output, never silent.** A withheld list that
    /// looks like an empty one is how a `head -8` becomes "there are none".
    private func singleSessionTokenLines() -> [String] {
        let all = singleSessionDistinctiveTokens
        guard !all.isEmpty else { return ["  single-session distinctive tokens: none"] }
        let ceiling = 60
        if all.count <= ceiling {
            return ["  single-session distinctive tokens (\(all.count)): \(all.joined(separator: ", "))"]
        }
        return [
            "  single-session distinctive tokens: \(all.count) — LIST WITHHELD above \(ceiling); "
            + "first \(ceiling) shown, the rest are NOT absent: \(all.prefix(ceiling).joined(separator: ", "))"
        ]
    }

    private func shortIds(_ ids: [UUID]) -> String {
        ids.map { String($0.uuidString.prefix(8)) }.joined(separator: ",")
    }

    private func describe(_ fate: Fate) -> String {
        switch fate {
        case .survived:
            return "SURVIVED"
        case let .eatenByOverlap(ratio, claimedBy):
            return "EATEN by overlap \(Int((ratio * 100).rounded()))% · claimed by \(claimedBy.joined(separator: ", "))"
        case .dismissedByUser:
            return "DISMISSED by the user"
        case let .belowMinimumSize(count):
            return "DROPPED below minimum size (\(count))"
        }
    }

    private func describe(_ fate: TokenFate) -> String {
        switch fate {
        case let .namesTheCluster(displaced):
            return displaced.map { "NAMES the cluster (displaced “\($0)”)" } ?? "NAMES the cluster"
        case .notDistinctive:
            return "NOT DISTINCTIVE — shared across sessions but neither proper noun nor bigram, so no proposal formed"
        case let .sessionSetNamedByAnotherToken(other):
            return "qualified, but “\(other)” already names this exact session set"
        }
    }
}

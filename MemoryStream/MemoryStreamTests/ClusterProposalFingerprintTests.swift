import Testing
import Foundation
@testable import HiMem

/// Money tests for `ClusterFingerprint` — the deterministic
/// identifier that lets `InboxManifest`'s dismissal store suppress
/// re-proposals of a cluster the user already declined.
///
/// Per spec § "Sort is the bench's resting state" and Tom's Q3
/// answer (July 4 2026): exact-set suppression only. Same clipIds
/// + same rule = same fingerprint = suppressed. Add a clip and
/// it's a new fingerprint (proposed fresh).
struct ClusterProposalFingerprintTests {

    @Test
    func fingerprint_sameClipIds_sameRule_matches() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let f1 = ClusterFingerprint.derive(clipIds: [a, b, c], ruleTag: .timePlace)
        let f2 = ClusterFingerprint.derive(clipIds: [a, b, c], ruleTag: .timePlace)
        #expect(f1 == f2)
    }

    /// The point of "sorted clipIds" — dismissal must survive the
    /// same set arriving in a different order (which happens when
    /// the proposer walks the inbox in reverse-chronological vs
    /// chronological order).
    @Test
    func fingerprint_reorderedClipIds_sameRule_matches() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let f1 = ClusterFingerprint.derive(clipIds: [a, b, c], ruleTag: .timePlace)
        let f2 = ClusterFingerprint.derive(clipIds: [c, a, b], ruleTag: .timePlace)
        #expect(f1 == f2)
    }

    @Test
    func fingerprint_differentClipIds_diverges() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let f1 = ClusterFingerprint.derive(clipIds: [a, b, c], ruleTag: .timePlace)
        let f2 = ClusterFingerprint.derive(clipIds: [a, b, d], ruleTag: .timePlace)
        #expect(f1 != f2)
    }

    /// Add-a-clip-to-a-cluster reads as a new cluster per spec
    /// exact-set rule. This is the mechanism that lets a
    /// previously-dismissed grouping resurface when the shape
    /// changes — user meaningfully changed their mind.
    @Test
    func fingerprint_addedClipId_isNewCluster() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let f1 = ClusterFingerprint.derive(clipIds: [a, b], ruleTag: .timePlace)
        let f2 = ClusterFingerprint.derive(clipIds: [a, b, c], ruleTag: .timePlace)
        #expect(f1 != f2, "Adding a clip must produce a distinct fingerprint — spec: exact-set suppression only")
    }

    /// Same clipIds under different rules read as different
    /// fingerprints. Rare (both rules can't confirm the same set
    /// in practice), but the differentiator prevents accidental
    /// dismissal cross-talk between rules.
    @Test
    func fingerprint_differentRuleTag_diverges() {
        let a = UUID()
        let b = UUID()
        let f1 = ClusterFingerprint.derive(clipIds: [a, b], ruleTag: .timePlace)
        let f2 = ClusterFingerprint.derive(clipIds: [a, b], ruleTag: .wordMatch)
        #expect(f1 != f2)
    }

    /// `ClusterProposal.fingerprint` is a pass-through to the
    /// derive helper — verify the wiring so a rename of one side
    /// can't silently break the other.
    @Test
    func proposal_fingerprintMatchesStaticDerive() {
        let a = UUID()
        let b = UUID()
        let proposal = ClusterProposal(
            clipIds: [a, b],
            ruleTag: .timePlace,
            whyText: "2 clips · 5-minute stretch, same place",
            proposedName: "Dinner at the CIA",
            previewLines: []
        )
        let derived = ClusterFingerprint.derive(clipIds: [a, b], ruleTag: .timePlace)
        #expect(proposal.fingerprint == derived)
    }

    /// Codable roundtrip — the dismissal set persists to disk
    /// with the manifest. Fingerprints must survive JSON encode +
    /// decode without changing value.
    @Test
    func fingerprint_codableRoundtrip_preservesValue() throws {
        let a = UUID()
        let b = UUID()
        let original = ClusterFingerprint.derive(clipIds: [a, b], ruleTag: .wordMatch)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClusterFingerprint.self, from: encoded)
        #expect(decoded == original)
    }
}

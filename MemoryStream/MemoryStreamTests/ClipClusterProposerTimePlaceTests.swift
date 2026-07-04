import Testing
import Foundation
@testable import HiMem

/// Money tests for `ClipClusterProposer.proposeTimePlace(sessions:)`
/// per `Captured Clips · session-first · spec.md` v3 § "Clustering
/// is Honest-Label":
///
///  * **Positive:** the CIA dinner dogfood — 5 wrist-raise clips
///    between 6:09 and 6:18 PM at one place — proposes ONE cluster
///    of one session (idle-gap merges the 5 wrist-raises first).
///    In a two-session variant (2 sittings 30 min apart at the
///    same restaurant), those two sessions cluster into one.
///
///  * **Negative:** a road trip with 3 clips from 3 different
///    towns hours apart proposes NO cluster (each pair fails the
///    time OR proximity gate).
///
///  * **Location required:** a session with no coords is skipped
///    from time+place clustering, even if a time-adjacent
///    same-place peer exists. Spec § 81: "never invent a 'same
///    place' you can't confirm."
///
///  * **Under-suggest:** single session on the bench yields NO
///    proposals (nothing to cluster with).
struct ClipClusterProposerTimePlaceTests {

    // MARK: - Fixtures

    /// A session anchored at a single clip. Real inbox usage
    /// almost always groups multiple clips per session via
    /// idle-gap; for cluster tests one-clip-per-session is
    /// sufficient to exercise the pair math.
    private func session(
        at time: Date,
        lat: Double? = nil,
        lon: Double? = nil,
        transcript: String = "test clip"
    ) -> ClipGroup {
        let clip = InboxClip(
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
        return ClipGroup(clips: [clip])
    }

    // MARK: - Positive

    /// Two sessions 30 min apart at the same restaurant — clearly
    /// one dinner across two sittings — cluster into one proposal.
    @Test
    func twoSessions_sameRestaurant_30MinApart_cluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base, lat: 41.789, lon: -73.939)                     // CIA courtyard
        let s2 = session(at: base.addingTimeInterval(30 * 60), lat: 41.789, lon: -73.939)

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: [s1, s2])

        #expect(proposals.count == 1, "One cluster expected for two sessions at same coords within window; got \(proposals.count)")
        #expect(proposals.first?.ruleTag == .timePlace)
        #expect(proposals.first?.clipIds.count == 2)
    }

    // MARK: - Negative

    /// Road trip: three sessions in three different towns, hours
    /// apart. No pair passes BOTH gates → no cluster proposed.
    @Test
    func roadTrip_differentTownsHoursApart_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        // Nazareth, PA
        let s1 = session(at: base, lat: 40.740, lon: -75.309)
        // Martin Guitar (Nazareth) — 4 min later, same town.
        // This pair WOULD cluster on the time+place rule (they're
        // close in space and time). That's actually correct
        // behavior — it's what the spec's "Nazareth & Martin
        // Guitar" cluster shows. So keep it out of this negative
        // test.
        let s2 = session(at: base.addingTimeInterval(2 * 3600), lat: 39.174, lon: -75.527)  // Milford
        let s3 = session(at: base.addingTimeInterval(5 * 3600), lat: 39.833, lon: -77.230)  // Gettysburg

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: [s1, s2, s3])

        #expect(proposals.isEmpty, "Three far-apart towns hours apart must NOT cluster; got \(proposals.count)")
    }

    // MARK: - Location required

    /// One session at a place, one without coords, in the same
    /// time window — no cluster. Location is a hard requirement.
    @Test
    func missingLocation_excludesSessionFromTimePlace() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let placed = session(at: base, lat: 41.789, lon: -73.939)
        let unplaced = session(at: base.addingTimeInterval(30 * 60), lat: nil, lon: nil)

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: [placed, unplaced])

        #expect(proposals.isEmpty, "Session with no coords must be excluded from time+place cluster — spec § 81 hard requirement")
    }

    /// Two sessions both without coords in the same time window —
    /// no cluster. Even if the user was clearly at one place, we
    /// don't invent it. Spec § 81.
    @Test
    func bothMissingLocation_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base, lat: nil, lon: nil)
        let s2 = session(at: base.addingTimeInterval(30 * 60), lat: nil, lon: nil)

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: [s1, s2])

        #expect(proposals.isEmpty)
    }

    // MARK: - Time gate

    /// Two sessions at the same place but 3 hours apart — outside
    /// the 90-min time window — do not cluster. Time gate holds
    /// even at zero distance.
    @Test
    func samePlaceButFarInTime_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base, lat: 41.789, lon: -73.939)
        let s2 = session(at: base.addingTimeInterval(3 * 3600), lat: 41.789, lon: -73.939)

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: [s1, s2])

        #expect(proposals.isEmpty)
    }

    // MARK: - Proximity gate

    /// Same time (30 min apart) but 1 km apart — outside the 200m
    /// proximity gate — do not cluster.
    @Test
    func closeInTimeButFarInSpace_doesNotCluster() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base, lat: 41.789, lon: -73.939)
        // ~1 km east
        let s2 = session(at: base.addingTimeInterval(30 * 60), lat: 41.789, lon: -73.926)

        let proposals = ClipClusterProposer.proposeTimePlace(sessions: [s1, s2])

        #expect(proposals.isEmpty)
    }

    // MARK: - Guards

    /// Single session on the bench → no proposals possible.
    @Test
    func singleSession_yieldsNoProposals() {
        let s = session(at: Date(), lat: 41.789, lon: -73.939)
        let proposals = ClipClusterProposer.propose(sessions: [s], dismissed: [])
        #expect(proposals.isEmpty)
    }

    /// Dismissed fingerprint is suppressed.
    @Test
    func dismissedFingerprint_isFilteredOut() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let s1 = session(at: base, lat: 41.789, lon: -73.939)
        let s2 = session(at: base.addingTimeInterval(30 * 60), lat: 41.789, lon: -73.939)

        // First pass — get the fingerprint of the cluster we'll
        // dismiss.
        let firstPass = ClipClusterProposer.propose(sessions: [s1, s2], dismissed: [])
        #expect(firstPass.count == 1)
        guard let fingerprint = firstPass.first?.fingerprint else {
            Issue.record("Expected one proposal to derive fingerprint from")
            return
        }

        // Second pass — same input + dismissed set containing
        // that fingerprint → no proposals.
        let secondPass = ClipClusterProposer.propose(sessions: [s1, s2], dismissed: [fingerprint])
        #expect(secondPass.isEmpty, "Dismissed fingerprint must suppress re-propose (spec § 67)")
    }
}

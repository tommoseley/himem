import Foundation

/// Groups `InboxClip` rows into capture sessions for the Captured
/// Clips surface. A session is a deterministic grouping by
/// `rollGroupId` (when present — the on-a-roll signal) OR by
/// time+location window (legacy fallback).
///
/// See `docs/design/captured-clips-session-first-spec.md` for the
/// product model: sessions are proto-Memories; on the session-first
/// inbox list they are the unit. Clips live one level deeper in the
/// session detail view.
///
/// Pure / static — no Core Data or I/O dependencies. Tested in
/// `OnARollTests` (rollGroupId precedence) and worth adding more
/// coverage as the session-first redesign lands.
enum ClipSessionGrouper {
    /// Time gap above which two consecutive clips can't be the same
    /// session under the legacy (no-rollGroupId) heuristic. Tightened
    /// from 10 min → 3 min on 2026-05-27 after a 5.5-min-apart pair
    /// merged into one card per Tom's screenshot. 3 min covers "I
    /// paused to think but kept going"; anything longer reads as a
    /// fresh sitting.
    static let sessionTimeWindowSeconds: TimeInterval = 3 * 60

    /// Distance threshold (meters) for legacy time+location
    /// sessioning. Two clips both with coordinates further apart
    /// than this don't merge.
    static let sessionProximityMeters: Double = 50

    /// Groups newest-first.
    static func group(_ clips: [InboxClip]) -> [ClipGroup] {
        let sorted = clips.sorted { $0.capturedAt > $1.capturedAt }
        var groups: [[InboxClip]] = []
        for clip in sorted {
            if let lastGroup = groups.last, let lastClip = lastGroup.last,
               sameSession(lastClip, clip) {
                groups[groups.count - 1].append(clip)
            } else {
                groups.append([clip])
            }
        }
        return groups.map { ClipGroup(clips: $0) }
    }

    /// True when two clips belong to the same capture session.
    ///
    /// `rollGroupId` is the deterministic per-recording signal: every
    /// clip in one Record→Stop cycle (including all Next-tap splits)
    /// shares the id, by construction. Mixed-nil therefore CANNOT be
    /// from the same recording — one clip explicitly knows which
    /// session it belongs to and the other doesn't. Pre-2026-05-27
    /// the mixed-nil case fell back to time+location and merged
    /// nearby clips; that produced one card for two distinct 5.5-min-
    /// apart recordings in Tom's screenshot. Now: mixed-nil splits.
    ///
    /// The time+location legacy heuristic only runs when BOTH clips
    /// lack a rollGroupId — i.e. truly old data captured before the
    /// roll feature shipped.
    static func sameSession(_ a: InboxClip, _ b: InboxClip) -> Bool {
        switch (a.rollGroupId, b.rollGroupId) {
        case let (.some(aRoll), .some(bRoll)):
            return aRoll == bRoll
        case (.some, .none), (.none, .some):
            // One clip knows its session, the other doesn't — by the
            // rollGroupId invariant they're from different sessions.
            return false
        case (.none, .none):
            // Legacy time+location fallback.
            guard abs(a.capturedAt.timeIntervalSince(b.capturedAt)) <= sessionTimeWindowSeconds else {
                return false
            }
            guard let aLat = a.latitude, let aLon = a.longitude,
                  let bLat = b.latitude, let bLon = b.longitude
            else {
                return true
            }
            return haversineMeters(lat1: aLat, lon1: aLon, lat2: bLat, lon2: bLon)
                <= sessionProximityMeters
        }
    }

    /// Great-circle distance via the haversine formula. Sufficient
    /// precision for the ~50 m session threshold; no CoreLocation
    /// dependency so callable from the static grouping path.
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
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

/// One capture session — the unit of the session-first Captured
/// Clips list. Wraps an ordered set of `InboxClip` rows that the
/// user will bundle into one Memory.
struct ClipGroup: Identifiable, Hashable {
    let clips: [InboxClip]

    static func == (lhs: ClipGroup, rhs: ClipGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Stable identity for SwiftUI ForEach. Sessions are
    /// re-grouped on every `InboxManifest` change, so the id needs
    /// to be deterministic per-content rather than per-build.
    /// `rollGroupId` (when present) or the earliest clipId is
    /// stable across re-groups of the same content.
    var id: UUID {
        clips.first?.rollGroupId ?? clips.first?.clipId ?? UUID()
    }

    var capturedAt: Date {
        // Session's representative time = the earliest clip's
        // capturedAt. Clips inside a group come in newest-first;
        // the session card shows the start of the session.
        clips.last?.capturedAt ?? .distantPast
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var clipCount: Int { clips.count }

    /// Clips with no transcript AND transcription attempted —
    /// today's "likely accidental" predicate.
    var accidentalClips: [InboxClip] {
        clips.filter { $0.transcript.isEmpty && $0.transcriptionAttempted }
    }

    var usableClips: [InboxClip] {
        let accidentals = Set(accidentalClips.map(\.clipId))
        return clips.filter { !accidentals.contains($0.clipId) }
    }

    var isAllAccidental: Bool {
        !clips.isEmpty && usableClips.isEmpty
    }
}

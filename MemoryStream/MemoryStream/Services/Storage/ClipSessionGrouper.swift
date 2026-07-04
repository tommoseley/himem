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
    /// Idle-gap threshold (v3, locked July 4 2026 per `Captured
    /// Clips · session-first · spec.md` § "Idle-gap sessioning"):
    /// clips separated by less than this belong to the same session;
    /// a longer gap closes it. Silence is the boundary. Default 10
    /// minutes covers the dinner-at-the-CIA dogfood case where five
    /// wrist-raises across 9 minutes are obviously *one sitting*.
    ///
    /// Provisional. A real dinner has 10-min+ lulls between courses
    /// which the strict rule wrongly splits; the post-v1 "hold a
    /// block open" affordance is what closes that gap (spec § 3.2).
    ///
    /// **History note:** was 3 min from 2026-05-27 → 2026-07-04
    /// (over-tightened during the wrist-raise-per-session era, when
    /// a 5.5-min-apart pair merged wrongly). The July 4 v3 lock
    /// intentionally trades the occasional over-merge (a dinner
    /// across a very long lull) against the frequent under-merge
    /// (every 4-minute pause splits a real sitting) — the latter
    /// was the dogfood pain.
    static let sessionTimeWindowSeconds: TimeInterval = 10 * 60

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
    /// **v3 (July 4 2026) idle-gap rule.** `rollGroupId` always
    /// overrides — an On-a-roll roll is one session regardless of
    /// gaps because the user already declared it as continuous. For
    /// everything else, silence is the boundary: two consecutive
    /// clips separated by less than `sessionTimeWindowSeconds`
    /// belong to the same sitting. Location is intentionally not
    /// part of the base rule — the spec allows it as a tiebreaker
    /// only when two rolls overlap in time (a rare edge; not
    /// implemented here). Determinism is the point: a clock, not a
    /// classifier.
    ///
    /// **Mixed-nil-rollGroupId split remains.** If one clip has a
    /// rollGroupId and the other doesn't, they belong to different
    /// recordings by the rollGroupId invariant — the one clip
    /// explicitly knows its session and the other doesn't. This
    /// remains stricter than pure idle-gap on purpose.
    static func sameSession(_ a: InboxClip, _ b: InboxClip) -> Bool {
        switch (a.rollGroupId, b.rollGroupId) {
        case let (.some(aRoll), .some(bRoll)):
            return aRoll == bRoll
        case (.some, .none), (.none, .some):
            // One clip knows its session, the other doesn't — by the
            // rollGroupId invariant they're from different sessions.
            return false
        case (.none, .none):
            // Idle-gap rule: clocked silence closes a session.
            return abs(a.capturedAt.timeIntervalSince(b.capturedAt)) <= sessionTimeWindowSeconds
        }
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

    /// What the collapsed Captured Clips card should show in its
    /// body region. Introduced 2026-05-29 to close a contradictory-
    /// display bug where a single-clip session whose only clip was
    /// accidental rendered both "Transcribing…" (body) and "1 clip
    /// auto-excluded · no speech" (footer) at once.
    ///
    /// Rules:
    ///   - At least one usable transcript → `.preview(joined)`
    ///   - No usable transcripts AND every clip has been attempted
    ///     (so we know nothing more is coming) → `.allAccidental`,
    ///     and the body renders nothing (the footer's accidental
    ///     line carries the message)
    ///   - At least one clip is still pending (attempted == false)
    ///     → `.transcribing`, the legitimate in-flight state
    var collapsedBodyVariant: CollapsedBodyVariant {
        let fragments = clips.compactMap { clip -> String? in
            let t = clip.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if !fragments.isEmpty {
            return .preview(fragments.joined(separator: " \u{2026} "))
        }
        if isAllAccidental {
            return .allAccidental
        }
        return .transcribing
    }
}

enum CollapsedBodyVariant: Equatable {
    case preview(String)
    case transcribing
    case allAccidental
}

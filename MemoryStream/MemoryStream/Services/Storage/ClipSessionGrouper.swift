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
    ///
    /// `soloClipIds` — voice clip ids the user has *Removed from
    /// session* (`Clip model · spec.md` § "Clip triage" July 12
    /// 2026). Each solo clip becomes its own single-clip group
    /// regardless of neighbours in the idle window; the remaining
    /// clips still session together across the removed one. This
    /// lets the user pull a stray clip out of the middle of a
    /// three-clip sitting without splitting the surviving pair.
    /// Empty set (default) preserves the pre-July-12 behaviour.
    static func group(_ clips: [InboxClip], soloClipIds: Set<UUID> = []) -> [ClipGroup] {
        let sorted = clips.sorted { $0.capturedAt > $1.capturedAt }
        var regularGroups: [[InboxClip]] = []
        var soloGroups: [[InboxClip]] = []
        for clip in sorted {
            if soloClipIds.contains(clip.clipId) {
                soloGroups.append([clip])
                continue
            }
            if let lastGroup = regularGroups.last, let lastClip = lastGroup.last,
               sameSession(lastClip, clip) {
                regularGroups[regularGroups.count - 1].append(clip)
            } else {
                regularGroups.append([clip])
            }
        }
        // Merge regular + solo, then sort by the group's first
        // (newest) clip so the bench stays reverse-chronological
        // regardless of where the solo clip fell in time.
        let combined = (regularGroups + soloGroups).map { ClipGroup(clips: $0) }
        return combined.sorted { lhs, rhs in
            let l = lhs.clips.first?.capturedAt ?? .distantPast
            let r = rhs.clips.first?.capturedAt ?? .distantPast
            return l > r
        }
    }

    /// True when two clips belong to the same capture session.
    ///
    /// **v3 (July 4 2026, revised same day) idle-gap rule.**
    ///
    /// - **Same rollGroupId** → always one session. Spec § 39:
    ///   "rollGroupId always overrides — an On-a-roll roll is one
    ///   session regardless of gaps." A long pause inside a
    ///   declared roll doesn't split it because the user already
    ///   declared it continuous.
    ///
    /// - **Any other case** (both nil, mixed nil/some, or two
    ///   different non-nil rollGroupIds) → apply the idle-gap.
    ///   Silence is the boundary. Two wrist-raises 4 min apart
    ///   are one sitting even though each carries its own auto-
    ///   generated rollGroupId — that's the CIA dinner dogfood
    ///   pattern (July 4). Two recordings 30 min apart split
    ///   even if they share nil rollGroupIds — the silence closed
    ///   the session.
    ///
    /// **This intentionally supersedes the 2026-05-27 "mixed-nil
    /// splits" and "different-rollGroupIds split" rules.** Those
    /// were written when each Record→Stop cycle was thought of as
    /// its own session; the v3 spec redefines a session as *a
    /// sitting*, which is a clock property, not a recording
    /// property. rollGroupId still binds a declared roll together;
    /// it no longer separates otherwise-close-in-time captures.
    ///
    /// Location isn't part of the base rule — the spec allows it
    /// as a tiebreaker only when two rolls overlap in time (rare
    /// edge; not implemented here).
    static func sameSession(_ a: InboxClip, _ b: InboxClip) -> Bool {
        // Same-roll short-circuit: user-declared continuity beats
        // the clock in both directions.
        if let aRoll = a.rollGroupId,
           let bRoll = b.rollGroupId,
           aRoll == bRoll {
            return true
        }
        // Everything else falls through to the idle-gap. Different
        // rollGroupIds (auto-generated per wrist-raise) don't split
        // clips that would otherwise be one sitting by the clock.
        return abs(a.capturedAt.timeIntervalSince(b.capturedAt)) <= sessionTimeWindowSeconds
    }
}

/// One capture session — the unit of the session-first Captured
/// Clips list. Wraps an ordered set of `InboxClip` rows that the
/// user will bundle into one Memory.
struct ClipGroup: Identifiable, Hashable {
    let clips: [InboxClip]

    /// Equality/hash reflect **membership + content**, not just `id`
    /// (P0 2026-07-14). `id` is the `rollGroupId`, which is stable no
    /// matter how many clips remain — so id-only equality made a
    /// 3-clip group and a post-delete 2-clip group compare *equal*,
    /// and SwiftUI (which uses `Equatable`/`Hashable` for
    /// change-detection and `navigationDestination` identity) skipped
    /// the re-render: the opened session kept showing every clip, both
    /// waveform badges stuck at the old count, and the deleted clip's
    /// row stayed tappable → a blank detail that self-dismissed. The
    /// header escaped it only because it reads `InboxManifest.count`
    /// directly. Comparing the clips fixes change-detection while `id`
    /// (below) stays stable so `ForEach` row identity survives a
    /// delete. Same disease + cure as `EntryDisplayModel`
    /// (`DisplayModels.swift`), which had the identical id-only
    /// staleness bug.
    static func == (lhs: ClipGroup, rhs: ClipGroup) -> Bool {
        lhs.clips == rhs.clips
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(clips.map(\.clipId))
    }

    /// Stable identity for SwiftUI ForEach. Sessions are
    /// re-grouped on every `InboxManifest` change, so the id needs
    /// to be deterministic per-content rather than per-build.
    /// `rollGroupId` (when present) or the earliest clipId is
    /// stable across re-groups of the same content — deliberately
    /// membership-*independent* so a row keeps its identity across an
    /// add/delete (equality, above, carries the change).
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
        // Locked July 12 2026 (`Clip model · spec.md` §Model):
        // "preview of the FIRST clip's words (capture order, never a
        // concatenation of all clips)." The grouper stores clips
        // newest-first; capture-order first = oldest = the end of
        // the array. Falls through to the next-earliest clip with
        // words when the earliest one has an empty transcript — same
        // rule, just picking a later fragment, never joining across
        // clips.
        let earliestFirst = clips.sorted { $0.capturedAt < $1.capturedAt }
        let firstWithWords = earliestFirst.first { clip in
            !clip.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let firstWithWords {
            return .preview(firstWithWords.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
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

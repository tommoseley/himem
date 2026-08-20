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
    /// **Coupling, added 2026-08-02 (F36) — this constant now has a second
    /// visible effect.** The New lens reads it to decide how long a clip
    /// stays "still in play" after being opened, so retuning the grouping
    /// threshold also retunes how long clips linger in New. That is
    /// deliberate — one notion of "still in play" for the lens and the
    /// grouper — but it means a future tuning changes two behaviours, and
    /// this value has already moved once (3 min → 10 min, July 4).
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
    /// **The empty case must never mint a fresh UUID** (device, 2026-08-09).
    ///
    /// It did — so an empty group's identity changed on *every read*, and
    /// `ForEach` reads identity repeatedly. SwiftUI could never converge on a
    /// diff and the Clips screen wedged: fast render, small bench, no loop of
    /// our own, the churn entirely inside SwiftUI's diffing. Four `body` passes
    /// at 0.4ms each and then silence. Proven by this fix — a stable sentinel
    /// closed the hang on its own.
    ///
    /// The doc above says the id is "deterministic per-content"; the fallback
    /// was the one branch where it was not, which is why it read as safe.
    ///
    /// `emptyGroupId` is a fixed sentinel, so two empty groups now COLLIDE on
    /// one id rather than each inventing a new one. That is deliberate: a
    /// visibly wrong list is a far better failure than an unkillable freeze,
    /// and a collision is diagnosable where per-read churn is not.
    ///
    /// This predates C2 step 2b-ii (it is present at `5fdd0a6^`), so it is
    /// fixed here on its own merits rather than folded into that step's redo —
    /// reverting 2b-ii would otherwise have hidden it again (the F6d lesson:
    /// removing the trigger while leaving the defect live is how it goes
    /// invisible).
    static let emptyGroupId = UUID(uuidString: "00000000-0000-0000-0000-00000000E317")!

    var id: UUID {
        clips.first?.rollGroupId ?? clips.first?.clipId ?? Self.emptyGroupId
    }

    var capturedAt: Date {
        // Session's representative time = the earliest clip's
        // capturedAt. Clips inside a group come in newest-first;
        // the session card shows the start of the session.
        clips.last?.capturedAt ?? .distantPast
    }

    var totalDuration: TimeInterval {
        Self.totalDuration(of: clips)
    }

    var clipCount: Int { clips.count }

    /// Clips with no transcript AND transcription attempted —
    /// today's "likely accidental" predicate.
    var accidentalClips: [InboxClip] {
        Self.accidentalClips(in: clips)
    }

    var usableClips: [InboxClip] {
        Self.usableClips(in: clips)
    }

    var isAllAccidental: Bool {
        Self.isAllAccidental(clips)
    }

    // MARK: - Voice derivations, as functions of the clips alone
    //
    // **Lifted from the computed vars above — C2 step 4 slice C, 2026-08-19.**
    //
    // These four (plus `collapsedBodyVariant` below) read `clips` and nothing
    // else, so they are properties of a *list of voice clips*, not of a
    // `ClipGroup`. Slice C retires the voice-only projection at the card layer,
    // and `ResolvedSession` needs exactly these derivations over the voice half
    // of its items.
    //
    // The alternative was for the card layer to build a throwaway
    // `ClipGroup(clips: voice)` to reach them. That is how B25 happened: a
    // projection constructed for one purpose, whose `id` was then read as an
    // identity it was never fit to carry. Rather than construct the type and
    // rely on nobody touching its `id`, the derivations move to where the `id`
    // does not exist at all — the defect is removed by construction rather than
    // by a rule someone has to remember (CLAUDE.md § Non-Negotiables).
    //
    // The instance properties delegate rather than duplicate, so
    // `SessionCollapsedBodyVariantTests` and the rest keep testing the one
    // implementation both callers reach.

    static func totalDuration(of clips: [InboxClip]) -> TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    static func accidentalClips(in clips: [InboxClip]) -> [InboxClip] {
        clips.filter { $0.transcript.isEmpty && $0.transcriptionAttempted }
    }

    static func usableClips(in clips: [InboxClip]) -> [InboxClip] {
        let accidentals = Set(accidentalClips(in: clips).map(\.clipId))
        return clips.filter { !accidentals.contains($0.clipId) }
    }

    static func isAllAccidental(_ clips: [InboxClip]) -> Bool {
        !clips.isEmpty && usableClips(in: clips).isEmpty
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
        Self.collapsedBodyVariant(of: clips)
    }

    /// See `collapsedBodyVariant` above for the rules; lifted alongside the
    /// other voice derivations in slice C so `ResolvedSession` reaches the same
    /// implementation without constructing a `ClipGroup`.
    static func collapsedBodyVariant(of clips: [InboxClip]) -> CollapsedBodyVariant {
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
        if isAllAccidental(clips) {
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

// `BenchLensClips` lived here until 2026-08-10 and is deleted with the
// follow-up to C2 step 2b-ii-c2. It answered "which bench CLIPS does this lens
// show?" at the item level; F37 inverted that to "which SESSIONS does this lens
// admit?", and the answer moved into `RenderedBench.compose` — which by then was
// also the only thing that could have called it. Its behavioural coverage lives
// in `RenderedBenchTests` and its threshold guard in `ClipsStillInPlayTests`,
// re-anchored on `compose`.
//
// Deleted rather than left in place. A type with no production caller whose
// tests still pass is the shape this project has now been bitten by twice —
// `FirstImportState`'s zero production readers under a doc asserting a completed
// contract, and the hand-rolled second `AVAudioPlayer` while `AudioPlayerService`
// sat unused. Green tests over dead code read as coverage and are not.

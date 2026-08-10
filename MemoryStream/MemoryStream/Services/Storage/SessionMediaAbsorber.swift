import Foundation
import CoreData

/// Bridges voice-only `ClipGroup` sessions to the unplaced
/// `MediaReference` pool: given a list of voice sessions and a list
/// of unplaced media refs, return which media items belong inside
/// which session (by time-window overlap).
///
/// Introduced 2026-07-11 for the media-agnostic idle-gap fix
/// (`Captured Clips · session-first · spec.md` §Model, July 11
/// lock). Prior to this, photo/video/note captures floated above
/// their voice-session sitting in a separate `unplacedDayGroupedStack`
/// — a photo shot 2 minutes after a voice clip appeared in a stack
/// on top of the session card it belonged to, not inside it. This
/// helper folds them in.
///
/// A media item is *absorbed* into a session when its `createdAt`
/// falls within `[session.earliestCapturedAt −
/// sessionTimeWindowSeconds/2, session.latestCapturedAt +
/// sessionTimeWindowSeconds/2]`. The half-window on each side keeps
/// the "one sitting" idea symmetric — a photo at the tail of a
/// dinner still joins even if the last voice clip was a few minutes
/// earlier.
///
/// **Not full sessioning.** The proper (Slice H) solution is a
/// single unified list built from `UnifiedBenchGrouper`, which
/// promotes lone media items into their own singleton sessions and
/// unifies the whole render pipeline. This absorber is a targeted
/// bridge so mixed sessions land now, while the top-level list
/// merger ships next.
enum SessionMediaAbsorber {

    /// For each voice session, which unplaced media refs belong
    /// inside it by time. Also returns the set of media ids that
    /// were absorbed, so the caller can filter those out of any
    /// separate unplaced list to avoid double-rendering.
    struct Result {
        let mediaBySessionId: [UUID: [MediaReference]]
        let absorbedRefIds: Set<UUID>
    }

    static func absorb(
        sessions: [ClipGroup],
        unplacedMedia: [MediaReference]
    ) -> Result {
        guard !sessions.isEmpty, !unplacedMedia.isEmpty else {
            return Result(mediaBySessionId: [:], absorbedRefIds: [])
        }
        var mediaBySessionId: [UUID: [MediaReference]] = [:]
        var absorbedIds = Set<UUID>()
        let half = ClipSessionGrouper.sessionTimeWindowSeconds / 2

        for session in sessions {
            let times = session.clips.map(\.capturedAt)
            guard let earliest = times.min(), let latest = times.max() else { continue }
            let windowStart = earliest.addingTimeInterval(-half)
            let windowEnd = latest.addingTimeInterval(half)

            let inWindow = unplacedMedia.filter { ref in
                guard let created = ref.createdAt else { return false }
                // Skip note-only refs — they don't have a chrono anchor
                // yet that makes sense to absorb; leave them in the
                // unplaced stack until Slice H unifies both flows.
                guard ref.mediaTypeEnum != .note else { return false }
                return created >= windowStart && created <= windowEnd
            }
            if !inWindow.isEmpty {
                mediaBySessionId[session.id] = inWindow.sorted {
                    ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
                }
                for ref in inWindow {
                    absorbedIds.insert(ref.id)
                }
            }
        }
        return Result(mediaBySessionId: mediaBySessionId, absorbedRefIds: absorbedIds)
    }
}

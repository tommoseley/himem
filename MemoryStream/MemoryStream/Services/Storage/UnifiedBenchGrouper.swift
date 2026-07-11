import Foundation

/// One item on the Clips bench — a captured fragment of any media
/// type. Value-typed by design so the grouper stays pure (no Core
/// Data or file I/O leakage); the view layer resolves back to the
/// concrete `InboxClip` / `MediaReference` by `id`.
///
/// Introduced 2026-07-11 for the media-agnostic idle-gap fix
/// (`Captured Clips · session-first · spec.md` §Model): a photo
/// captured within the idle window of a voice clip must land in
/// the same session card, not float above it in a separate stack.
struct BenchClipItem: Equatable, Hashable {
    let id: UUID
    let kind: Kind
    let capturedAt: Date
    /// On-a-roll signal from the phone/watch voice pipeline. Nil for
    /// media clips (photos/videos/notes have no roll concept).
    /// A shared non-nil `rollGroupId` binds items into one session
    /// regardless of the idle-gap clock — the user declared it
    /// continuous.
    let rollGroupId: UUID?

    enum Kind: Equatable, Hashable {
        case voice
        case image
        case video
        case note
    }
}

/// One capture session — the mixed-media analogue of `ClipGroup`.
/// Contains any combination of voice/image/video/note items sharing
/// an idle-gap window.
struct UnifiedSession: Identifiable, Hashable {
    /// Session items, sorted **oldest-first** so the reader can watch
    /// the sitting unfold in the natural order (matches
    /// `ScrMixedSession` in `screens-clips-page.jsx`).
    let items: [BenchClipItem]

    static func == (lhs: UnifiedSession, rhs: UnifiedSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Stable identity for SwiftUI ForEach — deterministic per-content
    /// so re-grouping doesn't churn the diff. Prefers a shared
    /// `rollGroupId` (present on declared rolls) over the earliest
    /// item's id.
    var id: UUID {
        items.first?.rollGroupId ?? items.first?.id ?? UUID()
    }

    /// The session's representative time = its earliest item's
    /// timestamp (the sitting *began* here).
    var capturedAt: Date {
        items.first?.capturedAt ?? .distantPast
    }

    var itemCount: Int { items.count }

    var hasVoice: Bool { items.contains(where: { $0.kind == .voice }) }
    var hasMedia: Bool {
        items.contains(where: { $0.kind == .image || $0.kind == .video })
    }
    var hasNote: Bool { items.contains(where: { $0.kind == .note }) }
}

/// Groups `BenchClipItem`s into `UnifiedSession`s using the same
/// idle-gap rule as `ClipSessionGrouper` — extended to work across
/// media types.
///
/// **Rule** (media-agnostic, locked July 11 2026):
/// - A shared, non-nil `rollGroupId` binds items into one session
///   regardless of the clock. The user declared it continuous.
/// - Otherwise the idle-gap boundary from `ClipSessionGrouper`
///   applies: items separated by less than
///   `ClipSessionGrouper.sessionTimeWindowSeconds` (default 10 min)
///   are the same session; a longer gap closes it. Silence is the
///   boundary. Media type is irrelevant to the boundary.
///
/// Sessions are returned **newest-first** at the top level (matching
/// the reverse-chronological bench list), but items *within* each
/// session are **oldest-first** (the sitting reads in the direction
/// it happened).
enum UnifiedBenchGrouper {

    static func group(_ items: [BenchClipItem]) -> [UnifiedSession] {
        guard !items.isEmpty else { return [] }
        // Chronological input drives the boundary decision — walk the
        // list oldest-to-newest so `sameSession` gates against the
        // most recently added item in the growing session.
        let ascending = items.sorted { $0.capturedAt < $1.capturedAt }
        var buckets: [[BenchClipItem]] = []
        for item in ascending {
            if let lastBucket = buckets.last,
               let lastItem = lastBucket.last,
               sameSession(lastItem, item) {
                buckets[buckets.count - 1].append(item)
            } else {
                buckets.append([item])
            }
        }
        // Buckets already carry items in oldest-first order (as
        // required). Reverse the *bucket* order so the resulting
        // list of sessions is newest-first.
        return buckets.reversed().map { UnifiedSession(items: $0) }
    }

    /// True when two items belong to the same capture session.
    /// Mirrors `ClipSessionGrouper.sameSession` semantics — a
    /// shared, non-nil `rollGroupId` short-circuits; otherwise
    /// idle-gap applies.
    static func sameSession(_ a: BenchClipItem, _ b: BenchClipItem) -> Bool {
        if let aRoll = a.rollGroupId, let bRoll = b.rollGroupId, aRoll == bRoll {
            return true
        }
        let gap = abs(a.capturedAt.timeIntervalSince(b.capturedAt))
        return gap <= ClipSessionGrouper.sessionTimeWindowSeconds
    }
}

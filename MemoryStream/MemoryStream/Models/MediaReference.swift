import Foundation
import CoreData

@objc(MediaReference)
public class MediaReference: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var mediaType: String // "image", "voice", "video", "note"
    /// Photo/video local-asset id (PHAsset) or audio filename for `.voice`.
    /// Empty/unused for `.note` fragments.
    @NSManaged public var osIdentifier: String
    @NSManaged public var isAccessible: Bool
    @NSManaged public var createdAt: Date?
    /// Bumped by every `EntryLifecycleService` edit path that mutates
    /// a clip's content (note `text`, voice `transcript`, etc.). Drives
    /// the edit half of `JournalEntry.hasChangesSinceLastOrganize` so a
    /// memory whose clips were edited (without new clips added) still
    /// surfaces the Refresh affordance. Nil for never-edited clips.
    @NSManaged public var lastEditedAt: Date?
    /// On-a-roll grouping signal. Stamped at recording-session start
    /// (see `NextClipController`) and preserved across Next taps —
    /// every clip in the same roll carries the same `rollGroupId`.
    /// The phone-side session-grouper consults this as a
    /// deterministic override over time+location heuristics, so a
    /// roll that spans a long walk lands in one Memory even if
    /// location drifts. Nil for clips captured before this feature
    /// (and for non-voice fragments that don't need it).
    /// See `docs/design/on-a-roll-spec.md` § Implementation notes.
    @NSManaged public var rollGroupId: UUID?
    /// Per-clip location captured at recording-session start. Watch
    /// clips carry the watch's one-shot fix; phone clips snapshot the
    /// composer's start-of-session fix. Nil for clips captured before
    /// this attribute (existing watch-/phone-recorded data) and for
    /// `.note` typed fragments that never call a locator.
    @NSManaged public var latitude: NSNumber?
    @NSManaged public var longitude: NSNumber?
    /// Cached reverse-geocoded place name, e.g. "Bishop St, Bluffton".
    /// Format mirrors `JournalEntry.locationName` and runs through
    /// `PlacemarkFormatter.displayName(from:)`. Resolved lazily by
    /// the ingestion path after the lat/lon are stored, so the clip's
    /// row can render the city name without a render-time geocode
    /// hop. Nil while the resolve is in flight, or for legacy clips
    /// and `.note` fragments.
    @NSManaged public var placeName: String?
    @NSManaged public var thumbnailCacheFilename: String?
    /// Speech-recognition transcript for `.voice` fragments. Nil for
    /// other types and for legacy voice refs created before this
    /// attribute existed.
    @NSManaged public var transcript: String?
    /// Body text for `.note` fragments (typed notes that live in the
    /// chronological capture stream alongside voice/photo/video). Nil for
    /// non-note types.
    @NSManaged public var text: String?
    /// Human-written description for `.image` and `.video` fragments —
    /// the manual stand-in for the future visual-analysis pass. Per
    /// `docs/design/HiMem · Photo Descriptions.html`: AI Organize and
    /// search read this exactly like a voice transcript, so a photo-
    /// only memory becomes organizable and findable now. Nil for
    /// voice/note types and for image/video items the user hasn't
    /// described yet. Storage attribute is `mediaDescription` (not
    /// `description`) because `description` collides with `NSObject`.
    @NSManaged public var mediaDescription: String?
    /// Where this clip was captured — "phone" / "watch" / "mac" (mirrors
    /// `JournalEntry.SourceDevice`). Drives the per-clip source glyph on
    /// the clip card (Finding-2, July 18 2026 schema batch). Nil = unknown
    /// (legacy clips captured before this attribute) → no glyph shown; a
    /// nil never falsely claims "phone."
    @NSManaged public var sourceDevice: String?
    /// Edges linking this clip to any memory (0–N). Membership is
    /// exclusively encoded here per the v1 ontology (clip is evidence;
    /// interpretation lives on the edge).
    @NSManaged public var edges: NSSet?
    /// Non-nil = this clip is in Recently Deleted (P8, July 19 2026).
    /// Set by an explicit "Delete this Clip", a batch delete, OR the
    /// last-reference auto-retire when its only memory is Let Go. A
    /// recycled clip is excluded from every bench/memory query and purged
    /// after 30 days. Rides the V8 CloudKit deploy. Mirrors
    /// `JournalEntry.recycledAt` / `Project.recycledAt`.
    @NSManaged public var recycledAt: Date?
}

extension MediaReference {
    /// LIVE memories this clip is attached to, sorted by `linkedAt`
    /// descending — most-recently-attached first (matches the
    /// "Referenced in" list ordering on Clip Detail).
    ///
    /// A **recycled** memory is NOT a live connection: its edge is preserved
    /// (so restoring the memory reunites them) but it must not surface here,
    /// or a clip whose only memory is in the trash strands in Clips/All
    /// advertising an invisible "Untitled memory" (TestFlight #4a, 2026-07-25).
    /// `isRecycled` is a scalar `Bool` (nil reads `false` → live), so this is
    /// nil-safe for CloudKit-synced records. Mirrors
    /// `JournalEntry.projectsArray`, which already filters recycled.
    var memoriesArray: [JournalEntry] {
        edgesArray.compactMap { $0.memory }.filter { !$0.isRecycled }
    }

    /// Edges attaching this clip to memories, sorted by `linkedAt`
    /// descending. Nil-safe — a `MemoryClipEdge` row imported before
    /// the `linkedAt` cell was populated sinks to the bottom rather
    /// than trapping the getter (July 11 2026 crash fix — see
    /// `MemoryClipEdge.linkedAt` doc).
    var edgesArray: [MemoryClipEdge] {
        let set = edges as? Set<MemoryClipEdge> ?? []
        return set.sorted { ($0.linkedAt ?? .distantPast) > ($1.linkedAt ?? .distantPast) }
    }

    /// Alias — semantic view of `memoriesArray` for Clip Detail's
    /// "Referenced in" list. Sorted by `linkedAt` descending.
    var referencingMemoriesSortedByLinkedAtDesc: [JournalEntry] {
        memoriesArray
    }

    /// Number of **live** memories referencing this clip — the connection
    /// count. Drives "Evidence in N memories", delete-warning copy, and the
    /// clip's connected/Unconnected read. Recycled memories don't count (see
    /// `memoriesArray`), so a clip whose only memory is trashed reads as
    /// Unconnected rather than advertising it.
    var referencingMemoryCount: Int {
        memoriesArray.count
    }

    /// RAW edge count — every edge regardless of the memory's recycled state.
    /// The P8 last-reference recycle/restore rule is defined on *pure edge
    /// count at delete time* (`EntryLifecycleService.recycle`/`restore`), a
    /// deliberate no-history design; it uses this, NOT the recycled-aware
    /// `referencingMemoryCount`, so that lock is preserved unchanged.
    var edgeCount: Int {
        (edges as? Set<MemoryClipEdge>)?.count ?? 0
    }

    /// Fetch predicate for "no live-memory connection" — the Unconnected lens.
    /// An edge to a recycled memory (or a dangling edge with no memory) is not
    /// a connection, so a clip whose only memory is trashed matches here and
    /// surfaces on the Unconnected bench. Nil-safe on the optional `isRecycled`
    /// (a NULL-flagged synced memory is live, so its clip is NOT unconnected).
    static var noLiveMemoryConnectionPredicate: NSPredicate {
        NSPredicate(format: "SUBQUERY(edges, $e, $e.memory != nil AND ($e.memory.isRecycled == NO OR $e.memory.isRecycled == nil)).@count == 0")
    }
}

extension MediaReference {
    /// Fragment kinds that can hang off a Memory. The "media" name is
    /// historical — `.note` is a typed-text fragment with no underlying
    /// asset; the others reference an audio/photo/video file.
    enum MediaType: String, Hashable {
        case image = "image"
        case voice = "voice"
        case video = "video"
        case note = "note"
    }

    var mediaTypeEnum: MediaType {
        MediaType(rawValue: mediaType) ?? .image
    }
}

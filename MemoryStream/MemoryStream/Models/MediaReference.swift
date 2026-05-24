import Foundation
import CoreData

@objc(MediaReference)
public class MediaReference: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
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
    @NSManaged public var entry: JournalEntry?
}

extension MediaReference {
    /// Fragment kinds that can hang off a Memory. The "media" name is
    /// historical — `.note` is a typed-text fragment with no underlying
    /// asset; the others reference an audio/photo/video file.
    enum MediaType: String {
        case image = "image"
        case voice = "voice"
        case video = "video"
        case note = "note"
    }

    var mediaTypeEnum: MediaType {
        MediaType(rawValue: mediaType) ?? .image
    }
}

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

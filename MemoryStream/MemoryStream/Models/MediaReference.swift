import Foundation
import CoreData

@objc(MediaReference)
public class MediaReference: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
    @NSManaged public var mediaType: String // "image", "voice", "video"
    @NSManaged public var osIdentifier: String
    @NSManaged public var isAccessible: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var thumbnailCacheFilename: String?
    /// Transcript captured at recording time for `.voice` refs. Nil for
    /// image/video refs and for legacy voice refs created before this
    /// attribute existed.
    @NSManaged public var transcript: String?
    @NSManaged public var entry: JournalEntry?
}

extension MediaReference {
    enum MediaType: String {
        case image = "image"
        case voice = "voice"
        case video = "video"
    }

    var mediaTypeEnum: MediaType {
        MediaType(rawValue: mediaType) ?? .image
    }
}

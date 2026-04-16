import Foundation
import CoreData

@objc(MediaReference)
public class MediaReference: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var entryId: UUID
    @NSManaged public var mediaType: String // "image", "voice", "video"
    @NSManaged public var osIdentifier: String
    @NSManaged public var isAccessible: Bool
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

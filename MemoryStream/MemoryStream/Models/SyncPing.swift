import Foundation
import CoreData

@objc(SyncPing)
public class SyncPing: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
}

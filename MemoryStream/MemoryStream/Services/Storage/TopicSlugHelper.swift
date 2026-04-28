import Foundation

/// Single source of truth for topic slug generation.
/// Replaces 3 duplicate inline implementations.
enum TopicSlugHelper {
    static func slugify(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

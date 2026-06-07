import Foundation

/// Dispatch helper that classifies a `MediaReference.osIdentifier` as
/// either a ubiquity filename (HiMem-owned bytes in the iCloud Drive
/// container) or a `PHAsset.localIdentifier` (legacy reference to the
/// user's Photos library).
///
/// **Why both formats exist.** Per
/// `docs/design/Storage architecture · CLAUDE.md` Rule 1, new captures
/// store their bytes in the ubiquity container and the
/// `osIdentifier` records the filename. Pre-migration MediaReference
/// rows still hold `PHAsset.localIdentifier` strings — those rows
/// resolve via PhotoKit until Phase 7's migration copies them into
/// ubiquity.
///
/// **The disambiguation.** `PHAsset.localIdentifier` strings have the
/// shape `<UUID>/L0/001` (always contain `/`). Ubiquity filenames are
/// single path components like `<UUID>.jpg` (never contain `/`). The
/// check is intentionally syntactic; even a freshly minted ubiquity
/// filename never carries a slash, and PhotoKit identifiers always do.
enum MediaResolver {

    enum Resolution {
        /// `osIdentifier` is a ubiquity filename. Read directly from the URL.
        case ubiquity(URL)
        /// `osIdentifier` is a `PHAsset.localIdentifier`. Caller must use PhotoKit.
        case photoKit(identifier: String)
    }

    static func resolve(osIdentifier: String, mediaType: MediaReference.MediaType) -> Resolution {
        if isPhotoKitIdentifier(osIdentifier) {
            return .photoKit(identifier: osIdentifier)
        }
        switch mediaType {
        case .image:
            return .ubiquity(UbiquityStore.shared.photoURL(for: osIdentifier))
        case .video:
            return .ubiquity(UbiquityStore.shared.videoURL(for: osIdentifier))
        case .voice:
            return .ubiquity(UbiquityStore.shared.audioURL(for: osIdentifier))
        case .note:
            // Notes don't carry an external file — `osIdentifier` is
            // an internal marker. Treat as ubiquity (the path is
            // never read for `.note`).
            return .ubiquity(UbiquityStore.shared.photoURL(for: osIdentifier))
        @unknown default:
            return .ubiquity(UbiquityStore.shared.photoURL(for: osIdentifier))
        }
    }

    /// True iff `osIdentifier` looks like a `PHAsset.localIdentifier`
    /// (contains a slash). PhotoKit's IDs are `<UUID>/L0/001`; HiMem's
    /// ubiquity filenames never contain a slash.
    static func isPhotoKitIdentifier(_ osIdentifier: String) -> Bool {
        osIdentifier.contains("/")
    }
}

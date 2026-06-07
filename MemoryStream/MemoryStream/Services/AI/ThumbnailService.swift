import Foundation
import Photos
import UIKit
import CryptoKit

@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let thumbnailSize = CGSize(width: 200, height: 200)

    // MARK: - Cache Directory (Library/Caches — excluded from backup, OS-evictable)

    static var thumbnailDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func thumbnailURL(for filename: String) -> URL {
        thumbnailDirectory.appendingPathComponent(filename)
    }

    /// Filename derived from the asset's local identifier. Same identifier
    /// always maps to the same file, which lets `cacheThumbnail` skip the
    /// PHImageManager round-trip and disk write on repeat calls.
    private func cacheFilename(for localIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data(localIdentifier.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex + ".jpg"
    }

    // MARK: - Synchronous disk read

    func cachedThumbnail(filename: String) -> UIImage? {
        let url = Self.thumbnailURL(for: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Fetch from PHImageManager and cache to disk

    /// Idempotent: if a thumbnail for `localIdentifier` is already on disk,
    /// returns the existing filename without re-fetching. The composer
    /// view re-runs its `.task` on every appearance and we want repeats
    /// to be free.
    ///
    /// Routes via `MediaResolver`: ubiquity-backed media (HiMem-owned
    /// bytes) loads the file directly + resizes; PhotoKit-backed media
    /// (legacy `PHAsset.localIdentifier`) takes the original
    /// `PHImageManager` path.
    func cacheThumbnail(for localIdentifier: String) async -> String? {
        let filename = cacheFilename(for: localIdentifier)
        let url = Self.thumbnailURL(for: filename)
        if FileManager.default.fileExists(atPath: url.path) {
            return filename
        }

        // Images may be either kind; for thumbnails of audio/video
        // we don't generate a still — that returns nil here and the
        // tile renders without a thumbnail.
        switch MediaResolver.resolve(osIdentifier: localIdentifier, mediaType: .image) {
        case .ubiquity(let fileURL):
            return await ubiquityThumbnail(fileURL: fileURL, cacheURL: url, cacheFilename: filename)
        case .photoKit(let identifier):
            return await phImageManagerThumbnail(identifier: identifier, cacheURL: url, cacheFilename: filename)
        }
    }

    /// Loads the full image from the ubiquity URL, downsamples to the
    /// thumbnail size, writes the cache file, and returns the cache
    /// filename. Returns nil if the file isn't downloaded yet
    /// (ubiquity in progress) — caller will retry on next appearance.
    private func ubiquityThumbnail(fileURL: URL, cacheURL: URL, cacheFilename: String) async -> String? {
        if UbiquityStore.shared.downloadStatus(at: fileURL) == .notDownloaded {
            UbiquityStore.shared.startDownload(at: fileURL)
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        let thumbnail = await image.byPreparingThumbnail(ofSize: thumbnailSize) ?? image
        guard let jpeg = thumbnail.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try jpeg.write(to: cacheURL)
            return cacheFilename
        } catch {
            return nil
        }
    }

    /// Legacy path for `MediaReference.osIdentifier` strings that are
    /// `PHAsset.localIdentifier` values (pre-migration data).
    /// Functionally identical to the pre-2026-06-07 implementation.
    private func phImageManagerThumbnail(identifier: String, cacheURL: URL, cacheFilename: String) async -> String? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !didResume else { return }
                didResume = true
                guard let image,
                      let jpeg = image.jpegData(compressionQuality: 0.8) else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    try jpeg.write(to: cacheURL)
                    continuation.resume(returning: cacheFilename)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Full-resolution fetch for viewer

    func fullImage(for localIdentifier: String) async -> UIImage? {
        switch MediaResolver.resolve(osIdentifier: localIdentifier, mediaType: .image) {
        case .ubiquity(let fileURL):
            if UbiquityStore.shared.downloadStatus(at: fileURL) == .notDownloaded {
                UbiquityStore.shared.startDownload(at: fileURL)
                return nil
            }
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return UIImage(data: data)
        case .photoKit(let identifier):
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
                return nil
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            return await withCheckedContinuation { continuation in
                var didResume = false
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if isDegraded { return }
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Evict

    func evictThumbnail(filename: String) {
        try? FileManager.default.removeItem(at: Self.thumbnailURL(for: filename))
    }
}

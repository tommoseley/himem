import Foundation
import Photos
import UIKit
import CoreData

/// One-shot migration that copies bytes for every PHAsset-backed
/// photo / video `MediaReference` into the iCloud Drive ubiquity
/// container, then updates the `osIdentifier` to the new ubiquity
/// filename. After this migration runs, every `MediaReference.osIdentifier`
/// in the database is a ubiquity filename — the legacy PhotoKit
/// resolution path in `MediaResolver` and `ThumbnailService` only
/// runs for rows the migration hasn't reached yet.
///
/// **Why this exists.** Per
/// `docs/design/Storage architecture · CLAUDE.md` Rule 1, originals
/// must live in iCloud Drive so they're durable across uninstall and
/// available cross-device. Pre-migration `MediaReference` rows hold
/// `PHAsset.localIdentifier` values pointing into the user's Photos
/// library, which has neither property. This migration walks those
/// rows, extracts bytes via PhotoKit, writes them to ubiquity, and
/// rewrites the identifier so subsequent reads use the canonical
/// HiMem-owned copy.
///
/// **Idempotency.** A UserDefaults flag gates the full sweep
/// (`hasCompleted`). Per-row work is also idempotent: each row is
/// re-checked for PhotoKit-id shape before migrating, so a
/// partially-complete sweep resumes correctly on the next launch.
///
/// **Lifecycle.** Wired into `LaunchScreenView.runMigration()` after
/// `UbiquityStore.warmUp()` resolves (otherwise the destination
/// container URL would be nil and the migration would write to the
/// sandbox fallback — defeating the purpose). Runs on a background
/// context so the UI is never blocked.
enum MediaReferenceUbiquityMigration {

    private static let completionKey = "himem.media.ubiquityMigrationV1Complete"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completionKey)
    }

    /// Launches the migration as a background task. Returns immediately;
    /// the migration runs to completion (or partial completion) in the
    /// background and re-runs next launch if interrupted.
    static func scheduleIfNeeded(in storage: StorageService) {
        if hasCompleted { return }
        // Only run when ubiquity is actually available — otherwise
        // we'd "migrate" by moving bytes from PhotoKit into sandbox,
        // gaining nothing and losing the PhotoKit pointer.
        guard UbiquityStore.shared.containerURL != nil else { return }
        Task.detached(priority: .background) {
            await runIfNeeded(in: storage)
        }
    }

    static func runIfNeeded(in storage: StorageService) async {
        if hasCompleted { return }
        guard UbiquityStore.shared.containerURL != nil else { return }
        let context = storage.backgroundContext()
        // Predicate: image OR video AND osIdentifier looks like a
        // PhotoKit identifier (contains "/"). PhotoKit ids always
        // contain a slash; ubiquity filenames never do.
        let ids: [NSManagedObjectID] = await context.perform {
            let request = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            request.predicate = NSPredicate(
                format: "(mediaType == %@ OR mediaType == %@) AND osIdentifier CONTAINS %@",
                MediaReference.MediaType.image.rawValue,
                MediaReference.MediaType.video.rawValue,
                "/"
            )
            request.includesPropertyValues = false
            return ((try? context.fetch(request)) ?? []).map(\.objectID)
        }
        guard !ids.isEmpty else {
            UserDefaults.standard.set(true, forKey: completionKey)
            NSLog("[HiMem][MediaMigration] no PHAsset-backed media to migrate — marking complete")
            return
        }
        NSLog("[HiMem][MediaMigration] migrating \(ids.count) PHAsset-backed media references to ubiquity")
        var migrated = 0
        var skipped = 0
        for objectID in ids {
            let outcome = await migrateOne(objectID: objectID, in: context)
            switch outcome {
            case .migrated:   migrated += 1
            case .skipped:    skipped += 1
            }
        }
        NSLog("[HiMem][MediaMigration] done: migrated=\(migrated), skipped=\(skipped) (PHAsset gone or extract failed)")
        if migrated + skipped == ids.count {
            UserDefaults.standard.set(true, forKey: completionKey)
        }
        // Else: some rows weren't reached for a reason that wasn't a
        // .skipped (cancellation, error during fetch). The flag stays
        // unset; next launch retries.
    }

    private enum Outcome { case migrated, skipped }

    private static func migrateOne(objectID: NSManagedObjectID, in context: NSManagedObjectContext) async -> Outcome {
        // Snapshot the row's identifying state.
        struct Snapshot { let osIdentifier: String; let mediaType: MediaReference.MediaType }
        let snapshot: Snapshot? = await context.perform {
            guard let ref = try? context.existingObject(with: objectID) as? MediaReference else {
                return nil
            }
            let osId = ref.osIdentifier
            guard !osId.isEmpty, osId.contains("/") else { return nil }
            return Snapshot(osIdentifier: osId, mediaType: ref.mediaTypeEnum)
        }
        guard let snapshot else { return .skipped }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [snapshot.osIdentifier], options: nil).firstObject else {
            // PHAsset gone — the row points at a vanished library
            // asset. Leave the osIdentifier untouched; the renderer
            // will show its "missing" state and the user can either
            // delete the row or live with the broken link.
            return .skipped
        }
        let newFilename: String?
        switch snapshot.mediaType {
        case .image:
            newFilename = await extractImageToUbiquity(asset: asset)
        case .video:
            newFilename = await extractVideoToUbiquity(asset: asset)
        default:
            return .skipped
        }
        guard let newFilename else { return .skipped }
        await context.perform {
            guard let ref = try? context.existingObject(with: objectID) as? MediaReference else { return }
            ref.osIdentifier = newFilename
            try? context.save()
        }
        return .migrated
    }

    private static func extractImageToUbiquity(asset: PHAsset) async -> String? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        guard let image, let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let destination = UbiquityStore.shared.photoURL(for: filename)
        do {
            try UbiquityStore.shared.writeData(data, to: destination)
            return filename
        } catch {
            NSLog("[HiMem][MediaMigration] image write failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func extractVideoToUbiquity(asset: PHAsset) async -> String? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let sourceURL: URL? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let sourceURL else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = UbiquityStore.shared.videoURL(for: filename)
        do {
            // PHAsset video URLs point at PhotoKit-owned files inside
            // the user's library cache. We need to COPY (not move)
            // since we don't own the source.
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: sourceURL, to: destination)
            return filename
        } catch {
            NSLog("[HiMem][MediaMigration] video copy failed: \(error.localizedDescription)")
            return nil
        }
    }
}

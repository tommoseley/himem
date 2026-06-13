import Foundation
import Photos
import UIKit
import AVFoundation

@MainActor
final class CameraService: ObservableObject {
    static let shared = CameraService()

    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var cameraAuthorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var error: CameraError?

    enum CameraError: LocalizedError, Equatable {
        case notAuthorized
        case saveFailed(String)

        var errorDescription: String? {
            // User-facing strings only — stock human sentences. Raw
            // detail on `.saveFailed` stays inside the enum for
            // NSLog / telemetry; we don't dump it at the user.
            switch self {
            case .notAuthorized:
                return "HiMem can't save photos to your library. You can allow access in Settings."
            case .saveFailed:
                return "Couldn't save that capture. Try again in a moment."
            }
        }
    }

    // MARK: - Photo Library authorization

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Camera (AVCaptureDevice) authorization
    //
    // Without this preflight, UIImagePickerController(sourceType: .camera) shows
    // a black preview when permission hasn't been resolved yet — exactly what
    // testers hit on first launch after a TestFlight install.

    /// Requests camera access from the user. Returns true if granted (or already
    /// granted), false if denied/restricted. Updates `cameraAuthorizationStatus`.
    @discardableResult
    func requestCameraAccess() async -> Bool {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current == .authorized {
            cameraAuthorizationStatus = .authorized
            return true
        }
        if current == .denied || current == .restricted {
            cameraAuthorizationStatus = current
            return false
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorizationStatus = granted ? .authorized : .denied
        return granted
    }

    /// Convenience used by camera trigger buttons. Returns true if the caller
    /// should proceed to present the picker; surfaces a Settings hint via
    /// ErrorState on denial. Callers are responsible for stopping any active
    /// SpeechService recording before calling this — that path already
    /// releases the audio session cleanly.
    func ensureCameraAccess() async -> Bool {
        let granted = await requestCameraAccess()
        if !granted {
            ErrorState.shared.report(.mediaError("Camera access is off. Enable it in Settings to capture photos and videos."))
        }
        return granted
    }

    // MARK: - Save to ubiquity + Photos library

    /// Saves the captured photo to the iCloud Drive ubiquity container
    /// (the canonical home — that's what `MediaReference.osIdentifier`
    /// will reference) and also to the user's Photos library as a
    /// courtesy (default-on; gated by `alsoSaveToPhotosLibrary`).
    /// Returns the ubiquity filename for `MediaReference.osIdentifier`.
    ///
    /// See `docs/design/Storage architecture · CLAUDE.md` Rule 6.
    func savePhoto(_ image: UIImage) async throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        let destinationURL = UbiquityStore.shared.photoURL(for: filename)
        // JPEG at 0.9 — visually indistinguishable from PNG for photos,
        // ~5-10x smaller. Keeps iCloud quota usage reasonable.
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw CameraError.saveFailed("JPEG encoding failed")
        }
        do {
            try UbiquityStore.shared.writeData(data, to: destinationURL)
        } catch {
            throw CameraError.saveFailed("Ubiquity write failed: \(error.localizedDescription)")
        }
        if alsoSaveToPhotosLibrary {
            // Best-effort secondary write to Photos library. If it
            // fails the user still has the canonical copy in ubiquity;
            // the Photos-library copy is convenience, not authority.
            await savePhotoToPhotosLibrary(image)
        }
        return filename
    }

    /// Saves the captured video to the ubiquity container by moving
    /// the temp file in place, then optionally copies to the Photos
    /// library. Returns the ubiquity filename.
    func saveVideo(at fileURL: URL) async throws -> String {
        let ext = fileURL.pathExtension.isEmpty ? "mov" : fileURL.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destinationURL = UbiquityStore.shared.videoURL(for: filename)
        do {
            // Move into the ubiquity store. NSFileCoordinator ensures
            // a concurrent iCloud sync read sees a consistent state.
            try UbiquityStore.shared.moveIntoStore(sourceURL: fileURL, destinationURL: destinationURL)
        } catch {
            throw CameraError.saveFailed("Ubiquity move failed: \(error.localizedDescription)")
        }
        if alsoSaveToPhotosLibrary {
            await saveVideoToPhotosLibrary(at: destinationURL)
        }
        return filename
    }

    /// User-facing toggle (Settings → "Also save captures to my
    /// Photos library"). **Default off** per the data-custody lock:
    /// media lives in HiMem's iCloud Files container; the Photos copy
    /// is an opt-in courtesy for users who want their captures to
    /// appear in Photos for sharing or printing.
    ///
    /// When on, captures land in a single album named
    /// `Self.photosAlbumName` ("HiMem"). The previous per-topic album
    /// scheme was retired June 10 2026.
    var alsoSaveToPhotosLibrary: Bool {
        UserDefaults.standard.object(forKey: Self.alsoSaveToPhotosLibraryKey) as? Bool ?? false
    }

    static let alsoSaveToPhotosLibraryKey = "himem.camera.alsoSaveToPhotosLibrary"

    /// Single album we drop captures into when the user has opted in.
    /// One album, not per-topic. Created lazily on first save.
    static let photosAlbumName = "HiMem"

    /// Best-effort copy to the user's Photos library, placed in the
    /// "HiMem" album. Returns silently on failure — the canonical
    /// copy is already in ubiquity, and a user without Photos library
    /// permission still keeps their memories.
    private func savePhotoToPhotosLibrary(_ image: UIImage) async {
        guard isAuthorized else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var assetPlaceholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                assetPlaceholder = request.placeholderForCreatedAsset
            } completionHandler: { success, _ in
                if success, let assetPlaceholder {
                    Task {
                        await Self.addAssetToHiMemAlbum(placeholder: assetPlaceholder)
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func saveVideoToPhotosLibrary(at fileURL: URL) async {
        guard isAuthorized else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var assetPlaceholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges {
                if let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL) {
                    assetPlaceholder = request.placeholderForCreatedAsset
                }
            } completionHandler: { success, _ in
                if success, let assetPlaceholder {
                    Task {
                        await Self.addAssetToHiMemAlbum(placeholder: assetPlaceholder)
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Adds a freshly-created asset into the "HiMem" Photos album,
    /// creating the album on first call. Best-effort: failure here
    /// leaves the asset in the user's Photos library at its default
    /// location (still visible to them, just not foldered).
    private static func addAssetToHiMemAlbum(placeholder: PHObjectPlaceholder) async {
        let albumName = Self.photosAlbumName
        let album: PHAssetCollection
        if let existing = findAlbum(named: albumName) {
            album = existing
        } else {
            guard let created = await createAlbum(named: albumName) else { return }
            album = created
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
        guard assets.count > 0 else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets(assets)
        }
    }

    private static func findAlbum(named name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", name)
        return PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: options
        ).firstObject
    }

    private static func createAlbum(named name: String) async -> PHAssetCollection? {
        var placeholder: PHObjectPlaceholder?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(withTitle: name)
                placeholder = request.placeholderForCreatedAssetCollection
            }
        } catch {
            return nil
        }
        guard let localId = placeholder?.localIdentifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [localId], options: nil
        ).firstObject
    }
}

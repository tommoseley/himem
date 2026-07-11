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

    // MARK: - Save to ubiquity

    /// Saves the captured photo to the iCloud Drive ubiquity container —
    /// the canonical (and only) home per the locked data-custody
    /// decision. Returns the ubiquity filename for
    /// `MediaReference.osIdentifier`.
    ///
    /// The old "Also save captures to my Photos library" toggle was
    /// retired 2026-07-10 (see `screens-settings.jsx` lines 5-9,
    /// 231-234): a second copy in Photos contradicted the locked
    /// principle that HiMem media lives in the user's HiMem iCloud
    /// Files folder, never the Photos library.
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
        return filename
    }

    /// Saves the captured video to the ubiquity container by moving
    /// the temp file in place. Returns the ubiquity filename.
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
        return filename
    }
}

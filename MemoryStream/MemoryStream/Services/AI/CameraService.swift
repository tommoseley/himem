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
            switch self {
            case .notAuthorized:
                return "Photo library access denied. Enable in Settings to save captured media."
            case .saveFailed(let detail):
                return "Failed to save media: \(detail)"
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

    // MARK: - Save to Photos

    func savePhoto(_ image: UIImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var localIdentifier: String?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if success, let identifier = localIdentifier {
                    continuation.resume(returning: identifier)
                } else {
                    continuation.resume(throwing: CameraError.saveFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }

    func saveVideo(at fileURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var localIdentifier: String?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                localIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if success, let identifier = localIdentifier {
                    continuation.resume(returning: identifier)
                } else {
                    continuation.resume(throwing: CameraError.saveFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }
}

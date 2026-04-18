import Foundation
import Photos
import UIKit

@MainActor
final class CameraService: ObservableObject {
    static let shared = CameraService()

    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
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

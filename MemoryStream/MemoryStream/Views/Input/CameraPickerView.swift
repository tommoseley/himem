import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct CameraPickerView: UIViewControllerRepresentable {
    enum CaptureResult {
        case photo(UIImage)
        case video(URL)
    }

    enum CaptureMode: String, Identifiable {
        case photo, video, both
        var id: String { rawValue }
    }

    var captureMode: CaptureMode = .both
    var onCapture: (CaptureResult) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.allowsEditing = false
        switch captureMode {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
            picker.cameraCaptureMode = .video
            picker.videoMaximumDuration = 120
        case .both:
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            picker.cameraCaptureMode = .photo
            picker.videoMaximumDuration = 120
        }
        picker.delegate = context.coordinator
        return picker
    }

    // Intentional no-op. Setting cameraCaptureMode or mediaTypes on a live
    // UIImagePickerController tears down its AVCaptureSession (black preview).
    // Once configured in makeUIViewController the picker doesn't need updates;
    // SwiftUI re-renders of the parent must not propagate to it.
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onDismiss: onDismiss)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (CaptureResult) -> Void
        let onDismiss: () -> Void

        init(onCapture: @escaping (CaptureResult) -> Void, onDismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onDismiss = onDismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(.photo(image))
            } else if let videoURL = info[.mediaURL] as? URL {
                onCapture(.video(videoURL))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}

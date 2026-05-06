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
        // PortraitImagePickerController locks the picker to portrait
        // orientation. UIImagePickerController is officially portrait-only
        // (per Apple docs), and the system's landscape adaptation places a
        // portrait-shaped camera viewport inside a landscape window — the
        // user sees a small preview strip with controls floating in black
        // space. Locking to portrait is what Camera, Notes scanner, and
        // most third-party photo apps do.
        let picker = PortraitImagePickerController()
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

/// UIImagePickerController locked to portrait orientation. The system camera
/// preview is portrait-shaped and doesn't adapt cleanly to landscape: in a
/// landscape window iOS shows a small preview strip with controls floating
/// over a black background. Locking the picker to portrait means iOS will
/// rotate the picker view to portrait when presented, regardless of device
/// orientation, matching the behaviour of the system Camera and Notes
/// scanner. The captured photo/video itself respects the gravity-sensed
/// orientation; only the picker's chrome is locked.
final class PortraitImagePickerController: UIImagePickerController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { true }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
}

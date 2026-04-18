import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraPickerView: UIViewControllerRepresentable {
    enum CaptureResult {
        case photo(UIImage)
        case video(URL)
    }

    var onCapture: (CaptureResult) -> Void
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = 120
        picker.delegate = context.coordinator
        return picker
    }

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
            picker.dismiss(animated: true)

            if let image = info[.originalImage] as? UIImage {
                onCapture(.photo(image))
            } else if let videoURL = info[.mediaURL] as? URL {
                onCapture(.video(videoURL))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onDismiss()
        }
    }
}

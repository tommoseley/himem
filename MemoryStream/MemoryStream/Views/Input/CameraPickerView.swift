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
        // Two-layer portrait lock:
        //   1. PortraitImagePickerController declares its own preferred
        //      orientation as .portrait.
        //   2. OrientationLock.shared.portraitOnly = true so the AppDelegate
        //      clamps the whole window to portrait while the picker is up.
        //      Without (2) SwiftUI's .fullScreenCover host VC overrides
        //      any orientation a child VC requests; the picker ends up
        //      adapted to landscape with a portrait-shaped camera viewport
        //      and the user sees the broken-preview behavior Apple's docs
        //      acknowledge.
        // Plus an iOS-16 geometry request to force-rotate now if the
        // device was already in landscape when the picker opened.
        OrientationLock.shared.portraitOnly = true
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
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
        // Photo / video composer is active — disable the system idle
        // timer per the CLAUDE.md "Wake Lock (Idle Timer)" rule.
        // Released in `dismantleUIViewController` so the lock lifts on
        // commit, cancel, or any other dismissal path.
        WakeLock.shared.acquire()
        return picker
    }

    // Intentional no-op. Setting cameraCaptureMode or mediaTypes on a live
    // UIImagePickerController tears down its AVCaptureSession (black preview).
    // Once configured in makeUIViewController the picker doesn't need updates;
    // SwiftUI re-renders of the parent must not propagate to it.
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    /// Release the portrait lock when the picker is torn down so the rest
    /// of the app gets its `allButUpsideDown` orientations back.
    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        OrientationLock.shared.portraitOnly = false
        // Symmetric release of the wake lock acquired in
        // `makeUIViewController`. SwiftUI guarantees dismantle fires
        // on every dismissal path (commit, cancel, scene change), so
        // there's no leak window. MainActor-hop because dismantle is
        // synchronous-nonisolated by the protocol but the wake lock
        // is main-actor-isolated.
        Task { @MainActor in
            WakeLock.shared.release()
        }
    }

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

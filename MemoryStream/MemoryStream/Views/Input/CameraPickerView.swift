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
        // **No runtime orientation clamp. Deleted unconditionally
        // (2026-08-02), widening F18's iPad-only removal.**
        //
        // F18 removed the clamp on iPad after it produced a black preview
        // there, and kept it on iPhone. The device pass settled which half
        // was right: **iPad — the platform that LOST the clamp — works;
        // iPhone — the platform that KEPT it — fails.** F18 was right about
        // the symptom and too narrow about the cause. The ruling was
        // "iPad-only" because iPad was where the failure was observed, not
        // because iPhone was known good.
        //
        // The mechanism the clamp depended on is gone on this OS. The log
        // shows `-[UIApplication statusBarOrientation]`,
        // `isStatusBarHidden` and `setStatusBarHidden:` all reporting
        // "deprecated and is a no-op on 27.0 and later", immediately
        // followed by `Attempted to change to mode Portrait with an
        // unsupported device (BackTriple)` and
        // `CMVideoFormatDescriptionGetDimensions … err=-12710 (Invalid
        // desc)` — the capture device failing to configure, which is what
        // a black preview is. We were fighting a system that had stopped
        // honouring the request.
        //
        // `PortraitImagePickerController` keeps declaring its own preferred
        // orientation — that is the supported way to express the
        // preference, and it is retained deliberately. What is retired is
        // the app-wide runtime clamp (`OrientationLock` +
        // `requestGeometryUpdate`) wrapped around the picker.
        //
        // Guarded by `CameraPickerOrientationTests`.
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

    /// Teardown. The portrait-lock release that used to live here went with
    /// the clamp itself (2026-08-02) — releasing a lock nobody sets is dead
    /// code, and leaving it would imply the clamp still exists.
    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
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

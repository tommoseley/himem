import SwiftUI
import AVFoundation
import Photos

/// Shared sheet/fullscreen plumbing for the Append spec's single-modality
/// capture flows. Bind a `CaptureModality?` and provide an `onCaptured`
/// closure; this modifier presents the appropriate surface for the active
/// modality and forwards the result via the closure.
///
/// Used by both JournalView (capture-new) and EntryExpandedView (append).
/// The two callers differ only in what they do with the result.
struct CaptureFlowHost: ViewModifier {
    @Binding var activeModality: CaptureModality?
    @ObservedObject var speechService: SpeechService
    let onCaptured: (CapturedItem) -> Void

    @State private var isMountingCamera = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: voiceBinding) {
                VoiceCaptureScreen(
                    onFinish: { filename, transcript in
                        onCaptured(.voice(filename: filename, transcript: transcript))
                    },
                    onCancel: {},
                    speechService: speechService
                )
            }
            .sheet(isPresented: noteBinding) {
                NoteCaptureScreen(
                    onFinish: { text in
                        if !text.isEmpty { onCaptured(.note(text: text)) }
                    },
                    onCancel: {}
                )
            }
            .fullScreenCover(isPresented: photoBinding) {
                CameraPickerView(
                    captureMode: .photo,
                    onCapture: { result in
                        Task { await handleCameraResult(result) }
                    },
                    onDismiss: {
                        activeModality = nil
                    }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: videoBinding) {
                CameraPickerView(
                    captureMode: .video,
                    onCapture: { result in
                        Task { await handleCameraResult(result) }
                    },
                    onDismiss: {
                        activeModality = nil
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: attachBinding) {
                PhotoLibraryPicker { identifiers in
                    if !identifiers.isEmpty {
                        onCaptured(.attach(localIdentifiers: identifiers))
                    }
                    activeModality = nil
                }
            }
    }

    // MARK: - Per-modality bindings

    private var voiceBinding: Binding<Bool> {
        Binding(
            get: { activeModality == .voice },
            set: { presented in if !presented && activeModality == .voice { activeModality = nil } }
        )
    }
    private var noteBinding: Binding<Bool> {
        Binding(
            get: { activeModality == .note },
            set: { presented in if !presented && activeModality == .note { activeModality = nil } }
        )
    }
    private var photoBinding: Binding<Bool> {
        Binding(
            get: { activeModality == .photo },
            set: { presented in if !presented && activeModality == .photo { activeModality = nil } }
        )
    }
    private var videoBinding: Binding<Bool> {
        Binding(
            get: { activeModality == .video },
            set: { presented in if !presented && activeModality == .video { activeModality = nil } }
        )
    }
    private var attachBinding: Binding<Bool> {
        Binding(
            get: { activeModality == .attach },
            set: { presented in if !presented && activeModality == .attach { activeModality = nil } }
        )
    }

    // MARK: - Camera result → MediaReference id

    @MainActor
    private func handleCameraResult(_ result: CameraPickerView.CaptureResult) async {
        do {
            switch result {
            case .photo(let image):
                let id = try await CameraService.shared.savePhoto(image)
                onCaptured(.photo(localIdentifier: id))
            case .video(let url):
                let id = try await CameraService.shared.saveVideo(at: url)
                onCaptured(.video(localIdentifier: id))
            }
        } catch {
            ErrorState.shared.report(.mediaError(error.localizedDescription))
        }
        activeModality = nil
    }
}

extension View {
    /// Attaches the Append spec's single-modality capture flows. Each surface
    /// presents off the same `activeModality` binding; the host receives the
    /// resulting artifact through `onCaptured` and decides whether to
    /// save-new or append.
    func captureFlowHost(
        activeModality: Binding<CaptureModality?>,
        speechService: SpeechService,
        onCaptured: @escaping (CapturedItem) -> Void
    ) -> some View {
        modifier(CaptureFlowHost(
            activeModality: activeModality,
            speechService: speechService,
            onCaptured: onCaptured
        ))
    }
}

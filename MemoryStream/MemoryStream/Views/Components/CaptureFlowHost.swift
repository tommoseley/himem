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
    /// F30 · non-zero while the attach picker is copying into the
    /// ubiquity container. Owned here so the indicator draws OVER the
    /// system picker rather than inside it.
    @State private var attachImportingCount = 0
    @ObservedObject var speechService: SpeechService
    /// When non-nil, the voice composer renders an "Adding to · X"
    /// header pill so the user knows which Memory the captured
    /// clips will land in. Per `docs/Voice Composer · spec` —
    /// the append composer is identical to direct-voice plus this
    /// pill. Pass `nil` for capture-new flows.
    let appendingTo: String?
    /// How the capture was initiated — threaded to the voice composer so a
    /// hands-free (Siri) recording gets the recording cap and a held one
    /// doesn't. See `CaptureSource`.
    var captureSource: CaptureSource = .manual
    let onCaptured: (CapturedItem) -> Void

    @State private var isMountingCamera = false

    func body(content: Content) -> some View {
        content
            // Stop any active speech recording BEFORE the camera /
            // photo-library surfaces present. Both `UIImagePickerController`
            // (camera) and `PHPickerViewController` (library) compete
            // with `SpeechService` for the singleton `AVAudioSession` —
            // presenting while voice is `.record`-active can leave the
            // camera's internal capture session unable to start, which
            // surfaces as a black preview and `appleh16camerad: failed
            // preProcessJasper jasper` errors in the device console.
            // Project `CLAUDE.md` § Audio Session Coordination makes
            // this stop step mandatory at every camera-trigger button.
            // `SpeechService.stopRecording()` is a safe no-op when the
            // session wasn't recording (post-Step-9 guard).
            .onChange(of: activeModality) { _, newValue in
                switch newValue {
                case .photo, .video, .attach:
                    speechService.stopRecording()
                default:
                    break
                }
            }
            .sheet(isPresented: voiceBinding) {
                VoiceCaptureScreen(
                    onFinish: { clips, rollGroupId in
                        guard !clips.isEmpty else { return }
                        onCaptured(.voiceSession(clips: clips, rollGroupId: rollGroupId))
                    },
                    onCancel: {},
                    speechService: speechService,
                    appendingTo: appendingTo,
                    captureSource: captureSource
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
                // F18 · never present a dead interface. If the camera can't
                // start we say so where the viewfinder would have been —
                // a black preview is the silent no-op this project has
                // rejected twice (F9's stranded recorder, F6d's silent delete).
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
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
                } else {
                    CaptureUnavailableView(
                        message: CaptureUnavailableView.cameraMessage,
                        onDismiss: { activeModality = nil }
                    )
                }
            }
            .fullScreenCover(isPresented: videoBinding) {
                // F18 · never present a dead interface. If the camera can't
                // start we say so where the viewfinder would have been —
                // a black preview is the silent no-op this project has
                // rejected twice (F9's stranded recorder, F6d's silent delete).
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
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
                } else {
                    CaptureUnavailableView(
                        message: CaptureUnavailableView.cameraMessage,
                        onDismiss: { activeModality = nil }
                    )
                }
            }
            .sheet(isPresented: attachBinding) {
                ZStack {
                    PhotoLibraryPicker(importingCount: $attachImportingCount) { results in
                    if !results.isEmpty {
                        let items: [(localIdentifier: String, mediaType: MediaReference.MediaType)] =
                            results.map { ($0.filename, $0.mediaType) }
                        onCaptured(.attach(items: items))
                    }
                    activeModality = nil
                    }
                    // F30 · the import copies every picked item into the
                    // ubiquity container before the picker calls back, and
                    // PHPicker does not dismiss itself — so this window was
                    // several silent seconds on a frozen picker. Drawn HERE,
                    // over the sheet, never pushed into the picker: per
                    // CLAUDE.md § "UIKit Pickers in SwiftUI", writing state
                    // into a live picker tears down its session.
                    if attachImportingCount > 0 {
                        AttachImportingOverlay(count: attachImportingCount)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: attachImportingCount)
            }
    }

    /// The quiet "this is working" state for a multi-second attach import.
    /// Names what is happening and how much of it — Crucible: specific over
    /// vague ("2 items", never "a moment"). No cancel: the copy is already
    /// in flight per item and a half-import is worse than a finished one.
    private struct AttachImportingOverlay: View {
        let count: Int
        var body: some View {
            ZStack {
                Crucible.Color.scrim.ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(count == 1 ? "Adding 1 item…" : "Adding \(count) items…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Crucible.Color.ink)
                }
                .padding(28)
                .background(Crucible.Color.card, in: RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(count == 1 ? "Adding 1 item" : "Adding \(count) items")
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
        appendingTo: String? = nil,
        captureSource: CaptureSource = .manual,
        onCaptured: @escaping (CapturedItem) -> Void
    ) -> some View {
        modifier(CaptureFlowHost(
            activeModality: activeModality,
            speechService: speechService,
            appendingTo: appendingTo,
            captureSource: captureSource,
            onCaptured: onCaptured
        ))
    }
}

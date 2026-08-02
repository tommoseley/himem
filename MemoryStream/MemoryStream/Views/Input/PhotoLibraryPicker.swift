import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Wraps `PHPickerViewController` to select existing photos / videos
/// from the user's Photos library.
///
/// **Behavior** (per `docs/design/Storage architecture · CLAUDE.md` Rule 1):
/// the picker extracts bytes from every selected asset via
/// `NSItemProvider.loadFileRepresentation`, copies them into the iCloud
/// Drive ubiquity container, and returns the per-asset ubiquity
/// filenames + classification (`.image` / `.video`). The
/// `MediaReference.osIdentifier` then points at HiMem's own copy in
/// iCloud Drive, not at a `PHAsset.localIdentifier` — which means the
/// memory's photo can't be lost if the user later deletes the original
/// from their Photos library.
///
/// The extraction happens asynchronously after the picker returns. The
/// host UI sees the callback fire once *all* selected items have been
/// copied; partial failures are dropped from the results array and
/// logged.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    /// One imported asset's worth of result. `filename` is what to
    /// store in `MediaReference.osIdentifier`; `mediaType` tells the
    /// MediaReference what type to record.
    struct Result: Equatable {
        let filename: String
        let mediaType: MediaReference.MediaType
    }

    /// **F30 · how many items are being copied right now (0 = idle).**
    ///
    /// `didFinishPicking` moves every picked item into the ubiquity
    /// container before it calls back, and `PHPickerViewController` does
    /// NOT dismiss itself — so for a multi-second import the picker sat
    /// frozen on screen with no signal at all. The user had tapped Add
    /// and been given nothing to read.
    ///
    /// Reported outward rather than drawn here: this is a
    /// `UIViewControllerRepresentable` around a system controller, and
    /// `CLAUDE.md` § "UIKit Pickers in SwiftUI" is explicit that pushing
    /// state INTO a live picker tears down its session. The owner draws
    /// the indicator above it instead.
    @Binding var importingCount: Int

    let onPick: ([Result]) -> Void


    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0 // unlimited
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onProgress: { count in importingCount = count })
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([Result]) -> Void
        let onProgress: (Int) -> Void

        init(onPick: @escaping ([Result]) -> Void, onProgress: @escaping (Int) -> Void) {
            self.onPick = onPick
            self.onProgress = onProgress
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onPick([])
                return
            }
            // Announce the work BEFORE it starts — the whole defect was
            // a silent gap between the tap and the callback.
            onProgress(results.count)
            Task {
                let imported = await withTaskGroup(of: Result?.self) { group -> [Result] in
                    for result in results {
                        group.addTask {
                            await Self.importToUbiquity(result.itemProvider)
                        }
                    }
                    var collected: [Result] = []
                    for await item in group {
                        if let item { collected.append(item) }
                    }
                    return collected
                }
                await MainActor.run {
                    self.onProgress(0)
                    self.onPick(imported)
                }
            }
        }

        /// Extracts a file representation from the picked item provider
        /// and moves it into the ubiquity container. Returns `nil` if
        /// the extraction fails (best-effort; partial failures don't
        /// block the rest of the import).
        private static func importToUbiquity(_ provider: NSItemProvider) async -> Result? {
            // Classify: prefer image if both are advertised; videos
            // have a separate UTI lineage. PHPicker only advertises
            // one of the two for any given pick.
            let mediaType: MediaReference.MediaType
            let utType: UTType
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                mediaType = .video
                utType = .movie
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                mediaType = .image
                utType = .image
            } else {
                NSLog("[HiMem][PHPicker] unsupported UTI on picked item — skipping")
                return nil
            }

            // `loadFileRepresentation` writes a temp file we own and
            // need to move into ubiquity before the closure returns.
            // The closure is invoked once with the URL of the temp file.
            return await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: utType.identifier) { tempURL, error in
                    guard let tempURL else {
                        NSLog("[HiMem][PHPicker] load failed: \(error?.localizedDescription ?? "unknown")")
                        continuation.resume(returning: nil)
                        return
                    }
                    let ext = tempURL.pathExtension.isEmpty ? (mediaType == .video ? "mov" : "jpg") : tempURL.pathExtension
                    let filename = "\(UUID().uuidString).\(ext)"
                    let destination: URL = {
                        switch mediaType {
                        case .video: return UbiquityStore.shared.videoURL(for: filename)
                        case .image: return UbiquityStore.shared.photoURL(for: filename)
                        default:     return UbiquityStore.shared.photoURL(for: filename) // unreachable
                        }
                    }()
                    do {
                        // `loadFileRepresentation` requires us to copy
                        // before the closure returns — the OS deletes
                        // the temp file after the callback. Route the
                        // copy through `UbiquityStore.copyIntoStore` so
                        // the destination write is NSFileCoordinator-
                        // wrapped — otherwise iCloud's file-presenter
                        // can read mid-write and ship a torn blob to
                        // other devices.
                        try UbiquityStore.shared.copyIntoStore(sourceURL: tempURL, destinationURL: destination)
                        continuation.resume(returning: Result(filename: filename, mediaType: mediaType))
                    } catch {
                        NSLog("[HiMem][PHPicker] ubiquity copy failed: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

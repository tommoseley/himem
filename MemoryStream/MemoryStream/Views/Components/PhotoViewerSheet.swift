import SwiftUI
import Photos

/// Full-screen viewer for a photo `MediaReference` — the image consume
/// surface (Q3 "tap to view full size"), sibling of `VideoPlayerSheet`.
/// Resolves bytes via `MediaResolver` (ubiquity file or legacy PhotoKit),
/// shows the image on black, and **always offers an exit: tap anywhere ·
/// swipe down · the ✕.**
///
/// Replaces the bare `QuickLookViewer` presentation, which — hosted in a
/// SwiftUI `.sheet` without a navigation controller — rendered no Done
/// chrome and captured the swipe gesture, leaving the full-screen image
/// with no way out (device bug, 2026-07-21). The trade is QuickLook's
/// pinch-zoom / share for a guaranteed, standard dismiss.
struct PhotoViewerSheet: View {
    let item: MediaDisplayItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var loadError: String? = nil
    /// Live swipe-down offset for the interactive dismiss.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                    .offset(y: dragOffset)
            } else if let loadError {
                errorState(loadError)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        // Tap anywhere to close.
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        // Swipe down to close; a short drag springs back.
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(16)
            }
            .accessibilityLabel("Close photo")
        }
        .task { await loadImage() }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func loadImage() async {
        switch MediaResolver.resolve(osIdentifier: item.localIdentifier, mediaType: .image) {
        case .ubiquity(let url):
            if UbiquityStore.shared.downloadStatus(at: url) == .notDownloaded {
                UbiquityStore.shared.startDownload(at: url)
                loadError = "Downloading from iCloud — try again in a moment."
                return
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadError = "Photo was moved or deleted."
                return
            }
            if let img = UIImage(contentsOfFile: url.path) {
                image = img
            } else {
                loadError = "Couldn't open this photo."
            }
        case .photoKit(let identifier):
            await loadFromPhotoKit(identifier: identifier)
        }
    }

    /// Legacy path for refs whose `osIdentifier` is still a
    /// `PHAsset.localIdentifier` (pre-ubiquity migration). Mirrors
    /// `VideoPlayerSheet.loadFromPhotoKit`. `.highQualityFormat` delivers
    /// a single (non-degraded) callback, so the continuation resumes once.
    private func loadFromPhotoKit(identifier: String) async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            loadError = "Photo is no longer available in Photos."
            return
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        let resolved: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { img, _ in
                continuation.resume(returning: img)
            }
        }
        if let resolved {
            image = resolved
        } else {
            loadError = "Could not load photo from Photos."
        }
    }
}

import SwiftUI
import Photos

/// Full-screen viewer for a photo `MediaReference` — the image consume
/// surface (Q3 "tap to view full size"), sibling of `VideoPlayerSheet`.
/// Resolves bytes via `MediaResolver` (ubiquity file or legacy PhotoKit)
/// and shows the image on black.
///
/// **Viewing:** pinch to zoom, double-tap to toggle zoom, drag to pan
/// when zoomed. **Dismiss:** tap (at fit scale), swipe down (at fit
/// scale), or the ✕. **Share** via the system share sheet.
///
/// Replaces the bare `QuickLookViewer` presentation, which — hosted in a
/// SwiftUI `.sheet` without a navigation controller — rendered no dismiss
/// chrome and captured the swipe gesture, leaving the image with no way
/// out (device bug, 2026-07-21). This restores QuickLook's zoom + share
/// while keeping an explicit, standard dismiss.
struct PhotoViewerSheet: View {
    let item: MediaDisplayItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var loadError: String? = nil
    /// Ubiquity file URL, when resolved — shared in preference to the
    /// re-encoded `UIImage` so the original bytes/metadata travel.
    @State private var shareURL: URL? = nil
    @State private var showShare = false

    // Zoom + pan state.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    /// Swipe-down-to-dismiss translation (only active at fit scale).
    @State private var dragDismiss: CGFloat = 0

    private let maxScale: CGFloat = 5
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    imageLayer(image, viewport: geo.size)
                } else if let loadError {
                    errorState(loadError)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .overlay(alignment: .topLeading) { if image != nil { shareButton } }
            .overlay(alignment: .topTrailing) { closeButton }
        }
        .task { await loadImage() }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    // MARK: - Image + gestures

    @ViewBuilder
    private func imageLayer(_ image: UIImage, viewport: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(x: offset.width, y: offset.height + dragDismiss)
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport: viewport))
            .simultaneousGesture(magnifyGesture(viewport: viewport))
            // Double-tap must be evaluated before single-tap so a single
            // tap waits for it to fail.
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture(count: 1) { singleTap() }
            .ignoresSafeArea()
    }

    private func magnifyGesture(viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                } else {
                    offset = clamp(offset, viewport: viewport)
                    lastOffset = offset
                }
            }
    }

    private func dragGesture(viewport: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    // Pan the zoomed image.
                    offset = clamp(
                        CGSize(width: lastOffset.width + value.translation.width,
                               height: lastOffset.height + value.translation.height),
                        viewport: viewport
                    )
                } else if value.translation.height > 0 {
                    // Swipe down to dismiss (fit scale only).
                    dragDismiss = value.translation.height
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastOffset = offset
                } else if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragDismiss = 0 }
                }
            }
    }

    /// Single tap: dismiss when at fit scale; zoom back to fit when zoomed
    /// (so an accidental tap never closes a photo you're examining).
    private func singleTap() {
        if scale > 1 {
            resetZoom()
        } else {
            dismiss()
        }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = doubleTapScale
                lastScale = doubleTapScale
            }
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            scale = 1; lastScale = 1
            offset = .zero; lastOffset = .zero
        }
    }

    /// Keep the zoomed image within bounds — pan can't push an edge past
    /// centre. Approximate (uses the viewport, not the letterboxed image
    /// rect), which errs toward a little slack rather than a hard stop.
    private func clamp(_ proposed: CGSize, viewport: CGSize) -> CGSize {
        let maxX = max(0, viewport.width * (scale - 1) / 2)
        let maxY = max(0, viewport.height * (scale - 1) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    // MARK: - Chrome

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
                .padding(16)
        }
        .accessibilityLabel("Close photo")
    }

    private var shareButton: some View {
        Button { showShare = true } label: {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
                .padding(16)
        }
        .accessibilityLabel("Share photo")
    }

    private var shareItems: [Any] {
        if let shareURL { return [shareURL] }
        if let image { return [image] }
        return []
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

    // MARK: - Load

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
                shareURL = url
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

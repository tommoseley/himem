import SwiftUI
import AVKit
import Photos

/// Full-screen player sheet for a video MediaReference. Resolves the
/// file via `MediaResolver`:
/// - **Ubiquity-backed** videos (the default path for new captures
///   since Phase 4 of the iCloud Drive migration) play directly from
///   the file URL.
/// - **PhotoKit-backed** videos (legacy `PHAsset.localIdentifier`
///   strings on entries pre-dating Phase 7's migration) fetch an
///   `AVAsset` from `PHImageManager` first, then play.
///
/// Tap-to-open lives in `EntryExpandedView`; the chronological capture
/// stream's photo-tap callback dispatches to this sheet for `.video`
/// items and to `PhotoDescriptionEditSheet` for `.image`. Per Crucible:
/// the player is the *playback* affordance; editing a video's
/// description still rides on the leading-Edit swipe, which keeps using
/// the description sheet.
struct VideoPlayerSheet: View {
    let item: MediaDisplayItem

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil
    @State private var loadError: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        // Best-effort autoplay. iOS will pause if the
                        // ringer/silent switch or audio session policy
                        // forbids — that's fine; the user taps play.
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(16)
            }
            .accessibilityLabel("Close video")
        }
        .task {
            await loadPlayer()
        }
    }

    private func loadPlayer() async {
        switch MediaResolver.resolve(osIdentifier: item.localIdentifier, mediaType: .video) {
        case .ubiquity(let url):
            if UbiquityStore.shared.downloadStatus(at: url) == .notDownloaded {
                UbiquityStore.shared.startDownload(at: url)
                loadError = "Downloading from iCloud — try again in a moment."
                return
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadError = "Video file was moved or deleted."
                return
            }
            player = AVPlayer(url: url)
        case .photoKit(let identifier):
            await loadFromPhotoKit(identifier: identifier)
        }
    }

    /// Legacy path for entries whose `osIdentifier` is still a
    /// `PHAsset.localIdentifier`. `PHImageManager.requestAVAsset`
    /// returns an `AVAsset` we can hand to `AVPlayer` directly —
    /// includes any in-progress iCloud download via PhotoKit.
    private func loadFromPhotoKit(identifier: String) async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            loadError = "Video is no longer available in Photos."
            return
        }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        let resolvedAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        guard let avAsset = resolvedAsset else {
            loadError = "Could not load video from Photos."
            return
        }
        let item = AVPlayerItem(asset: avAsset)
        player = AVPlayer(playerItem: item)
    }
}

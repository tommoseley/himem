import SwiftUI
import AVKit
import Photos

struct MediaViewerView: View {
    let item: MediaDisplayItem
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if item.mediaType == .video, let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if let fullImage {
                    Image(uiImage: fullImage)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Media no longer available")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await load()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func load() async {
        // Stop any audio playback that might conflict
        AudioPlayerService.shared.stop()

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil).firstObject else {
            isLoading = false
            return
        }

        if item.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic

            await withCheckedContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    if let avAsset {
                        let playerItem = AVPlayerItem(asset: avAsset)
                        Task { @MainActor in
                            self.player = AVPlayer(playerItem: playerItem)
                            self.isLoading = false
                            self.player?.play()
                        }
                    } else {
                        Task { @MainActor in self.isLoading = false }
                    }
                    continuation.resume()
                }
            }
        } else {
            fullImage = await ThumbnailService.shared.fullImage(for: item.localIdentifier)
            isLoading = false
        }
    }
}

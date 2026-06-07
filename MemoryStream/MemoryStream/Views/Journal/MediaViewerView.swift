import SwiftUI
import AVKit
import Photos

struct MediaViewerView: View {
    let item: MediaDisplayItem
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var isLoading = true
    /// Tracks whether `load()` activated the AVAudioSession (video
    /// path only). Used by `onDisappear` to deactivate symmetrically
    /// — without this, the session leaked into `.playback` mode
    /// indefinitely after any video viewing, which on a plugged-in
    /// iPhone made the device feel like it was refusing to sleep.
    @State private var activatedAudioSession = false

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
                            .accessibilityHidden(true)
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
            if activatedAudioSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                activatedAudioSession = false
            }
        }
    }

    private func load() async {
        // Stop any audio playback that might conflict
        AudioPlayerService.shared.stop()

        if item.mediaType == .video {
            await loadVideo()
        } else {
            fullImage = await ThumbnailService.shared.fullImage(for: item.localIdentifier)
            isLoading = false
        }
    }

    private func loadVideo() async {
        // Configure audio session for video playback. The matching
        // `setActive(false)` lives in `onDisappear`, gated on
        // `activatedAudioSession` so an image-only viewing (which
        // never activates) doesn't churn the HAL.
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
        activatedAudioSession = true

        switch MediaResolver.resolve(osIdentifier: item.localIdentifier, mediaType: .video) {
        case .ubiquity(let fileURL):
            if UbiquityStore.shared.downloadStatus(at: fileURL) == .notDownloaded {
                UbiquityStore.shared.startDownload(at: fileURL)
                isLoading = false
                return
            }
            let playerItem = AVPlayerItem(url: fileURL)
            self.player = AVPlayer(playerItem: playerItem)
            self.isLoading = false
            self.player?.play()
        case .photoKit(let identifier):
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
                isLoading = false
                return
            }
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
        }
    }
}

import SwiftUI
import AVKit
import Photos

/// Full-frame viewer for a photo or video. Editing the description
/// is delegated to `PhotoDescriptionEditSheet` (presented as a child
/// sheet), so the viewer itself is read-only — per
/// `docs/design/HiMem · Edit Sheet.html` June 2026.
///
/// **Background follows the system theme** via `Crucible.Color.paper`.
struct MediaViewerView: View {
    let item: MediaDisplayItem
    /// Persists the edited description. Forwarded to
    /// `PhotoDescriptionEditSheet`. Called on Done with a changed
    /// trimmed value.
    let onSaveDescription: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var isLoading = true
    @State private var activatedAudioSession = false
    /// Tracks the committed description so the read mode updates
    /// immediately after the user saves in `PhotoDescriptionEditSheet`.
    /// `item` is a parent-side struct snapshot that won't refresh
    /// while the viewer stays presented.
    @State private var savedDescription: String?
    @State private var presentingEditor = false

    var body: some View {
        ZStack(alignment: .top) {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                mediaStage
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                descriptionPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task {
            savedDescription = item.mediaDescription
            await load()
        }
        .onDisappear {
            player?.pause()
            if activatedAudioSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                activatedAudioSession = false
            }
        }
        .sheet(isPresented: $presentingEditor) {
            // Pass a refreshed item so the editor's initial state
            // reflects what's currently committed in this viewer.
            var refreshed = item
            refreshed.mediaDescription = savedDescription
            return PhotoDescriptionEditSheet(item: refreshed) { newDescription in
                onSaveDescription(newDescription)
                let trimmed = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                savedDescription = trimmed.isEmpty ? nil : trimmed
                NSLog("[HiMem][MediaDesc] viewer committed description for item \(item.id): \(trimmed.count) chars")
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(width: 30, height: 30)
                    .background(Crucible.Color.sunk)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(Self.timestampFormatter.string(from: item.createdAt))
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink2)
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Media stage

    private var mediaStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Crucible.Color.sunk)
            if isLoading {
                ProgressView().tint(Crucible.Color.ink3)
            } else if item.mediaType == .video, let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let fullImage {
                Image(uiImage: fullImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(Crucible.Color.ink3)
                    Text("Media no longer available")
                        .font(.subheadline)
                        .foregroundStyle(Crucible.Color.ink3)
                }
            }
        }
    }

    // MARK: - Description panel (read-only)

    /// Read-only summary of the saved description below the photo.
    /// Tap any part of it to launch `PhotoDescriptionEditSheet`. No
    /// inline editor lives here — editing is a sheet, per the unified
    /// edit-sheet design.
    private var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DESCRIPTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.top, 16)
                .padding(.bottom, 9)
            Group {
                if let desc = savedDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    ScrollView {
                        Text(desc)
                            .font(.system(size: 14.5))
                            .foregroundStyle(Crucible.Color.ink)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { presentingEditor = true }
                } else {
                    MediaDescriptionEmpty()
                        .onTapGesture { presentingEditor = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Text("Tap to edit")
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Media load

    private func load() async {
        AudioPlayerService.shared.stop()
        if item.mediaType == .video {
            await loadVideo()
        } else {
            fullImage = await ThumbnailService.shared.fullImage(for: item.localIdentifier)
            isLoading = false
        }
    }

    private func loadVideo() async {
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

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

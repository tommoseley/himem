import SwiftUI
import AVKit
import Photos

/// Full-frame viewer for a photo or video plus the human-written
/// description below it. Per
/// `docs/design/HiMem · Photo Descriptions.html`:
/// - Image / video is the hero on top, dark background.
/// - Description panel slides in from the bottom in cream — read or
///   edit modes share the same surface (no separate edit screen).
/// - Empty description shows the same prompt as the inline card; tap
///   to begin editing.
/// - Save commits via `onSaveDescription` and closes the viewer.
struct MediaViewerView: View {
    let item: MediaDisplayItem
    /// Persists the edited description. Called on Save if the trimmed
    /// text differs from the initial value. Skipped on plain Done or
    /// on Save with no change.
    let onSaveDescription: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var isLoading = true
    /// Tracks whether `load()` activated the AVAudioSession (video
    /// path only). Used by `onDisappear` to deactivate symmetrically.
    @State private var activatedAudioSession = false
    @State private var draftDescription: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            mediaStage
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 0)
                .frame(height: isEditing ? 150 : nil, alignment: .center)
            descriptionPanel
        }
        .background(Color(red: 26/255, green: 22/255, blue: 18/255))
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            draftDescription = item.mediaDescription ?? ""
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            Spacer()
            Text(Self.timestampFormatter.string(from: item.createdAt))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.7))
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
                .fill(Color(red: 42/255, green: 37/255, blue: 32/255))
            if isLoading {
                ProgressView().tint(.white)
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
                        .foregroundStyle(Color.white.opacity(0.32))
                    Text("Media no longer available")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: - Description panel

    private var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DESCRIPTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.top, 16)
                .padding(.bottom, 9)
            if isEditing {
                editor
            } else {
                reader
            }
            footer
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18
            )
            .fill(Crucible.Color.paper)
        )
    }

    @ViewBuilder
    private var reader: some View {
        if let desc = item.mediaDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            Text(desc)
                .font(.system(size: 14.5))
                .foregroundStyle(Crucible.Color.ink)
                .lineSpacing(3)
                .frame(minHeight: 78, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { beginEditing() }
        } else {
            MediaDescriptionEmpty()
                .onTapGesture { beginEditing() }
        }
    }

    @ViewBuilder
    private var editor: some View {
        TextEditor(text: $draftDescription)
            .focused($editorFocused)
            .font(.system(size: 14.5))
            .foregroundStyle(Crucible.Color.ink)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 78)
            .background(Crucible.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Crucible.Color.accent, lineWidth: 2)
            )
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text(isEditing ? "Part of this memory · searchable" : "Tap to edit")
                .font(.system(size: 11))
                .foregroundStyle(Crucible.Color.ink3)
            Spacer()
            if isEditing {
                Button {
                    commitAndClose()
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Crucible.Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Actions

    private func beginEditing() {
        isEditing = true
        editorFocused = true
    }

    private func commitAndClose() {
        let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (item.mediaDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != original {
            onSaveDescription(trimmed)
        }
        player?.pause()
        dismiss()
    }

    // MARK: - Media load

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

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

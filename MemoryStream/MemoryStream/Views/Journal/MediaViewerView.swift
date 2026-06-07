import SwiftUI
import AVKit
import Photos

/// Full-frame viewer for a photo or video plus the human-written
/// description below it. Per
/// `docs/design/HiMem · Photo Descriptions.html` part 3 (Viewer ·
/// editing):
/// - Image / video is the hero on top.
/// - In edit mode the image collapses to 150 height to make room for
///   the keyboard.
/// - Description panel sits below — read or edit modes share the same
///   surface (no separate edit screen).
/// - Top bar holds Cancel + ochre Done in edit mode; the keyboard has
///   clearance because Save isn't placed above it (Proofread / Rewrite
///   QuickType strip fight).
/// - **Background follows the system theme** via `Crucible.Color.paper`
///   — the design tool's dark canvas was the artboard backdrop, not
///   the intended runtime look.
/// - **Editor occupies only the free space between image and keyboard**
///   and scrolls internally. The TextEditor's frame is bounded by the
///   description panel's allocated space, which shrinks as the keyboard
///   raises.
struct MediaViewerView: View {
    let item: MediaDisplayItem
    /// Persists the edited description. Called on Done if the trimmed
    /// text differs from the initial value. Skipped on Cancel.
    let onSaveDescription: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var fullImage: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var isLoading = true
    /// Tracks whether `load()` activated the AVAudioSession (video
    /// path only). Used by `onDisappear` to deactivate symmetrically.
    @State private var activatedAudioSession = false
    @State private var draftDescription: String = ""
    /// The committed-and-currently-displayed description. The viewer's
    /// `item` is a struct snapshot from the parent — it doesn't update
    /// when the user saves a new description, so the reader has to
    /// track its own committed state. Initialized from
    /// `item.mediaDescription` in `.task`; updated by
    /// `commitAndReturnToReading`.
    @State private var savedDescription: String?
    @State private var isEditing: Bool = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Crucible.Color.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                mediaStage
                    .frame(height: isEditing ? 150 : nil)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                descriptionPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task {
            savedDescription = item.mediaDescription
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

    /// Top bar in two modes:
    /// - Reading: close `×` left, timestamp center, empty spacer right.
    /// - Editing: "Cancel" left, timestamp center, ochre "Done" right.
    ///
    /// **Save lives in the top bar, not above the keyboard.** iOS's
    /// Proofread / Rewrite QuickType strip occupies the row directly
    /// above the keyboard; any Save control placed there fights the
    /// system surface. The top bar is always free.
    private var header: some View {
        HStack {
            if isEditing {
                Button {
                    cancelEditing()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15))
                        .foregroundStyle(Crucible.Color.ink2)
                }
                .buttonStyle(.plain)
            } else {
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
            }
            Spacer()
            Text(Self.timestampFormatter.string(from: item.createdAt))
                .font(.system(size: 12.5))
                .foregroundStyle(Crucible.Color.ink2)
            Spacer()
            if isEditing {
                Button {
                    commitAndReturnToReading()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Crucible.Color.accent)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 30, height: 30)
            }
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

    // MARK: - Description panel

    /// VStack laid out as: eyebrow (fixed) → editor/reader (flexible)
    /// → footer (fixed). The flexible middle child consumes whatever
    /// vertical space remains after the keyboard takes its bite —
    /// that's how the TextEditor stays bounded to the visible region
    /// and scrolls internally rather than growing under the keyboard.
    private var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DESCRIPTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Crucible.Color.ink3)
                .padding(.top, 16)
                .padding(.bottom, 9)
            Group {
                if isEditing {
                    editor
                } else {
                    reader
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var reader: some View {
        // Reads `savedDescription` (local @State) not `item.mediaDescription`
        // — `item` is a parent-side snapshot that doesn't update when
        // the user commits a new description from inside the viewer.
        if let desc = savedDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            ScrollView {
                Text(desc)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { beginEditing() }
        } else {
            MediaDescriptionEmpty()
                .onTapGesture { beginEditing() }
        }
    }

    /// The TextEditor lives inside the flexible Group above. Its frame
    /// is therefore bounded by the description panel's allocated
    /// space, which shrinks as the keyboard raises — so the editor
    /// scrolls internally rather than extending under the keyboard.
    @ViewBuilder
    private var editor: some View {
        TextEditor(text: $draftDescription)
            .focused($editorFocused)
            .font(.system(size: 14.5))
            .foregroundStyle(Crucible.Color.ink)
            .scrollContentBackground(.hidden)
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
        }
        .padding(.top, 12)
    }

    // MARK: - Actions

    private func beginEditing() {
        draftDescription = savedDescription ?? ""
        isEditing = true
        editorFocused = true
    }

    private func cancelEditing() {
        // Discard the draft and drop back to reading. Editor closes;
        // viewer itself stays open. The user can hit `×` from there
        // to dismiss the whole sheet.
        draftDescription = savedDescription ?? ""
        isEditing = false
        editorFocused = false
    }

    private func commitAndReturnToReading() {
        let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (savedDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != original {
            onSaveDescription(trimmed)
            // Update the local committed state so the reader renders
            // the new description immediately. The Core Data write
            // propagates back through the parent's @FetchRequest on
            // the next render cycle.
            savedDescription = trimmed.isEmpty ? nil : trimmed
            NSLog("[HiMem][MediaDesc] committed description for item \(item.id): \(trimmed.count) chars")
        }
        isEditing = false
        editorFocused = false
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

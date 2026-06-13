import SwiftUI

/// Sheet-presented editor for a photo or video's human-written
/// description. Built on the shared `EditTextSheet` template — matches
/// the voice clip transcript editor's chrome exactly so the two read
/// as siblings (per `docs/design/HiMem · Edit Sheet.html` June 2026).
///
/// The hero block houses a small thumbnail of the photo or video; the
/// footer slot houses the static caption "Part of this memory ·
/// searchable" — the parallel to *Retry transcription* in the
/// transcript editor.
///
/// Tapping the thumbnail opens the larger viewer in place — QuickLook
/// for photos, the AVPlayer-backed `VideoPlayerSheet` for videos. The
/// description editor is the primary surface; the viewer is the
/// deeper-dive a user reaches when they want to see the capture full
/// size or play it back.
struct PhotoDescriptionEditSheet: View {
    let item: MediaDisplayItem
    /// Persists the edited description. Called on Done if the trimmed
    /// text differs from the initial value. Skipped on Cancel and on
    /// Done with no changes.
    let onSaveDescription: (String) -> Void
    /// Removes the photo/video clip. The sheet dismisses immediately
    /// on tap — the bottom Delete is its own deliberation per
    /// `HiMem · Buttons & Actions.html` §3 (June 12 2026), no confirm.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftDescription: String = ""
    @State private var thumbnail: UIImage?
    /// Non-nil while QuickLook is presented over this sheet for the
    /// photo. Routes through `MediaResolver` — legacy PHAsset items
    /// won't resolve to a file URL and simply do nothing on tap
    /// (rare post-migration; better than presenting an error).
    @State private var photoViewerItem: QuickLookItem? = nil
    /// Non-nil while `VideoPlayerSheet` is presented for the video.
    @State private var videoViewerItem: MediaDisplayItem? = nil

    var body: some View {
        EditTextSheet(
            title: item.mediaType == .video ? "Video" : "Photo",
            metadata: metadataLine,
            fieldLabel: "Description",
            text: $draftDescription,
            onCancel: { dismiss() },
            onDone: {
                commitIfChanged()
                dismiss()
            },
            hero: { hero },
            footer: { footer }
        )
        .task {
            draftDescription = item.mediaDescription ?? ""
            if thumbnail == nil {
                if let cached = await ThumbnailService.shared.cacheThumbnail(for: item.localIdentifier, mediaType: item.mediaType) {
                    thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
                }
            }
        }
        .sheet(item: $photoViewerItem) { qlItem in
            QuickLookViewer(url: qlItem.url)
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $videoViewerItem) { videoItem in
            VideoPlayerSheet(item: videoItem)
        }
    }

    /// Opens the larger viewer for the current item — QuickLook for
    /// photos (still images), `VideoPlayerSheet` for videos
    /// (autoplay + iCloud-download messaging). Legacy PHAsset photos
    /// that don't resolve to a file URL silently do nothing; the
    /// rare miss is preferable to a crash.
    private func openLargerViewer() {
        switch item.mediaType {
        case .image:
            switch MediaResolver.resolve(osIdentifier: item.localIdentifier,
                                         mediaType: item.mediaType) {
            case .ubiquity(let url):
                photoViewerItem = QuickLookItem(url: url)
            case .photoKit:
                break
            }
        case .video:
            videoViewerItem = item
        default:
            break
        }
    }

    // MARK: - Metadata line

    private var metadataLine: String {
        var parts: [String] = []
        parts.append(Self.timestampFormatter.string(from: item.createdAt))
        if let place = item.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            parts.append(place)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Hero (thumbnail)

    /// Small thumbnail of the photo or video. ~116×150 per the design.
    /// Tap → opens the larger viewer (QuickLook for photo, the
    /// AVPlayer-backed `VideoPlayerSheet` for video). The editor is
    /// the primary surface; the viewer is the deeper-dive a user
    /// reaches when they want to see the capture full-size.
    private var hero: some View {
        HStack {
            Spacer()
            Button(action: openLargerViewer) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Crucible.Color.sunk)
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 116, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: item.mediaType == .video ? "video" : "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(Crucible.Color.ink4)
                    }
                    if item.mediaType == .video {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .frame(width: 116, height: 150)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.mediaType == .video ? "Play video" : "View photo")
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Part of this memory · searchable")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                Spacer()
            }
            // Bottom Delete clip — the photo/video editor is the
            // "opened item" for media captures, so its own delete sits
            // here per `Memory Detail · unified editing model.md`
            // (June 12 2026). Dismisses the sheet immediately on tap;
            // the parent's delete callback handles the rest.
            BottomDeleteButton(kind: .delete(noun: "clip")) {
                onDelete()
                dismiss()
            }
        }
    }

    // MARK: - Save

    private func commitIfChanged() {
        let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (item.mediaDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != original else { return }
        onSaveDescription(trimmed)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

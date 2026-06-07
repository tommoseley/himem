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
struct PhotoDescriptionEditSheet: View {
    let item: MediaDisplayItem
    /// Persists the edited description. Called on Done if the trimmed
    /// text differs from the initial value. Skipped on Cancel and on
    /// Done with no changes.
    let onSaveDescription: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftDescription: String = ""
    @State private var thumbnail: UIImage?

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
                if let cached = await ThumbnailService.shared.cacheThumbnail(for: item.localIdentifier) {
                    thumbnail = ThumbnailService.shared.cachedThumbnail(filename: cached)
                }
            }
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
    /// Tap-to-zoom isn't part of this sheet — full viewing happens
    /// elsewhere; here the thumb is just identification.
    private var hero: some View {
        HStack {
            Spacer()
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
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Part of this memory · searchable")
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
            Spacer()
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

import SwiftUI
import CoreData

/// Picker that appends inbox clips to an existing memory. Audio files
/// move from Documents/Inbox/audio/ into the standard voice store; each
/// clip becomes a new MediaReference of type .voice on the chosen entry.
struct AddClipsToMemorySheet: View {
    let clips: [InboxClip]
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [JournalEntry] = []
    @State private var searchText: String = ""

    private let storage = StorageService.shared
    private let lifecycle = EntryLifecycleService()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.id) { entry in
                        Button {
                            append(to: entry)
                        } label: {
                            row(for: entry)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Crucible.Color.paper)
            .searchable(text: $searchText, prompt: "Search memories")
            .navigationTitle("Add to memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
            }
        }
        .onAppear { loadEntries() }
    }

    private var filtered: [JournalEntry] {
        if searchText.isEmpty { return entries }
        let needle = searchText.lowercased()
        return entries.filter {
            ($0.title ?? "").lowercased().contains(needle)
            || $0.content.lowercased().contains(needle)
        }
    }

    private func row(for entry: JournalEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 20))
                .foregroundStyle(Crucible.Color.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(timeLabel(for: entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func loadEntries() {
        let req = JournalEntry.fetchAllChronological(limit: 200)
        if let result = try? storage.viewContext.fetch(req) {
            entries = result.filter { !$0.isRecycled }
        }
    }

    private func timeLabel(for date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · h:mm a"
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return fmt.string(from: date)
    }

    private func append(to entry: JournalEntry) {
        var captures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
        var joinedTranscript: [String] = []

        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            do {
                if FileManager.default.fileExists(atPath: voiceURL.path) {
                    try FileManager.default.removeItem(at: voiceURL)
                }
                try FileManager.default.moveItem(at: inboxURL, to: voiceURL)
                captures.append((clip.audioFilename, .voice))
                if !clip.transcript.isEmpty { joinedTranscript.append(clip.transcript) }
            } catch {
                continue
            }
        }

        lifecycle.append(
            entryId: entry.id,
            additionalContent: joinedTranscript.joined(separator: "\n\n"),
            mediaCaptures: captures
        )

        // Copy per-clip transcripts onto the new MediaReferences. Fetching
        // by `osIdentifier` directly is more robust than traversing
        // `entry.mediaReferences` here — the relationship may still hold
        // a snapshot from before lifecycle.append wrote the new refs.
        for clip in clips where !clip.transcript.isEmpty {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "osIdentifier == %@", clip.audioFilename)
            req.fetchLimit = 1
            if let ref = try? storage.viewContext.fetch(req).first {
                ref.transcript = clip.transcript
            }
        }
        try? storage.save(context: storage.viewContext)

        InboxManifest.shared.removeBatch(clipIds: clips.map { $0.clipId })
        dismiss()
    }
}

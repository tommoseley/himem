import SwiftUI
import CoreData

/// Promotes N inbox clips into a single new JournalEntry. Audio files
/// move from Documents/Inbox/audio/ to the standard voice store; manifest
/// rows are dropped; lifecycle.save creates the entry with the clips
/// attached as MediaReferences of type .voice.
struct CreateMemoryFromClipsSheet: View {
    let clips: [InboxClip]
    @ObservedObject var viewModel: JournalViewModel

    @State private var title: String = ""
    @State private var selectedTopic: String? = nil
    @Environment(\.dismiss) private var dismiss

    private let storage = StorageService.shared
    private let lifecycle = EntryLifecycleService()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                titleField
                topicChips
                summary
                Spacer()
                createButton
            }
            .padding(20)
            .background(Crucible.Color.paper)
            .navigationTitle("New memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink3)
            TextField("Optional — AI will suggest one if blank", text: $title)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Crucible.Color.hairline, lineWidth: 1)
                )
        }
    }

    private var topicChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Topic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "None", topic: nil)
                    ForEach(viewModel.topics, id: \.self) { topic in
                        chip(label: topic, topic: topic)
                    }
                }
            }
        }
    }

    private func chip(label: String, topic: String?) -> some View {
        let isSelected = selectedTopic == topic
        return Button {
            selectedTopic = topic
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Crucible.Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Crucible.Color.accent : Crucible.Color.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Crucible.Color.hairline, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(clips.count) clip\(clips.count == 1 ? "" : "s") · \(totalDurationLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink2)
            ForEach(clips.prefix(3)) { clip in
                HStack(spacing: 6) {
                    Circle().fill(Crucible.Color.accent).frame(width: 5, height: 5)
                    Text(clip.transcript.isEmpty ? "(transcript pending)" : clip.transcript)
                        .font(.caption)
                        .foregroundStyle(Crucible.Color.ink3)
                        .lineLimit(2)
                }
            }
            if clips.count > 3 {
                Text("+ \(clips.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink4)
                    .padding(.leading, 11)
            }
        }
    }

    private var createButton: some View {
        Button {
            createMemory()
        } label: {
            Text("Create")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Crucible.Color.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var totalDurationLabel: String {
        let total = clips.reduce(0.0) { $0 + $1.duration }
        return String(format: "%d:%02d total", Int(total) / 60, Int(total) % 60)
    }

    // MARK: - Promotion

    /// Moves each clip's audio from Documents/Inbox/audio/ into the
    /// standard voice store at Documents/VoiceEntries/, builds a single
    /// JournalEntry through lifecycle.save with all clips attached, then
    /// drops the inbox manifest rows.
    private func createMemory() {
        // Build the joined transcript for entry.content. Empty transcripts
        // contribute nothing; AI will summarize from whatever's there.
        let joinedTranscript = clips
            .map { $0.transcript }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        var captures: [(localIdentifier: String, mediaType: MediaReference.MediaType)] = []
        for clip in clips {
            let inboxURL = InboxManifest.audioURL(for: clip.audioFilename)
            let voiceURL = SpeechService.audioURL(for: clip.audioFilename)
            do {
                if FileManager.default.fileExists(atPath: voiceURL.path) {
                    try FileManager.default.removeItem(at: voiceURL)
                }
                try FileManager.default.moveItem(at: inboxURL, to: voiceURL)
                captures.append((clip.audioFilename, .voice))
            } catch {
                // If the move fails, skip that clip — its inbox row stays
                // for retry on the next attempt.
                continue
            }
        }

        let inputType: JournalEntry.InputType = .voiceInApp
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let newId = viewModel.saveEntry(
            content: joinedTranscript,
            inputType: inputType,
            mediaCaptures: captures,
            topicName: selectedTopic
        )

        // Post-save fixups: copy per-clip transcripts onto each new
        // MediaReference (lifecycle.save's `mediaCaptures` tuple doesn't
        // carry transcripts), and apply the user-supplied title if any.
        // Fetch the MediaReferences by `osIdentifier` directly rather than
        // traversing `entry.mediaReferences` — the relationship can hold a
        // snapshot from before lifecycle.save linked the new refs in.
        if let newId {
            let request = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            request.predicate = NSPredicate(format: "id == %@", newId as CVarArg)
            request.fetchLimit = 1
            if let entry = try? storage.viewContext.fetch(request).first,
               !trimmedTitle.isEmpty {
                entry.title = trimmedTitle
            }
            for clip in clips where !clip.transcript.isEmpty {
                let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
                req.predicate = NSPredicate(format: "osIdentifier == %@", clip.audioFilename)
                req.fetchLimit = 1
                if let ref = try? storage.viewContext.fetch(req).first {
                    ref.transcript = clip.transcript
                }
            }
            try? storage.save(context: storage.viewContext)
        }

        // Drop manifest rows — audio files were already moved out.
        InboxManifest.shared.removeBatch(clipIds: clips.map { $0.clipId })
        dismiss()
    }
}

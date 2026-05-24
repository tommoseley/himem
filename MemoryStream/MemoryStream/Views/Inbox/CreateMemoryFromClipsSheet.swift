import SwiftUI
import CoreData

/// Promotes N inbox clips into a single new JournalEntry. Audio files
/// move from Documents/Inbox/audio/ to the standard voice store; manifest
/// rows are dropped; lifecycle.save creates the entry with the clips
/// attached as MediaReferences of type .voice.
///
/// Visual layout per `docs/Himem · Captured Clips (session-first)-2.html` §3
/// (Make a Memory · confirm sheet). Operational-to-reflective seam: this
/// sheet softens from triage into Memory creation. Ochre summary chip
/// names the scope at the top; AI-suggested title renders in AI blue
/// with an AI tag.
struct CreateMemoryFromClipsSheet: View {
    let clips: [InboxClip]
    /// Source session — used to render the ochre summary chip
    /// ("3 clips · 3:36 PM · 0:12"). Optional so existing single-clip
    /// callers can keep working.
    var session: ClipGroup? = nil
    @ObservedObject var viewModel: JournalViewModel

    @State private var title: String = ""
    /// Tracks whether the user has overwritten the AI-suggested title.
    /// Drives the `AI` tag visibility — once they type, the tag drops.
    @State private var userEditedTitle: Bool = false
    @State private var selectedTopic: String? = nil
    @State private var aiSuggestedTitle: String? = nil
    @Environment(\.dismiss) private var dismiss

    private let storage = StorageService.shared
    private let lifecycle = EntryLifecycleService()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if let session {
                    summaryChip(for: session)
                }
                titleField
                topicChips
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Crucible.Color.paper)
            .navigationTitle("New memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Crucible.Color.ink2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createMemory()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Crucible.Color.accent)
                }
            }
            .onAppear {
                // Forward-looking placeholder: when the AI title fetch
                // lands, populate `aiSuggestedTitle` here and seed
                // `title` from it. Until then, the field stays empty
                // with the suggestion helper.
                if title.isEmpty, let suggestion = aiSuggestedTitle {
                    title = suggestion
                }
            }
        }
        // 68% per JSX — half-height with the session card still
        // partly visible above. User can drag to large if they need
        // more room (e.g. long title).
        .presentationDetents([.fraction(0.68), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Summary chip (ochre, names the session scope)

    /// Session-summary chip per JSX: 28pt rounded-rect icon tile
    /// holding a microphone glyph, then "N clips · time · duration"
    /// primary line + "M clips excluded" sub-line. Card background,
    /// hairline border (not accent tint background).
    private func summaryChip(for session: ClipGroup) -> some View {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let timeStr = f.string(from: session.capturedAt)
        let bundleCount = clips.count
        let countStr = bundleCount == 1 ? "1 clip" : "\(bundleCount) clips"
        let durStr = formatDuration(session.totalDuration)
        let accidentalCount = session.clips.count - bundleCount
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Crucible.Color.accentTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(countStr) · \(timeStr) · \(durStr)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                if accidentalCount > 0 {
                    Text(accidentalCount == 1
                         ? "1 clip excluded"
                         : "\(accidentalCount) clips excluded")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
    }

    // MARK: - Title field (with AI tag + helper)

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                if hasAISuggestion {
                    aiTagChip
                }
                Spacer()
            }
            TextField("", text: $title, prompt: Text(titlePlaceholder).foregroundColor(Crucible.Color.ink4))
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(titleTextColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Crucible.Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(hasAISuggestion ? Crucible.Color.aiBlueTint : Crucible.Color.hairline, lineWidth: 1)
                )
                .onChange(of: title) { _, newValue in
                    if let suggestion = aiSuggestedTitle, newValue != suggestion {
                        userEditedTitle = true
                    }
                }
            if hasAISuggestion, !userEditedTitle {
                Text("Suggested from your transcripts. Tap to rewrite.")
                    .font(.caption)
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var hasAISuggestion: Bool {
        aiSuggestedTitle != nil && !userEditedTitle
    }

    private var titleTextColor: Color {
        hasAISuggestion ? Crucible.Color.aiBlue : Crucible.Color.ink
    }

    private var titlePlaceholder: String {
        aiSuggestedTitle != nil
            ? "Suggested title…"
            : "Optional — AI will suggest one if blank"
    }

    private var aiTagChip: some View {
        Text("AI")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Crucible.Color.aiBlue)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Crucible.Color.aiBlueTint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Topic chips (existing topics + "+ New")

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
                    newTopicChip
                }
            }
        }
    }

    /// Active topic chip per JSX: ochre-on-cream styling with a
    /// warm-grey dot. Background `rgba(198,74,28,0.16)`, border
    /// `rgba(198,74,28,0.28)`, text `#7A3A14`, dot `#7A6B4F`.
    /// Inactive chips stay card-on-hairline, ink2 text.
    private func chip(label: String, topic: String?) -> some View {
        let isSelected = selectedTopic == topic
        return Button {
            selectedTopic = topic
        } label: {
            HStack(spacing: 6) {
                if isSelected, topic != nil {
                    Circle()
                        .fill(Color(hex: 0x7A6B4F))
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: 0x7A3A14) : Crucible.Color.ink2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(isSelected
                        ? Color(red: 198/255, green: 74/255, blue: 28/255, opacity: 0.16)
                        : Crucible.Color.card)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected
                    ? Color(red: 198/255, green: 74/255, blue: 28/255, opacity: 0.28)
                    : Crucible.Color.hairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// Forward-looking "+ New" chip per spec. Tapping today is a
    /// no-op — when the inline new-topic flow lands, hook the action
    /// here.
    private var newTopicChip: some View {
        Button { /* TODO: inline new-topic flow */ } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("New")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Crucible.Color.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Crucible.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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

            // Stamp per-clip lat/lon from the watch's location fix
            // and kick off background reverse-geocode so the clip-row
            // header in Memory Detail can show "Bishop St, Bluffton"
            // alongside the date + time. No-op when the watch
            // captured without a fix (location permission off, no
            // signal, etc.).
            for clip in clips {
                ClipLocationResolver.stamp(
                    osIdentifier: clip.audioFilename,
                    latitude: clip.latitude,
                    longitude: clip.longitude,
                    in: storage.viewContext
                )
            }
        }

        // Drop manifest rows — audio files were already moved out.
        InboxManifest.shared.removeBatch(clipIds: clips.map { $0.clipId })
        dismiss()
    }
}

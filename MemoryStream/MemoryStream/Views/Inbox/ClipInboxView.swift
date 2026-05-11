import SwiftUI
import AVFoundation

/// Captured Clips inbox — staging area for fragments arriving from the
/// Apple Watch. The user reviews, multi-selects, then either creates a
/// new memory from the selected clips, appends them to an existing
/// memory, or deletes them. Once organized, the audio moves out of
/// Documents/ClipInbox/ and into the standard voice store.
///
/// Visual spec: serif h1 ("N from your Watch") + time-range subtitle,
/// time-proximity-grouped cards with a per-group meta line and Select all
/// affordance, ochre selection state, dark "New memory" primary action,
/// pill selection-count badge above the action bar. Empty state is a calm
/// "All organized" with a checkmark — the inbox is a steady state, not a
/// deficit.
struct ClipInboxView: View {
    @ObservedObject var inbox: InboxManifest = .shared
    @ObservedObject var viewModel: JournalViewModel

    @State private var selected: Set<UUID> = []
    @State private var showCreate = false
    @State private var showAddToMemory = false
    @State private var playingClipId: UUID?
    @State private var player: AVAudioPlayer?
    @State private var pendingDeleteIds: Set<UUID> = []
    /// Per-clip expand toggle for long transcripts. When a clipId is in
    /// this set, its transcript renders without a line-limit; otherwise
    /// it caps at `collapsedLineLimit` and shows a "Show more" affordance.
    @State private var expandedClipIds: Set<UUID> = []

    /// Cached output of `groupClips(_:)` — recomputed only when
    /// `inbox.clips` actually changes. The previous implementation
    /// re-sorted + re-grouped on every render (audit 2026-05-09: HIGH
    /// cost on dense inboxes).
    @State private var groupedClips: [ClipGroup] = []
    /// Heuristic: transcripts shorter than this don't bother offering the
    /// expand toggle — they fit in the collapsed view anyway.
    private let collapsedLineLimit = 4
    private let expandThresholdChars = 180

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Crucible.Color.paper.ignoresSafeArea()
                if inbox.isEmpty {
                    emptyState
                } else {
                    list
                }
                if !selected.isEmpty {
                    actionBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Captured Clips")
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(Crucible.Color.ink3)
                        .textCase(.uppercase)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(inbox.isEmpty ? "Done" : "Later") { dismiss() }
                        .foregroundStyle(Crucible.Color.accent)
                }
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: { selected.removeAll() }) {
            CreateMemoryFromClipsSheet(
                clips: clipsForCurrentSelection(),
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $showAddToMemory, onDismiss: { selected.removeAll() }) {
            AddClipsToMemorySheet(
                clips: clipsForCurrentSelection()
            )
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete \(pendingDeleteIds.count == 1 ? "clip" : "clips")", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIds.removeAll()
            }
        } message: {
            Text("This audio is only on this iPhone — it can't be recovered.")
        }
        .onDisappear { stopPlayback() }
        .onAppear {
            groupedClips = Self.groupClips(inbox.clips)
        }
        .onChange(of: inbox.clips) { _, newClips in
            groupedClips = Self.groupClips(newClips)
        }
    }

    // MARK: - Header / list

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                inboxHeader
                ForEach(Array(groupedClips.enumerated()), id: \.offset) { _, group in
                    groupHeader(for: group)
                    LazyVStack(spacing: 6) {
                        ForEach(group.clips) { clip in
                            clipCard(clip)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                Color.clear.frame(height: 110) // bottom inset for action bar
            }
        }
    }

    private var inboxHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.system(.title, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
                .padding(.top, 6)
            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(Crucible.Color.ink2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var headerTitle: String {
        let n = inbox.count
        return n == 1 ? "1 from your Watch" : "\(n) from your Watch"
    }

    private var headerSubtitle: String {
        guard let first = inbox.clips.map(\.capturedAt).min(),
              let last = inbox.clips.map(\.capturedAt).max() else { return "" }
        let cal = Calendar.current
        let dayLabel: String
        if cal.isDateInToday(first) {
            dayLabel = "Today"
        } else if cal.isDateInYesterday(first) {
            dayLabel = "Yesterday"
        } else {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            dayLabel = f.string(from: first)
        }
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "h:mm a"
        let firstStr = timeFmt.string(from: first)
        let lastStr = timeFmt.string(from: last)
        let range = firstStr == lastStr ? firstStr : "\(firstStr)–\(lastStr)"
        return "\(dayLabel), \(range) · bundle them into a memory."
    }

    // MARK: - Group header

    private func groupHeader(for group: ClipGroup) -> some View {
        let allInGroupSelected = group.clips.allSatisfy { selected.contains($0.clipId) }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(groupTitle(for: group))
                    .font(.footnote.bold())
                    .foregroundStyle(Crucible.Color.ink)
                Text(groupMeta(for: group))
                    .font(.caption2)
                    .foregroundStyle(Crucible.Color.ink3)
                    .monospacedDigit()
            }
            Spacer()
            Button(allInGroupSelected ? "Deselect" : "Select all") {
                toggleGroupSelection(group, selectAll: !allInGroupSelected)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Crucible.Color.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func groupTitle(for group: ClipGroup) -> String {
        // Topic + reverse-geocoded place name aren't wired yet. For v1 the
        // group title is just "Capture session" — informative without
        // claiming a specificity we can't deliver. Upgrade when location
        // place names are added (see TODO at app root).
        "Capture session"
    }

    private func groupMeta(for group: ClipGroup) -> String {
        let total = group.clips.reduce(0) { $0 + $1.duration }
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "h:mm a"
        let first = group.clips.map(\.capturedAt).min() ?? Date()
        let last = group.clips.map(\.capturedAt).max() ?? Date()
        let firstStr = timeFmt.string(from: first)
        let lastStr = timeFmt.string(from: last)
        let range = firstStr == lastStr ? firstStr : "\(firstStr)–\(lastStr)"
        let countLabel = group.clips.count == 1 ? "1 clip" : "\(group.clips.count) clips"
        return "\(countLabel) · \(range) · \(durationLabel(total)) total"
    }

    // MARK: - Clip card

    /// Three-way render for a clip card based on whether speech recognition
    /// has run and whether it produced text. The "no speech" branch is
    /// dimmed and labels the clip as accidental — matches the design's
    /// muted variant so the user can delete it with confidence.
    private enum ClipDisplayState {
        case hasTranscript
        case pending      // recognizer hasn't finished yet
        case noSpeech     // recognizer ran, returned nothing
    }

    private func displayState(for clip: InboxClip) -> ClipDisplayState {
        if !clip.transcript.isEmpty { return .hasTranscript }
        return clip.transcriptionAttempted ? .noSpeech : .pending
    }

    private func clipCard(_ clip: InboxClip) -> some View {
        let isSelected = selected.contains(clip.clipId)
        let isPlaying = playingClipId == clip.clipId
        let state = displayState(for: clip)
        let isExpanded = expandedClipIds.contains(clip.clipId)
        let canExpand = state == .hasTranscript && clip.transcript.count > expandThresholdChars

        return HStack(alignment: .top, spacing: 10) {
            // Left column — checkbox at top, play button directly under
            // it (only when there's a playable transcript). This keeps
            // the body column reading as a clean text block, with affordances
            // stacked along the leading edge.
            VStack(spacing: 8) {
                Button {
                    toggle(clip.clipId)
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                isSelected ? Crucible.Color.accent : Crucible.Color.ink4,
                                lineWidth: 1.5
                            )
                            .background(Circle().fill(isSelected ? Crucible.Color.accent : .clear))
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Deselect clip" : "Select clip")

                // Play button is always shown — even on "no speech detected"
                // clips. The audio file exists regardless of transcription
                // outcome, and the user may want to verify what's actually
                // there before deleting (or retrying recognition).
                Button {
                    isPlaying ? stopPlayback() : playClip(clip)
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Crucible.Color.accent)
                        .frame(width: 28, height: 28)
                        .background(Crucible.Color.accentTint)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop playback" : "Play clip")
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                clipMeta(clip)

                switch state {
                case .hasTranscript:
                    Text("\u{201C}\(clip.transcript)\u{201D}")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Crucible.Color.ink)
                        .lineLimit(isExpanded ? nil : collapsedLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                case .pending:
                    Text("Transcript pending")
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(Crucible.Color.ink3)
                case .noSpeech:
                    Text("No speech detected · likely accidental")
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(Crucible.Color.ink3)
                    Button {
                        retryTranscription(clip)
                    } label: {
                        Text("Retry transcription")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Crucible.Color.accent)
                    }
                    .buttonStyle(.plain)
                }

                if canExpand {
                    Button {
                        if isExpanded { expandedClipIds.remove(clip.clipId) }
                        else { expandedClipIds.insert(clip.clipId) }
                    } label: {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Crucible.Color.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { toggle(clip.clipId) }
        }
        .padding(.vertical, 12)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color(hex: 0xFFF8F1) : Crucible.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected ? Crucible.Color.accent : Crucible.Color.hairline,
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .opacity(state == .noSpeech ? 0.55 : 1.0)
    }

    private func clipMeta(_ clip: InboxClip) -> some View {
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "h:mm a"
        return HStack(spacing: 6) {
            Text(timeFmt.string(from: clip.capturedAt))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink2)
                .monospacedDigit()
            Circle().fill(Crucible.Color.ink4).frame(width: 3, height: 3)
            HStack(spacing: 3) {
                Image(systemName: "applewatch")
                    .font(.caption2)
                Text("Watch")
                    .font(.caption2)
            }
            .foregroundStyle(Crucible.Color.ink3)
            Circle().fill(Crucible.Color.ink4).frame(width: 3, height: 3)
            Text(durationLabel(clip.duration))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    // MARK: - Retry transcription

    /// Re-runs `TranscriptionService` against the clip's audio file. Useful
    /// when the first pass came back empty but the user can hear speech in
    /// the recording — most commonly because the model wasn't yet
    /// downloaded or the engine had a hiccup. The new result replaces the
    /// stored transcript regardless of outcome (still empty → stays
    /// "no speech detected").
    private func retryTranscription(_ clip: InboxClip) {
        let url = InboxManifest.audioURL(for: clip.audioFilename)
        Task {
            let result = await TranscriptionService.shared.transcribe(audioURL: url)
            inbox.recordTranscriptionAttempt(clipId: clip.clipId, transcript: result.text)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Crucible.Color.sunk)
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Text("All organized")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Crucible.Color.ink)
            Text("When you record on your Apple Watch and it syncs back, fragments will land here for review.")
                .font(.subheadline)
                .foregroundStyle(Crucible.Color.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            // Selection-count pill aligned to the leading edge of the bar.
            HStack {
                Text(selected.count == 1 ? "1 selected" : "\(selected.count) selected")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Crucible.Color.card)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Crucible.Color.ink))
                Spacer()
            }
            .padding(.leading, 28)
            .padding(.bottom, 6)

            HStack(spacing: 6) {
                Button {
                    showCreate = true
                } label: {
                    Label {
                        Text("New memory")
                            .font(.footnote.weight(.semibold))
                    } icon: {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Crucible.Color.card)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Crucible.Color.ink))
                }
                .buttonStyle(.plain)

                Button {
                    showAddToMemory = true
                } label: {
                    Label {
                        Text("Add to…")
                            .font(.footnote.weight(.semibold))
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Crucible.Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Button {
                    pendingDeleteIds = selected
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Crucible.Color.danger)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(selected.count == 1 ? "clip" : "selected clips")")
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Crucible.Color.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Crucible.Color.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Crucible.Color.paper.opacity(0), Crucible.Color.paper],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 80)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Selection / actions

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func toggleGroupSelection(_ group: ClipGroup, selectAll: Bool) {
        let groupIds = Set(group.clips.map(\.clipId))
        if selectAll {
            selected.formUnion(groupIds)
        } else {
            selected.subtract(groupIds)
        }
    }

    private func clipsForCurrentSelection() -> [InboxClip] {
        inbox.clips.filter { selected.contains($0.clipId) }
    }

    private var deleteDialogTitle: String {
        pendingDeleteIds.count == 1 ? "Delete 1 clip?" : "Delete \(pendingDeleteIds.count) clips?"
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { !pendingDeleteIds.isEmpty },
            set: { if !$0 { pendingDeleteIds.removeAll() } }
        )
    }

    private func performDelete() {
        for id in pendingDeleteIds {
            inbox.remove(clipId: id)
            selected.remove(id)
        }
        pendingDeleteIds.removeAll()
    }

    // MARK: - Playback

    private func playClip(_ clip: InboxClip) {
        stopPlayback()
        let url = InboxManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.play()
            player = p
            playingClipId = clip.clipId
            Task { [duration = p.duration] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) + 200_000_000)
                await MainActor.run { stopPlayback() }
            }
        } catch {
            return
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingClipId = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Grouping

    /// Time-proximity grouping — clips within ~10 minutes of each other
    /// land in the same group. Cheap, deterministic, no AI cost.
    /// Location is captured per-clip but not used for grouping until we
    /// have reverse-geocoded place names.
    /// Pure (static) so it can be called from the cache-refresh
    /// `onChange(of:)` without capturing `self`.
    private static func groupClips(_ clips: [InboxClip]) -> [ClipGroup] {
        let sorted = clips.sorted { $0.capturedAt > $1.capturedAt }
        var groups: [[InboxClip]] = []
        for clip in sorted {
            if let lastGroup = groups.last,
               let lastClip = lastGroup.last,
               abs(lastClip.capturedAt.timeIntervalSince(clip.capturedAt)) <= 600 {
                groups[groups.count - 1].append(clip)
            } else {
                groups.append([clip])
            }
        }
        return groups.map { ClipGroup(clips: $0) }
    }

    // MARK: - Helpers

    private func durationLabel(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}

private struct ClipGroup {
    let clips: [InboxClip]
}

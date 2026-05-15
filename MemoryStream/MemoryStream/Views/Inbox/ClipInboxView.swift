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

    /// Cached output of `groupClips(_:)` — recomputed only when
    /// `inbox.clips` actually changes. The previous implementation
    /// re-sorted + re-grouped on every render (audit 2026-05-09: HIGH
    /// cost on dense inboxes).
    @State private var groupedClips: [ClipGroup] = []

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

    /// Per the Watch → Memory flow spec (2026-05-14, step 9): no
    /// transcript preview in MVP — each row shows audio + capture time
    /// + duration only. The user reviews by playback, not by reading.
    /// The transcript stored on `InboxClip` remains available for v2
    /// (AI title / topic suggestion) but isn't surfaced here.
    private func clipCard(_ clip: InboxClip) -> some View {
        let isSelected = selected.contains(clip.clipId)
        let isPlaying = playingClipId == clip.clipId

        return HStack(spacing: 12) {
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

            Button {
                isPlaying ? stopPlayback() : playClip(clip)
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Crucible.Color.accent)
                    .frame(width: 36, height: 36)
                    .background(Crucible.Color.accentTint)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Stop playback" : "Play clip")

            clipMeta(clip)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { toggle(clip.clipId) }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
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
    }

    private func clipMeta(_ clip: InboxClip) -> some View {
        let timeFmt = DateFormatter(); timeFmt.dateFormat = "h:mm a"
        return HStack(spacing: 8) {
            Text(timeFmt.string(from: clip.capturedAt))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Crucible.Color.ink)
                .monospacedDigit()
            Circle().fill(Crucible.Color.ink4).frame(width: 3, height: 3)
            Text(durationLabel(clip.duration))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Crucible.Color.ink3)
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

    /// Session grouping per the Watch → Memory flow spec (step 5):
    /// ~10 min AND ~50 m proximity → same session. Clips without
    /// location coordinates fall back to time-only proximity (both
    /// clips' lat/lon must be present for the distance check to apply).
    /// Computed at the call site each time the inbox changes; cached in
    /// `groupedClips` so the render path doesn't re-sort.
    private static let sessionTimeWindowSeconds: TimeInterval = 10 * 60
    private static let sessionProximityMeters: Double = 50

    private static func groupClips(_ clips: [InboxClip]) -> [ClipGroup] {
        let sorted = clips.sorted { $0.capturedAt > $1.capturedAt }
        var groups: [[InboxClip]] = []
        for clip in sorted {
            if let lastGroup = groups.last, let lastClip = lastGroup.last,
               sameSession(lastClip, clip) {
                groups[groups.count - 1].append(clip)
            } else {
                groups.append([clip])
            }
        }
        return groups.map { ClipGroup(clips: $0) }
    }

    private static func sameSession(_ a: InboxClip, _ b: InboxClip) -> Bool {
        guard abs(a.capturedAt.timeIntervalSince(b.capturedAt)) <= sessionTimeWindowSeconds else {
            return false
        }
        // If either clip lacks coordinates, fall back to time-only.
        guard let aLat = a.latitude, let aLon = a.longitude,
              let bLat = b.latitude, let bLon = b.longitude
        else {
            return true
        }
        return haversineMeters(lat1: aLat, lon1: aLon, lat2: bLat, lon2: bLon)
            <= sessionProximityMeters
    }

    /// Great-circle distance via the haversine formula. Sufficient
    /// precision for the ~50 m session threshold; no CoreLocation
    /// dependency, so callable from the static grouping path.
    private static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthR = 6_371_000.0
        let toRad = Double.pi / 180
        let dLat = (lat2 - lat1) * toRad
        let dLon = (lon2 - lon1) * toRad
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * toRad) * cos(lat2 * toRad)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthR * c
    }

    // MARK: - Helpers

    private func durationLabel(_ d: TimeInterval) -> String {
        String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}

private struct ClipGroup {
    let clips: [InboxClip]
}

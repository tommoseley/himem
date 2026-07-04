import SwiftUI
import AVFoundation

/// Session-first Captured Clips · v2. One surface. Cards expand in
/// place. Per-clip triage lives **inside** the expanded card — never
/// on a new screen. Per `docs/Himem · Captured Clips (session-first)-2.html`
/// and the 2026-05-19 critique that drove the rebuild.
///
/// Visual register: operational throughout (SF Pro, denser layout,
/// no editorial type). The voice softens to reflective only at the
/// confirm sheet. No selection rings, no "Bundle as memory" verb,
/// no bottom action bar, no amber badges. "Make a Memory" is the
/// primary verb and lives inside every card.
struct SessionListView: View {
    @ObservedObject var inbox: InboxManifest = .shared
    @ObservedObject var arrivals: InboxArrivalTracker = .shared
    @ObservedObject var viewModel: JournalViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ClipGroup] = []
    @State private var expandedSessionId: UUID? = nil
    @State private var bundleSession: BundleRequest? = nil
    @State private var playingClipId: UUID? = nil
    @State private var player: AVAudioPlayer? = nil
    /// Tracks whether THIS view activated the audio session. Only
    /// flipped true after a successful setActive(true) in playClip;
    /// gates stopPlayback's setActive(false) so we never deactivate
    /// a session we don't own. Per CLAUDE.md § Audio Session
    /// Coordination — mirrors AudioPlayerService.sessionActivated.
    @State private var sessionActivated = false
    /// Per-session, per-clip selection state for the expanded card.
    /// Keyed by clip id. Defaults to "non-accidental clips selected"
    /// when the user expands a session for the first time; once they
    /// toggle a ring, manual selection takes over.
    @State private var sessionSelections: [UUID: Set<UUID>] = [:]

    /// Wraps the bundle action with the chosen clip subset so the
    /// confirm sheet bundles exactly what's checked, not a re-derived
    /// "all usable" set.
    struct BundleRequest: Identifiable {
        let id = UUID()
        let session: ClipGroup
        let clipsToBundle: [InboxClip]
    }

    var body: some View {
        // No inner NavigationStack — this view is pushed onto the
        // parent's stack (per v2 spec: "Captured Clips isn't a modal
        // — back only"). Routing comes from JournalView /
        // SettingsView via `.navigationDestination(isPresented:)`.
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            if inbox.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Captured Clips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Crucible.Color.accent)
            }
        }
        .sheet(item: $bundleSession) { request in
            CreateMemoryFromClipsSheet(
                clips: request.clipsToBundle,
                session: request.session,
                viewModel: viewModel
            )
        }
        .onAppear {
            sessions = computeSessions()
            // Tutorial #4 (Captured Clips · the Watch story). Spec
            // gate: opened **non-empty** — clips have actually
            // arrived. Empty-state is intentionally NOT a trigger
            // (nothing to explain yet). The orchestrator handles the
            // once-each + session/day caps + arming gate.
            if !sessions.isEmpty {
                TutorialOrchestrator.shared.tryFire(.watchStory)
            }
        }
        .onChange(of: inbox.clips) { _, _ in
            sessions = computeSessions()
            // If a session expanded its last clip away, collapse.
            if let id = expandedSessionId,
               !sessions.contains(where: { $0.id == id }) {
                expandedSessionId = nil
            }
        }
        .onChange(of: arrivals.clipsInFlight) { _, _ in
            // In-flight clips are rendered as IncomingCard, NOT as
            // a SessionCard inside the session list. When the
            // tracker changes (clip enters/leaves any in-flight
            // phase) the sessions need to be re-grouped without
            // those clipIds to avoid double-rendering.
            sessions = computeSessions()
        }
        .onDisappear { stopPlayback() }
    }

    /// Groups the inbox's clips into sessions for the SessionCard
    /// list, EXCLUDING any clips currently in-flight in the arrival
    /// tracker — those render separately as `IncomingCard` rows
    /// above the session list. Without this filter, a clip in the
    /// `.transcribing` phase (which IS in the inbox manifest) would
    /// double-render: once as a transcribing IncomingCard and once
    /// as a session-list row with the legitimate-but-confusing
    /// "Transcribing…" body variant.
    private func computeSessions() -> [ClipGroup] {
        let inFlight = arrivals.clipsInFlight.keys
        guard !inFlight.isEmpty else {
            return ClipSessionGrouper.group(inbox.clips)
        }
        let inFlightSet = Set(inFlight)
        return ClipSessionGrouper.group(
            inbox.clips.filter { !inFlightSet.contains($0.clipId) }
        )
    }

    // MARK: - Workbench + Sort layer (v3, July 4 2026)

    /// The current cluster proposals — the Sort layer's confident
    /// groupings, rendered as `ClusterCardStack` above the loose
    /// session list. Recomputed from sessions + dismissed set on
    /// every render; the proposer is pure and cheap, and this is
    /// how spec § "Sort is the bench's resting state" says to do
    /// it ("Sort is what Captured Clips looks like now").
    private var proposals: [ClusterProposal] {
        ClipClusterProposer.propose(
            sessions: sessions,
            dismissed: inbox.dismissedClusterFingerprints
        )
    }

    /// Sessions NOT currently in a cluster proposal — the loose
    /// pile below the cluster stack. Spec § "Lead with signal,
    /// never bury the rest": the loose pile is always in plain
    /// sight, not subtracted or hidden by the Sort layer.
    private var looseSessions: [ClipGroup] {
        let clusteredClipIds = Set(proposals.flatMap(\.clipIds))
        guard !clusteredClipIds.isEmpty else { return sessions }
        return sessions.filter { session in
            !session.clips.contains(where: { clusteredClipIds.contains($0.clipId) })
        }
    }

    /// "Not together" tap — record the dismissal and let the manifest
    /// prune-on-write logic keep the store clean.
    private func handleClusterDismiss(_ proposal: ClusterProposal) {
        InboxManifest.shared.dismissCluster(proposal)
    }

    /// "Keep these · N memories" tap — resolve each proposal to its
    /// live clips, batch commit via `SortBatchCommit`. Clips leave
    /// the manifest on success; the ClusterCardStack disappears
    /// naturally because the proposer no longer sees the placed
    /// clipIds.
    private func handleClusterBatchCommit() {
        let byClipId: [UUID: InboxClip] = Dictionary(uniqueKeysWithValues: inbox.clips.map { ($0.clipId, $0) })
        let resolved: [(proposal: ClusterProposal, clips: [InboxClip])] = proposals.map { p in
            let clips = p.clipIds.compactMap { byClipId[$0] }
            return (p, clips)
        }
        SortBatchCommit.commit(resolved, viewModel: viewModel, storage: StorageService.shared)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing new from your Watch")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text("Audio you record on your Apple Watch lands here.")
                .font(.footnote)
                .foregroundStyle(Crucible.Color.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                let inFlight = arrivals.sortedNewestFirst()
                if !inFlight.isEmpty {
                    // Global sync state at-a-glance. Spec § SYNC /
                    // INCOMING — `SyncStrip` reads aggregate phase
                    // and shifts visual state for paused vs receiving.
                    SyncStrip(
                        receivingIndex: receivingIndex(among: inFlight),
                        totalInFlight: inFlight.count,
                        allPaused: allPaused(among: inFlight)
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    // Per-clip IncomingCards above the ready session
                    // list.
                    LazyVStack(spacing: 12) {
                        ForEach(inFlight) { clip in
                            IncomingCard(
                                capturedAt: clip.capturedAt,
                                durationSeconds: clip.durationSeconds,
                                placeName: nil,
                                phase: clip.phase
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                ClusterCardStack(
                    proposals: proposals,
                    onDismiss: handleClusterDismiss,
                    onCommitAll: handleClusterBatchCommit
                )
                LazyVStack(spacing: 12) {
                    ForEach(looseSessions) { session in
                        sessionCard(session)
                    }
                }
                .padding(.horizontal, 14)
                Color.clear.frame(height: 20)
            }
        }
        .refreshable {
            // Manual nudge — asks the watch to retry any pending
            // transferFile in its queue, then re-broadcasts acks for
            // every inbox clip so the watch can drop stale pending
            // rows whose original ack got lost. Idempotent on both
            // sides. Wired here so a stuck "Hasn't reached your phone"
            // banner on the watch has an obvious user remedy.
            WatchSessionDelegate.shared.requestWatchPendingFlush()
            WatchSessionDelegate.shared.reconcileWatchAcks()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerTitle)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(Crucible.Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }


    private var headerTitle: String {
        // Title counts EVERYTHING the watch is sending, ready or
        // in-flight — "N from your Watch" stays honest about the
        // full incoming workload. Manifest clips include the
        // already-in-flight ones (the file lands in the manifest
        // at `acceptArrivedClip` time, before transcription); add
        // any pre-announced clips that aren't yet in the manifest.
        let inFlightOnly = arrivals.clipsInFlight.keys.filter { id in
            !inbox.clips.contains(where: { $0.clipId == id })
        }.count
        let n = inbox.count + inFlightOnly
        return n == 1 ? "1 from your Watch" : "\(n) from your Watch"
    }

    private var headerSubtitle: String {
        // Range covers every clip we know about — ready manifest
        // rows AND in-flight tracker entries. Pre-announced but
        // not-yet-landed clips carry their `capturedAt` from the
        // wire payload.
        let manifestCapturedAts = inbox.clips.map(\.capturedAt)
        let inFlightCapturedAts = arrivals.clipsInFlight.values.map(\.capturedAt)
        let all = manifestCapturedAts + inFlightCapturedAts
        guard let first = all.min(), let last = all.max() else { return "" }
        let syncingCount = arrivals.inFlightCount
        // When syncing, swap to the sync-aware variant so the user
        // sees "K ready · J syncing · time-range" instead of the
        // plain session count. Cross-day handling and the bug-fix
        // contract from `CapturedClipsHeaderSubtitleTests` are
        // preserved inside the builder.
        if syncingCount > 0 {
            return CapturedClipsSubtitleBuilder.syncAwareSubtitle(
                earliest: first,
                latest: last,
                readySessionCount: sessions.count,
                syncingClipCount: syncingCount
            )
        }
        return CapturedClipsSubtitleBuilder.subtitle(
            earliest: first,
            latest: last,
            sessionCount: sessions.count
        )
    }

    /// 1-indexed position of the first non-paused in-flight clip
    /// (the one actively downloading or transcribing). Defaults to
    /// 1 when nothing is actively progressing.
    private func receivingIndex(among inFlight: [InboxArrivalTracker.InFlightClip]) -> Int {
        guard let idx = inFlight.firstIndex(where: { clip in
            switch clip.phase {
            case .downloading, .transcribing: return true
            case .waiting, .paused: return false
            }
        }) else { return 1 }
        return idx + 1
    }

    /// `true` when every in-flight clip is paused — drives the
    /// SyncStrip's warn-tint "Watch out of range" rendering.
    private func allPaused(among inFlight: [InboxArrivalTracker.InFlightClip]) -> Bool {
        guard !inFlight.isEmpty else { return false }
        return inFlight.allSatisfy { clip in
            if case .paused = clip.phase { return true }
            return false
        }
    }

    // MARK: - Session card (collapsed + expanded variants)

    /// One session card. Collapsed shows time + clip count + transcript
    /// snippets + Make a Memory + play. Tapping the card body expands
    /// in place to reveal full per-clip transcripts and per-clip
    /// swipe-to-delete. No navigation push. No bottom action bar.
    @ViewBuilder
    private func sessionCard(_ session: ClipGroup) -> some View {
        let isExpanded = expandedSessionId == session.id
        VStack(alignment: .leading, spacing: 0) {
            sessionMetaRow(session)
            if isExpanded {
                expandedBody(session)
            } else {
                collapsedBody(session)
            }
            // v3 (July 4 2026): the "Make a Memory" pill is folded
            // into the expander — it appears only when the card is
            // expanded, right above the delete zone. Collapsed cards
            // carry no ochre; the transcript is the loudest thing on
            // them. Tapping the collapsed card body → expands →
            // reveals the pill as the primary action.
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Crucible.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) {
                toggleExpand(session)
            }
        }
        // Swipe-to-discard and long-press Trash both retired per
        // `HiMem · Buttons & Actions.html` §3 (June 12 2026). The
        // session is "opened" by tapping the card; the bottom `Delete
        // session` button inside the expanded body is the sole
        // destruction path.
        .contextMenu {
            Button {
                let selected = selectionFor(session)
                let clips = session.clips.filter { selected.contains($0.clipId) }
                guard !clips.isEmpty else { return }
                bundleSession = BundleRequest(session: session, clipsToBundle: clips)
            } label: {
                Label("Make a Memory", systemImage: "sparkles")
            }
        }
    }

    // Meta rows (per JSX mock v3): top row is time · clips · duration
    // (SF Pro 13 semi ink for time; 12 medium ink2 for the rest); a
    // sub-row below carries the date (SF Pro 11.5 ink3). Location
    // parked for the workbench+Sort phase where a resolved placeName
    // would sit next to the date.
    //
    // Dates are always shown because the workbench spans multiple
    // days — "Today" for today, "Yesterday" for yesterday, short
    // "Wed Jul 2" for older. Removes the ambiguity of a 3-day-old
    // road-trip clip reading like today's.
    private func sessionMetaRow(_ session: ClipGroup) -> some View {
        let timeStr: String = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return f.string(from: session.capturedAt)
        }()
        let clipPart = session.clipCount == 1 ? "1 clip" : "\(session.clipCount) clips"
        let durStr = formatDuration(session.totalDuration)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(timeStr)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .monospacedDigit()
                Text("·").foregroundStyle(Crucible.Color.ink3)
                Text(clipPart)
                Text("·").foregroundStyle(Crucible.Color.ink3)
                Text(durStr).monospacedDigit()
                Spacer()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Crucible.Color.ink2)
            Text(sessionDateLabel(session.capturedAt))
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    /// Human-friendly date label for a session's `capturedAt`.
    /// Today → "Today"; yesterday → "Yesterday"; older → weekday +
    /// short month + day (e.g. "Wed Jul 2"). Same-year assumption
    /// holds for MVP; year suffix can be added when clips regularly
    /// linger past year-end.
    private func sessionDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }

    // MARK: - Collapsed body

    /// Single block of quoted speech joined with " … " between clips,
    /// capped at 3 lines. Per spec Bug #8: "Reads like the thought it
    /// was," not a stack of separate quoted lines like a status log.
    @ViewBuilder
    private func collapsedBody(_ session: ClipGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Body variant is decided on ClipGroup so the
            // "Transcribing…" vs "(nothing, the footer carries it)"
            // vs "preview" choice is unit-testable and can't
            // contradict the accidental footer below. See
            // `ClipSessionGrouper.swift` + `SessionCollapsedBody-
            // VariantTests`.
            switch session.collapsedBodyVariant {
            case .preview(let text):
                Text("\u{201C}\(text)\u{201D}")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Crucible.Color.ink2)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            case .transcribing:
                Text("Transcribing…")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Crucible.Color.ink3)
            case .allAccidental:
                // Render nothing here; `accidentalNote` below
                // carries the messaging ("1 clip auto-excluded ·
                // no speech"). Showing both was the bug we're
                // closing.
                EmptyView()
            }
            accidentalNote(session)
        }
        .padding(.top, 8)
    }

    // MARK: - Expanded body (per-clip rows: ring + meta + transcript + chevron)

    /// Each clip is a row: selection ring on the left, offset/duration
    /// meta, transcript (or italic accidental note), trailing chevron.
    /// Accidentals appear at their chronological position with an empty
    /// ring (auto-excluded by default; user can opt them in by tapping).
    /// Usable clips default-selected with a filled ochre ring + check.
    @ViewBuilder
    private func expandedBody(_ session: ClipGroup) -> some View {
        let selected = selectionFor(session)
        let ordered = orderedClipsByOffset(session)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, clip in
                clipRow(
                    clip,
                    indexInSession: idx,
                    session: session,
                    isSelected: selected.contains(clip.clipId),
                    isLast: idx == ordered.count - 1
                )
            }
            // v3 (July 4 2026): the "Make a Memory" pill lives here,
            // folded into the expander. One primary verb, one tap.
            sessionActionRow(session, isExpanded: true)
                .padding(.top, 18)
            // Bottom `Delete session` — the session is the opened item
            // on Captured Clips per `Memory Detail · unified editing
            // model.md` (June 12 2026). Swipe-to-discard and long-press
            // Trash were both retired; this is the sole destruction
            // path. No confirm — scrolling past every clip in the
            // session *is* the deliberation.
            BottomDeleteButton(kind: .delete(noun: "session")) {
                deleteSession(session)
            }
            .padding(.top, 18)
            .padding(.bottom, 4)
        }
        .padding(.top, 10)
    }

    /// Clips ordered earliest-first within the session (matches the
    /// spec's chronological row order).
    private func orderedClipsByOffset(_ session: ClipGroup) -> [InboxClip] {
        session.clips.sorted { $0.capturedAt < $1.capturedAt }
    }

    @ViewBuilder
    private func clipRow(_ clip: InboxClip, indexInSession: Int, session: ClipGroup, isSelected: Bool, isLast: Bool) -> some View {
        let accidental = clip.transcript.isEmpty && clip.transcriptionAttempted
        let isPlaying = playingClipId == clip.clipId
        // Manually-excluded clips (user toggled off) dim to 0.55.
        // Auto-excluded clips keep full opacity (so the italic
        // "No speech detected" line stays readable). Per JSX:
        // `opacity: !included && !autoExcluded ? 0.55 : 1`.
        let manuallyExcluded = !isSelected && !accidental
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                clipSelectionRing(isSelected: isSelected) {
                    toggleClipSelection(clipId: clip.clipId, in: session)
                }
                VStack(alignment: .leading, spacing: 4) {
                    clipMetaRow(clip, indexInSession: indexInSession, session: session)
                    clipBody(clip, accidental: accidental, included: isSelected)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleClipSelection(clipId: clip.clipId, in: session)
                }
                clipPlayButton(clip: clip, isPlaying: isPlaying)
            }
            .padding(.vertical, 12)
            .opacity(manuallyExcluded ? 0.55 : 1.0)
            if !isLast {
                Rectangle()
                    .fill(Crucible.Color.hairline)
                    .frame(height: 0.5)
            }
        }
    }

    /// Per-clip play glyph — the only play affordance in the v2 spec.
    /// Per spec Bug #7: "Play button heavier than the primary action"
    /// was wrong. Stroke-only triangle in ink3 inside a 26pt frame,
    /// no background circle, no accent tint. Quiet by design.
    private func clipPlayButton(clip: InboxClip, isPlaying: Bool) -> some View {
        Button {
            if isPlaying {
                stopPlayback()
            } else {
                playClip(clip)
            }
        } label: {
            Image(systemName: isPlaying ? "stop" : "play")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Crucible.Color.ink3)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop clip" : "Play clip")
    }

    /// Selection toggle per Crucible: ring, never check.
    /// Empty → excluded. Filled (ochre) with a small paper-color
    /// inner dot → included. Spec Bug #2: "Filled ochre checkmark
    /// circles for selected clips" is wrong; the filled state has
    /// no glyph, just a tinier filled dot inside the ring.
    private func clipSelectionRing(isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isSelected ? Crucible.Color.accent : Crucible.Color.ink4,
                        lineWidth: 1.5
                    )
                    .background(Circle().fill(isSelected ? Crucible.Color.accent : Color.clear))
                    .frame(width: 20, height: 20)
                if isSelected {
                    // Paper-color inner dot — selection indicator
                    // without resorting to a check glyph. Matches
                    // `IncludeRing` in the JSX exactly.
                    Circle()
                        .fill(Crucible.Color.accentInk)
                        .frame(width: 8, height: 8)
                }
            }
            .contentShape(Rectangle())
            .padding(.top, 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Exclude this clip" : "Include this clip")
    }

    private func clipMetaRow(_ clip: InboxClip, indexInSession: Int, session: ClipGroup) -> some View {
        // "0:00   0:05" for the first clip (offset 0, duration); "+10s   0:05" for later.
        let offset = clip.capturedAt.timeIntervalSince(session.capturedAt)
        let offsetStr: String
        if indexInSession == 0 || offset < 1 {
            offsetStr = "0:00"
        } else {
            offsetStr = "+\(Int(offset))s"
        }
        return HStack(spacing: 12) {
            Text(offsetStr)
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)
            Text(formatDuration(clip.duration))
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Crucible.Color.ink3)
    }

    @ViewBuilder
    private func clipBody(_ clip: InboxClip, accidental: Bool, included: Bool) -> some View {
        // Per JSX: `color: muted ? ink3 : ink2` and italic only when
        // auto-excluded. Manually-excluded clips are handled by the
        // row's 0.55 opacity above — text itself stays roman.
        let muted = !included || accidental
        if !clip.transcript.isEmpty {
            Text("\u{201C}\(clip.transcript)\u{201D}")
                .font(.system(size: 13))
                .foregroundStyle(muted ? Crucible.Color.ink3 : Crucible.Color.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if accidental {
            Text("No speech detected · likely accidental")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(Crucible.Color.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Transcribing…")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(Crucible.Color.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func accidentalNote(_ session: ClipGroup) -> some View {
        let n = session.accidentalClips.count
        if n > 0 {
            Text(n == 1
                 ? "1 clip auto-excluded · no speech"
                 : "\(n) clips auto-excluded · no speech")
                .font(.footnote)
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    // MARK: - Action row (Make a Memory + optional Discard link)

    /// Action row layout per v2.2 (June 12 2026 delete sweep): the
    /// Make a Memory pill is the only action-row affordance. The
    /// session's own destruction lives at the bottom of the expanded
    /// body — same bottom-Delete rule as everywhere else; swipe and
    /// Action row rendered under both collapsed and expanded bodies.
    /// Per `Captured Clips · session-first · spec.md` v3 § "Session card
    /// anatomy": one full-width `Make a Memory` pill, one primary verb,
    /// one tap. Line 172 explicitly rejects "Create memory" /
    /// "Bundle" / "Save as memory" / "Bundle as memory" — do not drift.
    @ViewBuilder
    private func sessionActionRow(_ session: ClipGroup, isExpanded: Bool) -> some View {
        let selected = selectionFor(session)
        let selectedClips = session.clips.filter { selected.contains($0.clipId) }
        let isDisabled = selectedClips.isEmpty
        HStack(spacing: 12) {
            makeAMemoryPill(session, selectedClips: selectedClips, isDisabled: isDisabled)
        }
    }

    /// Make a Memory pill — full capsule (height 40, radius 20),
    /// 14pt semibold paper-color text, trailing chevron arrow.
    /// Matches `MakeAMemoryPill` in the JSX exactly. Disabled state
    /// drops the ochre to 35% alpha so it reads as inert rather than
    /// dimmed (per JSX: `rgba(198,74,28,0.35)`).
    @ViewBuilder
    private func makeAMemoryPill(_ session: ClipGroup, selectedClips: [InboxClip], isDisabled: Bool) -> some View {
        Button {
            bundleSession = BundleRequest(session: session, clipsToBundle: selectedClips)
        } label: {
            HStack(spacing: 8) {
                Text("Make a Memory")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Crucible.Color.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isDisabled
                        ? Crucible.Color.accent.opacity(0.35)
                        : Crucible.Color.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // Prevent the pill tap from being swallowed by the card's
        // tap-to-expand gesture.
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
    }

    // MARK: - Selection state

    /// Returns the current selection for a session — explicit if the
    /// user has toggled anything, otherwise the default (non-accidental
    /// clips selected).
    private func selectionFor(_ session: ClipGroup) -> Set<UUID> {
        if let explicit = sessionSelections[session.id] {
            return explicit.intersection(Set(session.clips.map(\.clipId)))
        }
        return Set(session.usableClips.map(\.clipId))
    }

    private func toggleClipSelection(clipId: UUID, in session: ClipGroup) {
        var current = selectionFor(session)
        if current.contains(clipId) {
            current.remove(clipId)
        } else {
            current.insert(clipId)
        }
        sessionSelections[session.id] = current
    }

    // MARK: - Behavior

    private func toggleExpand(_ session: ClipGroup) {
        if expandedSessionId == session.id {
            expandedSessionId = nil
        } else {
            expandedSessionId = session.id
        }
    }

    private func deleteSession(_ session: ClipGroup) {
        // Stop playback first: if any clip in this session is
        // currently playing, leaving the AVAudioPlayer pointed at a
        // file we're about to remove leaks audio + an activated audio
        // session past the row's disappearance.
        if let playing = playingClipId, session.clips.contains(where: { $0.clipId == playing }) {
            stopPlayback()
        }
        let ids = session.clips.map(\.clipId)
        for id in ids {
            inbox.remove(clipId: id)
        }
        if expandedSessionId == session.id { expandedSessionId = nil }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func playClip(_ clip: InboxClip) {
        stopPlayback()
        let url = InboxManifest.audioURL(for: clip.audioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            sessionActivated = true
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            playingClipId = clip.clipId
        } catch {
            // Silent — playback isn't critical to the flow.
        }
    }

    /// Per CLAUDE.md § Audio Session Coordination: only call
    /// setActive(false) on a session we activated. Calling it on
    /// an already-inactive session churns the audio HAL and can
    /// stomp on whatever other audio path (SpeechService,
    /// AudioPlayerService) currently owns the session.
    /// Mirrors AudioPlayerService's canonical pattern.
    private func stopPlayback() {
        player?.stop()
        player = nil
        playingClipId = nil
        if sessionActivated {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
    }
}

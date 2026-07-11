import SwiftUI
import CoreData
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
    @Environment(\.managedObjectContext) private var context

    @State private var sessions: [ClipGroup] = []
    /// Unplaced photo/video refs pulled into each voice session by
    /// `SessionMediaAbsorber` (July 11 2026 media-agnostic lock).
    /// Keyed by `ClipGroup.id`. Recomputed on inbox change or Core
    /// Data change; published to `BenchAbsorbedMediaBus` so the
    /// parent `ClipsTabView` can filter these out of its top
    /// day-grouped stack (avoids double-rendering).
    @State private var absorbedMediaBySessionId: [UUID: [MediaReference]] = [:]
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
    /// Per-session absorbed-media inclusion. Keyed by session id;
    /// value is the `Set` of `MediaReference.id` that the user has
    /// excluded from the bundle by tapping the ring on an absorbed
    /// media row (photo / video). Default = empty (all media
    /// included). Bundling filters `absorbedMediaBySessionId` by
    /// this set — an excluded media ref stays on the bench as a
    /// loose clip after the voice bundle commits.
    @State private var sessionExcludedMediaIds: [UUID: Set<UUID>] = [:]
    /// Per-clip retry-transcription state — populated while a
    /// retry is in flight so the row's link shows a "Retrying…"
    /// spinner and disables to prevent double-taps. Cleared when
    /// the outcome lands.
    @State private var retryingClipIds: Set<UUID> = []
    /// Per-clip inline status shown right after a retry that
    /// didn't overwrite the transcript (empty result, model
    /// installing, file unreadable, transcriber failed). Auto-
    /// clears after 4s so it doesn't linger. Draft protection:
    /// we never overwrite the existing transcript on failure —
    /// the message is the only user-visible signal that the retry
    /// happened but didn't land new text.
    @State private var clipRetryStatus: [UUID: String] = [:]

    /// Wraps the bundle action with the chosen clip subset so the
    /// confirm sheet bundles exactly what's checked, not a re-derived
    /// "all usable" set.
    struct BundleRequest: Identifiable {
        let id = UUID()
        let session: ClipGroup
        let clipsToBundle: [InboxClip]
        /// Absorbed photo/video/note `MediaReference`s the user
        /// kept included on the media rows (i.e. did NOT deselect
        /// via the ring). The create-memory step attaches these
        /// to the new/existing entry via `StorageService.createEdge`
        /// so a mixed session (2 voice + 1 photo) yields one
        /// memory that actually contains all three clips. Empty
        /// when the session has no absorbed media.
        let absorbedMediaRefs: [MediaReference]
    }

    var body: some View {
        // No inner NavigationStack; no navigation title; no toolbar
        // "Done" button. Per `Captured Clips · session-first · spec.md`
        // v4, this view is only ever embedded as the Clips tab's default
        // content — the parent (`ClipsTabView`) owns the title ("Clips")
        // and the tab bar handles navigation. The modal-push paths from
        // Settings + JournalView (2026-07-09) are retired.
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            if inbox.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .sheet(item: $bundleSession) { request in
            CreateMemoryFromClipsSheet(
                clips: request.clipsToBundle,
                session: request.session,
                absorbedMediaRefs: request.absorbedMediaRefs,
                viewModel: viewModel
            )
        }
        .onAppear {
            sessions = computeSessions()
            recomputeAbsorbedMedia()
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
            recomputeAbsorbedMedia()
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
            recomputeAbsorbedMedia()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            // Media refs land as unplaced refs on Core Data change.
            // Re-absorb so a photo captured now appears inside its
            // sitting's session card.
            recomputeAbsorbedMedia()
        }
        .onDisappear {
            stopPlayback()
            // Clear absorption on teardown so a re-mount of Clips
            // starts fresh — matters if the Clips tab is torn down
            // while unplaced refs are still queued.
            BenchAbsorbedMediaBus.shared.setAbsorbed([])
        }
    }

    /// Runs `SessionMediaAbsorber` against the current sessions and
    /// unplaced media refs. Publishes the absorbed id set for
    /// `ClipsTabView` to consume.
    private func recomputeAbsorbedMedia() {
        let unplaced = fetchUnplacedNonVoiceRefs()
        let result = SessionMediaAbsorber.absorb(
            sessions: sessions,
            unplacedMedia: unplaced
        )
        absorbedMediaBySessionId = result.mediaBySessionId
        BenchAbsorbedMediaBus.shared.setAbsorbed(result.absorbedRefIds)
    }

    /// Fetch unplaced photo/video/note MediaReferences — candidates
    /// for absorption into a voice session's time window.
    private func fetchUnplacedNonVoiceRefs() -> [MediaReference] {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(
            format: "edges.@count == 0 AND mediaType != %@",
            MediaReference.MediaType.voice.rawValue
        )
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(req)) ?? []
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
    ///
    /// **Deferred to the next runloop tick.** The commit shrinks
    /// `proposals` to empty (all clips placed), which causes
    /// `ClusterCardStack` to render `EmptyView`. If we mutate
    /// `InboxManifest.shared` synchronously inside the button's
    /// tap closure, SwiftUI can tear down the button's parent view
    /// mid-callback and render the whole ScrollView blank until
    /// the next tick — the "went dark with just the back button"
    /// symptom Tom reported after committing 8 clips into one
    /// memory (July 4 2026). Deferring lets the button action
    /// return before the view hierarchy churns.
    ///
    /// Also forces `sessions` to recompute at the end as belt-and-
    /// braces against the `.onChange(of: inbox.clips)` observer
    /// firing on a beat that misses the render window.
    private func handleClusterBatchCommit() {
        let byClipId: [UUID: InboxClip] = Dictionary(uniqueKeysWithValues: inbox.clips.map { ($0.clipId, $0) })
        let resolved: [(proposal: ClusterProposal, clips: [InboxClip])] = proposals.map { p in
            let clips = p.clipIds.compactMap { byClipId[$0] }
            return (p, clips)
        }
        DispatchQueue.main.async {
            SortBatchCommit.commit(resolved, viewModel: viewModel, storage: StorageService.shared)
            self.sessions = self.computeSessions()
        }
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
        .padding(.top, 12)
        .padding(.bottom, 16)
    }


    private var headerTitle: String {
        // Title counts EVERYTHING landing on the bench, ready or
        // in-flight — "N new clips" stays honest about the full
        // incoming workload regardless of source. Manifest clips
        // include the already-in-flight ones (the file lands in the
        // manifest at `acceptArrivedClip` time, before transcription);
        // add any pre-announced clips that aren't yet in the manifest.
        //
        // Source-agnostic per `CLAUDE.md` §Phone (July 10 2026,
        // line 142 corollary): the bench takes clips from Watch AND
        // from the phone Clips-FAB, so the headline never names a
        // source. Source lives per-clip on the card, not here.
        let inFlightOnly = arrivals.clipsInFlight.keys.filter { id in
            !inbox.clips.contains(where: { $0.clipId == id })
        }.count
        // Include absorbed photo/video items (July 11 media-agnostic
        // lock) so the count is honest across media types — a mixed
        // sitting reads "3 new clips," not "2" with a stray photo
        // row inside the card.
        let absorbedMediaCount = absorbedMediaBySessionId.values.reduce(0) { $0 + $1.count }
        let n = inbox.count + inFlightOnly + absorbedMediaCount
        return BenchHeaderTitleBuilder.title(clipCount: n)
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
                bundleSession = BundleRequest(
                    session: session,
                    clipsToBundle: clips,
                    absorbedMediaRefs: includedAbsorbedMedia(in: session)
                )
            } label: {
                // "Create one memory" is the placement primitive for an
                // already-grouped (idle-gap) session per
                // docs/design/Kingfisher Language.md. Retired: "Make a Memory."
                Label("Create one memory", systemImage: "sparkles")
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
    /// Summary line per the July 11 mixed-session spec update
    /// (`docs/design/screens-clips-page.jsx` §ScrMixedSession):
    /// **per-media glyphs + counts** via `MediaRow`, never a flat
    /// `"N clips"` label. Two voice + one photo reads as
    /// `mic 2 · camera 1`, not `3 clips` — matches how the memory
    /// card composition line reads elsewhere, so the count
    /// vocabulary stays consistent across surfaces.
    private func sessionMetaRow(_ session: ClipGroup) -> some View {
        let voiceClips = session.clips.map {
            ClipDisplayModel(inboxClip: $0, sessionStart: session.capturedAt)
        }
        let mediaClips = (absorbedMediaBySessionId[session.id] ?? []).map {
            ClipDisplayModel(mediaReference: $0, sessionStart: session.capturedAt)
        }
        let composition = CompositionModel.from(clips: voiceClips + mediaClips)
        let timeStr: String = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return f.string(from: session.capturedAt)
        }()
        let durStr = formatDuration(session.totalDuration)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(timeStr)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                    .monospacedDigit()
                Text("·").foregroundStyle(Crucible.Color.ink3)
                MediaRow(counts: composition.mediaCounts, iconSize: 12, textSize: 13.5)
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
        let rows = chronologicalRows(session)
        VStack(alignment: .leading, spacing: 0) {
            // Interleaved voice + media rows sorted by capture time
            // (July 11 spec §Model): the sitting reads in the order
            // it happened — `voice(0:00) → photo(+128s) → voice(+180s)`
            // — never voice-batched-then-media-batched. Voice-only
            // sessions collapse to the same render as before.
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                switch row {
                case .voice(let clip, let voiceIndex):
                    clipRow(
                        clip,
                        indexInSession: voiceIndex,
                        session: session,
                        isSelected: selected.contains(clip.clipId),
                        isLast: idx == rows.count - 1
                    )
                case .media(let ref):
                    mediaClipRow(ref, session: session, isLast: idx == rows.count - 1)
                }
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

    /// One row in the expanded session card — a voice clip or an
    /// absorbed media ref. Interleaved by capture time so the
    /// reader watches the sitting in the order it happened
    /// (July 11 lock, `Captured Clips · session-first · spec.md`
    /// §Model). `voiceIndex` is the position among the session's
    /// **voice** clips only (so the "0:00 / +Ns" offset labels
    /// stay honest — the offset is against the session start,
    /// not the merged row index).
    private enum ExpandedRow: Identifiable {
        case voice(InboxClip, voiceIndex: Int)
        case media(MediaReference)

        var id: UUID {
            switch self {
            case .voice(let c, _): return c.clipId
            case .media(let r):    return r.id
            }
        }

        var capturedAt: Date {
            switch self {
            case .voice(let c, _): return c.capturedAt
            case .media(let r):    return r.createdAt ?? .distantPast
            }
        }
    }

    /// Returns the session's voice clips + absorbed media items
    /// merged into one chronological list. Media without a
    /// `createdAt` sink to the start (`.distantPast`) rather than
    /// crashing the sort.
    private func chronologicalRows(_ session: ClipGroup) -> [ExpandedRow] {
        let voiceOrdered = orderedClipsByOffset(session)
        let voiceRows: [ExpandedRow] = voiceOrdered.enumerated().map { idx, clip in
            .voice(clip, voiceIndex: idx)
        }
        let media = absorbedMediaBySessionId[session.id] ?? []
        let mediaRows: [ExpandedRow] = media.map { .media($0) }
        return (voiceRows + mediaRows).sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Row for an absorbed photo/video within a session — thumbnail
    /// + label + time, no fake transcript, no retry link. Rendered
    /// after voice rows per `screens-clips-page.jsx` §SessionMediaRow.
    /// Tap navigates into `ClipDetailView` (same destination as loose
    /// clips in the top day-grouped stack pre-absorption).
    ///
    /// Slice 8 (Sessions bench convergence): renders through
    /// `ClipAtomView(register: .operational)`. Ring binding wired
    /// to `sessionExcludedMediaIds[session.id]` — tapping the ring
    /// toggles the media clip's inclusion in the bundle-a-memory
    /// commit. Excluded media stays on the bench as a loose clip
    /// after the voice bundle commits (see
    /// `handleCommitOneMemory` for the filter).
    @ViewBuilder
    private func mediaClipRow(_ ref: MediaReference, session: ClipGroup, isLast: Bool) -> some View {
        // Photos/videos have no explicit session offset — the atom's
        // operational timing header computes offset against
        // sessionStart, but for absorbed media the offset reads as
        // the wall-clock delta. Passing sessionStart keeps the
        // header consistent with voice rows.
        let sessionStart = ref.createdAt // best available anchor for a lone media clip
        let model = ClipDisplayModel(mediaReference: ref, duration: nil, sessionStart: sessionStart)
        let refId = ref.id
        let sessionId = session.id
        let isIncluded = !(sessionExcludedMediaIds[sessionId]?.contains(refId) ?? false)
        // Real ring binding — reads/writes `sessionExcludedMediaIds`
        // so the user can toggle absorbed media in/out of the bundle.
        // Getter returns "included" (i.e. NOT excluded); setter
        // flips the exclusion set.
        let ringBinding = Binding<Bool>(
            get: { !(sessionExcludedMediaIds[sessionId]?.contains(refId) ?? false) },
            set: { newIncluded in
                var set = sessionExcludedMediaIds[sessionId] ?? []
                if newIncluded { set.remove(refId) } else { set.insert(refId) }
                sessionExcludedMediaIds[sessionId] = set
            }
        )
        VStack(spacing: 0) {
            NavigationLink {
                ClipDetailView(ref: ref)
            } label: {
                ClipAtomView(
                    model: model,
                    register: .operational,
                    ring: ringBinding
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isIncluded ? 1.0 : 0.55)
            if !isLast {
                Rectangle()
                    .fill(Crucible.Color.hairline)
                    .frame(height: 0.5)
            }
        }
    }

    /// Short "3:36 PM" formatter — parity with the voice clip's
    /// offset display within a session row.
    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    @ViewBuilder
    private func clipRow(_ clip: InboxClip, indexInSession: Int, session: ClipGroup, isSelected: Bool, isLast: Bool) -> some View {
        let accidental = clip.transcript.isEmpty && clip.transcriptionAttempted
        let isPlaying = playingClipId == clip.clipId
        // Manually-excluded clips (user toggled off) dim to 0.55.
        // Auto-excluded (accidental) clips keep full opacity — the
        // italic "No speech detected" line reads as informational,
        // not deselected. Container chrome: opacity + divider live
        // outside the atom because they're session-scoped, not
        // clip-scoped.
        let manuallyExcluded = !isSelected && !accidental
        let model = ClipDisplayModel(inboxClip: clip, sessionStart: session.capturedAt)
        // Ring binding — `toggleClipSelection` handles both directions
        // (insert or remove), so the setter ignores the incoming value
        // and just flips.
        let ringBinding = Binding<Bool>(
            get: { isSelected },
            set: { _ in toggleClipSelection(clipId: clip.clipId, in: session) }
        )
        VStack(spacing: 0) {
            ClipAtomView(
                model: model,
                register: .operational,
                ring: ringBinding,
                onTapContent: { toggleClipSelection(clipId: clip.clipId, in: session) },
                onPlayEvidence: {
                    if isPlaying {
                        stopPlayback()
                    } else {
                        playClip(clip)
                    }
                },
                onRetryTranscription: model.failed ? { retryClipTranscription(clip) } : nil,
                isPlayingEvidence: isPlaying,
                pendingTranscript: !clip.transcriptionAttempted,
                accidentalTranscript: accidental,
                retryStatus: retryStatusText(for: clip)
            )
            .opacity(manuallyExcluded ? 0.55 : 1.0)
            if !isLast {
                Rectangle()
                    .fill(Crucible.Color.hairline)
                    .frame(height: 0.5)
            }
        }
    }

    /// Retry link's inline status suffix ("Retrying…", or the last
    /// short outcome text). Nil = no suffix, meaning either the
    /// retry hasn't been triggered or the auto-clear timer already
    /// fired. `retryingClipIds` beats `clipRetryStatus` — a caller
    /// re-tapping mid-status jumps back to "Retrying…" immediately.
    private func retryStatusText(for clip: InboxClip) -> String? {
        if retryingClipIds.contains(clip.clipId) {
            return "Retrying…"
        }
        return clipRetryStatus[clip.clipId]
    }

    /// Kicks off a re-run of `TranscriptionService` against the
    /// clip's audio in the inbox directory. On a successful
    /// non-empty result, overwrites the manifest row's transcript
    /// via `recordTranscriptionAttempt`. On failure or empty
    /// result, leaves the transcript untouched (draft protection)
    /// and surfaces a brief inline status that auto-clears after
    /// 4s.
    private func retryClipTranscription(_ clip: InboxClip) {
        let clipId = clip.clipId
        retryingClipIds.insert(clipId)
        clipRetryStatus[clipId] = nil
        Task {
            let url = InboxManifest.audioURL(for: clip.audioFilename)
            // Label the console line so a user-triggered retry is
            // easy to spot next to auto-sweep transcribes. Filter
            // "[HiMem][Retry]" in Console to see just these.
            NSLog("[HiMem][Retry] user tapped clip=\(clipId.uuidString.prefix(8)) file=\(clip.audioFilename)")
            let outcome = await TranscriptionService.shared.transcribe(audioURL: url)
            NSLog("[HiMem][Retry] outcome clip=\(clipId.uuidString.prefix(8)) kind=\(retryOutcomeLabel(outcome))")
            await MainActor.run {
                applyClipRetryOutcome(clipId: clipId, outcome: outcome)
            }
        }
    }

    /// Stringifies a `TranscriptionService.Outcome` for the retry
    /// console line. Mirrors the shape of `InboxTranscriptionDispatcher`'s
    /// diagnostic logs so the two are easy to compare.
    private nonisolated func retryOutcomeLabel(_ outcome: TranscriptionService.Outcome) -> String {
        switch outcome {
        case .transcribed(let result):
            return "transcribed(text=\(result.text.count)ch segments=\(result.segmentCount) cov=\(String(format: "%.2f", result.coverageSeconds))s)"
        case .modelNotInstalled: return "modelNotInstalled"
        case .fileUnreadable(let e): return "fileUnreadable(\(e.localizedDescription))"
        case .transcriberFailed(let e): return "transcriberFailed(\(e.localizedDescription))"
        }
    }

    private func applyClipRetryOutcome(clipId: UUID, outcome: TranscriptionService.Outcome) {
        retryingClipIds.remove(clipId)
        switch outcome {
        case .transcribed(let result) where !result.text.isEmpty:
            InboxManifest.shared.recordTranscriptionAttempt(clipId: clipId, transcript: result.text)
            clipRetryStatus[clipId] = nil
            return
        case .transcribed(let result):
            // Cross-tabulate segments × coverage to distinguish
            // real-world empty-result modes. Matches the DIAG tags
            // in `TranscriptionService.transcribe`. Actionable
            // language beats a bare "Nothing recognized" — the user
            // needs to know whether to try again, re-record, or
            // dig into settings.
            if result.segmentCount == 0 && result.coverageSeconds < 0.1 {
                clipRetryStatus[clipId] = "Recognizer couldn't process this file"
            } else if result.segmentCount == 0 {
                clipRetryStatus[clipId] = "Scanned, heard no recognizable speech"
            } else {
                clipRetryStatus[clipId] = "Segments returned empty"
            }
        case .modelNotInstalled:
            clipRetryStatus[clipId] = "Speech model still installing"
        case .fileUnreadable:
            clipRetryStatus[clipId] = "Couldn't read the audio"
        case .transcriberFailed:
            clipRetryStatus[clipId] = "Recognizer had trouble"
        }
        // Auto-clear the status line after 4s so it doesn't
        // linger. Same pattern as `AudioPlayerSheet`'s
        // `applyRetryOutcome` on Memory Detail.
        let statusSnapshot = clipRetryStatus[clipId]
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if clipRetryStatus[clipId] == statusSnapshot {
                clipRetryStatus.removeValue(forKey: clipId)
            }
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

    /// Placement pill — full capsule (height 40, radius 20),
    /// 14pt semibold paper-color text, trailing chevron arrow.
    /// Matches `MakeAMemoryPill` in the JSX exactly (JSX symbol name
    /// preserved; visible copy is "Create one memory" per Kingfisher
    /// Language.md — the placement primitive for an idle-gap session).
    /// Disabled state drops the ochre to 35% alpha so it reads as
    /// inert rather than dimmed (per JSX: `rgba(198,74,28,0.35)`).
    @ViewBuilder
    private func makeAMemoryPill(_ session: ClipGroup, selectedClips: [InboxClip], isDisabled: Bool) -> some View {
        Button {
            bundleSession = BundleRequest(
                session: session,
                clipsToBundle: selectedClips,
                absorbedMediaRefs: includedAbsorbedMedia(in: session)
            )
        } label: {
            HStack(spacing: 8) {
                Text("Create one memory")
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

    /// Absorbed photo/video refs for `session` that the user has
    /// NOT deselected on the media clip ring. Feeds
    /// `BundleRequest.absorbedMediaRefs` so the create-memory step
    /// attaches these to the new/existing entry via
    /// `StorageService.createEdge`. Order preserved from
    /// `absorbedMediaBySessionId` (which itself is `createdAt`-
    /// sorted upstream).
    private func includedAbsorbedMedia(in session: ClipGroup) -> [MediaReference] {
        let excluded = sessionExcludedMediaIds[session.id] ?? []
        let all = absorbedMediaBySessionId[session.id] ?? []
        guard !excluded.isEmpty else { return all }
        return all.filter { !excluded.contains($0.id) }
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


import SwiftUI
import CoreData
import AVFoundation

/// Session-first Captured Clips · workbench. Now rendered as the
/// default (New) view of the Clips tab via `ClipsTabView`. Per-clip
/// triage lives **inside** the pushed opened-session screen — never
/// on a new screen from the list. Per `docs/design/Captured Clips ·
/// session-first · spec.md` v3 and the 2026-05-19 critique that
/// drove the rebuild.
///
/// Visual register: operational throughout (SF Pro, denser layout,
/// no editorial type). The voice softens to reflective only at the
/// confirm sheet. No selection rings, no bottom action bar, no
/// amber badges. **"Start a Memory"** is the primary verb, ochre
/// pill, at the action position inside the opened session — locked
/// by `docs/design/Clip model · spec.md` §Model and `docs/design/
/// Kingfisher Language.md` (Idle-gap session row).
struct SessionListView: View {
    @ObservedObject var inbox: InboxManifest = .shared
    @ObservedObject var arrivals: InboxArrivalTracker = .shared
    @ObservedObject var viewModel: JournalViewModel
    /// New = unseen (P7-2): when true, reviewed clips are filtered out of
    /// the sessions so the New lens shows only fresh, un-eyeballed intake.
    /// Default false (All shows everything).
    var hideReviewed: Bool = false
    /// P7-4 multi-select (shared Clips-tab selection). Selecting a session
    /// card batch-selects every clip in it (matches the "opening a session
    /// marks all its clips" orthogonality); Sort cluster proposals are NOT
    /// part of multi-select (they keep their own Add / Not-together).
    @ObservedObject var selection: ClipsSelection
    @Environment(\.managedObjectContext) private var context

    @State private var sessions: [ClipGroup] = []
    /// Unplaced photo/video refs pulled into each voice session by
    /// `SessionMediaAbsorber` (July 11 2026 media-agnostic lock).
    /// Keyed by `ClipGroup.id`. Recomputed on inbox change or Core
    /// Data change; published to `BenchAbsorbedMediaBus` so the
    /// parent `ClipsTabView` can filter these out of its top
    /// day-grouped stack (avoids double-rendering).
    @State private var absorbedMediaBySessionId: [UUID: [MediaReference]] = [:]
    @State private var bundleSession: BundleRequest? = nil
    // Clip-editor cycle 2: the boxed ✎ Edit opens the unified ClipEditorModal
    // as a sheet, superseding the pushed ClipDetailView.
    @State private var editingClip: ClipEditorModal.Source? = nil
    // Cluster-editor single-open accordion (row/chevron tap expands-to-read).
    @State private var openClusterClipId: UUID? = nil
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
    // Sort cluster editor (Model A transient trim, ruling 2026-07-15).
    // Both view-state only — trims are provisional-and-reversible until
    // the batch commit; nothing here touches the proposer or any store.
    @State private var expandedClusterFingerprints: Set<String> = []
    @State private var removedByFingerprint: [String: Set<UUID>] = [:]
    // Single-open accordion for the cluster editor's compact rows — the
    // clipId whose transcript is expanded (nil = all collapsed). Same
    // container-owned model as Memory Detail's compact stream.
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
        /// Seeds the sheet's Title field when placing a cluster (the cluster's
        /// proposed title, e.g. "Kingfisher Wharf"). Editable; clearing it
        /// falls back to the AI-suggest default. `nil` for single loose bench
        /// clips (keep the optional/AI-suggest default). (2026-07-17, §Sort.)
        var prefillTitle: String? = nil
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
                prefillTitle: request.prefillTitle,
                viewModel: viewModel
            )
        }
        .sheet(item: $editingClip) { source in
            ClipEditorModal(source: source)
        }
        // `Clip model · spec.md` §Model (July 12 2026 lock): the
        // Clips list is calm. Tapping a session card pushes into an
        // opened-session screen where Create/Delete live. The
        // destination auto-dismisses if the session vanishes from
        // the manifest mid-flight (all clips placed, all deleted).
        .navigationDestination(for: ClipGroup.self) { session in
            openedSessionContent(sessionId: session.id)
        }
        .onAppear {
            sessions = computeSessions()
            recomputeAbsorbedMedia()
            registerSessionIds()
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
            registerSessionIds()
        }
        .onChange(of: arrivals.clipsInFlight) { _, _ in
            // In-flight clips are rendered as IncomingCard, NOT as
            // a SessionCard inside the session list. When the
            // tracker changes (clip enters/leaves any in-flight
            // phase) the sessions need to be re-grouped without
            // those clipIds to avoid double-rendering.
            sessions = computeSessions()
            recomputeAbsorbedMedia()
            registerSessionIds()
        }
        .onChange(of: inbox.soloClipIds) { _, _ in
            // The user *Removed a clip from session* on Clip Detail
            // (Chunk C, Clip triage July 12 2026). The manifest's
            // publish fires here even though `clips` didn't change;
            // re-group so the removed clip snaps into its own
            // single-clip card without waiting for another mutation.
            sessions = computeSessions()
            registerSessionIds()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            // Media refs land as unplaced refs on Core Data change.
            // Re-absorb so a photo captured now appears inside its
            // sitting's session card.
            recomputeAbsorbedMedia()
            registerSessionIds()
        }
        .onDisappear {
            stopPlayback()
            // Clear absorption on teardown so a re-mount of Clips
            // starts fresh — matters if the Clips tab is torn down
            // while unplaced refs are still queued.
            BenchAbsorbedMediaBus.shared.setAbsorbed([])
        }
    }

    /// Publishes the New view's session-side selectable ids for Select-all
    /// (P7-4) — only loose sessions, since Sort clusters are excluded from
    /// multi-select. The unplaced stack registers its own ids under
    /// "unplaced" from `ClipsTabView`.
    private func registerSessionIds() {
        selection.registerVisible(looseSessions.flatMap { sessionSelectableIds($0) }, source: "sessions")
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
    /// `applyFilter: false` derives sessions from the *unfiltered* inbox
    /// even under the New lens. The opened session detail uses it: once
    /// you're inside a session, marking its clips reviewed (P7-2) must
    /// not make the session vanish out from under you (the New-filtered
    /// derivation would drop every just-marked clip → AutoDismiss).
    private func computeSessions(applyFilter: Bool = true) -> [ClipGroup] {
        let inFlight = arrivals.clipsInFlight.keys
        let solo = inbox.soloClipIds
        // New = unseen: drop reviewed clips so a session the user has
        // already eyeballed leaves the New lens (P7-2). All shows
        // everything (hideReviewed == false).
        let base = (applyFilter && hideReviewed) ? inbox.clips.filter { !$0.reviewed } : inbox.clips
        guard !inFlight.isEmpty else {
            return ClipSessionGrouper.group(base, soloClipIds: solo)
        }
        let inFlightSet = Set(inFlight)
        return ClipSessionGrouper.group(
            base.filter { !inFlightSet.contains($0.clipId) },
            soloClipIds: solo
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

    // MARK: - Cluster editor (§87 · Model A transient trim, 2026-07-15)

    /// Member clips of a cluster (kept + set-aside), ordered by the
    /// proposal's `clipIds`, for the expanded editor rows.
    private func clips(forCluster proposal: ClusterProposal) -> [InboxClip] {
        let byId = Dictionary(inbox.clips.map { ($0.clipId, $0) }, uniquingKeysWith: { first, _ in first })
        return proposal.clipIds.compactMap { byId[$0] }
    }

    /// `Add to a memory…` on a cluster — routes the cluster's KEPT clips
    /// (set-aside excluded) into the shared placement sheet
    /// (`CreateMemoryFromClipsSheet` via `bundleSession`): Start a new memory
    /// or add to an existing one. On confirm the clips are placed + disposed
    /// from the inbox, so the cluster leaves Sort and `Keep these · N`
    /// recomputes. The ochre `Keep these · N` stays the primary; this is the
    /// quiet secondary exception path (2026-07-17, §Sort-is-the-moment).
    private func addClusterToMemory(_ proposal: ClusterProposal) {
        // Route through the SHARED, tested trim logic (ClusterTrim) — set-aside
        // exclusion + drop-empty + order — so the placement path can't diverge
        // from it. (The batch commit is retired; the trim it fed is not.)
        guard let trimmed = ClusterTrim.keptForCommit(
            proposals: [proposal], removedByFingerprint: removedByFingerprint
        ).first else { return }
        let byId = Dictionary(inbox.clips.map { ($0.clipId, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = trimmed.keptClipIds.compactMap { byId[$0] }
        guard !kept.isEmpty else { return }
        bundleSession = BundleRequest(
            session: ClipGroup(clips: kept),
            clipsToBundle: kept,
            absorbedMediaRefs: [],
            prefillTitle: proposal.proposedName
        )
    }

    /// `Adjust` / card-body tap — toggle the in-place editor.
    private func toggleClusterExpanded(_ proposal: ClusterProposal) {
        let fp = proposal.fingerprint.rawValue
        if expandedClusterFingerprints.contains(fp) {
            expandedClusterFingerprints.remove(fp)
        } else {
            expandedClusterFingerprints.insert(fp)
        }
    }

    /// Single-open accordion toggle for a cluster editor row — opening one
    /// clip's transcript collapses the prior (reading; editing is ✎ Edit).
    private func toggleClusterClip(_ clipId: UUID) {
        openClusterClipId = (openClusterClipId == clipId) ? nil : clipId
    }

    /// `Remove` — set a clip aside within the cluster (transient trim,
    /// a per-clip "Not together"). Reversible via `reAddClipToCluster`.
    private func removeClipFromCluster(_ proposal: ClusterProposal, _ clipId: UUID) {
        let fp = proposal.fingerprint.rawValue
        var set = removedByFingerprint[fp] ?? []
        set.insert(clipId)
        removedByFingerprint[fp] = set
    }

    /// `Add back` — undo a trim; the clip rejoins the kept set.
    private func reAddClipToCluster(_ proposal: ClusterProposal, _ clipId: UUID) {
        let fp = proposal.fingerprint.rawValue
        guard var set = removedByFingerprint[fp] else { return }
        set.remove(clipId)
        removedByFingerprint[fp] = set.isEmpty ? nil : set
    }

    // MARK: - Empty state

    private var emptyState: some View {
        // Source-agnostic copy per `CLAUDE.md` §Phone (July 12 2026):
        // clips arrive from the phone FAB, the Watch, and Siri, so
        // the empty-state must not headline any one source. Wording
        // matches `screens-clips-page.jsx §ScrClipsEmpty`.
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing new")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink)
            Text("Clips you capture — with the + button, on your Watch, or with Siri — land here.")
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
                    clipsFor: clips(forCluster:),
                    expandedFingerprints: expandedClusterFingerprints,
                    removedByFingerprint: removedByFingerprint,
                    onToggleExpand: toggleClusterExpanded,
                    onRemoveClip: removeClipFromCluster,
                    onReAddClip: reAddClipToCluster,
                    onOpenClip: { editingClip = $0 },
                    openClipId: openClusterClipId,
                    onToggleClusterClip: toggleClusterClip,
                    onDismiss: handleClusterDismiss,
                    onAddToMemory: addClusterToMemory
                )
                // The ochre "Keep these · N" is the FOOTER of the proposals
                // section (header + cards + bar = one group). A divider +
                // quiet section header opens the ungrouped region below it, so
                // the ochre bar can't be misread as acting on the loose clips
                // (2026-07-17, §Sort-is-the-moment). Only when both regions
                // exist.
                if !proposals.isEmpty && !looseSessions.isEmpty {
                    ungroupedSectionHeader
                }
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

    /// Divider + quiet header opening the ungrouped ("not yet connected")
    /// clips as a region distinct from the proposals section above (whose
    /// footer is the ochre commit bar). Section label per `CLAUDE.md` §Phone
    /// ("Not yet connected", never internal jargon).
    private var ungroupedSectionHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Crucible.Color.hairline)
                .frame(height: 0.5)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Text("Not yet connected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink)
                Text(headerSubtitle)
                    .font(.footnote)
                    .foregroundStyle(Crucible.Color.ink3)
            }
            Spacer()
            // Quiet "Select" enters multi-select on New (P7-4); shown only
            // when there are loose sessions to select and not already in mode.
            if !selection.selecting && !looseSessions.isEmpty {
                Button("Select") { selection.enter() }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
            }
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

    // MARK: - Session card (calm collapsed row + push to OpenedSession)

    /// A calm session card in the list. Composition + first-clip
    /// preview + "Tap to review" chevron; no Create / Delete
    /// buttons. Tapping pushes into `openedSessionContent` (via the
    /// `.navigationDestination(for: ClipGroup.self)` at `body` level)
    /// where Start / Delete live at the bottom of the opened item.
    /// Locked July 12 2026 (`Clip model · spec.md` §Model):
    /// > "a list of eight sessions must not be eight pairs of
    /// > shouting buttons. Tapping opens the session, and *that* is
    /// > where Start a Memory (the ochre primary, at the action
    /// > position) and Delete session (red, bottom-most) live."
    /// The selectable clip ids a session card batch-selects: its voice
    /// clips + any absorbed media refs shown inside the card. Partitioned
    /// by backing downstream (clipIds → inbox, refIds → media).
    private func sessionSelectableIds(_ session: ClipGroup) -> [UUID] {
        session.clips.map(\.clipId) + (absorbedMediaBySessionId[session.id] ?? []).map(\.id)
    }

    @ViewBuilder
    private func sessionCard(_ session: ClipGroup) -> some View {
        if selection.selecting {
            // Selecting mode (P7-4): the card is one toggle target that
            // batch-selects every clip in the session; navigation stands
            // down. A leading select circle + the "selects all N" note.
            let ids = sessionSelectableIds(session)
            Button { selection.toggleAll(ids) } label: {
                HStack(alignment: .top, spacing: 11) {
                    DragSelectCircle(checked: selection.isChecked(all: ids), selection: selection)
                        .padding(.top, 16)
                    sessionCardFace(session, selecting: true)
                }
            }
            .buttonStyle(.plain)
            .reportsClipRowFrame(ids, enabled: true)
        } else {
            sessionCardNavLink(session)
        }
    }

    @ViewBuilder
    private func sessionCardNavLink(_ session: ClipGroup) -> some View {
        NavigationLink(value: session) {
            sessionCardFace(session, selecting: false)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Swipe-to-discard and long-press Trash both retired per
        // `HiMem · Buttons & Actions.html` §3 (June 12 2026). The
        // session is "opened" by tapping the card; the bottom `Delete
        // session` button inside the pushed opened-session view is
        // the sole destruction path.
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
                // "Start a Memory" is the locked verb for an already-
                // grouped (idle-gap) session per
                // `docs/design/Kingfisher Language.md` (row: Idle-gap
                // session) and `docs/design/Clip model · spec.md`
                // §Model. Retired: "Make a Memory," "Create one memory."
                // `plus.circle` (neutral user-action icon) — not
                // `sparkles`, which the Crucible button rule reserves
                // for AI-blue buttons and drops from ochre user actions.
                Label("Start a Memory", systemImage: "plus.circle")
            }
        }
    }

    /// The card's visual face — shared by the resting (nav-link) and
    /// selecting (toggle) paths. In selecting mode the footer swaps to the
    /// "selects all N clips" note and the border goes accent when checked.
    @ViewBuilder
    private func sessionCardFace(_ session: ClipGroup, selecting: Bool) -> some View {
        let ids = sessionSelectableIds(session)
        let checked = selecting && selection.isChecked(all: ids)
        VStack(alignment: .leading, spacing: 0) {
            sessionMetaRow(session)
            collapsedBody(session)
            if selecting {
                let n = ids.count
                Text("Selecting the session selects all \(n) \(n == 1 ? "clip" : "clips")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink4)
                    .padding(.top, 10)
            } else {
                tapToReviewFooter
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Crucible.Color.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(checked ? Crucible.Color.accent : Crucible.Color.hairline, lineWidth: 1)
        )
    }

    /// The quiet "Tap to review" affordance at the bottom of a
    /// collapsed session card. The full-card `NavigationLink`
    /// already carries the tap; this is signal for the reader, not
    /// a second button. Matches `SessionCard` in
    /// `docs/design/screens-clips-page.jsx` (July 12 lock).
    private var tapToReviewFooter: some View {
        HStack(spacing: 5) {
            Text("Tap to review")
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Crucible.Color.ink3)
        .padding(.top, 12)
    }

    // MARK: - Opened session (pushed screen)

    /// The pushed opened-session screen — the composition + all
    /// clip rows + Start-a-Memory (ochre primary) + Delete-session
    /// (red, bottom-most). Reuses the existing `sessionMetaRow` +
    /// `expandedBody` helpers verbatim; the only new pieces are the
    /// scroll container, the paper background, and a nav title.
    /// Auto-dismisses via `AutoDismissView` when the underlying
    /// session leaves the manifest mid-flight (all clips placed into
    /// a memory, all deleted, or bundled by Sort).
    @ViewBuilder
    private func openedSessionContent(sessionId: UUID) -> some View {
        // Derive the session **live** from the manifest, not the
        // `sessions` @State snapshot (P0 2026-07-14 · "all counts read
        // from one reconciled source"). `computeSessions()` reads
        // `inbox.clips` / `arrivals.clipsInFlight` directly, so this
        // pushed screen re-renders the instant a clip is deleted or
        // arrives inside it — the snapshot could lag behind a mutation
        // made two navigation levels deep. Cheap: one grouping pass over
        // a small inbox per render of a single opened session.
        if let session = computeSessions(applyFilter: false).first(where: { $0.id == sessionId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sessionMetaRow(session)
                    expandedBody(session)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(Crucible.Color.paper.ignoresSafeArea())
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            // Open the container → its contents are seen (Tom, July 19):
            // opening a session card marks every clip in it reviewed in
            // one act, so the session leaves New as a batch rather than
            // demanding one open per clip. Derived unfiltered above so
            // this doesn't dismiss the screen it just cleared.
            .onAppear { markSessionReviewed(session) }
        } else {
            AutoDismissView()
        }
    }

    /// Marks every clip in an opened session reviewed (P7-2 per-session
    /// rule). Voice clips ride the manifest (one batched persist);
    /// absorbed media refs use the per-device bench store. Idempotent —
    /// re-opening a fully-seen session is a no-op (no write).
    private func markSessionReviewed(_ session: ClipGroup) {
        inbox.markReviewed(clipIds: session.clips.map(\.clipId))
        for ref in absorbedMediaBySessionId[session.id] ?? [] {
            BenchClipReviewStore.markReviewed(ref.id)
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
            // v3 (July 4 2026): the primary pill lives here, folded
            // into the expander. One primary verb ("Start a Memory"),
            // one tap. Verb locked by `Clip model · spec.md` §Model
            // and `Kingfisher Language.md` (Idle-gap session row).
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
        // Single-clip session hides the ring per spec §Clip triage.
        // Absorbed-media rows count with voice clips because the
        // ring is meaningful when the session has more than one
        // clip in any form.
        let totalClips = session.clips.count + (absorbedMediaBySessionId[session.id]?.count ?? 0)
        let effectiveRing: Binding<Bool>? = totalClips > 1 ? ringBinding : nil
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ClipAtomView(
                    model: model,
                    register: .operational,
                    ring: effectiveRing,
                    // Row body is non-interactive (2026-07-17): no
                    // whole-row-to-edit. The boxed ✎ Edit is the one edit
                    // affordance → modal; ring stays an independent control.
                    showDescriptionInvite: true,
                    // CD 2026-07-12: session-triage row density.
                    isDenseContainer: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                ClipEditButton(action: { editingClip = .managed(ref) })
            }
            // No row-level opacity dim on excluded rows: spec §Clip
            // triage forbids greying the content (dim = failed-clip
            // vocabulary, which pairs a Retry link — a media clip
            // has neither). Hollow ring is the sole excluded signal.
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
        let model = ClipDisplayModel(inboxClip: clip, sessionStart: session.capturedAt)
        // Ring binding — `toggleClipSelection` handles both directions
        // (insert or remove), so the setter ignores the incoming value
        // and just flips.
        let ringBinding = Binding<Bool>(
            get: { isSelected },
            set: { _ in toggleClipSelection(clipId: clip.clipId, in: session) }
        )
        // Single-clip session hides the ring per spec §Clip triage
        // ("excluding the sole clip equals deleting the session — so
        // inclusion selection is meaningless"). Count includes
        // absorbed media because the ring is meaningful whenever
        // there's more than one clip on the card.
        let totalClips = session.clips.count + (absorbedMediaBySessionId[session.id]?.count ?? 0)
        let effectiveRing: Binding<Bool>? = totalClips > 1 ? ringBinding : nil
        VStack(spacing: 0) {
            // Chunk B: voice content-tap opens ClipDetailView with the
            // clip's InboxClip source — the referenced-in section
            // renders its "not attached to a memory yet" empty state.
            // Ring stays a Button inside the label so it toggles
            // independently of the navigation push (SwiftUI's Button-
            // in-NavigationLink pattern the media row already uses).
            HStack(spacing: 8) {
                ClipAtomView(
                    model: model,
                    register: .operational,
                    ring: effectiveRing,
                    // Row body non-interactive (2026-07-17): no
                    // whole-row-to-edit. The boxed ✎ Edit is the one edit
                    // affordance → modal. Play / Retry / ring stay independent.
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
                    // CD 2026-07-12: leading media glyph + demoted
                    // offset stamp so the row scans as a triage
                    // line, not a reading surface.
                    isDenseContainer: true,
                    retryStatus: retryStatusText(for: clip)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                ClipEditButton(action: { editingClip = .inbox(clip) })
            }
            // No row-level opacity dim on excluded rows: spec §Clip
            // triage forbids greying the transcript because it
            // collides with the failed-clip style. The hollow ring
            // is the sole excluded-state signal; a failed clip is
            // the one that dims (and pairs a Retry link).
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

    // MARK: - Action row (Start a Memory)

    /// Action row layout per v2.2 (June 12 2026 delete sweep): the
    /// Start-a-Memory pill is the only action-row affordance. The
    /// session's own destruction lives at the bottom of the expanded
    /// body — same bottom-Delete rule as everywhere else; swipe and
    /// long-press Trash are retired. Per `Captured Clips · session-
    /// first · spec.md` v3 § "Session card anatomy": one full-width
    /// primary pill, one primary verb, one tap. `Kingfisher Language.md`
    /// (Idle-gap session row) and `Clip model · spec.md` §Model lock
    /// the verb as **"Start a Memory"**. Explicitly rejected in the
    /// spec: "Create memory," "Bundle," "Save as memory," "Bundle as
    /// memory," "Create one memory," "Make a Memory" — do not drift.
    @ViewBuilder
    private func sessionActionRow(_ session: ClipGroup, isExpanded: Bool) -> some View {
        let selected = selectionFor(session)
        let selectedClips = session.clips.filter { selected.contains($0.clipId) }
        let isDisabled = selectedClips.isEmpty
        HStack(spacing: 12) {
            startAMemoryPill(session, selectedClips: selectedClips, isDisabled: isDisabled)
        }
    }

    /// Primary pill — full capsule (height 40, radius 20), 14pt
    /// semibold paper-color text, trailing chevron arrow. Verb:
    /// **"Start a Memory"** — the locked label for an already-grouped
    /// (idle-gap) session per `docs/design/Kingfisher Language.md`
    /// (row: Idle-gap session) and `docs/design/Clip model · spec.md`
    /// §Model. Disabled state drops the ochre to 35% alpha so it reads
    /// as inert rather than dimmed (per JSX: `rgba(198,74,28,0.35)`).
    @ViewBuilder
    private func startAMemoryPill(_ session: ClipGroup, selectedClips: [InboxClip], isDisabled: Bool) -> some View {
        Button {
            bundleSession = BundleRequest(
                session: session,
                clipsToBundle: selectedClips,
                absorbedMediaRefs: includedAbsorbedMedia(in: session)
            )
        } label: {
            HStack(spacing: 8) {
                Text("Start a Memory")
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
        // Session vanishing from `sessions` after `computeSessions()`
        // re-runs triggers `AutoDismissView` in `openedSessionContent`
        // (Chunk E2, July 12 2026) — the opened-session pushed screen
        // pops back to the calm list.
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

/// Renders nothing and immediately pops itself off the navigation
/// stack. Used by `SessionListView.openedSessionContent` when the
/// pushed session vanishes from the manifest (all clips placed,
/// bundled by Sort, or deleted mid-flight) — the user shouldn't be
/// stranded on a screen whose data source is gone.
private struct AutoDismissView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Color.clear.onAppear { dismiss() }
    }
}


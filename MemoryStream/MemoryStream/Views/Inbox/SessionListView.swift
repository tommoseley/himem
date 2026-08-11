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
    /// F22 · the one fact this view reads before it claims to be empty.
    @ObservedObject private var firstImport = FirstImportState.shared
    @ObservedObject var viewModel: JournalViewModel
    /// New = unseen (P7-2): when true, reviewed clips are filtered out of
    /// the sessions so the New lens shows only fresh, un-eyeballed intake.
    /// Default false (All shows everything).
    var hideReviewed: Bool = false
    /// True when a SIBLING view in the same lens (the New lens's unplaced
    /// day-grouped ref stack) has content. The empty state must be mutually
    /// exclusive with ALL lens content, not just this view's sessions — else
    /// "Nothing new" renders directly above the sibling's populated rows
    /// (device pass 2026-07-27). See `showsEmptyState`.
    var hasSiblingContent: Bool = false
    /// P7-4 multi-select (shared Clips-tab selection). Selecting a session
    /// card batch-selects every clip in it (matches the "opening a session
    /// marks all its clips" orthogonality); Sort cluster proposals are NOT
    /// part of multi-select (they keep their own Add / Not-together).
    @ObservedObject var selection: ClipsSelection
    @Environment(\.managedObjectContext) private var context
    /// Backing-aware transcript writes for bench clips (P0-3): a materialized
    /// clip is a ref, so `Transcribe again` must land on the ref, never no-op.
    private let lifecycle = EntryLifecycleService()

    @State private var sessions: [ClipGroup] = []
    /// Every session on the bench, lens or no lens — the drill-in's source.
    /// See `RenderedBench.allSessions` for why the pushed screen cannot read
    /// the lensed set.
    @State private var allSessions: [ClipGroup] = []
    /// The Sort layer's confident groupings. **Now composed alongside the
    /// bench rather than recomputed on every render**: the proposer consumes
    /// the bench's sessions and `RenderedBench.compose` consumes the
    /// proposals, so the two are settled together in `composeDrawnBench` and
    /// stored. A computed property here would re-propose on every `body` pass
    /// AND could disagree with the `clustered` set the bench was built from.
    @State private var proposals: [ClusterProposal] = []
    /// The unified bench clip list (P0-3): in-flight manifest rows UNION the
    /// materialized zero-edge voice refs (`MediaReference`), deduped by clipId.
    /// A transcribed clip lives ONLY as a synced ref (it follows the person,
    /// not the device); in-flight clips live ONLY in the per-device manifest —
    /// so the union is disjoint in practice and the dedup is the id-keyed belt
    /// for the migration window (risk-1). Recomputed alongside `sessions` (and
    /// on Core Data change) so a materialized ref re-groups the bench. Source of
    /// truth: `docs/architecture/2026-07-25-clip-sync-single-source-of-truth.md`.
    @State private var benchClips: [InboxClip] = []
    /// **What this surface draws, as one value** (C2 step 2b-ii-c2).
    ///
    /// Every number the header says is a property of this. Before the swap
    /// the header assembled its own — `lensClips.count + inFlightOnly +
    /// absorbedMediaCount` for the count, a *different* union for the span,
    /// and `sessions.count` for the session term: three separately-scoped
    /// sets in one sentence, which is how "7 new clips · 0 sessions" rendered
    /// above a visible card under a green gate.
    @State private var drawn: DrawnBench = DrawnBench(loose: [], clusteredSessions: [], inFlight: [])
    /// The photo/video/note refs of each drawn session, keyed by the
    /// projected `ClipGroup.id`.
    ///
    /// **This is now a PROJECTION of the drawn grouping, not a second pass.**
    /// `SessionMediaAbsorber` used to decide media membership on its own rule
    /// (±5 min from the session's *span*), while `UnifiedBenchGrouper` decides
    /// it by a ≤10 min gap to the *adjacent item*, chaining — two rules for
    /// one question, which is why the header could count a photo the cards
    /// drew elsewhere. The grouper is now the only answer, and this map is
    /// read back out of it.
    @State private var mediaBySessionId: [UUID: [MediaReference]] = [:]
    /// Media refs by id — the resolve side of the projection above.
    @State private var mediaRefsById: [UUID: MediaReference] = [:]
    @State private var bundleSession: BundleRequest? = nil
    // Clip-editor cycle 2: the boxed ✎ Edit opens the unified ClipEditorModal
    // as a sheet, superseding the pushed ClipDetailView.
    @State private var editingClip: ClipEditorModal.Source? = nil
    // Cluster-editor single-open accordion (row/chevron tap expands-to-read).
    @State private var openClusterClipId: UUID? = nil
    /// Derived from the player, never stored: `AudioPlayerService` publishes
    /// what is playing, including when playback ends on its own. A local copy
    /// is what stayed lit after a clip finished (F23 T2.3).
    private var playingClipId: UUID? {
        guard let file = audio.currentFile, audio.isPlaying else { return nil }
        return inbox.clips.first(where: { $0.audioFilename == file })?.clipId
    }
    /// The one owner of phone playback and of the shared audio session's
    /// lifecycle. This view previously mirrored its `sessionActivated` bookkeeping
    /// alongside a second `AVAudioPlayer`; both are the owner's job (F23 T2.3).
    @ObservedObject private var audio = AudioPlayerService.shared
    /// Per-session, per-clip selection state for the expanded card.
    /// Keyed by clip id. Defaults to "non-accidental clips selected"
    /// when the user expands a session for the first time; once they
    /// toggle a ring, manual selection takes over.
    @State private var sessionSelections: [UUID: Set<UUID>] = [:]
    /// Per-session absorbed-media inclusion. Keyed by session id;
    /// value is the `Set` of `MediaReference.id` that the user has
    /// excluded from the bundle by tapping the ring on an absorbed
    /// media row (photo / video). Default = empty (all media
    /// included). Bundling filters `mediaBySessionId` by
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
        // `let _ =` because a bare call in a ViewBuilder is read as a view.
        let _ = BenchPerf.body(sessions: sessions.count, clips: benchClips.count, lens: drawn.count)
        ZStack {
            Crucible.Color.paper.ignoresSafeArea()
            // **"Nothing new" needs THREE conditions, and each was found
            // separately** (merge of `main` into `f8`, 2026-08-02). Both
            // branches fixed a different half of the same sentence, so the
            // resolution is the conjunction — dropping either side reopens a
            // shipped defect:
            //
            //  - Gate on the VISIBLE sessions (hideReviewed-filtered), not
            //    `inbox.isEmpty` (the raw manifest) — the New lens also draws
            //    materialized/loose refs the manifest doesn't know about.
            //  - Not while a SIBLING stack has content (device pass
            //    2026-07-27: "Nothing new" rendered above eight populated
            //    loose-ref rows).
            //  - Not while the first CloudKit import is STILL LOOKING (F22) —
            //    on a fresh install an empty local store means "we haven't
            //    finished", not "she has none", and on the surface whose
            //    subject is content she feared losing, certainty is the harm.
            //
            // All three live in one pure predicate so the rule is money-tested
            // in a single place rather than re-derived at each call site.
            // **`drawn.count`, not `sessions.isEmpty`** — `sessions` is the
            // LOOSE pile after the 2b-ii-c2 swap, so a bench whose every
            // session a cluster proposal consumed would have drawn "Nothing
            // new" over a screen full of cluster cards. Gating on the drawn
            // set is the same fix as the header's: ask the value that knows
            // what is on screen.
            if drawn.count > 0 {
                list
            } else if Self.showsEmptyState(
                sessionsEmpty: true,
                hasSiblingContent: hasSiblingContent,
                mayAssertEmpty: firstImport.mayAssertEmpty
            ) {
                emptyState
            }
            // else: a sibling stack is rendering, or the import is still
            // running — draw nothing rather than assert emptiness.
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
            // P0-3: promote any transcribed manifest clip to a synced
            // zero-edge ref BEFORE the first render — the one-shot launch
            // migration + catch-up. Running it here (before benchClips is
            // read) is the structural guarantee against double-render: a
            // clip is only ever in ONE store at read time (risk-1).
            ArrivedClipMaterializer.materializeAll(in: context)
            regroupSessions()
            registerSessionIds()
            // Tutorial #4 (Captured Clips · the Watch story). Spec
            // gate: opened **non-empty** — clips have actually
            // arrived. Empty-state is intentionally NOT a trigger
            // (nothing to explain yet). The orchestrator handles the
            // once-each + session/day caps + arming gate.
            // `drawn.count`, matching the empty-state gate: "opened non-empty"
            // means something is on screen, which a fully-clustered bench is.
            if drawn.count > 0 {
                TutorialOrchestrator.shared.tryFire(.watchStory)
            }
        }
        .onChange(of: inbox.clips) { _, _ in
            regroupSessions()
            registerSessionIds()
        }
        .onChange(of: arrivals.clipsInFlight) { _, _ in
            // In-flight clips are rendered as IncomingCard, NOT as
            // a SessionCard inside the session list. When the
            // tracker changes (clip enters/leaves any in-flight
            // phase) the sessions need to be re-grouped without
            // those clipIds to avoid double-rendering.
            regroupSessions()
            registerSessionIds()
        }
        // **The Sort layer's own state now drives a recompose** (2b-ii-c2).
        // `proposals` and the loose pile used to be computed properties, so a
        // set-aside or a "Not together" re-derived them on the next render for
        // free. They are composed once per regroup now — which is what makes
        // the header and the cards read one value — so the two inputs the user
        // can change without touching the manifest have to say so.
        //
        // Missing these would silently revert **F44**: a clip set aside from a
        // cluster would leave the proposal and never come back to the loose
        // list, which is the subtractive posture J2 retired.
        .onChange(of: removedByFingerprint) { _, _ in
            regroupSessions()
            registerSessionIds()
        }
        .onChange(of: inbox.dismissedClusterFingerprints) { _, _ in
            regroupSessions()
            registerSessionIds()
        }
        .onChange(of: inbox.soloClipIds) { _, _ in
            // The user *Removed a clip from session* on Clip Detail
            // (Chunk C, Clip triage July 12 2026). The manifest's
            // publish fires here even though `clips` didn't change;
            // re-group so the removed clip snaps into its own
            // single-clip card without waiting for another mutation.
            regroupSessions()
            registerSessionIds()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            // P0-3: a materialized voice ref (this device) or a ref synced
            // in from another device lands here — recompute the bench so it
            // re-groups. Also media refs land as unplaced refs; re-absorb so
            // a photo captured now appears inside its sitting's session card.
            regroupSessions()
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

    /// **The ONE place `sessions` is regrouped** (F38, 2026-08-02).
    ///
    /// F38's invariant was that regrouping and refreshing the media map must
    /// happen together, because a regroup that left the map behind produced
    /// entries nothing could draw. **That invariant is now structural rather
    /// than remembered**: both come out of a single `composeDrawnBench` call,
    /// so there is no longer an order in which they can be done separately.
    ///
    /// Four of the five original call sites remembered to pair them and one
    /// did not (`:239`, the remove-clip-from-session regroup). That is an
    /// invariant carried by memory; this makes it structural, and
    /// `BenchCountAndProposalCopyTests` asserts there is exactly one
    /// assignment site so a sixth cannot quietly appear.
    private func regroupSessions() {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { BenchPerf.regroup(since: t0, sessions: sessions.count, lens: drawn.count) }
        composeDrawnBench()
    }

    /// **The swap (C2 step 2b-ii-c2): one composition, read by everything.**
    ///
    /// `BenchInventory → RenderedBench → DrawnBench`, then projected back into
    /// the concrete `ClipGroup` + `MediaReference` pair the card layer
    /// consumes. The header, the cards, the cluster stack and selection all
    /// now read one value composed here, which is the entire point — seven
    /// defects in this file were a number computed from a different set than
    /// the one being drawn, and each was closed by scoping one more term
    /// correctly until the next appeared.
    ///
    /// **The proposal cycle, and why it is two calls rather than two
    /// groupings.** `ClipClusterProposer` consumes the bench's sessions and
    /// `compose` consumes the proposals, so neither can go first. Composing
    /// with no proposals settles the grouping; `claiming` then applies what
    /// the proposer said without regrouping. Proposals decide only which
    /// region an item is drawn in, never whether it is drawn — so the count
    /// is invariant across the two calls.
    private func composeDrawnBench() {
        let voiceRefs = fetchZeroEdgeVoiceRefs()
        let mediaRefs = fetchUnplacedNonVoiceRefs()
        // Premise 2 of the redo contract — **voice resolves from BOTH stores,
        // at every site, built in from the start.** The reverted 2b-ii built
        // its lookup from `inbox.clips` alone while the item set unioned
        // manifest rows AND refs, so on a mature bench (where `materializeAll`
        // has drained transcribed rows into refs) nearly every voice clip
        // resolved to nothing: that is what rendered "1 clip from 1 sitting"
        // over three rows spanning 58 minutes. `composeBenchClips` IS the
        // two-store union, so the resolve is built on it rather than beside
        // it.
        //
        // Held in a LOCAL and assigned to `@State` at the end. Everything
        // below resolves through `voiceById`, so the composition never depends
        // on whether a `@State` write is readable within the same call — a
        // question with a subtle answer and no reason to be asked.
        let clips = ArrivedClipMaterializer.composeBenchClips(
            manifestClips: inbox.clips,
            refs: voiceRefs
        )
        let voiceById = Dictionary(clips.map { ($0.clipId, $0) }, uniquingKeysWith: { first, _ in first })
        let mediaById = Dictionary(mediaRefs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let inventory = BenchInventory.compose(
            manifestClips: inbox.clips,
            refs: (voiceRefs + mediaRefs).map {
                BenchRefDescriptor(
                    id: $0.id,
                    kind: Self.benchKind(of: $0),
                    createdAt: $0.createdAt,
                    rollGroupId: $0.rollGroupId
                )
            },
            refIsReviewed: { BenchClipReviewStore.isReviewed($0) }
        )
        let ungrouped = RenderedBench.compose(
            allItems: inventory.items,
            reviewedIds: inventory.reviewedIds,
            hideReviewed: hideReviewed,
            now: Date(),
            inFlightIds: Set(arrivals.clipsInFlight.keys),
            soloIds: inbox.soloClipIds
        )
        // The proposer still speaks `ClipGroup`, so it is asked about the
        // projected sessions — the same projection the cards render, not a
        // separately-derived one.
        let project: (UnifiedSession) -> ClipGroup = { Self.projectGroup($0, voiceById: voiceById) }
        let proposed = ClipClusterProposer.propose(
            sessions: ungrouped.sessions.map(project),
            dismissed: inbox.dismissedClusterFingerprints
        )
        let bench = ungrouped.claiming(proposals: proposed, trim: removedByFingerprint)
        let drawnBench = DrawnBench.from(bench, proposals: proposed)

        benchClips = clips
        mediaRefsById = mediaById
        drawn = drawnBench
        proposals = proposed
        sessions = drawnBench.loose.map(project)
        allSessions = bench.allSessions.map(project)
        // Keyed by the PROJECTED group's id, not the `UnifiedSession`'s. The
        // two differ by construction: `ClipGroup.clips` is newest-first and
        // `UnifiedSession.items` is oldest-first, so each takes its id from
        // the opposite end of the sitting. Keying the map by whatever the card
        // will actually look up is the difference between a media row drawing
        // and a media row silently missing.
        //
        // Built over `allSessions`, not the drawn ones, because the drill-in
        // reads a session the lens may already have dropped — the same reason
        // `allSessions` exists. Entries nothing draws are harmless now that no
        // count is derived from this map; F38's ruling against them was about
        // the header *counting* media it could not draw, and the header no
        // longer reads media at all.
        var media: [UUID: [MediaReference]] = [:]
        for session in bench.allSessions {
            let refs = session.items.compactMap { mediaById[$0.id] }
            if !refs.isEmpty { media[project(session).id] = refs }
        }
        mediaBySessionId = media
        // `ClipsTabView` filters its sibling unplaced stack by this set so a
        // photo drawn inside a session card does not also draw above it. The
        // bus survives the absorber's retirement because the *question* it
        // answers survives — it is now answered by the grouping rather than by
        // a second pass with its own rule.
        //
        // Scoped to what THIS surface draws: a voiceless session belongs to
        // the sibling stack until step 3 (`drawsVoicelessSessions`), so its
        // media must not be filtered out of the stack that is still drawing
        // it.
        BenchAbsorbedMediaBus.shared.setAbsorbed(
            Set(drawnBench.items.filter { $0.kind != .voice }.map(\.id))
        )
    }

    /// Resolve a drawn session back to the concrete `ClipGroup` the card layer
    /// renders. Media items are carried by `mediaBySessionId` alongside.
    ///
    /// **`voiceById` is the two-store union**, passed in rather than rebuilt:
    /// premise 2 says voice resolves from both stores at every site, and a
    /// map built per call from a `@State` array would be both the wrong
    /// question (which store?) asked N times and O(n·m) work in a path
    /// `[BenchPerf]` measures.
    ///
    /// Newest-first to match `ClipSessionGrouper.group`'s convention, which
    /// `ClipGroup.capturedAt` (reading `clips.last`) and `id` (reading
    /// `clips.first`) both depend on — the opposite end from
    /// `UnifiedSession`, which is why the media map is keyed by the projected
    /// group rather than by the session it came from.
    private static func projectGroup(
        _ session: UnifiedSession,
        voiceById: [UUID: InboxClip]
    ) -> ClipGroup {
        let voice = session.items
            .filter { $0.kind == .voice }
            .compactMap { voiceById[$0.id] }
            .sorted { $0.capturedAt > $1.capturedAt }
        return ClipGroup(clips: voice)
    }

    private static func benchKind(of ref: MediaReference) -> BenchClipItem.Kind {
        switch ref.mediaTypeEnum {
        case .voice: return .voice
        case .image: return .image
        case .video: return .video
        case .note:  return .note
        }
    }

    /// Fetch the materialized bench voice clips — zero-edge, non-recycled
    /// `MediaReference`s of `mediaType == voice`. The read-side mirror of
    /// `fetchUnplacedNonVoiceRefs` (which pulls the absorbable photo/video).
    private func fetchZeroEdgeVoiceRefs() -> [MediaReference] {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(
            format: "edges.@count == 0 AND recycledAt == nil AND mediaType == %@",
            MediaReference.MediaType.voice.rawValue
        )
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? context.fetch(req)) ?? []
    }

    /// Fetch unplaced photo/video/note MediaReferences — candidates
    /// for absorption into a voice session's time window.
    private func fetchUnplacedNonVoiceRefs() -> [MediaReference] {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        // P8: exclude recycled clips from session absorption candidates.
        req.predicate = NSPredicate(
            format: "edges.@count == 0 AND recycledAt == nil AND mediaType != %@",
            MediaReference.MediaType.voice.rawValue
        )
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    // MARK: - Workbench + Sort layer (v3, July 4 2026)

    /// Sessions NOT currently in a cluster proposal — the loose
    /// pile below the cluster stack. Spec § "Lead with signal,
    /// never bury the rest": the loose pile is always in plain
    /// sight, not subtracted or hidden by the Sort layer.
    ///
    /// **Now `sessions` itself** (C2 step 2b-ii-c2). `RenderedBench.loose`
    /// already removes clustered items, drops the sessions a proposal
    /// consumed whole, and returns the remainder of a partly-claimed one —
    /// **F44's set-aside-comes-back, unchanged in behaviour and moved to the
    /// value that owns it.** Recomputing it here from `proposals.clipIds`
    /// was a second producer of the clustered set: four independent producers
    /// existed for clips and three for media, which is how the same item
    /// could be clustered by one term and loose by another.
    ///
    /// The subset case still deliberately misses its media: a partly-claimed
    /// session's projected id derives from a different first clip, so no entry
    /// matches — correct, because the cluster card now owns that media (kept
    /// in its glyphs, set-aside in its own block) and drawing it twice is the
    /// duplication class F35(b) closed.
    private var looseSessions: [ClipGroup] { sessions }

    /// "Not together" tap — record the dismissal and let the manifest
    /// prune-on-write logic keep the store clean.
    private func handleClusterDismiss(_ proposal: ClusterProposal) {
        InboxManifest.shared.dismissCluster(proposal)
    }

    // MARK: - Cluster editor (§87 · Model A transient trim, 2026-07-15)

    /// Member clips of a cluster (kept + set-aside), ordered by the
    /// proposal's `clipIds`, for the expanded editor rows.
    private func clips(forCluster proposal: ClusterProposal) -> [InboxClip] {
        let byId = Dictionary(benchClips.map { ($0.clipId, $0) }, uniquingKeysWith: { first, _ in first })
        return proposal.clipIds.compactMap { byId[$0] }
    }

    /// **F40 · the absorbed media of every session this proposal consumed.**
    ///
    /// A proposal is built from WHOLE sessions, and absorbed media rendered
    /// only inside session cards — so when a cluster took every session on
    /// the bench, its photos appeared nowhere while still being counted.
    /// Ruled 2026-08-02: the photos are bench items the user captured, and
    /// they appear wherever their clips appear.
    ///
    /// A session belongs to this proposal when any of its clips is in it;
    /// proposals consume whole sessions, so "any" and "all" coincide here.
    /// Deduped by ref id — a session cannot contribute the same media twice,
    /// but the union is taken defensively rather than assumed.
    ///
    /// **Scans `allSessions`, not `sessions`.** After the 2b-ii-c2 swap
    /// `sessions` is the LOOSE pile — a session a proposal consumed whole is
    /// no longer in it, which is precisely the case F40 exists for. Iterating
    /// the drawn-loose set here would restore the original defect exactly: a
    /// cluster that took every session on the bench would show none of its
    /// photos.
    private func media(forCluster proposal: ClusterProposal) -> [MediaReference] {
        let clusterIds = Set(proposal.clipIds)
        var seen: Set<UUID> = []
        var out: [MediaReference] = []
        for session in allSessions where session.clips.contains(where: { clusterIds.contains($0.clipId) }) {
            for ref in mediaBySessionId[session.id] ?? [] where !seen.contains(ref.id) {
                seen.insert(ref.id)
                out.append(ref)
            }
        }
        return out
    }

    /// The proposal's media MINUS anything the user set aside (F43).
    /// `removedByFingerprint` is a `Set<UUID>` and the handlers never look
    /// the id up, so it carries `MediaReference.id` alongside clip ids
    /// without a parallel store or a key change.
    private func includedClusterMedia(_ proposal: ClusterProposal) -> [MediaReference] {
        let removed = removedByFingerprint[proposal.fingerprint.rawValue] ?? []
        return media(forCluster: proposal).filter { !removed.contains($0.id) }
    }

    /// **The card's subtitle, computed from what is KEPT** (F43).
    ///
    /// `ClusterProposal.whyText` is a stored `let` fixed at construction, so
    /// it describes the ORIGINAL membership forever. On device that read
    /// "7 clips from 3 sittings · 125 minutes apart" above 3 kept clips —
    /// and two of those three numbers were right ONLY because the kept set
    /// happened to retain both extremes. Setting aside an endpoint makes the
    /// span silently wrong while still looking plausible.
    ///
    /// Sittings are recomputed by regrouping the kept clips through the same
    /// grouper the bench uses, so the lens, the card and this line cannot
    /// disagree about what a sitting is.
    private func clusterSubtitle(_ proposal: ClusterProposal, _ kept: [InboxClip]) -> String {
        let keptMedia = includedClusterMedia(proposal)
        let sittings = ClipSessionGrouper.group(kept, soloClipIds: inbox.soloClipIds).count
        return ClusterSubtitleBuilder.subtitle(
            clipCount: kept.count + keptMedia.count,
            sittingCount: sittings,
            capturedAts: kept.map(\.capturedAt)
        )
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
        let byId = Dictionary(benchClips.map { ($0.clipId, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = trimmed.keptClipIds.compactMap { byId[$0] }
        guard !kept.isEmpty else { return }
        // **F43 · the cluster commit used to pass `absorbedMediaRefs: []`**
        // while BOTH session paths pass `includedAbsorbedMedia(in:)`. So no
        // photo was ever committed from a cluster: bundling stranded them on
        // the bench while the voice clips moved into the memory. F40 made the
        // card count and show them, which turned a consistent absence into a
        // confident display over a path that disagreed.
        //
        // Respects the same set-aside store the voice rows use, so a photo
        // the user excluded is excluded here too.
        let keptMedia = includedClusterMedia(proposal)
        bundleSession = BundleRequest(
            session: ClipGroup(clips: kept),
            clipsToBundle: kept,
            absorbedMediaRefs: keptMedia,
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

    /// **May we say "Nothing new"?** True only when all three hold — no
    /// visible sessions, no sibling lens content, and the first CloudKit
    /// import has finished looking.
    ///
    /// Pure, so the rule is money-tested in one place rather than re-derived
    /// at each call site. Each condition is a separately-found defect and
    /// each is load-bearing:
    ///
    ///  - `sessionsEmpty` — the visible, hideReviewed-filtered sessions, not
    ///    the raw manifest (which doesn't know about materialized refs).
    ///  - `hasSiblingContent` — device pass 2026-07-27: "Nothing new"
    ///    rendered directly above eight populated loose-ref rows, because
    ///    the gate ignored a sibling stack rendering in the same lens.
    ///  - `mayAssertEmpty` — F22: on a fresh install an empty local store
    ///    means "we haven't finished looking," not "she has none." Passed in
    ///    as an argument rather than read inside, so this stays pure AND the
    ///    call site remains a real production read of `mayAssertEmpty` —
    ///    `FirstImportStateTests` counts those and explicitly rejects a
    ///    comment as a read.
    ///
    /// The three arrived from two branches (`main`'s device-pass fixes and
    /// `f8`'s F22 work) and were merged as a conjunction 2026-08-02:
    /// they are different halves of one sentence, and dropping either half
    /// reopens a shipped defect.
    static func showsEmptyState(
        sessionsEmpty: Bool,
        hasSiblingContent: Bool,
        mayAssertEmpty: Bool
    ) -> Bool {
        sessionsEmpty && !hasSiblingContent && mayAssertEmpty
    }

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
                    mediaFor: media(forCluster:),
                    subtitleFor: clusterSubtitle,
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
        // The Select entry for New lives at the ClipsTabView level (a
        // consistent position across all three filters) — SessionListView's
        // header renders only when the inbox is non-empty, so hosting Select
        // here would hide it whenever New is all returned-refs / all-clustered.
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


    /// **Reads `drawn` and nothing else** — premise 4 of the redo contract,
    /// and the reason `theHeaderAssemblesNoCountOfItsOwn` exists.
    ///
    /// This line used to assemble `lensClips.count + inFlightOnly +
    /// absorbedMediaCount`: three separately-scoped sets, of which F35(a) and
    /// F38 each corrected one and left the others. It was green at 1394/192
    /// while reading **"7 new clips · 0 sessions"** above a card plainly on
    /// screen, because every guard asserted on the composition and the
    /// composition was correct — nothing asserted on what the view read out
    /// of it.
    ///
    /// Source-agnostic per `CLAUDE.md` §Phone (July 10 2026, line 142
    /// corollary): the bench takes clips from the Watch AND the phone
    /// Clips-FAB, so the headline never names a source. Source lives
    /// per-clip on the card, not here.
    private var headerTitle: String {
        BenchHeaderTitleBuilder.title(clipCount: drawn.count)
    }

    /// The span and the session term, from the same value the count came
    /// from. **`capturedAts` and `count` read one `items` array**, so the
    /// span can no longer range a different set than the number above it —
    /// which it did continuously, under a green gate, in this exact surface:
    /// the count included absorbed media and the span did not, so a photo
    /// moved the number and not the dates.
    private var headerSubtitle: String {
        let all = drawn.capturedAts
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
                readySessionCount: drawn.sessionTerm,
                syncingClipCount: syncingCount
            )
        }
        return CapturedClipsSubtitleBuilder.subtitle(
            earliest: first,
            latest: last,
            sessionCount: drawn.sessionTerm
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
        session.clips.map(\.clipId) + (mediaBySessionId[session.id] ?? []).map(\.id)
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
        // **The UNFILTERED grouping** (`RenderedBench.allSessions`, projected).
        // Opening a session marks its clips reviewed, so a lens-filtered
        // derivation would drop the very session being read and
        // `AutoDismissView` would pop the screen out from under the reader.
        //
        // Under F37 this is also what makes the drill-in's own header honest:
        // the session carries every member it has, and the list header above
        // it now counts those same members. The 2 · 2 · 4 reading that F37
        // was raised for cannot recur, because there is no longer a
        // pre-shrunk session for the card to describe.
        if let session = allSessions.first(where: { $0.id == sessionId }) {
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
        for ref in mediaBySessionId[session.id] ?? [] {
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
        let mediaClips = (mediaBySessionId[session.id] ?? []).map {
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
        let media = mediaBySessionId[session.id] ?? []
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
        let totalClips = session.clips.count + (mediaBySessionId[session.id]?.count ?? 0)
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
        let totalClips = session.clips.count + (mediaBySessionId[session.id]?.count ?? 0)
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
            // P0-3: land the re-transcription on whichever store backs the
            // clip — a materialized clip is a ref, so the manifest path alone
            // would silently drop the retry result.
            lifecycle.writeBenchClipTranscript(clipId: clipId, transcript: result.text)
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
    /// `mediaBySessionId` (which itself is `createdAt`-
    /// sorted upstream).
    private func includedAbsorbedMedia(in session: ClipGroup) -> [MediaReference] {
        let excluded = sessionExcludedMediaIds[session.id] ?? []
        let all = mediaBySessionId[session.id] ?? []
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

    /// Bench playback runs through `AudioPlayerService` — the one owner of
    /// phone playback and of the shared audio session's lifecycle.
    ///
    /// This view used to hand-roll its own `AVAudioPlayer` just to reach the
    /// inbox store, and that copy had no `AVAudioPlayerDelegate`: a clip played
    /// to its natural end never deactivated the `.playback` session and the row
    /// stayed lit (F23 T2.3). The owner already solved both — `play(url:label:)`
    /// covers the second store.
    private func playClip(_ clip: InboxClip) {
        audio.play(url: InboxManifest.audioURL(for: clip.audioFilename),
                   label: clip.audioFilename)
    }

    private func stopPlayback() {
        audio.stop()
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


/// **`[BenchPerf]` — the instrument that ended the 2026-08-09 Clips freeze.**
///
/// Same posture as `[Amp]` (B10) and `[Meter]` (D10), and it earned its keep
/// the same way: three cost-shaped hypotheses were reasoned off the diff and
/// all three died against one measurement. `render` at 0.0–0.4ms over a
/// 47-item bench, four `body` passes, then silence — which is what redirected
/// the search from cost to identity and found `ClipGroup.id` minting a fresh
/// UUID on every read.
///
/// It reads no state it does not already have and changes no behaviour. Kept
/// wired to the reverted composition path rather than parked, because a
/// complete-but-uncalled type is precisely what this rebuild exists to stop
/// (`UnifiedBenchGrouper` sat that way since July; `MediaBlobOrphanSweep`
/// before it). **It carries into the C2 step 2b-ii redo, where the device pass
/// needs it.**
///
/// What each line answers:
///   * `body`/`regroup` counts climbing without bound → a CYCLE
///   * one entry with a large `ms`                    → COST
///   * counts that stop while the screen is frozen    → neither: the churn is
///     inside SwiftUI's diff, which is the freeze this instrument found
///
/// Rate-limited so it cannot become the bottleneck: every call for the first
/// 20, then every 25th.
@MainActor
enum BenchPerf {
    private static var bodyCount = 0
    private static var regroupCount = 0
    private static var firstAt: CFAbsoluteTime?

    private static func shouldLog(_ n: Int) -> Bool { n <= 20 || n % 25 == 0 }

    private static func elapsed() -> Double {
        let now = CFAbsoluteTimeGetCurrent()
        if firstAt == nil { firstAt = now }
        return now - (firstAt ?? now)
    }

    /// `lens` is **`DrawnBench.count` — what the header says**, and after the
    /// 2b-ii-c2 swap that is the number to watch: it is the one the surface
    /// asserts, so a `lens` that disagrees with what is on screen is the
    /// whole class this rebuild exists to end, reported by the instrument
    /// rather than by a screenshot.
    ///
    /// It also still explains B16. The device showed `sessions=3 → 2 → 1`
    /// with `clips=27` constant, which reads as sessions being regrouped away
    /// under a fixed clip set. It is not: on the New lens `stillInPlay` needs
    /// `now − latest < 10 min`, so for 8-day-old clips it is permanently empty
    /// and admission reduces to "contains something unreviewed". Sessions
    /// shrink only as clips become **reviewed** — P7-2 working.
    ///
    /// **The cost that used to be stated here is gone.** `lens` was
    /// `lensClips.count`, a computed property that regrouped the full bench on
    /// every read, so the instrument added a grouping pass per `body`. It now
    /// reads a stored value composed once per regroup, and the `regroup` line
    /// still prints the real cost.
    static func body(sessions: Int, clips: Int, lens: Int) {
        bodyCount += 1
        guard shouldLog(bodyCount) else { return }
        NSLog("[HiMem][BenchPerf] body #\(bodyCount) · sessions=\(sessions) · lens=\(lens) · clips=\(clips) · t+\(String(format: "%.2f", elapsed()))s")
    }

    // `disagreement` (2b-ii-c1) is retired with the swap: it compared the old
    // bench against the new one, and there is now only one. It did its job —
    // it fired `oldCount=4 newCount=3` on device and caught a real in-flight
    // regression that would otherwise have shipped inside `DrawnBench`, and
    // its second run measured the absorber/grouper margin at zero divergence
    // with media present, which is what made this swap a mechanical edit
    // rather than a leap.

    static func regroup(since t0: CFAbsoluteTime, sessions: Int, lens: Int) {
        regroupCount += 1
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        guard shouldLog(regroupCount) else { return }
        NSLog("[HiMem][BenchPerf] regroup #\(regroupCount) · \(String(format: "%.1f", ms))ms · sessions=\(sessions) · lens=\(lens) · t+\(String(format: "%.2f", elapsed()))s")
    }
}

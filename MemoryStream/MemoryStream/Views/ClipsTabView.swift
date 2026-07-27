import SwiftUI
import CoreData
import UIKit

/// The Clips tab — first-class evidence surface (Clips · Memories ·
/// Projects). Cold launch always lands on Memories; the Clips tab is
/// reached via tab selection or the arrival banner / notification tap.
///
/// Layout per `docs/design/screens-clips-page.jsx`:
///
///   ┌──────────────────────────────────────────────┐
///   │  Clips                                    ⌕   │  serif title + search
///   │  [New] [All] [Voice] [Photos] [Notes]         │  filter chips
///   ├──────────────────────────────────────────────┤
///   │  «content varies by filter»                   │
///   └──────────────────────────────────────────────┘
///
/// Filters:
/// - **New** — workbench-and-Sort resting state. `SessionListView`
///   handles cluster proposals + idle-gap session cards; any refs that
///   returned from a memory (`edges.count == 0` but not in the inbox
///   manifest) sit above with day-group headers.
/// - **All** — flat, chronological list of every `MediaReference`,
///   day-grouped. Placed clips show an "In: [memory chips]" row per
///   `HiMem · evidence and context.md` §"Referenced in."
/// - **Voice / Photos / Notes** — same flat list restricted by media
///   type.
///
/// **Photo/video rendering** (2026-07-09 spec update): photos/videos
/// use real thumbnails, and contiguous same-minute + same-place bursts
/// collapse into one `BurstRow` per `screens-clips-page.jsx` — the
/// "wall of identical Photo rows" was the July 9 dogfood failure.
struct ClipsTabView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject private var inbox = InboxManifest.shared
    @ObservedObject private var absorbedBus = BenchAbsorbedMediaBus.shared
    @StateObject private var viewModel = JournalViewModel()
    /// Status axis — `New ⟷ All`, the primary lens. Ochre toggle.
    /// See `ClipsStatus` for the July 12 2026 lock.
    @State private var status: ClipsStatus = .new
    /// Type axis — media kind (independent of status). Neutral chip
    /// row. `.all` = every media type; `.video` is a first-class case
    /// (was folded into `.photos` in the retired single-row filter).
    @State private var type: ClipsType = .all
    @State private var unplacedRefs: [MediaReference] = []
    /// The clip being edited in the unified `ClipEditorModal` sheet (Clip-editor
    /// cycle 2) — supersedes the pushed `ClipDetailView` for the bench.
    @State private var editingClip: ClipEditorModal.Source?
    /// Single-open accordion for the New view's loose-clip flat stack.
    @State private var expandedUnplacedItemId: String? = nil
    /// Coalesces a burst of `NSManagedObjectContextObjectsDidChange`
    /// notifications (which flood the main thread during CloudKit
    /// import waves around freshly-arrived watch clips) into a
    /// single `loadUnplaced()` fetch. Untuned, each notification
    /// ran the fetch synchronously on main and starved the
    /// session-card tap gesture's animation.
    @State private var unplacedReload = DebouncedTrigger(interval: .milliseconds(250))
    /// Top-bar sheet/nav destinations. Each tab presents its own copies
    /// so any tab can reach search / Learn / settings without routing
    /// through Memories. Per `docs/design/screens-home.jsx` §HomeTopBar,
    /// the top bar (wordmark + search + ? + settings) is identical on
    /// every tab.
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showTutorials = false
    /// Signal from the Clips status sheet's quick-filter shortcuts.
    /// See `ClipsStatusSheet` — the sheet fires a pending filter and
    /// this view consumes it into its own `filter` state.
    @ObservedObject private var filterBus = ClipsFilterBus.shared
    /// Observed for the post-Create "Memory created" toast per
    /// `Clip model · spec.md` §Start a Memory (July 12 2026).
    @ObservedObject private var memoryNav = MemoryNavigationBus.shared
    /// Non-nil while the created-memory toast is on screen. Timer
    /// clears it after ~3.5s; the View button also clears via the
    /// nav-bus route.
    @State private var toastAutoDismissTask: Task<Void, Never>? = nil
    /// Unconnected multi-select (P7-3). Drives the pinned action bar.
    @ObservedObject private var selection = ClipsSelection.shared
    /// "Delete N clips?" confirm — clips have no Recently Deleted yet, so
    /// batch delete is permanent; the confirm is the interim net.
    @State private var showDeleteConfirm = false
    /// Carries the selected clips into the "Add to a memory" create flow.
    @State private var selectionBundle: SessionListView.BundleRequest? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if selection.selecting {
                            // Photos-style selecting top bar (mock, July 2026)
                            // replaces the status header: Cancel · N selected ·
                            // Select all.
                            selectingTopBar
                            dragHint
                        } else {
                            ClipsHeader(
                                status: $status,
                                type: $type,
                                onSearchTap: { showSearch = true },
                                onSettingsTap: { showSettings = true },
                                onHelpTap: { showTutorials = true }
                            )
                        }
                        content
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            // Clear the floating capture FAB so the last clip
                            // rows don't run under it (device pass 2026-07-27:
                            // 12pt let rows sit under the FAB + tab pill). The
                            // selecting case already reserves 84pt for the
                            // selection action bar (the FAB is hidden then).
                            .padding(.bottom, selection.selecting ? 84 : 108)
                    }
                }
                .coordinateSpace(name: ClipsSelectionSpace.name)
                .onPreferenceChange(ClipRowFramesKey.self) { selection.rowFrames = $0 }
                if let toastMemoryId = memoryNav.justCreatedMemoryId {
                    MemoryCreatedToast(
                        onView: {
                            // Fire the actual navigation signal that
                            // `HiMemTabView` (switches to Memories)
                            // and `JournalView` (pushes detail)
                            // observe. Clearing `justCreatedMemoryId`
                            // dismisses this toast; the bus's
                            // `pendingOpenMemoryId` drives the push.
                            toastAutoDismissTask?.cancel()
                            memoryNav.justCreatedMemoryId = nil
                            memoryNav.pendingOpenMemoryId = toastMemoryId
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if selection.selecting {
                    selectionActionBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: selection.selecting)
            .animation(.easeOut(duration: 0.22), value: memoryNav.justCreatedMemoryId)
            .background(Crucible.Color.paper.ignoresSafeArea())
            .navigationTitle("Clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { loadUnplaced() }
            .onDisappear { unplacedReload.cancel() }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: context
            )) { _ in
                unplacedReload.fire { loadUnplaced() }
            }
            .onChange(of: memoryNav.justCreatedMemoryId) { _, newValue in
                // 3.5s auto-dismiss on the toast when it's shown.
                // Cancel any prior task so back-to-back creates
                // extend the visible time correctly.
                toastAutoDismissTask?.cancel()
                guard newValue != nil else { return }
                // F8 · during the guided walkthrough, keep the "Memory created ·
                // View" toast up until the user taps View — its `openMemory`
                // beat points at this toast, and a 3.5s auto-dismiss would
                // strand it. `isRunning` (not a specific beat) so this is robust
                // to onChange ordering with `memoryDidStart`.
                guard !WalkthroughOrchestrator.shared.isRunning else { return }
                toastAutoDismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if !Task.isCancelled {
                        memoryNav.justCreatedMemoryId = nil
                    }
                }
            }
            .onChange(of: filterBus.pending) { _, pending in
                if let pending {
                    status = pending.status
                    type = pending.type
                    filterBus.pending = nil
                }
            }
            .sheet(item: $editingClip) { source in
                ClipEditorModal(source: source)
            }
            .sheet(item: $selectionBundle) { request in
                CreateMemoryFromClipsSheet(
                    clips: request.clipsToBundle,
                    session: request.session,
                    absorbedMediaRefs: request.absorbedMediaRefs,
                    prefillTitle: request.prefillTitle,
                    viewModel: viewModel
                )
            }
            .onChange(of: status) { _, _ in
                // Selection is per-filter (the visible id set differs), so
                // switching filters leaves selecting mode and drops the
                // now-stale visible registry.
                selection.exit()
                selection.resetVisible()
            }
            .alert(selection.count == 1 ? "Delete 1 clip?" : "Delete \(selection.count) clips?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { performSelectionDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                // P8b: batch delete now soft-deletes to Recently Deleted on
                // both backings (recoverable 30 days), so the copy matches
                // the memory/project soft-delete language.
                Text("Moves to Recently Deleted · kept for 30 days.")
            }
            .navigationDestination(isPresented: $showSearch) {
                SearchView(
                    onSelectEntry: { _ in showSearch = false },
                    onCaptureNewWith: { _ in showSearch = false }
                )
            }
            .navigationDestination(isPresented: $showTutorials) {
                TutorialsHubView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Multi-select (P7-4 — general across New · All · Unconnected)

    /// The selecting-mode top bar (mock, July 2026) — replaces the status
    /// header while `selection.selecting`: Cancel (exit) · N selected ·
    /// Select all (of the visible ids the content view registered).
    private var selectingTopBar: some View {
        HStack {
            Button("Cancel") { selection.exit() }
                .font(.system(size: 15))
                .foregroundStyle(Crucible.Color.ink2)
            Spacer()
            Text(selection.count == 1 ? "1 selected" : "\(selection.count) selected")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Crucible.Color.ink)
            Spacer()
            Button("Select all") { selection.selectAll() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Crucible.Color.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// The drag-to-select affordance hint (mock, July 2026).
    private var dragHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .semibold))
            Text("Drag down the circles to select a run")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Crucible.Color.ink4)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    /// Pinned bottom action bar shown throughout selecting mode: Add to a
    /// memory… (ochre) + Delete N (danger). Both disable at 0 selected.
    private var selectionActionBar: some View {
        HStack(spacing: 10) {
            Button { startAddSelectedToMemory() } label: {
                Text("Add to a memory…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(selection.count == 0)
            .opacity(selection.count == 0 ? 0.5 : 1)
            Button { showDeleteConfirm = true } label: {
                Text(selection.count == 0 ? "Delete" : "Delete \(selection.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.danger)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 18)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Crucible.Color.danger, lineWidth: 1.5))
                    .contentShape(Rectangle()) // edge-to-edge tap (stroke pill interior is transparent)
            }
            .buttonStyle(.plain)
            .disabled(selection.count == 0)
            .opacity(selection.count == 0 ? 0.5 : 1)
        }
        .padding(12)
        .background(Crucible.Color.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
    }

    /// Deletes the selected clips, partitioned by backing: InboxClips →
    /// manifest dispose (tombstone + watch ack), MediaReferences → hard
    /// delete. Both are the established delete paths (arbiter-consistent).
    /// Permanent — gated behind the confirm alert (no clip Recently
    /// Deleted yet). Same partition on every filter (New/All/Unconnected).
    private func performSelectionDelete() {
        let ids = selection.selectedIds
        let clipIds = InboxManifest.shared.clips.filter { ids.contains($0.clipId) }.map(\.clipId)
        let refIds = ids.subtracting(Set(clipIds))
        // P8b: both backings now SOFT-delete to Recently Deleted (recoverable
        // 30 days) — inbox clips via the manifest recycledAt, refs via
        // MediaReference.recycledAt. No longer permanent.
        if !clipIds.isEmpty { InboxManifest.shared.recycleClips(clipIds: clipIds) }
        if !refIds.isEmpty {
            EntryLifecycleService(storage: .shared, processingEngine: .shared)
                .recycleClips(refIds: refIds)
        }
        selection.exit()
    }

    /// Routes the selection into one new memory via the established
    /// create-from-clips flow: InboxClips promote (clipsToBundle), loose
    /// MediaReferences attach via createEdge (absorbedMediaRefs). Same mix
    /// handling on every filter.
    private func startAddSelectedToMemory() {
        guard selection.count > 0 else { return }
        let ids = selection.selectedIds
        let inboxClips = InboxManifest.shared.clips.filter { ids.contains($0.clipId) }
        let refIds = ids.subtracting(Set(inboxClips.map(\.clipId)))
        var refs: [MediaReference] = []
        if !refIds.isEmpty {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "id IN %@", refIds)
            refs = (try? context.fetch(req)) ?? []
        }
        selectionBundle = SessionListView.BundleRequest(
            session: ClipGroup(clips: inboxClips),
            clipsToBundle: inboxClips,
            absorbedMediaRefs: refs
        )
        selection.exit()
    }

    // MARK: - Filter branch

    @ViewBuilder
    private var content: some View {
        switch status {
        case .new:
            // New = unseen (reviewed == false). The workbench (sessions +
            // unplaced stack) filtered to unreviewed clips (P7-2 predicate).
            // Type filter is not applied to the workbench in this cut — a
            // follow-up when "new videos only" gets a use pattern.
            //
            // Select entry sits here (not in SessionListView's header) so it
            // shows on every New layout — sessions, returned-refs-only, or
            // all-clustered. Bare (no caption): the "N new clips" serif
            // header renders just below inside SessionListView.
            VStack(alignment: .leading, spacing: 6) {
                selectCaption(nil)
                newFilterContent
            }
        case .all:
            // All = everything (no connection or review filter).
            VStack(alignment: .leading, spacing: 10) {
                selectCaption("All clips.")
                FlatClipsListView(type: type, connection: .any, selection: selection, onOpen: { editingClip = .managed($0) })
            }
        case .unconnected:
            // Unconnected = connectionCount == 0 — the cleanup lens, as a
            // UNIFIED list across backing types (P7-3, July 19 2026):
            // unpromoted InboxClips + detached/loose MediaReferences.
            VStack(alignment: .leading, spacing: 10) {
                selectCaption("Clips not connected to any memory.")
                UnconnectedListView(type: type, onOpen: { editingClip = $0 }, selection: selection)
            }
        }
    }

    /// The resting caption row that carries the quiet "Select" entry into
    /// multi-select mode (mock, July 2026). Hidden while already selecting
    /// (the top bar takes over). The generalized read of the mock's
    /// Unconnected "Select" — one entry per filter's top caption row.
    @ViewBuilder
    private func selectCaption(_ text: String?) -> some View {
        if !selection.selecting {
            HStack {
                if let text {
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Crucible.Color.ink3)
                }
                Spacer()
                Button("Select") { selection.enter() }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Crucible.Color.accent)
            }
            .padding(.horizontal, 2)
        }
    }

    /// The default (New) content: unplaced-refs day-grouped stack at the
    /// top, then the workbench+Sort surface (`SessionListView`).
    ///
    /// Media refs *absorbed* into a voice session (per July 11 lock)
    /// are rendered inside their session card and filtered out here
    /// via `BenchAbsorbedMediaBus` — a photo that idle-gap-groups
    /// into a voice sitting appears once, in the session card, not
    /// again in the top stack.
    @ViewBuilder
    private var newFilterContent: some View {
        // Route through `ClipsUnplacedFilter.visible` so we skip
        // Core-Data-invalidated rows before touching `.id`. The
        // 250ms fetch debounce (added task #148 for CloudKit-churn
        // main-thread perf) can leave `unplacedRefs` holding a
        // deleted ref for a re-render window; `$0.id` on an
        // invalidated fault traps with `EXC_BREAKPOINT`. Money-tested
        // by `ClipsUnplacedFilterTests`.
        // New = unseen: hide reviewed refs (P7-2). A returned ref stays on
        // New until opened; once reviewed it's reachable via All /
        // Unconnected, but off the fresh-triage lens.
        let visibleUnplaced = ClipsUnplacedFilter.visible(
            refs: unplacedRefs,
            absorbed: absorbedBus.absorbedRefIds
        )
        .filter { !BenchClipReviewStore.isReviewed($0.id) }
        // P7-1 (July 18 2026): the new/unshaped session block goes on TOP;
        // the returned-from-memory day-grouped stack (older, previously-
        // connected-now-loose refs, running back months) goes BELOW. The
        // shipped build had these reversed, so a fresh session landed
        // under months of reverse-chron and "new arrivals appeared after
        // May 19." Whatever is surfaced as "to look at" leads the screen.
        let unplacedIds = visibleUnplaced.map(\.id)
        VStack(alignment: .leading, spacing: 12) {
            SessionListView(viewModel: viewModel, hideReviewed: true, selection: selection)
            if !visibleUnplaced.isEmpty {
                unplacedDayGroupedStack(refs: visibleUnplaced)
            }
        }
        // Register the unplaced-stack ids for New's Select-all (SessionListView
        // registers its session clips under "sessions").
        .onAppear { selection.registerVisible(unplacedIds, source: "unplaced") }
        .onChange(of: unplacedIds) { _, ids in selection.registerVisible(ids, source: "unplaced") }
    }

    /// Returned-from-memory clips, grouped by createdAt day, and within
    /// each day grouped further by burst-of-media so a burst of photos
    /// doesn't wall the list. Takes a pre-filtered ref list — the
    /// caller (`newFilterContent`) removes refs absorbed into a voice
    /// session's expanded body per the July 11 media-agnostic lock.
    @ViewBuilder
    private func unplacedDayGroupedStack(refs: [MediaReference]) -> some View {
        let groups = groupedByDay(refs: refs)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.day) { group in
                DayHeader(date: group.day)
                VStack(spacing: 8) {
                    ForEach(ClipsListItem.group(refs: group.refs)) { item in
                        ClipsListItemRow(
                            item: item,
                            onOpen: { editingClip = .managed($0) },
                            selection: selection,
                            isExpanded: expandedUnplacedItemId == item.id,
                            onToggleExpand: {
                                expandedUnplacedItemId = (expandedUnplacedItemId == item.id) ? nil : item.id
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadUnplaced() {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        // P8: exclude recycled clips (in Recently Deleted) from the bench.
        req.predicate = NSPredicate(format: "edges.@count == 0 AND recycledAt == nil")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        unplacedRefs = (try? context.fetch(req)) ?? []
    }

    private func fetchRef(id: UUID) -> MediaReference? {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    private func groupedByDay(refs: [MediaReference]) -> [(day: Date, refs: [MediaReference])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: refs) { ref in
            cal.startOfDay(for: ref.createdAt ?? .distantPast)
        }
        return grouped.map { (day: $0.key, refs: $0.value) }
            .sorted { $0.day > $1.day }
    }
}

/// Post-create confirmation toast — `Clip model · spec.md` §Create
/// one memory (July 12 2026): "dismiss the sheet and show a brief
/// **confirmation toast — 'Memory created' with a 'View' action** that
/// opens the new memory. The toast is the feedback; the user should
/// never have to navigate to Memories to confirm the thing they just
/// made exists." Auto-dismisses via a timer on
/// `ClipsTabView.toastAutoDismissTask`; View button routes through
/// `MemoryNavigationBus.pendingOpenMemoryId`.
struct MemoryCreatedToast: View {
    let onView: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Crucible.Color.confirmed)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text("Memory created")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Crucible.Color.accentInk)
            Spacer(minLength: 0)
            Button(action: onView) {
                Text("View")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Crucible.Color.accent)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Crucible.Color.ink)
                .shadow(color: Color.black.opacity(0.24), radius: 12, y: 6)
        )
    }
}

// MARK: - Filter — two independent axes (locked July 12 2026)

/// The **status** filter axis on the Clips tab — a two-state toggle
/// picking connected-ness, per `CLAUDE.md` §Phone (July 12 2026):
///
/// > "The filter is TWO independent axes, never one control: a
/// > **status** toggle (New ⟷ All) and a **type** filter (All /
/// > Voice / Photos / Video / Notes), so 'new videos only' is
/// > expressible. Status is the ochre two-state toggle (the primary
/// > lens); type is a neutral chip row (secondary refinement)."
///
/// The old single-row `ClipsFilter` (which mixed status and type
/// into `New · All · Voice · Photos · Notes`) is retired — it
/// hid Video entirely and conflated two orthogonal decisions.
enum ClipsStatus: String, CaseIterable, Identifiable, Hashable {
    case new, all, unconnected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new:         return "New"
        case .all:         return "All"
        case .unconnected: return "Unconnected"
        }
    }
}

/// The **type** filter axis on the Clips tab — media kind, per the
/// same July 12 2026 lock. Video is a first-class case here (was
/// folded into `.photos` before, invisible in the UI).
enum ClipsType: String, CaseIterable, Identifiable, Hashable {
    case all, voice, photos, video, notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    return "All"
        case .voice:  return "Voice"
        case .photos: return "Photos"
        case .video:  return "Video"
        case .notes:  return "Notes"
        }
    }
}

// MARK: - Shared segmented control

/// The ochre-track segmented pill used by the Clips header status lens —
/// factored out (July 20 2026) so Recently Deleted's type selector reuses
/// the exact control, not a lookalike. Generic over any identifiable option
/// with a display label. Selection language matches the Clips lock (Tom,
/// 2026-07-12): accent fill + accentInk bold text when selected; ink2
/// medium otherwise, on a `wash1` track.
struct HiMemSegmentedControl<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    /// Optional per-option count. When provided, a small count pill renders
    /// after the label for any option whose count is > 0. Omitted (nil) →
    /// label-only, byte-identical to the pre-count control (the Clips-tab
    /// status filter relies on that unchanged shape).
    var count: ((Option) -> Int)? = nil

    private var showsCounts: Bool { count != nil }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                segment(for: opt)
            }
        }
        .padding(3)
        .background(Crucible.Color.wash1, in: RoundedRectangle(cornerRadius: 10))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(for opt: Option) -> some View {
        let selected = selection == opt
        let n = count?(opt)
        return Button {
            selection = opt
        } label: {
            HStack(spacing: 5) {
                Text(label(opt))
                    .font(.system(size: 13.5, weight: selected ? .bold : .medium))
                    .tracking(-0.1)
                    .foregroundStyle(selected ? Crucible.Color.accentInk : Crucible.Color.ink2)
                if let n, n > 0 {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Crucible.Color.accentInk.opacity(0.9) : Crucible.Color.ink3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            selected ? Color.white.opacity(0.28) : Crucible.Color.sunk,
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, showsCounts ? 13 : 20)
            .frame(minHeight: 32)
            .background(
                selected ? Crucible.Color.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(n.map { "\(label(opt)), \($0)" } ?? label(opt))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Home top bar (unified across every tab)

/// The canonical top bar per `docs/design/screens-home.jsx` §HomeTopBar:
/// HiMem wordmark + tier mark on the left, search + ? + settings on
/// the right. Identical shape and glyphs across Clips / Memories /
/// Projects. Wired locally in each tab so any tab can reach the
/// destinations without routing through Memories.
struct HomeTopBar: View {
    let onSearchTap: () -> Void
    let onSettingsTap: () -> Void
    let onHelpTap: () -> Void

    @ObservedObject private var entitlement = Entitlement.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("HiMem")
                    .font(.caption2.bold())
                    .tracking(2.0)
                    .foregroundStyle(Crucible.Color.ink3)
                TierMark(isPlus: entitlement.isPlus, size: 10)
            }
            Spacer()
            HStack(spacing: 12) {
                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                }
                .accessibilityLabel("Search")

                // The `?` opens the Learn hub. Warm ink, never blue —
                // "Learn, not Help" per Kingfisher · North Star.
                Button(action: onHelpTap) {
                    Image(systemName: "questionmark.circle")
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                }
                .accessibilityLabel("Learn")

                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(Crucible.Color.ink)
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Header

/// Unified home top bar + Clips filter chips per
/// `docs/design/screens-home.jsx` §HomeTopBar and §ContextRow.
///
/// The top bar is identical across every tab (Clips / Memories /
/// Projects) — HiMem wordmark on the left, search + ? + settings on
/// the right. Object switching lives in the bottom TabBar. The old
/// serif "Clips" title on this surface was retired 2026-07-10 when
/// the three-tab home model unified.
///
/// Locked July 12 2026 (`CLAUDE.md` §Phone + `HiMem · the shaping
/// model.md`): two independent axes, **never** one control mixing them.
/// The status axis (New ⟷ All) is an ochre two-state toggle — the
/// primary lens. The type axis (All / Voice / Photos / Video / Notes)
/// is a neutral chip row — the secondary refinement.
struct ClipsHeader: View {
    @Binding var status: ClipsStatus
    @Binding var type: ClipsType
    let onSearchTap: () -> Void
    let onSettingsTap: () -> Void
    let onHelpTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeTopBar(
                onSearchTap: onSearchTap,
                onSettingsTap: onSettingsTap,
                onHelpTap: onHelpTap
            )
            statusToggle
            typeChipRow
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Chip order **All · New · Unconnected** (Tom, 2026-07-19) — the
    /// wider view first, `New` the default triage subset, `Unconnected`
    /// the cleanup lens on the right. Independent of the `ClipsStatus`
    /// enum declaration order.
    private static let statusOrder: [ClipsStatus] = [.all, .new, .unconnected]

    private var statusToggle: some View {
        HiMemSegmentedControl(options: Self.statusOrder, selection: $status, label: \.label)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ClipsType.allCases) { t in
                    typeChip(for: t)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func typeChip(for t: ClipsType) -> some View {
        // Same ochre selection language as the status toggle above
        // (Tom, 2026-07-12): accent fill + accentInk text + bold
        // weight when selected; ink2 text with a hairline outline
        // otherwise. The chip row has no wash1 track container (the
        // status toggle's track marks it as the primary two-state
        // control), but the button styling itself matches.
        let selected = type == t
        return Button {
            type = t
        } label: {
            Text(t.label)
                .font(.system(size: 13.5, weight: selected ? .bold : .medium))
                .tracking(-0.1)
                .foregroundStyle(selected ? Crucible.Color.accentInk : Crucible.Color.ink2)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(
                    selected ? Crucible.Color.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.clear : Crucible.Color.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(t.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Day header

struct DayHeader: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }
}

// MARK: - List item model + grouping

/// One row on the Clips flat list — either a single clip or a burst
/// of contiguous same-minute + same-place photos/videos.
enum ClipsListItem: Identifiable {
    case single(MediaReference)
    case burst([MediaReference])

    var id: String {
        switch self {
        case .single(let ref):
            return "single-\(ref.id.uuidString)"
        case .burst(let refs):
            return "burst-\(refs.first?.id.uuidString ?? UUID().uuidString)"
        }
    }

    /// The selectable clip ids this row represents. A burst selects as a
    /// unit (like a session batch-select), so its circle toggles every ref.
    var refIds: [UUID] {
        switch self {
        case .single(let ref): return [ref.id]
        case .burst(let refs):  return refs.map(\.id)
        }
    }

    /// Whether the carat expands the row in place (single-open accordion,
    /// July 22 2026). A **single voice/note** expands to its full
    /// transcript; a **media burst** expands to its N clips. A single
    /// photo/video has no transcript to reveal in place — its ✎ opens the
    /// modal directly.
    var isExpandable: Bool {
        switch self {
        case .burst: return true
        case .single(let ref): return ref.mediaTypeEnum == .voice || ref.mediaTypeEnum == .note
        }
    }

    /// Whether the collapsed row carries a top-level ✎ that edits one
    /// clip. A **burst never does** — editing a burst is per-clip inside
    /// the expanded accordion, never a silent clip-1 (the July 22 bug: a
    /// session-level ✎ deterministically opened `refs.first`). A single
    /// clip's ✎ edits that clip directly.
    var hasTopLevelEdit: Bool {
        switch self {
        case .burst:  return false
        case .single: return true
        }
    }

    /// Walks refs (assumed sorted newest-first) and coalesces
    /// contiguous photo/video runs whose adjacent captures land within
    /// 60 seconds of one another **and** share a placeName. Voice
    /// and note refs are never bursted — they always emit as `.single`.
    ///
    /// The "same-minute" rule is the July 9 spec: a photo-heavy day
    /// (e.g. dinner at Culinary Institute) shouldn't wall the list
    /// with dozens of identical "Photo" rows.
    static func group(refs: [MediaReference]) -> [ClipsListItem] {
        var out: [ClipsListItem] = []
        var run: [MediaReference] = []
        func flush() {
            if run.count >= 2 {
                out.append(.burst(run))
            } else if let solo = run.first {
                out.append(.single(solo))
            }
            run.removeAll()
        }
        for ref in refs {
            let isMedia = ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video
            if isMedia, let last = run.last, sameBurst(last, ref) {
                run.append(ref)
            } else {
                flush()
                if isMedia {
                    run = [ref]
                } else {
                    out.append(.single(ref))
                }
            }
        }
        flush()
        return out
    }

    private static func sameBurst(_ a: MediaReference, _ b: MediaReference) -> Bool {
        guard let ta = a.createdAt, let tb = b.createdAt else { return false }
        let gap = abs(tb.timeIntervalSince(ta))
        guard gap <= 60 else { return false }
        let placeA = (a.placeName ?? "").trimmingCharacters(in: .whitespaces)
        let placeB = (b.placeName ?? "").trimmingCharacters(in: .whitespaces)
        return placeA == placeB
    }
}

extension MediaReference {
    /// Adapts a bench clip to the `MediaDisplayItem` the shared
    /// Memory-Detail cards (`CompactClipRow` / `MediaCard`) consume, so
    /// the bench renders through the exact same components — one clip
    /// pattern, no drift (convergence 2026-07-22).
    var displayItem: MediaDisplayItem {
        MediaDisplayItem(
            id: id,
            localIdentifier: osIdentifier,
            mediaType: mediaTypeEnum,
            thumbnailCacheFilename: thumbnailCacheFilename,
            isAccessible: isAccessible,
            transcript: transcript,
            text: text,
            mediaDescription: mediaDescription,
            createdAt: createdAt ?? .distantPast,
            placeName: placeName,
            referencingMemoryCount: referencingMemoryCount
        )
    }
}

// MARK: - Row dispatch

/// Dispatches a `ClipsListItem` to the right row component. Wrapped in
/// a NavigationLink so the parent's `navigationDestination(for: UUID)`
/// pushes ClipDetailView on tap.
struct ClipsListItemRow: View {
    let item: ClipsListItem
    /// The boxed ✎ Edit opens the unified `ClipEditorModal`. It lives
    /// INSIDE the shared card (`CompactClipRow` / `MediaCard`), never
    /// floating outside — and a burst carries no top-level ✎ (each
    /// per-clip card has its own).
    let onOpen: (MediaReference) -> Void
    /// P7-4 multi-select. Non-nil = this list supports selecting; the
    /// leading circle appears (and the whole row toggles) only in mode.
    @ObservedObject var selection: ClipsSelection
    /// Single-open accordion state, owned by the list container.
    var isExpanded: Bool = false
    var onToggleExpand: () -> Void = {}

    // Consume surfaces, presented per-row (only the tapped row fires).
    @State private var photoViewerItem: MediaDisplayItem? = nil
    @State private var videoViewerItem: MediaDisplayItem? = nil
    @ObservedObject private var audioPlayer = AudioPlayerService.shared

    var body: some View {
        Group {
            if selection.selecting {
                // Selecting mode keeps the dense compact rows — the whole
                // row is one toggle target; the ✎ stands down (Photos-style).
                Button { selection.toggleAll(item.refIds) } label: {
                    HStack(spacing: 10) {
                        DragSelectCircle(checked: selection.isChecked(all: item.refIds), selection: selection)
                        selectingCore.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .reportsClipRowFrame(item.refIds, enabled: true)
            } else {
                convergedCard
            }
        }
        .fullScreenCover(item: $photoViewerItem) { PhotoViewerSheet(item: $0) }
        .fullScreenCover(item: $videoViewerItem) { VideoPlayerSheet(item: $0) }
    }

    /// The bench clip rendered through the SAME Memory-Detail cards — so
    /// the user reads them as one object (convergence 2026-07-22):
    /// voice/note → `CompactClipRow` (compact collapse → transcript
    /// in-envelope, ✎ inside); photo/video → `MediaCard` (banner + PHOTO
    /// badge, ✎ inside); a burst stays a dense strip that expands to its
    /// clips as per-clip `MediaCard`s.
    @ViewBuilder private var convergedCard: some View {
        switch item {
        case .single(let ref):
            switch ref.mediaTypeEnum {
            case .voice, .note:
                CompactClipRow(
                    item: ref.displayItem,
                    isOpen: isExpanded,
                    onTap: { toggle() },
                    onPlay: ref.mediaTypeEnum == .voice ? { playAudio(ref) } : nil,
                    onDelete: {},   // never rendered: onEdit routes edit/delete to the modal
                    onEdit: { onOpen(ref) },
                    isPlaying: isPlaying(ref)
                )
            case .image, .video:
                mediaCard(ref)
            }
        case .burst(let refs):
            burstCard(refs)
        }
    }

    private func mediaCard(_ ref: MediaReference) -> some View {
        MediaCard(
            item: ref.displayItem,
            onPlayVideo: ref.mediaTypeEnum == .video ? { videoViewerItem = ref.displayItem } : nil,
            onViewPhoto: ref.mediaTypeEnum == .image ? { photoViewerItem = ref.displayItem } : nil,
            onEdit: { onOpen(ref) }
        )
    }

    /// A media burst: a dense strip that expands (carat / card-body tap) to
    /// its clips as full per-clip `MediaCard`s, each with its own ✎. The
    /// collapsed strip is the one place the bench stays denser than Memory
    /// Detail — a 12-photo day must not open as 12 banners.
    @ViewBuilder private func burstCard(_ refs: [MediaReference]) -> some View {
        VStack(spacing: 8) {
            Button { toggle() } label: {
                BurstRow(refs: refs, isExpanded: isExpanded)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                ForEach(refs, id: \.id) { ref in
                    mediaCard(ref)
                }
            }
        }
    }

    /// Dense rows used only in selecting mode (multi-select density).
    @ViewBuilder private var selectingCore: some View {
        switch item {
        case .single(let ref):
            if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
                MediaClipRow(ref: ref)
            } else {
                LooseClipRow(ref: ref)
            }
        case .burst(let refs):
            BurstRow(refs: refs)
        }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.22)) { onToggleExpand() }
    }

    private func isPlaying(_ ref: MediaReference) -> Bool {
        audioPlayer.isPlaying && audioPlayer.currentFile == ref.osIdentifier
    }

    private func playAudio(_ ref: MediaReference) {
        if isPlaying(ref) { audioPlayer.stop() }
        else { audioPlayer.play(filename: ref.osIdentifier) }
    }
}

/// The Photos-style selection circle (mock, July 2026): 22px, hairline
/// ink4 ring at rest → accent fill + white check when selected. Shared by
/// every selectable row/session on the Clips tab.
struct SelectCircle: View {
    let checked: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(checked ? Crucible.Color.accent : Color.clear)
            Circle()
                .strokeBorder(checked ? Crucible.Color.accent : Crucible.Color.ink4, lineWidth: 2)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(checked ? "Selected" : "Not selected")
    }
}

// MARK: - LooseClipRow (voice / note)

/// Voice- and note-type row per `screens-clips-page.jsx` §LooseClipRow.
/// Text-first: transcript / note body preview + wash-tinted icon tile.
/// Placed clips add the "In: [memory chips]" row per §PlacedClipRow.
struct LooseClipRow: View {
    @ObservedObject var ref: MediaReference

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                metaLine
                previewLine
                if ref.referencingMemoryCount > 0 {
                    ReferencedInLine(ref: ref)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        // Tap-anywhere-on-the-card (Tom, 2026-07-12): the
        // parent `NavigationLink` label without an explicit
        // hit-testable shape only registers taps on rendered
        // content — `Spacer(minLength: 0)` and the padding regions
        // silently dropped taps, so the user reported having to
        // aim for the media glyph. Making the whole rounded card
        // a hit target routes every tap to the NavigationLink.
        .contentShape(RoundedRectangle(cornerRadius: 13))
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Crucible.Color.hairline.opacity(0.3))
                .frame(width: 30, height: 30)
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Crucible.Color.ink3)
        }
    }

    /// Canonical media glyphs — matches
    /// `EntryCardView.MediaGlyphRow` on the memory-card side.
    /// Sync 2026-07-11 per Tom's ask "these are all supposed to
    /// be identical."
    private var iconName: String {
        switch ref.mediaTypeEnum {
        case .voice: return "waveform"
        case .note:  return "text.alignleft"
        default:     return "questionmark"
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(clipTimeString(ref))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Crucible.Color.ink2)
            if let place = ref.placeName, !place.isEmpty {
                Text("·").foregroundStyle(Crucible.Color.ink4)
                Text(place)
                    .lineLimit(1)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var previewLine: some View {
        Text(previewText)
            .font(.system(size: 13.5))
            .foregroundStyle(Crucible.Color.ink2)
            .lineSpacing(2)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewText: String {
        switch ref.mediaTypeEnum {
        case .voice:
            let t = ref.transcript ?? ""
            return t.isEmpty ? "Voice clip" : "\u{201C}\(t)\u{201D}"
        case .note:
            let t = ref.text ?? ""
            return t.isEmpty ? "Note" : t
        default:
            return ""
        }
    }
}

// MARK: - MediaClipRow (single photo / video)

/// Single photo/video row per `screens-clips-page.jsx` §MediaClipRow.
/// 46×46 real thumbnail (loaded via `ThumbnailService`), Photo/Video
/// label + time · place. When placed, adds the referenced-in chip
/// row below the meta.
struct MediaClipRow: View {
    @ObservedObject var ref: MediaReference
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 11) {
            thumbnailView
            VStack(alignment: .leading, spacing: 1) {
                Text(ref.mediaTypeEnum == .video ? "Video" : "Photo")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Crucible.Color.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineLimit(1)
                if ref.referencingMemoryCount > 0 {
                    ReferencedInLine(ref: ref)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        // See LooseClipRow — same tap-anywhere-on-the-card fix.
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .task(id: ref.id) {
            if thumbnail == nil {
                if let name = await ThumbnailService.shared.cacheThumbnail(
                    for: ref.osIdentifier,
                    mediaType: ref.mediaTypeEnum
                ) {
                    thumbnail = ThumbnailService.shared.cachedThumbnail(filename: name)
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .center) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Crucible.Color.hairline.opacity(0.3))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: ref.mediaTypeEnum == .video ? "video" : "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(Crucible.Color.ink4)
                    }
            }
            if ref.mediaTypeEnum == .video {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.black)
                    }
            }
        }
    }

    private var subtitle: String {
        let t = clipTimeString(ref)
        if let place = ref.placeName, !place.isEmpty {
            return "\(t) · \(place)"
        }
        return t
    }
}

// MARK: - BurstRow (contiguous photos/videos)

/// A same-minute burst of photos/videos rendered as ONE row per
/// `screens-clips-page.jsx` §BurstRow. Meta line + thumbnail strip
/// (5 max) + "+N" overflow chip. The July 9 spec update — solves
/// the "wall of identical Photo rows" dogfood failure.
struct BurstRow: View {
    let refs: [MediaReference]
    /// Non-nil in the accordion (a media burst that expands to its clips):
    /// renders an in-card rotating carat. Nil in selecting mode (no carat).
    var isExpanded: Bool? = nil
    @State private var thumbnails: [UUID: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            metaLine
            thumbnailStrip
            if let anchor = refs.first, anchor.referencingMemoryCount > 0 {
                ReferencedInLine(ref: anchor)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Crucible.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Crucible.Color.hairline, lineWidth: 1)
        )
        // See LooseClipRow — same tap-anywhere-on-the-card fix.
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .task(id: refs.map(\.id)) {
            // Slice 6: batch-fetch through `BurstThumbnailPrefetcher`
            // with bounded concurrency (default 3). Retires the
            // R2-flagged storm where a 12-photo burst fired 12
            // parallel `ThumbnailService.cacheThumbnail` calls at
            // once — see `docs/architecture/2026-07-11-clip-model-
            // convergence-plan.md` § Q4a.
            let inputs = refs.prefix(5)
                .filter { thumbnails[$0.id] == nil }
                .map {
                    BurstThumbnailPrefetcher.PrefetchInput(
                        id: $0.id,
                        thumbnailKey: ClipDisplayModel.ThumbnailKey(
                            osIdentifier: $0.osIdentifier,
                            mediaType: $0.mediaTypeEnum
                        )
                    )
                }
            let loaded = await BurstThumbnailPrefetcher.prefetch(keys: inputs)
            for (id, image) in loaded {
                thumbnails[id] = image
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(anchorTime)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Crucible.Color.ink2)
            Text("·").foregroundStyle(Crucible.Color.ink4)
            Text(countText)
                .font(.system(size: 11.5))
                .foregroundStyle(Crucible.Color.ink3)
            if let place = refs.first?.placeName, !place.isEmpty {
                Text("·").foregroundStyle(Crucible.Color.ink4)
                Text(place)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Crucible.Color.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Crucible.Color.ink3)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            }
        }
    }

    private var thumbnailStrip: some View {
        HStack(spacing: 6) {
            ForEach(refs.prefix(5)) { ref in
                thumbnailTile(ref)
            }
            if refs.count > 5 {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Crucible.Color.hairline.opacity(0.35))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Text("+\(refs.count - 5)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Crucible.Color.ink3)
                    }
            }
        }
    }

    @ViewBuilder
    private func thumbnailTile(_ ref: MediaReference) -> some View {
        ZStack(alignment: .center) {
            if let image = thumbnails[ref.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Crucible.Color.hairline.opacity(0.3))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: ref.mediaTypeEnum == .video ? "video" : "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(Crucible.Color.ink4)
                    }
            }
            if ref.mediaTypeEnum == .video {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.black)
                    }
            }
        }
    }

    private var anchorTime: String {
        guard let ref = refs.first else { return "" }
        return clipTimeString(ref)
    }

    private var countText: String {
        let hasVideo = refs.contains { $0.mediaTypeEnum == .video }
        let hasImage = refs.contains { $0.mediaTypeEnum == .image }
        let noun: String
        if hasVideo && !hasImage {
            noun = refs.count == 1 ? "clip" : "clips"
        } else if hasImage && !hasVideo {
            noun = refs.count == 1 ? "photo" : "photos"
        } else {
            noun = "items"
        }
        return "\(refs.count) \(noun)"
    }
}

// MARK: - Referenced-in chip row (shared by all placed rows)

/// "IN CIA Dinner · Leadership" chip row per §PlacedClipRow in the JSX.
/// Wash-tinted chips (not topic-colored) — the topic identity belongs
/// to the memory row, not this reference.
struct ReferencedInLine: View {
    @ObservedObject var ref: MediaReference

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Text("In")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Crucible.Color.ink4)
            ForEach(memoryTitles.prefix(3), id: \.self) { title in
                Text(title)
                    .font(.system(size: 11.5))
                    .tracking(-0.05)
                    .foregroundStyle(Crucible.Color.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Crucible.Color.hairline.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if memoryTitles.count > 3 {
                Text("+\(memoryTitles.count - 3)")
                    .font(.system(size: 11))
                    .foregroundStyle(Crucible.Color.ink3)
            }
        }
    }

    private var memoryTitles: [String] {
        // Single canonical resolver (2026-07-26) — see ExistingMemoryPickerView
        // .rowTitle. Never the "Untitled memory" placeholder.
        ref.referencingMemoriesSortedByLinkedAtDesc.map(\.displayTitle)
    }
}

// MARK: - Time helpers

/// Shared "h:mm a" time formatter — used by every clip row so the
/// meta line reads coherently across bursts, singles, and looses.
private let clipTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f
}()

func clipTimeString(_ ref: MediaReference) -> String {
    guard let date = ref.createdAt else { return "" }
    return clipTimeFormatter.string(from: date)
}

// MARK: - Flat clip list

/// Renders a filter view (All / Voice / Photos / Notes) as a flat,
/// day-grouped clip list with burst-of-media collapse and real
/// thumbnails.
struct FlatClipsListView: View {
    /// The type axis (voice / photos / video / notes / all). `.photos`
    /// narrows to images ONLY here — the old shape lumped video into
    /// photos (invisibly), which retired July 12 2026 when Video
    /// became a first-class filter.
    let type: ClipsType
    /// The status connection lens (P7, July 19 2026): `.any` = everything
    /// (All), `.unconnected` = `connectionCount == 0` (Unconnected, the
    /// cleanup lens). Independent of the type axis.
    var connection: ConnectionLens = .any
    /// P7-4 multi-select (shared across filters).
    @ObservedObject var selection: ClipsSelection
    /// Opens the unified `ClipEditorModal` (threaded from `ClipsTabView`).
    let onOpen: (MediaReference) -> Void

    enum ConnectionLens { case any, unconnected }
    @Environment(\.managedObjectContext) private var context
    @State private var groups: [(day: Date, refs: [MediaReference])] = []
    /// Same debounce as `ClipsTabView.unplacedReload` — coalesces
    /// CloudKit-import notification bursts into a single main-thread
    /// fetch. See `DebouncedTrigger`.
    @State private var groupsReload = DebouncedTrigger(interval: .milliseconds(250))
    /// Single-open accordion: at most one flat row expanded at a time.
    @State private var expandedItemId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.day) { group in
                DayHeader(date: group.day)
                VStack(spacing: 8) {
                    ForEach(ClipsListItem.group(refs: group.refs)) { item in
                        ClipsListItemRow(
                            item: item,
                            onOpen: onOpen,
                            selection: selection,
                            isExpanded: expandedItemId == item.id,
                            onToggleExpand: {
                                expandedItemId = (expandedItemId == item.id) ? nil : item.id
                            }
                        )
                    }
                }
            }
            if groups.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, 20)
            }
        }
        .onAppear { reload() }
        .onDisappear { groupsReload.cancel() }
        .onChange(of: type) { _, _ in reload() }
        .onChange(of: connection) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            groupsReload.fire { reload() }
        }
    }

    private var emptyMessage: String {
        switch type {
        case .all:    return "No clips yet."
        case .voice:  return "No voice clips yet."
        case .photos: return "No photos yet."
        case .video:  return "No videos yet."
        case .notes:  return "No notes yet."
        }
    }

    private func reload() {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        var subpredicates: [NSPredicate] = []
        switch type {
        case .voice:
            subpredicates.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.voice.rawValue))
        case .photos:
            // Split from Video (July 12 2026 lock). `.photos` = images
            // only here; videos have their own case.
            subpredicates.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.image.rawValue))
        case .video:
            subpredicates.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.video.rawValue))
        case .notes:
            subpredicates.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.note.rawValue))
        case .all:
            break
        }
        // Unconnected lens: no edge to a LIVE memory. An edge to a recycled
        // memory is preserved but doesn't count as a connection, so a clip
        // whose only memory is trashed surfaces here (TestFlight #4a) instead
        // of stranding in All. (The New-view unplaced stack still uses raw
        // `edges.@count == 0` — "never placed" ≠ "no live connection".)
        if connection == .unconnected {
            subpredicates.append(MediaReference.noLiveMemoryConnectionPredicate)
        }
        // P8: recycled clips (Recently Deleted) never show on any Clips lens.
        subpredicates.append(NSPredicate(format: "recycledAt == nil"))
        req.predicate = subpredicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let refs = (try? context.fetch(req)) ?? []
        let cal = Calendar.current
        let grouped = Dictionary(grouping: refs) { ref in
            cal.startOfDay(for: ref.createdAt ?? .distantPast)
        }
        groups = grouped.map { (day: $0.key, refs: $0.value) }
            .sorted { $0.day > $1.day }
        // Register the visible id set for Select-all / drag (P7-4).
        selection.registerVisible(groups.flatMap { $0.refs.map(\.id) }, source: "flat")
    }
}

// MARK: - Unconnected (unified clip list)

/// One row in the Unconnected list. Carries its backing so the row can
/// both render (`ClipDisplayModel`) and open (`ClipEditorModal.Source`),
/// spanning the two backing types (P7-3, July 19 2026).
private struct UnconnectedItem: Identifiable {
    let id: UUID
    let model: ClipDisplayModel
    let source: ClipEditorModal.Source
    let capturedAt: Date
}

/// The Unconnected filter as a **unified list across backing types** —
/// unpromoted `InboxClip`s (watch/phone, source glyph per row) + detached /
/// loose `MediaReference`s (`edges == 0`). One reverse-chron list.
///
/// Read-only enabling slice: the multi-select (Delete / Add to a memory)
/// and the "was in a memory · now unconnected" line (needs a per-device
/// everConnected marker — no `everConnected` signal exists today) are the
/// following slices per the July 19 sequencing.
struct UnconnectedListView: View {
    let type: ClipsType
    let onOpen: (ClipEditorModal.Source) -> Void
    @ObservedObject var selection: ClipsSelection
    @ObservedObject var inbox: InboxManifest = .shared
    @Environment(\.managedObjectContext) private var context
    @State private var looseRefs: [MediaReference] = []
    @State private var refsReload = DebouncedTrigger(interval: .milliseconds(250))

    var body: some View {
        let items = buildItems()
        return VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Crucible.Color.ink3)
                    .padding(.top, 20)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        if selection.selecting {
                            // Selecting mode: whole row toggles; ✎ stands down.
                            Button { selection.toggle(item.id) } label: {
                                HStack(spacing: 10) {
                                    DragSelectCircle(checked: selection.selectedIds.contains(item.id), selection: selection)
                                    ClipAtomView(model: item.model, register: .operational, isDenseContainer: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .reportsClipRowFrame([item.id], enabled: true)
                        } else {
                            HStack(spacing: 10) {
                                ClipAtomView(model: item.model, register: .operational, isDenseContainer: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ClipEditButton(action: { onOpen(item.source) })
                            }
                        }
                        // Honest provenance on a previously-shaped clip (P7-3).
                        if wasInAMemory(item) {
                            Text("Was in a memory · now unconnected")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Crucible.Color.ink4)
                                .padding(.leading, selection.selecting ? 32 : 0)
                        }
                    }
                }
            }
        }
        .onAppear { reloadRefs(); registerVisibleIds() }
        .onDisappear { refsReload.cancel() }
        .onChange(of: type) { _, _ in reloadRefs() }
        .onChange(of: looseRefs) { _, _ in registerVisibleIds() }
        .onChange(of: inbox.clips) { _, _ in registerVisibleIds() }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            refsReload.fire { reloadRefs() }
        }
    }

    /// Publishes the current visible id set for Select-all / drag (P7-4).
    /// Kept out of `body` (mutating shared published state during a render
    /// pass would loop); driven by the data-change hooks instead.
    private func registerVisibleIds() {
        selection.registerVisible(buildItems().map(\.id), source: "flat")
    }

    /// True for a MediaReference that was previously attached to a memory
    /// (P7-3) — drives the "was in a memory · now unconnected" line.
    /// InboxClips are never previously-connected.
    private func wasInAMemory(_ item: UnconnectedItem) -> Bool {
        if case .managed(let ref) = item.source {
            return PreviouslyConnectedStore.wasConnected(ref.id)
        }
        return false
    }

    private var emptyMessage: String {
        switch type {
        case .all:    return "Nothing unconnected — every clip is in a memory."
        case .voice:  return "No unconnected voice clips."
        case .photos: return "No unconnected photos."
        case .video:  return "No unconnected videos."
        case .notes:  return "No unconnected notes."
        }
    }

    private func buildItems() -> [UnconnectedItem] {
        var items: [UnconnectedItem] = []
        // Unpromoted inbox clips are always unconnected (they have no edges
        // until promoted) and are voice (the Watch is audio-only; phone
        // bench captures land as MediaReferences). Include under All / Voice.
        if type == .all || type == .voice {
            for clip in inbox.clips where clip.status != .disposed {
                items.append(UnconnectedItem(
                    id: clip.clipId,
                    model: ClipDisplayModel(inboxClip: clip, sessionStart: nil),
                    source: .inbox(clip),
                    capturedAt: clip.capturedAt
                ))
            }
        }
        for ref in looseRefs {
            items.append(UnconnectedItem(
                id: ref.id,
                model: ClipDisplayModel(mediaReference: ref),
                source: .managed(ref),
                capturedAt: ref.createdAt ?? .distantPast
            ))
        }
        return items.sorted { $0.capturedAt > $1.capturedAt }
    }

    private func reloadRefs() {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        // P8: exclude recycled clips from the Unconnected list.
        var subs: [NSPredicate] = [
            NSPredicate(format: "edges.@count == 0"),
            NSPredicate(format: "recycledAt == nil"),
        ]
        switch type {
        case .voice:  subs.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.voice.rawValue))
        case .photos: subs.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.image.rawValue))
        case .video:  subs.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.video.rawValue))
        case .notes:  subs.append(NSPredicate(format: "mediaType == %@", MediaReference.MediaType.note.rawValue))
        case .all:    break
        }
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subs)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        looseRefs = (try? context.fetch(req)) ?? []
    }
}

/// Multi-select state for the Clips tab — a **general clips-list
/// capability** across every status filter (New · All · Unconnected),
/// not Unconnected-only (P7-4, July 2026). Held at the ClipsTabView level
/// so the top bar (Cancel · N selected · Select all) and the bottom
/// action bar (Add to a memory… · Delete N) pin to the screen while the
/// per-filter content views (`SessionListView`, `FlatClipsListView`,
/// `UnconnectedListView`) render the row/session select circles.
///
/// The model is **clip-level**: `selectedIds` holds individual clip ids
/// (InboxClip.clipId or MediaReference.id). A *session* is a derived
/// checkbox — checked iff all its clip ids are selected — so toggling a
/// session simply adds/removes its clip ids. That keeps Delete / Add
/// (which already partition by backing) working unchanged.
///
/// `selecting` is the Photos-style **mode** (mock, July 2026): at rest a
/// quiet "Select" enters it; the circles and bars appear only in mode.
@MainActor
final class ClipsSelection: ObservableObject {
    /// Shared so the tab shell (`HiMemTabView`) can read `selecting` to
    /// step the capture FAB aside while multi-select owns the bottom bar,
    /// without threading a binding through the TabView.
    static let shared = ClipsSelection()

    @Published var selecting = false
    @Published var selectedIds: Set<UUID> = []
    /// De-duplicated visible selectable ids in the active filter, merged
    /// across the sources that contribute to one filter (New = session
    /// clips + the unplaced stack). Drives Select-all. Registered per
    /// source and merged so two content views don't clobber each other.
    @Published private(set) var visibleIds: [UUID] = []
    private var visibleBySource: [String: [UUID]] = [:]

    func enter() { selecting = true }
    /// Leaves the mode and drops the selection (Cancel, or a filter change).
    func exit() {
        selecting = false
        selectedIds.removeAll()
    }
    func toggle(_ id: UUID) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    /// Explicit set — used by drag-to-select, which paints a target state
    /// across a run rather than toggling each row independently.
    func set(_ id: UUID, selected: Bool) {
        if selected { selectedIds.insert(id) } else { selectedIds.remove(id) }
    }
    /// Session-level toggle: a session is "checked" iff every clip is
    /// selected, so toggling flips the whole set together.
    func toggleAll(_ ids: [UUID]) {
        if ids.allSatisfy({ selectedIds.contains($0) }) {
            ids.forEach { selectedIds.remove($0) }
        } else {
            ids.forEach { selectedIds.insert($0) }
        }
    }
    func isChecked(all ids: [UUID]) -> Bool {
        !ids.isEmpty && ids.allSatisfy { selectedIds.contains($0) }
    }
    func selectAll() { selectedIds = Set(visibleIds) }
    /// Registers one source's visible ids and re-merges. Sources: "flat"
    /// (All / Unconnected), "sessions" + "unplaced" (New).
    func registerVisible(_ ids: [UUID], source: String) {
        visibleBySource[source] = ids
        var seen = Set<UUID>(); var out: [UUID] = []
        for group in visibleBySource.values {
            for id in group where !seen.contains(id) { seen.insert(id); out.append(id) }
        }
        visibleIds = out
    }
    /// Clears the visible registry — called on a filter switch so a stale
    /// source's ids can't leak into the next filter's Select-all.
    func resetVisible() {
        visibleBySource.removeAll()
        visibleIds = []
    }
    func clear() { selectedIds.removeAll() }
    var count: Int { selectedIds.count }

    // MARK: Drag-to-select (P7-4)
    //
    // The gesture lives on each select circle, so a drag that BEGINS on a
    // circle paints a run without fighting the scroll view (scrolls start
    // elsewhere). Row spans are registered by the container's
    // onPreferenceChange; the gesture hit-tests them by y.

    /// Row y-spans in the shared drag coordinate space (id-set + minY/maxY).
    /// Plain (non-published): only the drag reads it, and it's refreshed
    /// from layout, so publishing would just churn renders.
    var rowFrames: [ClipRowFrame] = []
    /// The state being painted across the run (nil = no drag in progress).
    /// The first row hit sets it to the opposite of its current state.
    private var dragPaint: Bool? = nil
    private var lastDragY: CGFloat = 0

    func dragChanged(to y: CGFloat) {
        guard selecting else { return }
        if dragPaint == nil {
            guard let row = rowFrames.first(where: { y >= $0.minY && y <= $0.maxY }) else { return }
            let paint = !isChecked(all: row.ids)
            dragPaint = paint
            row.ids.forEach { set($0, selected: paint) }
            lastDragY = y
        } else {
            guard let paint = dragPaint else { return }
            let lo = min(lastDragY, y), hi = max(lastDragY, y)
            for row in rowFrames where row.maxY >= lo && row.minY <= hi {
                row.ids.forEach { set($0, selected: paint) }
            }
            lastDragY = y
        }
    }
    func dragEnded() { dragPaint = nil }
}

/// The coordinate space the drag-to-select frame registry resolves in.
enum ClipsSelectionSpace { static let name = "clipsSelect" }

/// One selectable row's vertical span in the drag coordinate space.
struct ClipRowFrame: Equatable {
    let ids: [UUID]
    let minY: CGFloat
    let maxY: CGFloat
}

struct ClipRowFramesKey: PreferenceKey {
    static var defaultValue: [ClipRowFrame] = []
    static func reduce(value: inout [ClipRowFrame], nextValue: () -> [ClipRowFrame]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Reports a selectable row's y-span so drag-to-select can hit-test it.
    /// No-op when not selecting (avoids preference churn at rest).
    @ViewBuilder
    func reportsClipRowFrame(_ ids: [UUID], enabled: Bool) -> some View {
        if enabled {
            background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ClipRowFramesKey.self,
                        value: [ClipRowFrame(
                            ids: ids,
                            minY: geo.frame(in: .named(ClipsSelectionSpace.name)).minY,
                            maxY: geo.frame(in: .named(ClipsSelectionSpace.name)).maxY
                        )]
                    )
                }
            )
        } else {
            self
        }
    }
}

/// A `SelectCircle` that also carries the drag-to-select gesture. Because
/// the gesture originates on the small circle, a drag here reliably means
/// "paint a selection run" rather than "scroll" (P7-4).
struct DragSelectCircle: View {
    let checked: Bool
    @ObservedObject var selection: ClipsSelection
    var body: some View {
        SelectCircle(checked: checked)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(ClipsSelectionSpace.name))
                    .onChanged { selection.dragChanged(to: $0.location.y) }
                    .onEnded { _ in selection.dragEnded() }
            )
    }
}

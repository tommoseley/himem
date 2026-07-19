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
    @StateObject private var unconnectedSelection = UnconnectedSelection()
    /// "Delete N clips?" confirm — clips have no Recently Deleted yet, so
    /// batch delete is permanent; the confirm is the interim net.
    @State private var showUnconnectedDeleteConfirm = false
    /// Carries the selected clips into the "Add to a memory" create flow.
    @State private var unconnectedBundle: SessionListView.BundleRequest? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ClipsHeader(
                            status: $status,
                            type: $type,
                            onSearchTap: { showSearch = true },
                            onSettingsTap: { showSettings = true },
                            onHelpTap: { showTutorials = true }
                        )
                        content
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 12)
                    }
                }
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
                if status == .unconnected && !unconnectedSelection.selectedIds.isEmpty {
                    unconnectedActionBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: unconnectedSelection.selectedIds.isEmpty)
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
            .sheet(item: $unconnectedBundle) { request in
                CreateMemoryFromClipsSheet(
                    clips: request.clipsToBundle,
                    session: request.session,
                    absorbedMediaRefs: request.absorbedMediaRefs,
                    prefillTitle: request.prefillTitle,
                    viewModel: viewModel
                )
            }
            .onChange(of: status) { _, newStatus in
                // Leaving Unconnected drops the multi-select.
                if newStatus != .unconnected { unconnectedSelection.clear() }
            }
            .alert("Delete \(unconnectedSelection.selectedIds.count) clips?", isPresented: $showUnconnectedDeleteConfirm) {
                Button("Delete", role: .destructive) { performUnconnectedDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                // Clips have no Recently Deleted yet — batch delete is
                // permanent, so the copy is honest (distinct from the
                // memory/project soft-delete language).
                Text("This can't be undone. The clips and their transcripts are deleted.")
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

    // MARK: - Unconnected multi-select cleanup (P7-3)

    /// Pinned action bar for the Unconnected selection: Add to a memory…
    /// (ochre) + Delete N (danger). Appears when ≥1 clip is selected.
    private var unconnectedActionBar: some View {
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
            Button { showUnconnectedDeleteConfirm = true } label: {
                Text("Delete \(unconnectedSelection.selectedIds.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Crucible.Color.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Crucible.Color.danger, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Crucible.Color.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
    }

    /// Deletes the selected clips, partitioned by backing: InboxClips →
    /// manifest dispose (tombstone + watch ack), MediaReferences → hard
    /// delete. Both are the established delete paths (arbiter-consistent).
    /// Permanent — gated behind the confirm alert (no clip Recently
    /// Deleted yet).
    private func performUnconnectedDelete() {
        let ids = unconnectedSelection.selectedIds
        let clipIds = InboxManifest.shared.clips.filter { ids.contains($0.clipId) }.map(\.clipId)
        let refIds = ids.subtracting(Set(clipIds))
        if !clipIds.isEmpty { InboxManifest.shared.removeBatch(clipIds: clipIds) }
        if !refIds.isEmpty {
            EntryLifecycleService(storage: .shared, processingEngine: .shared)
                .deleteMediaReferences(ids: refIds)
        }
        unconnectedSelection.clear()
    }

    /// Routes the selection into one new memory via the established
    /// create-from-clips flow: InboxClips promote (clipsToBundle), loose
    /// MediaReferences attach via createEdge (absorbedMediaRefs).
    private func startAddSelectedToMemory() {
        let ids = unconnectedSelection.selectedIds
        let inboxClips = InboxManifest.shared.clips.filter { ids.contains($0.clipId) }
        let refIds = ids.subtracting(Set(inboxClips.map(\.clipId)))
        var refs: [MediaReference] = []
        if !refIds.isEmpty {
            let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
            req.predicate = NSPredicate(format: "id IN %@", refIds)
            refs = (try? context.fetch(req)) ?? []
        }
        unconnectedBundle = SessionListView.BundleRequest(
            session: ClipGroup(clips: inboxClips),
            clipsToBundle: inboxClips,
            absorbedMediaRefs: refs
        )
        unconnectedSelection.clear()
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
            newFilterContent
        case .all:
            // All = everything (no connection or review filter).
            FlatClipsListView(type: type, connection: .any, onOpen: { editingClip = .managed($0) })
        case .unconnected:
            // Unconnected = connectionCount == 0 — the cleanup lens, as a
            // UNIFIED list across backing types (P7-3, July 19 2026):
            // unpromoted InboxClips + detached/loose MediaReferences.
            UnconnectedListView(type: type, onOpen: { editingClip = $0 }, selection: unconnectedSelection)
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
        VStack(alignment: .leading, spacing: 12) {
            SessionListView(viewModel: viewModel, hideReviewed: true)
            if !visibleUnplaced.isEmpty {
                unplacedDayGroupedStack(refs: visibleUnplaced)
            }
        }
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
                        ClipsListItemRow(item: item, onOpen: { editingClip = .managed($0) })
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadUnplaced() {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "edges.@count == 0")
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
        HStack(spacing: 2) {
            ForEach(Self.statusOrder) { s in
                statusSegment(for: s)
            }
        }
        .padding(3)
        .background(Crucible.Color.wash1, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func statusSegment(for s: ClipsStatus) -> some View {
        let selected = status == s
        return Button {
            status = s
        } label: {
            Text(s.label)
                .font(.system(size: 13.5, weight: selected ? .bold : .medium))
                .tracking(-0.1)
                .foregroundStyle(selected ? Crucible.Color.accentInk : Crucible.Color.ink2)
                .padding(.horizontal, 20)
                .frame(minHeight: 32)
                .background(
                    selected ? Crucible.Color.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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

// MARK: - Row dispatch

/// Dispatches a `ClipsListItem` to the right row component. Wrapped in
/// a NavigationLink so the parent's `navigationDestination(for: UUID)`
/// pushes ClipDetailView on tap.
struct ClipsListItemRow: View {
    let item: ClipsListItem
    /// The boxed ✎ Edit opens the unified `ClipEditorModal` (2026-07-17: ✎ Edit
    /// is the one edit affordance; the row body is non-interactive — no
    /// whole-row-to-edit).
    let onOpen: (MediaReference) -> Void

    var body: some View {
        switch item {
        case .single(let ref):
            HStack(spacing: 8) {
                Group {
                    if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
                        MediaClipRow(ref: ref)
                    } else {
                        LooseClipRow(ref: ref)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ClipEditButton(action: { onOpen(ref) })
            }
        case .burst(let refs):
            HStack(spacing: 8) {
                BurstRow(refs: refs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let first = refs.first {
                    ClipEditButton(action: { onOpen(first) })
                }
            }
        }
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink4)
                .padding(.top, 2)
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink4)
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Crucible.Color.ink4)
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
        ref.referencingMemoriesSortedByLinkedAtDesc
            .map { $0.title?.isEmpty == false ? $0.title! : "Untitled memory" }
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
    /// Opens the unified `ClipEditorModal` (threaded from `ClipsTabView`).
    let onOpen: (MediaReference) -> Void

    enum ConnectionLens { case any, unconnected }
    @Environment(\.managedObjectContext) private var context
    @State private var groups: [(day: Date, refs: [MediaReference])] = []
    /// Same debounce as `ClipsTabView.unplacedReload` — coalesces
    /// CloudKit-import notification bursts into a single main-thread
    /// fetch. See `DebouncedTrigger`.
    @State private var groupsReload = DebouncedTrigger(interval: .milliseconds(250))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.day) { group in
                DayHeader(date: group.day)
                VStack(spacing: 8) {
                    ForEach(ClipsListItem.group(refs: group.refs)) { item in
                        ClipsListItemRow(item: item, onOpen: onOpen)
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
        // Unconnected lens: zero edges (the same predicate the New-view
        // unplaced stack uses). ANDed with the type filter.
        if connection == .unconnected {
            subpredicates.append(NSPredicate(format: "edges.@count == 0"))
        }
        req.predicate = subpredicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let refs = (try? context.fetch(req)) ?? []
        let cal = Calendar.current
        let grouped = Dictionary(grouping: refs) { ref in
            cal.startOfDay(for: ref.createdAt ?? .distantPast)
        }
        groups = grouped.map { (day: $0.key, refs: $0.value) }
            .sorted { $0.day > $1.day }
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
    @ObservedObject var selection: UnconnectedSelection
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
                    HStack(spacing: 10) {
                        // Inclusion checkbox (Sort model) — tap to select for
                        // the bottom-bar Delete / Add-to-memory actions.
                        Button {
                            selection.toggle(item.id)
                        } label: {
                            Image(systemName: selection.selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selection.selectedIds.contains(item.id) ? Crucible.Color.accent : Crucible.Color.ink4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selection.selectedIds.contains(item.id) ? "Selected" : "Not selected")
                        ClipAtomView(model: item.model, register: .operational, isDenseContainer: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ClipEditButton(action: { onOpen(item.source) })
                    }
                }
            }
        }
        .onAppear { reloadRefs() }
        .onDisappear { refsReload.cancel() }
        .onChange(of: type) { _, _ in reloadRefs() }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            refsReload.fire { reloadRefs() }
        }
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
        var subs: [NSPredicate] = [NSPredicate(format: "edges.@count == 0")]
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

/// Multi-select state for the Unconnected cleanup (P7-3). Held at the
/// ClipsTabView level so the action bar can pin to the screen bottom while
/// `UnconnectedListView` (inside the scroll) drives the checkboxes.
/// Selecting is the Sort inclusion model — a checkbox per row, always
/// visible; the bar appears once ≥1 is selected.
@MainActor
final class UnconnectedSelection: ObservableObject {
    @Published var selectedIds: Set<UUID> = []
    func toggle(_ id: UUID) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }
    func clear() { selectedIds.removeAll() }
}

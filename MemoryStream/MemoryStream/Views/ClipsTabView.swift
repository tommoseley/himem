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
    @State private var filter: ClipsFilter = .new
    @State private var unplacedRefs: [MediaReference] = []
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ClipsHeader(
                        filter: $filter,
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
            .onChange(of: filterBus.pendingFilter) { _, pending in
                if let pending {
                    filter = pending
                    filterBus.pendingFilter = nil
                }
            }
            .navigationDestination(for: UUID.self) { refId in
                if let ref = fetchRef(id: refId) {
                    ClipDetailView(ref: ref)
                }
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

    // MARK: - Filter branch

    @ViewBuilder
    private var content: some View {
        switch filter {
        case .new:
            newFilterContent
        case .all, .voice, .photos, .notes:
            FlatClipsListView(filter: filter)
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
        let visibleUnplaced = unplacedRefs.filter { !absorbedBus.absorbedRefIds.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            if !visibleUnplaced.isEmpty {
                unplacedDayGroupedStack(refs: visibleUnplaced)
            }
            SessionListView(viewModel: viewModel)
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
                        ClipsListItemRow(item: item)
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

// MARK: - Filter

enum ClipsFilter: String, CaseIterable, Identifiable, Hashable {
    case new, all, voice, photos, notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new: return "New"
        case .all: return "All"
        case .voice: return "Voice"
        case .photos: return "Photos"
        case .notes: return "Notes"
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
/// The filter chip row (New · All · Voice · Photos · Notes) sits
/// below the top bar as the tab's Context row.
struct ClipsHeader: View {
    @Binding var filter: ClipsFilter
    let onSearchTap: () -> Void
    let onSettingsTap: () -> Void
    let onHelpTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeTopBar(
                onSearchTap: onSearchTap,
                onSettingsTap: onSettingsTap,
                onHelpTap: onHelpTap
            )
            chipRow
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ClipsFilter.allCases) { f in
                    chip(for: f)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func chip(for f: ClipsFilter) -> some View {
        let selected = filter == f
        return Button {
            filter = f
        } label: {
            Text(f.label)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .tracking(-0.1)
                .foregroundStyle(selected ? Crucible.Color.accentInk : Crucible.Color.ink2)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(
                    selected ? Crucible.Color.accent : Crucible.Color.hairline.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(f.label)
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

    var body: some View {
        switch item {
        case .single(let ref):
            NavigationLink(value: ref.id) {
                Group {
                    if ref.mediaTypeEnum == .image || ref.mediaTypeEnum == .video {
                        MediaClipRow(ref: ref)
                    } else {
                        LooseClipRow(ref: ref)
                    }
                }
            }
            .buttonStyle(.plain)
        case .burst(let refs):
            NavigationLink(value: refs.first?.id ?? UUID()) {
                BurstRow(refs: refs)
            }
            .buttonStyle(.plain)
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
    let filter: ClipsFilter
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
                        ClipsListItemRow(item: item)
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
        .onChange(of: filter) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: context
        )) { _ in
            groupsReload.fire { reload() }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all:    return "No clips yet."
        case .voice:  return "No voice clips yet."
        case .photos: return "No photos or videos yet."
        case .notes:  return "No notes yet."
        case .new:    return ""
        }
    }

    private func reload() {
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        switch filter {
        case .voice:
            req.predicate = NSPredicate(
                format: "mediaType == %@",
                MediaReference.MediaType.voice.rawValue
            )
        case .photos:
            req.predicate = NSPredicate(
                format: "mediaType == %@ OR mediaType == %@",
                MediaReference.MediaType.image.rawValue,
                MediaReference.MediaType.video.rawValue
            )
        case .notes:
            req.predicate = NSPredicate(
                format: "mediaType == %@",
                MediaReference.MediaType.note.rawValue
            )
        case .all, .new:
            break
        }
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

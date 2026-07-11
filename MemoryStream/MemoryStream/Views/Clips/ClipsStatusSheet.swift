import SwiftUI
import CoreData

/// The Clips tab's Active Navigation Tap status sheet per
/// `docs/design/screens-clips-page.jsx` §ScrClipsStatusSheet and
/// `docs/design/CLAUDE.md` §Phone ("Active Navigation Tap"), locked
/// July 10 2026:
///
/// > "First tap on a tab navigates; tapping the *active* tab scrolls
/// > to top if scrolled, and — when already at top — presents a
/// > status sheet for that section. On Clips the sheet shows new
/// > arrivals by source (Watch / iPhone / Siri), what's processing
/// > (downloading / organizing), and what's available to shape (loose
/// > count) plus quick filter shortcuts — no census/vanity counts."
///
/// Sections:
/// 1. **New arrivals** — presence by source. Watch tinted ochre when
///    non-zero; other sources are quiet ink because they don't route
///    through the inbox today (see follow-up in the .md).
/// 2. **Processing** — what the app is doing right now.
/// 3. **Available to shape** — loose clips waiting to be placed.
///
/// The action row surfaces three quick filters: **Review new** (ochre)
/// jumps the New filter into focus; **Voice** and **Photos** switch
/// the filter chip row to the matching media type.
struct ClipsStatusSheet: View {
    let data: ClipsStatusData
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dragHandle
            title
            newArrivalsSection
            divider
            processingSection
            divider
            availableSection
            actionsRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: - Header

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Crucible.Color.hairline)
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
    }

    private var title: some View {
        Text("Clips")
            .font(.system(size: 22, design: .serif))
            .tracking(-0.4)
            .foregroundStyle(Crucible.Color.ink)
            .padding(.bottom, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Crucible.Color.hairline)
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var newArrivalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("New arrivals")
            statusLine(
                systemImage: "applewatch",
                label: "Apple Watch",
                value: data.watchArrivals,
                tint: data.watchArrivals > 0 ? Crucible.Color.accent : nil
            )
            statusLine(systemImage: "iphone", label: "iPhone", value: data.phoneArrivals)
            statusLine(systemImage: "waveform", label: "Siri", value: data.siriArrivals)
        }
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Processing")
            statusLine(
                systemImage: "arrow.down.circle",
                label: "Downloading",
                value: data.downloading
            )
            statusLine(
                systemImage: "sparkles",
                label: "Organizing",
                value: data.organizing,
                tint: data.organizing > 0 ? Crucible.Color.aiBlue : nil
            )
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Available to shape")
            statusLine(
                systemImage: "waveform",
                label: "Loose clips",
                value: data.looseClips
            )
        }
    }

    // MARK: - Line building blocks

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(Crucible.Color.ink3)
            .padding(.bottom, 2)
    }

    private func statusLine(
        systemImage: String,
        label: String,
        value: Int,
        tint: Color? = nil
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint ?? Crucible.Color.ink3)
                .frame(width: 26, alignment: .center)
            Text(label)
                .font(.system(size: 14.5))
                .tracking(-0.1)
                .foregroundStyle(Crucible.Color.ink)
            Spacer(minLength: 0)
            Text("\(value)")
                .font(.system(size: 14.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Crucible.Color.ink2)
        }
        .frame(minHeight: 38)
    }

    // MARK: - Actions row

    /// Three quick-filter shortcuts. Vocabulary mirrors the ClipsHeader
    /// filter chips exactly (per the spec's "mirror the header filter
    /// vocabulary" note).
    private var actionsRow: some View {
        HStack(spacing: 8) {
            reviewNewButton
            filterPill(label: "Voice", filter: .voice)
            filterPill(label: "Photos", filter: .photos)
        }
        .padding(.top, 16)
    }

    private var reviewNewButton: some View {
        Button {
            ClipsFilterBus.shared.pendingFilter = .new
            onDismiss()
        } label: {
            Text("Review new")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Crucible.Color.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Crucible.Color.accent, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func filterPill(label: String, filter: ClipsFilter) -> some View {
        Button {
            ClipsFilterBus.shared.pendingFilter = filter
            onDismiss()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Crucible.Color.ink2)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Crucible.Color.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data model

/// Snapshot of the Clips tab's live status at the moment the sheet
/// presents. Pulled together by `ClipsStatusDataSource.snapshot()`.
struct ClipsStatusData: Equatable {
    let watchArrivals: Int
    let phoneArrivals: Int
    let siriArrivals: Int
    let downloading: Int
    let organizing: Int
    let looseClips: Int

    static let empty = ClipsStatusData(
        watchArrivals: 0,
        phoneArrivals: 0,
        siriArrivals: 0,
        downloading: 0,
        organizing: 0,
        looseClips: 0
    )
}

/// Pure computation of the status snapshot from `InboxManifest` +
/// Core Data. Extracted so `HiMemTabView` can call it just-in-time
/// when the sheet mounts.
enum ClipsStatusDataSource {

    @MainActor
    static func snapshot() -> ClipsStatusData {
        let inbox = InboxManifest.shared
        let watchArrivals = inbox.clips.filter { $0.source == "watch" }.count
        // iPhone FAB voice and Siri captures land as memories directly,
        // not on the Clips bench, so their arrival counts are 0 here.
        // Post-launch: an arrival-log to attribute presence by source
        // even when the capture skips the inbox.
        let phoneArrivals = 0
        let siriArrivals = 0
        // "Downloading" = still coming in from Watch — either
        // pre-announce with the file not yet on disk, or file on
        // disk but transcription still queued.
        let downloading = inbox.clips.filter {
            $0.status == .announced || $0.status == .received
        }.count
        let organizing = processingTaskCount()
        let loose = looseRefCount()
        return ClipsStatusData(
            watchArrivals: watchArrivals,
            phoneArrivals: phoneArrivals,
            siriArrivals: siriArrivals,
            downloading: downloading,
            organizing: organizing,
            looseClips: loose
        )
    }

    @MainActor
    private static func processingTaskCount() -> Int {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<ProcessingTask>(entityName: "ProcessingTask")
        req.predicate = NSPredicate(format: "status == %@", ProcessingTask.Status.processing.rawValue)
        req.resultType = .countResultType
        return (try? ctx.count(for: req)) ?? 0
    }

    @MainActor
    private static func looseRefCount() -> Int {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "edges.@count == 0")
        req.resultType = .countResultType
        return (try? ctx.count(for: req)) ?? 0
    }
}

// MARK: - Filter bus

/// Session-scoped signal: the Clips status sheet's action buttons set
/// a pending filter; `ClipsTabView` observes and swaps its filter
/// state. Not persisted; a one-shot signal per user tap.
@MainActor
final class ClipsFilterBus: ObservableObject {
    static let shared = ClipsFilterBus()
    @Published var pendingFilter: ClipsFilter? = nil
    private init() {}
}

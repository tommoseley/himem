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
        // `screens-clips-page.jsx` §ScrClipsStatusSheet, locked
        // July 12 2026:
        // > "only sources that actually have arrivals appear — a
        // > source at 0 is omitted entirely, never shown as a
        // > 'Siri 0' zero row (census noise)."
        // The section header itself hides when no source has any
        // arrivals — an empty section reading only "NEW ARRIVALS"
        // is worse than no section at all.
        Group {
            if hasAnyArrivals {
                VStack(alignment: .leading, spacing: 0) {
                    eyebrow("New arrivals")
                    if data.watchArrivals > 0 {
                        statusLine(
                            systemImage: "applewatch",
                            label: "Apple Watch",
                            value: data.watchArrivals,
                            tint: Crucible.Color.accent
                        )
                    }
                    if data.phoneArrivals > 0 {
                        statusLine(systemImage: "iphone", label: "iPhone", value: data.phoneArrivals)
                    }
                    if data.siriArrivals > 0 {
                        statusLine(systemImage: "waveform", label: "Siri", value: data.siriArrivals)
                    }
                    // Media-type breakdown per Tom 2026-07-11: Photos /
                    // Videos / Notes get their own presence rows so the
                    // sheet reads the same media vocabulary the mixed
                    // session card uses (`MediaRow`). Count = loose refs
                    // of that kind (unattached to any memory). Glyphs
                    // match the memory-card canon (`camera` / `video` /
                    // `text.alignleft`) — same 2026-07-11 sync as
                    // `MediaRow.sfSymbol(for:)`.
                    if data.photoArrivals > 0 {
                        statusLine(systemImage: "camera", label: "Photos", value: data.photoArrivals)
                    }
                    if data.videoArrivals > 0 {
                        statusLine(systemImage: "video", label: "Videos", value: data.videoArrivals)
                    }
                    if data.noteArrivals > 0 {
                        statusLine(systemImage: "text.alignleft", label: "Notes", value: data.noteArrivals)
                    }
                }
            }
        }
    }

    private var hasAnyArrivals: Bool {
        data.watchArrivals + data.phoneArrivals + data.siriArrivals
            + data.photoArrivals + data.videoArrivals + data.noteArrivals > 0
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
        // Rename lock July 12 2026 (`screens-clips-page.jsx`
        // §ScrClipsStatusSheet):
        // > "'Not yet connected' — plain English, not internal
        // > jargon ('loose / available to shape'). It's the count
        // > of unshaped clips."
        // The section still renders when the count is zero (the
        // sheet's steady-state is often "everything is connected");
        // the label reads the honest state on its own.
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Not yet connected")
            statusLine(
                systemImage: "waveform",
                label: "Clips",
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
            // Type shortcuts jump to status=All so the user sees
            // every clip of that type, not just the un-shaped subset.
            // "Show me the voice clips" reads as full-history intent;
            // if they wanted only new voice, that's what the header's
            // two-axis control expresses.
            filterPill(label: "Voice", type: .voice)
            filterPill(label: "Photos", type: .photos)
        }
        .padding(.top, 16)
    }

    private var reviewNewButton: some View {
        Button {
            ClipsFilterBus.shared.pending = .init(status: .new, type: .all)
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

    private func filterPill(label: String, type: ClipsType) -> some View {
        Button {
            ClipsFilterBus.shared.pending = .init(status: .all, type: type)
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
    /// Loose photo `MediaReference` count — photos not yet
    /// attached to any memory. Added 2026-07-11 per Tom's ask
    /// so Photos gets its own row under **New arrivals**,
    /// matching the media vocabulary the mixed session card
    /// uses (`MediaRow`).
    let photoArrivals: Int
    /// Loose video count — same rationale as `photoArrivals`.
    let videoArrivals: Int
    /// Loose note count — same rationale as `photoArrivals`.
    let noteArrivals: Int
    let downloading: Int
    let organizing: Int
    let looseClips: Int

    static let empty = ClipsStatusData(
        watchArrivals: 0,
        phoneArrivals: 0,
        siriArrivals: 0,
        photoArrivals: 0,
        videoArrivals: 0,
        noteArrivals: 0,
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
        let byKind = looseRefCountsByKind()
        return Self.compute(
            clips: InboxManifest.shared.clips,
            organizing: processingTaskCount(),
            looseClips: byKind.total,
            photoArrivals: byKind.photo,
            videoArrivals: byKind.video,
            noteArrivals: byKind.note
        )
    }

    /// Pure computation of the sheet's status snapshot from the
    /// upstream sources. Extracted so the counting rules can be
    /// exercised at value-level without mounting SwiftUI or
    /// touching the singleton `InboxManifest.shared`.
    ///
    /// Contract:
    ///   - `watchArrivals` = clips with `source == "watch"`
    ///   - `phoneArrivals` = clips with `source == "phone"` (per
    ///     `PhoneCaptureBenchDispatcher` — since Slice D added
    ///     phone captures to the inbox bench, they no longer skip
    ///     it)
    ///   - `siriArrivals` = 0 (Siri captures still land as
    ///     memories directly, not on the bench)
    ///   - `photoArrivals` / `videoArrivals` / `noteArrivals` =
    ///     caller-supplied loose-`MediaReference` counts by
    ///     media type. Added 2026-07-11 so the sheet reports
    ///     Photos / Videos / Notes presence under **New
    ///     arrivals** alongside the source-based rows.
    ///   - `downloading` = clips with `.announced` or `.received`
    ///     status
    ///   - The passed-through `organizing` and `looseClips` are
    ///     computed by the Core Data readers on the caller side.
    static func compute(
        clips: [InboxClip],
        organizing: Int,
        looseClips: Int,
        photoArrivals: Int,
        videoArrivals: Int,
        noteArrivals: Int
    ) -> ClipsStatusData {
        let watchArrivals = clips.filter { $0.source == "watch" }.count
        let phoneArrivals = clips.filter { $0.source == "phone" }.count
        let siriArrivals = 0
        // "Downloading" = still coming in — either pre-announce
        // with the file not yet on disk, or file on disk but
        // transcription still queued.
        let downloading = clips.filter {
            $0.status == .announced || $0.status == .received
        }.count
        return ClipsStatusData(
            watchArrivals: watchArrivals,
            phoneArrivals: phoneArrivals,
            siriArrivals: siriArrivals,
            photoArrivals: photoArrivals,
            videoArrivals: videoArrivals,
            noteArrivals: noteArrivals,
            downloading: downloading,
            organizing: organizing,
            looseClips: looseClips
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

    /// Loose `MediaReference` counts split by `mediaType`. One
    /// count-only fetch per kind — a single fetch + partition
    /// on the returned rows would work too but at more memory
    /// cost, and the sheet renders infrequently. `total` is the
    /// aggregate, used for the "Available to shape · Loose
    /// clips" line so it stays honest even when the new per-
    /// kind rows report values.
    @MainActor
    private static func looseRefCountsByKind() -> (photo: Int, video: Int, note: Int, voice: Int, total: Int) {
        let photo = looseCount(mediaType: "image")
        let video = looseCount(mediaType: "video")
        let note = looseCount(mediaType: "note")
        let voice = looseCount(mediaType: "voice")
        return (photo, video, note, voice, photo + video + note + voice)
    }

    @MainActor
    private static func looseCount(mediaType: String) -> Int {
        let ctx = StorageService.shared.viewContext
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "edges.@count == 0 AND mediaType == %@", mediaType)
        req.resultType = .countResultType
        return (try? ctx.count(for: req)) ?? 0
    }
}

// MARK: - Filter bus

/// Session-scoped signal: the Clips status sheet's action buttons
/// set a pending filter request; `ClipsTabView` observes and swaps
/// its status/type state atomically. Not persisted; a one-shot signal
/// per user tap. Both axes always specified so the caller declares
/// the intended view in one shot (never leaving type stale from a
/// prior selection).
@MainActor
final class ClipsFilterBus: ObservableObject {
    static let shared = ClipsFilterBus()

    struct Pending: Equatable {
        let status: ClipsStatus
        let type: ClipsType
    }

    @Published var pending: Pending? = nil
    private init() {}
}

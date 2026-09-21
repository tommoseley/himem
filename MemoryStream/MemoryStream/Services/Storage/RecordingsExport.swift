import Foundation
import CoreData

/// **"Save a copy of your recordings"** — ruled by Tom, 2026-09-21.
///
/// ## Why this exists, and why it ships in Release
///
/// The descoping ADR's open question *Existing libraries* set a timing
/// constraint: *"Build the export before playback becomes inaccessible —
/// there are only two libraries, optionality is cheap exactly now, and
/// Judi's recordings are a person's memories rather than development
/// fixtures."*
///
/// **That last clause is what forces Release.** TestFlight ships Release, and
/// every other data tool in this app — the orphan sweep, both seeders — sits
/// behind `#if DEBUG` and is compiled out. An export behind `#if DEBUG` would
/// build, test, demo and review perfectly while being *structurally incapable*
/// of reaching the one library the constraint was written about. Guarded by
/// `RecordingsExportReleaseReachabilityTests`, which is the load-bearing test
/// in this feature: everything else here is recoverable, that is not.
///
/// ## What it covers, and what it deliberately does not
///
/// Scoped to the stated risk — **audio, plus the text that makes a file
/// identifiable without the app.** Photos and video are untouched by the
/// retirement and are not at risk, so they are not copied; an export that
/// quietly widened to "everything" would take minutes and gigabytes to
/// protect things nothing threatens.
///
/// ## A dated correction to the constraint itself (2026-09-21)
///
/// The ADR wrote the ordering against the wrong commit. Bench playback became
/// inaccessible at **I1 (`681ad16`)**, not at I2: `ClipsTabView` has had no
/// instantiation since the tab collapse, and `SessionListView` is only ever
/// constructed from inside it. So the at-risk set is **the unplaced
/// recordings**, not all pre-retirement voice parts — recordings that reached
/// a memory still play, through `EntryExpandedView` and `MediaTile`, neither
/// of which the deletion slice touches.
///
/// **And the live consumer is a different path entirely.** `§1`'s
/// `ArrivedClipMaterializer.materialize` calls `deleteAudio` on every Watch
/// arrival; that shipped and is running now. So this export protects a
/// **fixed** set while another path keeps discarding by design. Running it
/// twice a year would be pointless; running it once, soon, is the whole idea.
enum RecordingsExport {

    // MARK: - Snapshot (detached from Core Data by construction)

    /// One recording plus the text that makes it mean something in Finder.
    struct Recording: Equatable, Sendable {
        let id: UUID
        let sourceURL: URL
        let transcript: String
        let capturedAt: Date
        let placeName: String?
        /// Empty means **unplaced** — it never reached a memory. This is the
        /// set the I1 tab collapse stranded.
        let memoryIds: [UUID]
        var isPlaced: Bool { !memoryIds.isEmpty }
    }

    struct MemoryRecord: Equatable, Sendable {
        let id: UUID
        let title: String?
        let createdAt: Date
        let content: String
        let placeName: String?
    }

    /// **Values only — no `NSManagedObject` survives into the write step.**
    /// The copy can take a while (iCloud downloads), and reading a live
    /// context across that window is how a faulted object turns into a crash
    /// or a silently short folder.
    struct Snapshot: Equatable, Sendable {
        var recordings: [Recording] = []
        var memories: [MemoryRecord] = []
    }

    struct Outcome: Equatable, Sendable {
        let savedCount: Int
        let unavailableCount: Int
        let folderURL: URL?
    }

    // MARK: - Naming (pure)

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Characters that cannot appear in a filename on the destinations this
    /// folder plausibly lands on (APFS, iCloud Drive, and — because people do
    /// drag these onto a NAS — Windows shares). `/` and `:` are the ones that
    /// actually break on iOS; the rest are cheap insurance.
    private static let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>\u{0}")

    /// The first `limit` words of a transcript, safe to use as a filename.
    /// Returns "" when there is nothing usable — a recording that transcribed
    /// to silence still gets exported, just under its timestamp alone.
    static func firstWords(_ transcript: String, limit: Int = 6) -> String {
        let cleaned = transcript
            .components(separatedBy: .newlines).joined(separator: " ")
            .components(separatedBy: illegal).joined()
        let words = cleaned.split(separator: " ").prefix(limit)
        let joined = words.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap so a long compound word cannot push the whole name past a
        // filesystem's per-component limit once the stamp and extension are on.
        return String(joined.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// `2026-08-14 1432 — the pears were really good.m4a`
    static func exportName(capturedAt: Date, transcript: String, sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let words = firstWords(transcript)
        let base = stamp.string(from: capturedAt)
        return words.isEmpty ? "\(base).\(ext)" : "\(base) — \(words).\(ext)"
    }

    /// Assigns a unique filename to every recording.
    ///
    /// **Deterministic by construction** — sorted by capture time then id, so
    /// the same library exports to the same names twice, and a second run into
    /// a different folder is diffable against the first. Collisions get
    /// ` (2)`, ` (3)` … rather than silently overwriting, which is how two
    /// recordings in the same minute with the same opening words would
    /// otherwise become one.
    static func assignNames(_ recordings: [Recording]) -> [UUID: String] {
        var used: Set<String> = []
        var out: [UUID: String] = [:]
        for rec in recordings.sorted(by: { ($0.capturedAt, $0.id.uuidString) < ($1.capturedAt, $1.id.uuidString) }) {
            let wanted = exportName(capturedAt: rec.capturedAt, transcript: rec.transcript, sourceURL: rec.sourceURL)
            var name = wanted
            var n = 2
            while used.contains(name.lowercased()) {
                let ext = (wanted as NSString).pathExtension
                let stem = (wanted as NSString).deletingPathExtension
                name = "\(stem) (\(n)).\(ext)"
                n += 1
            }
            used.insert(name.lowercased())
            out[rec.id] = name
        }
        return out
    }

    // MARK: - Completion copy (pure)

    /// The completion state, in the voice Tom ruled on 2026-09-21 and
    /// **corrected the same day, after it told him something false.**
    ///
    /// The first version said: *"Saved 130 recordings. 108 couldn't be
    /// downloaded from iCloud — try again when you're on Wi-Fi."* He was on
    /// Wi-Fi. The sentence named a cause the app cannot know — it can see that
    /// a file has not arrived, and nothing more — and the cause it guessed was
    /// wrong, so the one action it offered was useless.
    ///
    /// **A completion line may report what happened and what to do. It may not
    /// diagnose why.** Hence: no network, no connection, no Wi-Fi, no offline.
    /// `theCopyNeverAssertsACause` forbids the words; this comment is the
    /// reason, so a future rewrite knows the rule is about claims rather than
    /// vocabulary.
    ///
    /// It must also never say "failed". A recording iCloud has not yet handed
    /// over is not damaged, and the difference is whether she thinks her
    /// memories are gone.
    static func completionMessage(savedCount: Int, unavailableCount: Int) -> String {
        let total = savedCount + unavailableCount
        if total == 0 { return "There are no recordings to save." }
        guard unavailableCount > 0 else {
            return savedCount == 1 ? "Saved 1 recording." : "Saved \(savedCount) recordings."
        }
        // Nothing arrived at all — "the rest" would have no referent, and
        // "Saved 0 of 130" reads like a failure report rather than a wait.
        // The one line here Tom did not rule; flagged as mine.
        guard savedCount > 0 else {
            return total == 1
                ? "Your recording is still in iCloud and hasn't come down yet — run this again in a few minutes."
                : "Your \(total) recordings are still in iCloud and haven't come down yet — run this again in a few minutes."
        }
        let noun = total == 1 ? "recording" : "recordings"
        return "Saved \(savedCount) of \(total) \(noun). The rest are still in iCloud and haven't come down yet — run this again in a few minutes."
    }

    // MARK: - Snapshot

    /// Reads every voice recording the library still holds, from both stores:
    /// materialized `MediaReference`s and the transient inbox's manifest rows.
    /// Recycled rows are skipped — Recently Deleted is a user decision, and
    /// copying out of it would resurrect what she threw away.
    @MainActor
    static func snapshot(context: NSManagedObjectContext,
                         manifestClips: [InboxClip]) -> Snapshot {
        var snap = Snapshot()

        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        req.predicate = NSPredicate(format: "mediaType == %@ AND recycledAt == nil",
                                    MediaReference.MediaType.voice.rawValue)
        let refs = (try? context.fetch(req)) ?? []

        var wantedMemoryIds: Set<UUID> = []
        for ref in refs {
            // **`id` is read through KVC, not the `@NSManaged` accessor.**
            // `MediaReference.id` is declared non-optional over an
            // `optional="YES"` model cell — every attribute in this model is
            // optional, because `NSPersistentCloudKitContainer` requires it —
            // and `StorageService` sets `shouldDeleteInaccessibleFaults`,
            // which nils every property of a row whose CloudKit record went
            // away. Reading the typed accessor on such a row traps with
            // `EXC_BREAKPOINT`; it has done so twice on device (2026-08-21).
            //
            // A nil-id row is unlikely to satisfy this fetch's predicate, so
            // this is belt rather than the only guard — but an export is the
            // one operation that must not die partway through, and skipping a
            // row costs one line. Guarded by `NilIdWholeTableReadTests`.
            guard let refId = ref.value(forKey: "id") as? UUID else { continue }
            let memoryIds = ((ref.edges as? Set<MemoryClipEdge>) ?? [])
                .compactMap { $0.memory?.isRecycled == true ? nil : $0.memoryId }
            wantedMemoryIds.formUnion(memoryIds)
            snap.recordings.append(Recording(
                id: refId,
                sourceURL: UbiquityStore.shared.audioURL(for: ref.osIdentifier),
                transcript: ref.transcript ?? "",
                capturedAt: ref.createdAt ?? Date(timeIntervalSince1970: 0),
                placeName: ref.placeName,
                memoryIds: memoryIds.sorted(by: { $0.uuidString < $1.uuidString })
            ))
        }

        // The transient inbox. Unplaced by definition — these are exactly the
        // rows the I1 tab collapse left without a surface.
        let known = Set(snap.recordings.map(\.id))
        for clip in manifestClips where !known.contains(clip.clipId) && !clip.audioFilename.isEmpty {
            snap.recordings.append(Recording(
                id: clip.clipId,
                sourceURL: UbiquityStore.shared.inboxURL(for: clip.audioFilename),
                transcript: clip.transcript,
                capturedAt: clip.capturedAt,
                placeName: nil,
                memoryIds: []
            ))
        }

        guard !wantedMemoryIds.isEmpty else { return snap }
        let mReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        mReq.predicate = NSPredicate(format: "id IN %@ AND isRecycled == NO", wantedMemoryIds)
        for entry in (try? context.fetch(mReq)) ?? [] {
            snap.memories.append(MemoryRecord(
                id: entry.id,
                title: entry.title,
                createdAt: entry.createdAt,
                content: entry.content,
                placeName: entry.locationName
            ))
        }
        return snap
    }

    // MARK: - Write

    private struct IndexEntry: Encodable {
        let file: String
        let recordedAt: Date
        let place: String?
        let transcript: String
        let memories: [String]
        let downloaded: Bool
    }

    /// The environment `write` touches: iCloud status, the download request,
    /// and the clock. Injected so the waiting policy is testable without a
    /// real container and without a test that actually sleeps.
    struct IO {
        var status: (URL) -> UbiquityStore.DownloadStatus
        var startDownload: (URL) -> Void
        var now: () -> Date
        var sleep: (TimeInterval) -> Void

        @MainActor static var live: IO {
            IO(status: { UbiquityStore.shared.downloadStatus(at: $0) },
               startDownload: { UbiquityStore.shared.startDownload(at: $0) },
               now: Date.init,
               sleep: { Thread.sleep(forTimeInterval: $0) })
        }
    }

    /// Copies the snapshot into `folder`, forcing iCloud downloads and
    /// **reporting what it could not retrieve**.
    ///
    /// *"An export preserves what's readable when it runs"* is only an honest
    /// sentence if the export says what wasn't readable — so an undownloaded
    /// file is counted and named in `index.json`, never skipped quietly.
    ///
    /// ## The waiting policy, and why it is per-file
    ///
    /// **A single shared budget across the whole library was the defect**
    /// (device, 2026-09-21): 238 recordings, 90 seconds, *"Saved 130. 108
    /// couldn't be downloaded"* — on Wi-Fi, with iCloud working correctly and
    /// still delivering. The budget expired mid-transfer and the export called
    /// that a result. A shared deadline does not scale with the thing it is
    /// bounding: the bigger the library, the less of it can possibly arrive,
    /// and the failure grows with exactly the libraries most worth exporting.
    ///
    /// So: every pending file is **requested up front** — that part was right,
    /// it lets iCloud queue the whole set and means most files are already
    /// down by the time the copy loop reaches them — and then each file gets
    /// **its own timeout**, with a large overall `ceiling` as the only global
    /// bound. An export run once may take minutes; that is fine, and
    /// `progress` exists so it can say so while it works.
    ///
    /// The retry-loop discipline that motivated the old shared budget still
    /// holds and is still satisfied: one request per file, a bounded wait, and
    /// a poll that sleeps rather than spins (CLAUDE.md § Measurement
    /// Discipline — the loop that wedged CoreDevice). What changed is the
    /// *size* of the bound, not its existence.
    static func write(_ snapshot: Snapshot,
                      into folder: URL,
                      perFileTimeout: TimeInterval = 120,
                      ceiling: TimeInterval = 1800,
                      io: IO,
                      progress: (Int, Int) -> Void = { _, _ in }) throws -> Outcome {
        let fm = FileManager.default
        let names = assignNames(snapshot.recordings)
        let audio = folder.appendingPathComponent("audio", isDirectory: true)
        let unplaced = folder.appendingPathComponent("unplaced", isDirectory: true)
        let memories = folder.appendingPathComponent("memories", isDirectory: true)
        for dir in [folder, audio, unplaced, memories] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // One download request per absent file, up front — this lets iCloud
        // queue the whole set while the copy loop walks it, so by the time a
        // later file is reached it has usually already arrived.
        for rec in snapshot.recordings where io.status(rec.sourceURL) != .downloaded {
            io.startDownload(rec.sourceURL)
        }

        var index: [IndexEntry] = []
        var saved = 0, unavailable = 0
        let total = snapshot.recordings.count
        let ceilingAt = io.now().addingTimeInterval(ceiling)

        for (i, rec) in snapshot.recordings.enumerated() {
            progress(i, total)
            guard let name = names[rec.id] else { continue }
            let destDir = rec.isPlaced ? audio : unplaced

            // **This file's own timeout**, clamped by the overall ceiling.
            if io.status(rec.sourceURL) != .downloaded {
                let waitUntil = min(io.now().addingTimeInterval(perFileTimeout), ceilingAt)
                while io.now() < waitUntil && io.status(rec.sourceURL) != .downloaded {
                    io.sleep(0.5)
                }
            }
            let got = io.status(rec.sourceURL) == .downloaded
            if got {
                try? fm.removeItem(at: destDir.appendingPathComponent(name))
                do {
                    try fm.copyItem(at: rec.sourceURL, to: destDir.appendingPathComponent(name))
                    saved += 1
                } catch {
                    unavailable += 1
                }
            } else {
                unavailable += 1
            }
            // The transcript rides beside an unplaced recording — nothing else
            // in the folder would say what it is.
            if !rec.isPlaced && !rec.transcript.isEmpty {
                let sidecar = (name as NSString).deletingPathExtension + ".txt"
                try? rec.transcript.write(to: unplaced.appendingPathComponent(sidecar),
                                          atomically: true, encoding: .utf8)
            }
            index.append(IndexEntry(
                file: (rec.isPlaced ? "audio/" : "unplaced/") + name,
                recordedAt: rec.capturedAt,
                place: rec.placeName,
                transcript: rec.transcript,
                memories: rec.memoryIds.map(\.uuidString),
                downloaded: got
            ))
        }

        for memory in snapshot.memories {
            let mine = snapshot.recordings
                .filter { $0.memoryIds.contains(memory.id) }
                .compactMap { names[$0.id] }
                .sorted()
            var md = "# \(memory.title ?? "Untitled")\n\n"
            md += DateFormatter.localizedString(from: memory.createdAt, dateStyle: .long, timeStyle: .short) + "\n"
            if let place = memory.placeName { md += place + "\n" }
            md += "\n" + memory.content + "\n"
            if !mine.isEmpty {
                md += "\n## Recordings\n\n" + mine.map { "- audio/\($0)" }.joined(separator: "\n") + "\n"
            }
            let stem = firstWords(memory.title ?? memory.content, limit: 8)
            let base = stamp.string(from: memory.createdAt)
            let file = stem.isEmpty ? "\(base).md" : "\(base) — \(stem).md"
            try? md.write(to: memories.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(index) {
            try? data.write(to: folder.appendingPathComponent("index.json"), options: .atomic)
        }

        progress(total, total)
        return Outcome(savedCount: saved, unavailableCount: unavailable, folderURL: folder)
    }

    /// Destination for a run: a dated folder in `tmp`, handed straight to the
    /// share sheet. Not written into the ubiquity container — the copy is
    /// hers to put wherever she likes, and writing it into HiMem's own store
    /// would be the one thing the row's copy promises not to do.
    static func destination(now: Date = Date()) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("HiMem Recordings \(f.string(from: now))", isDirectory: true)
    }
}

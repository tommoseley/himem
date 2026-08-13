#if DEBUG
import Foundation
import CoreData
import AVFoundation
import UIKit

/// **Bench fixtures for the device checks that have never been verified.**
/// DEBUG-only; the whole file compiles out of Release.
///
/// F41, F43 and F44 have stayed open not because they are hard to check but
/// because their preconditions are hard to *produce*. Each needs a specific
/// bench shape, and one of them — a cluster containing a **ref-backed** clip —
/// cannot be made by hand at all: a clip becomes ref-backed only by completing
/// a transcription and being materialized, which means waiting on real capture
/// and a real bench render. Seeding it on demand is the difference between a
/// check that gets run and a check that stays open.
///
/// **Everything here goes through the production paths**, which is the point:
/// `ArrivedClipMaterializer.materialize` promotes clips exactly as the app
/// does (and *refuses* without real audio on disk, which is why the seed
/// writes real audio), `ClipSessionGrouper`/`UnifiedBenchGrouper` do the
/// grouping, and `ClipClusterProposer` decides the clusters. A fixture built
/// by writing the desired end state directly would prove the renderer works
/// on data the app can never actually produce.
///
/// **Marked, and removable.** Every seeded id carries the established `5EED…`
/// prefix (the same convention as `debugSeedTestCluster`), every file is named
/// `5EED-…`, and `clear` removes exactly those — manifest rows, Core Data refs
/// and files — leaving real bench content untouched.
///
/// **Each cluster gets its OWN place, and the loose session none.** Found by
/// `QAFixtureSeederTests` before this ever reached a device: `proposeTimePlace`
/// clusters on time + shared location *independently of the words*, so seeding
/// every fixture at one coordinate collapsed all three into a single
/// "Together at …" proposal. The device pass would then have been reading a
/// shape nobody designed — and reading it as the bench misbehaving.
///
/// **Real media, deliberately.** Audio is a written CAF and photos are written
/// JPEGs, because a zero-byte or absent file no longer means "an inert seed":
/// since B15 it means *stranded bytes*, a different fixture entirely, which
/// would put the clip in `awaitingDownload` and silently invalidate any check
/// that depends on playback or on the clip being drawable.
enum QAFixtureSeeder {

    // MARK: - Identity

    /// `5EED0002-…` — this seeder's namespace, distinct from
    /// `debugSeedTestCluster`'s `5EED0000-…` so the two can coexist and
    /// `clear` never removes the other's rows.
    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "5EED0002-0000-0000-0000-%012d", n))!
    }

    static func isSeeded(_ id: UUID) -> Bool {
        id.uuidString.hasPrefix("5EED0002")
    }

    private static let filePrefix = "5EED-qa-"

    // MARK: - What gets built

    /// The four coexisting shapes: three clusters and one loose session.
    ///
    /// Kept separate from `seedFullyClusteredBench` because the two are
    /// **mutually exclusive by definition** — "every session is clustered"
    /// cannot be true while a loose session exists, and the dropped-session-term
    /// case is only reachable when it is. One button cannot produce both.
    @MainActor
    static func seedFixtures(in context: NSManagedObjectContext) -> String {
        clear(in: context)
        let now = Date()
        var notes: [String] = []
        notes.append(seedClusterA(now: now, in: context))
        notes.append(seedClusterB(now: now, in: context))
        notes.append(seedClusterC(now: now, in: context))
        notes.append(seedLooseSession(now: now, in: context))
        return notes.joined(separator: "\n\n")
    }

    /// Clusters only — no loose session, so **every** drawn session is claimed
    /// by a proposal. Reaches the two cases that need it: the session term
    /// dropping from the header, and "Nothing new" never rendering over a
    /// screen of cluster cards.
    @MainActor
    static func seedFullyClusteredBench(in context: NSManagedObjectContext) -> String {
        clear(in: context)
        let now = Date()
        var notes: [String] = []
        notes.append(seedClusterA(now: now, in: context))
        notes.append(seedClusterB(now: now, in: context))
        notes.append(seedClusterC(now: now, in: context))
        return notes.joined(separator: "\n\n")
            + "\n\nNo loose session seeded, so every drawn session is clustered."
    }

    // MARK: - Cluster A · a ref-backed clip inside a cluster (F41)

    /// Three sittings sharing the bigram **“Harbor Lantern”**, 15 minutes
    /// apart so the idle gap keeps them separate — then the **oldest is
    /// materialized into a `MediaReference`** through the real path.
    ///
    /// That last step is the fixture. `materialize` refuses unless the audio
    /// is actually on disk (`moveAudioToVoiceStore` returns false), so this
    /// also proves the written CAF is real. The result is a cluster whose
    /// members are backed by *both* stores at once — the shape premise 2
    /// exists for, and the one that made the reverted 2b-ii draw "1 clip"
    /// over three rows.
    @MainActor
    private static func seedClusterA(now: Date, in context: NSManagedObjectContext) -> String {
        let lines = [
            "Walking past Harbor Lantern before the tide turned — QA fixture 1",
            "Second pass by Harbor Lantern, quieter now — QA fixture 2",
            "Last look at Harbor Lantern on the way back — QA fixture 3",
        ]
        var seeded: [InboxClip] = []
        for i in 0..<3 {
            let clip = voiceClip(
                id: id(100 + i),
                capturedAt: now.addingTimeInterval(Double(-i) * 15 * 60),
                transcript: lines[i],
                coordinate: (32.2371, -80.8557)      // Bluffton
            )
            seeded.append(clip)
        }
        appendToManifest(seeded)
        // Materialize the OLDEST so the cluster spans both backings.
        let target = seeded[2]
        let materialized = ArrivedClipMaterializer.materialize(target, in: context) != nil
        return """
        CLUSTER A — “Harbor Lantern” · 3 voice clips, 15 min apart.
        The oldest is REF-BACKED\(materialized ? "" : " (MATERIALIZE FAILED — see log)"); the other two are manifest rows.
        For: F41 — the precondition that cannot be made by hand.
        """
    }

    // MARK: - Cluster B · a photo, and an endpoint worth setting aside (F43)

    /// Three sittings sharing **“Sparrow Quarry”**, with a photo two minutes
    /// after the oldest clip so the grouper folds it into that sitting.
    ///
    /// **The set-aside target is an ENDPOINT, deliberately.** F43's subtitle
    /// defect is that `whyText` is fixed at construction and keeps describing
    /// the original membership — but setting aside a *middle* clip leaves the
    /// span accidentally correct, because both extremes survive. Only removing
    /// an endpoint moves the true span, so only an endpoint can tell a
    /// recomputed subtitle from a stale one.
    @MainActor
    private static func seedClusterB(now: Date, in context: NSManagedObjectContext) -> String {
        let base = now.addingTimeInterval(-3 * 3600)
        let lines = [
            "Notes from Sparrow Quarry, north face in shadow — QA fixture 4",
            "More from Sparrow Quarry after the climb — QA fixture 5",
            "Leaving Sparrow Quarry as the light went — QA fixture 6",
        ]
        var seeded: [InboxClip] = []
        for i in 0..<3 {
            seeded.append(voiceClip(
                id: id(200 + i),
                capturedAt: base.addingTimeInterval(Double(-i) * 15 * 60),
                transcript: lines[i],
                coordinate: (44.3876, -68.2039)      // Acadia — far from Bluffton
            ))
        }
        appendToManifest(seeded)
        // Photo inside the OLDEST sitting's window (2 min after it).
        insertPhotoRef(
            id: id(210),
            createdAt: base.addingTimeInterval(-2 * 15 * 60 + 120),
            in: context
        )
        return """
        CLUSTER B — “Sparrow Quarry” · 3 voice clips + 1 photo (~3 h ago).
        The photo sits inside the OLDEST sitting. The oldest and newest clips are the span ENDPOINTS.
        For: F43 — (a) bundle it and the photo must land in the memory; (b) set aside an ENDPOINT and the subtitle's span must move.
        """
    }

    // MARK: - Cluster C · voice + photo + note in one cluster (F44)

    /// Three sittings sharing **“Thistle Beacon”**, with a photo *and* a note
    /// folded into the newest one — so the cluster card carries all three
    /// kinds at once.
    ///
    /// For F44's three-numbers check: the subtitle's count, the 📷 glyph and
    /// the "Show all N" expander are computed from three different places and
    /// must move together when anything is set aside.
    @MainActor
    private static func seedClusterC(now: Date, in context: NSManagedObjectContext) -> String {
        let base = now.addingTimeInterval(-6 * 3600)
        let lines = [
            "Thistle Beacon from the lower path — QA fixture 7",
            "Halfway up to Thistle Beacon now — QA fixture 8",
            "At Thistle Beacon, wind off the water — QA fixture 9",
        ]
        var seeded: [InboxClip] = []
        for i in 0..<3 {
            seeded.append(voiceClip(
                id: id(300 + i),
                capturedAt: base.addingTimeInterval(Double(-i) * 15 * 60),
                transcript: lines[i],
                coordinate: (47.6062, -122.3321)     // Seattle — far from both
            ))
        }
        appendToManifest(seeded)
        insertPhotoRef(id: id(310), createdAt: base.addingTimeInterval(180), in: context)
        insertNoteRef(
            id: id(311),
            createdAt: base.addingTimeInterval(300),
            text: "Ask about the ferry timetable — QA fixture note",
            in: context
        )
        return """
        CLUSTER C — “Thistle Beacon” · 3 voice clips + 1 photo + 1 note (~6 h ago).
        Photo and note fold into the NEWEST sitting, so one cluster carries all three kinds.
        For: F44 — subtitle count, 📷 glyph and “Show all N” must move together.
        """
    }

    // MARK: - A loose mixed session (F37)

    /// One sitting with a voice clip, a photo and a note inside the window,
    /// sharing no distinctive phrase with any cluster so the proposer leaves
    /// it alone.
    ///
    /// This is F37's case: the list header, the card glyph and the drill-in
    /// must all state the session's **full** contents (3), and the photo and
    /// note must be drawn **once** — inside the card, not also in the sibling
    /// unplaced stack above it.
    @MainActor
    private static func seedLooseSession(now: Date, in context: NSManagedObjectContext) -> String {
        let base = now.addingTimeInterval(-9 * 3600)
        appendToManifest([voiceClip(
            id: id(400),
            capturedAt: base,
            transcript: "Just thinking out loud about the week ahead — QA fixture 10",
            coordinate: nil          // no place: `proposeTimePlace` cannot reach it
        )])
        insertPhotoRef(id: id(410), createdAt: base.addingTimeInterval(120), in: context)
        insertNoteRef(
            id: id(411),
            createdAt: base.addingTimeInterval(240),
            text: "Pick up the spare key — QA fixture note",
            in: context
        )
        return """
        LOOSE SESSION — 1 voice + 1 photo + 1 note within 10 min (~9 h ago), no cluster.
        For: F37 — header, card glyph and drill-in must all say 3; the photo and note must be drawn ONCE.
        """
    }

    // MARK: - Clearing

    /// Removes every seeded row, ref and file — and nothing else.
    @MainActor
    static func clear(in context: NSManagedObjectContext) {
        InboxManifest.shared.removeBatch(
            clipIds: InboxManifest.shared.clips.map(\.clipId).filter(isSeeded)
        )
        let req = NSFetchRequest<MediaReference>(entityName: "MediaReference")
        if let refs = try? context.fetch(req) {
            for ref in refs where isSeeded(ref.id) {
                context.delete(ref)
            }
        }
        try? context.save()
        // Files last: a ref that failed to delete would otherwise point at
        // nothing, which is the stranded-bytes state rather than a clean slate.
        for dir in [UbiquityStore.shared.audioURL(for: ""), UbiquityStore.shared.photoURL(for: ""),
                    InboxManifest.audioURL(for: "")] {
            let base = dir.deletingLastPathComponent()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
            for name in names where name.hasPrefix(filePrefix) {
                try? FileManager.default.removeItem(at: base.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Building blocks

    /// A transcribed manifest clip with **real audio on disk**.
    ///
    /// `transcriptionAttempted: true` and `.transcribed` keep it out of the
    /// pending sweep entirely, so seeding never trips the B15 retry path; the
    /// audio is written because playback, and `materialize`, both need it.
    @MainActor
    private static func voiceClip(
        id clipId: UUID,
        capturedAt: Date,
        transcript: String,
        coordinate: (lat: Double, lon: Double)?
    ) -> InboxClip {
        let filename = "\(filePrefix)\(clipId.uuidString.prefix(8)).caf"
        writeTone(to: InboxManifest.audioURL(for: filename))
        return InboxClip(
            clipId: clipId,
            capturedAt: capturedAt,
            duration: 2,
            transcript: transcript,
            latitude: coordinate?.lat,
            longitude: coordinate?.lon,
            source: "phone",
            audioFilename: filename,
            transcriptionAttempted: true,
            rollGroupId: nil,
            status: .transcribed
        )
    }

    @MainActor
    private static func appendToManifest(_ new: [InboxClip]) {
        for clip in new { InboxManifest.shared.acceptClip(clip) }
    }

    @MainActor
    private static func insertPhotoRef(id refId: UUID, createdAt: Date, in context: NSManagedObjectContext) {
        let filename = "\(filePrefix)\(refId.uuidString.prefix(8)).jpg"
        writeSwatch(to: UbiquityStore.shared.photoURL(for: filename))
        let ref = MediaReference(context: context)
        ref.id = refId
        ref.osIdentifier = filename          // ubiquity filename → MediaResolver reads it directly
        ref.mediaType = MediaReference.MediaType.image.rawValue
        ref.createdAt = createdAt
        ref.sourceDevice = JournalEntry.SourceDevice.phone.rawValue
        ref.isAccessible = true
        try? context.save()
    }

    @MainActor
    private static func insertNoteRef(id refId: UUID, createdAt: Date, text: String, in context: NSManagedObjectContext) {
        let ref = MediaReference(context: context)
        ref.id = refId
        ref.osIdentifier = refId.uuidString
        ref.mediaType = MediaReference.MediaType.note.rawValue
        ref.createdAt = createdAt
        ref.text = text
        ref.sourceDevice = JournalEntry.SourceDevice.phone.rawValue
        ref.isAccessible = true
        try? context.save()
    }

    // MARK: - Real bytes

    /// A short mono tone. Real, decodable audio — `AVAudioPlayer` plays it and
    /// `materialize` accepts it. Silence would compress at the ~831× ratio the
    /// capture gate flags, so a tone keeps the seed out of that path too.
    private static func writeTone(to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let file = try? AVAudioFile(forWriting: url, settings: format.settings),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000)
        else { return }
        buffer.frameLength = 32_000
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) {
                samples[i] = 0.25 * sinf(2 * .pi * 440 * Float(i) / 16_000)
            }
        }
        try? file.write(from: buffer)
    }

    /// A small labelled JPEG, so a seeded photo is visibly a fixture on screen
    /// as well as by id.
    private static func writeSwatch(to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let size = CGSize(width: 480, height: 480)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.92, green: 0.45, blue: 0.26, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "QA\nFIXTURE"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let bounds = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2),
                withAttributes: attrs
            )
        }
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: url)
        }
    }
}
#endif

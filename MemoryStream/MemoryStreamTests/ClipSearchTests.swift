import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money tests for the Object-scope · Clips search path
/// (`Himem · Search.html` §"Object scope"). The load-bearing promise:
/// a **loose clip is invisible to a memory-only search**, so clip search
/// must surface it directly with its status.
@MainActor
@Suite(.serialized)
struct ClipSearchTests {

    private func make() -> (StorageService, SearchEngine) {
        let s = StorageService(inMemory: true)
        return (s, SearchEngine(storage: s))
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        return utc.date(from: comps)!
    }

    /// A `MediaReference` with no edges (loose bench clip).
    @discardableResult
    private func looseClip(in s: StorageService, id: String,
                           transcript: String? = nil, text: String? = nil, desc: String? = nil,
                           type: MediaReference.MediaType = .voice, createdAt: Date = Date()) -> MediaReference {
        let r = MediaReference(context: s.viewContext)
        r.id = UUID()
        r.osIdentifier = id
        r.mediaType = type.rawValue
        r.isAccessible = true
        r.createdAt = createdAt
        r.transcript = transcript
        r.text = text
        r.mediaDescription = desc
        try! s.viewContext.save()
        return r
    }

    // MARK: - The money test

    @Test func looseClip_invisibleToMemorySearch_foundByClipSearch_asUnconnected() throws {
        let (s, e) = make()
        looseClip(in: s, id: "loose.caf", transcript: "the tomato trellis idea")

        // No memory contains these words — a memory-only search misses it.
        #expect(try e.search(parsed: ScopeParser.parse("tomato")).isEmpty,
                "A loose clip's words are invisible to a memory-only search")

        let clipHits = try e.searchClips(parsed: ScopeParser.parse("tomato"))
        #expect(clipHits.count == 1)
        #expect(clipHits.first?.status == "Unconnected")
    }

    @Test func connectedClip_status_singularAndPlural() throws {
        let (s, e) = make()
        let a = try s.createEntry(content: "", inputType: .typed)
        let ref = try s.createVoiceFragment(for: a, audioFilename: "c.caf", transcript: "basil pesto notes")
        try s.viewContext.save()

        var hits = try e.searchClips(parsed: ScopeParser.parse("basil"))
        #expect(hits.first?.status == "in 1 memory")

        // Cite the same clip in a second memory → "in 2 memories".
        let b = try s.createEntry(content: "", inputType: .typed)
        try StorageService.createEdge(from: b, to: ref, linkedAt: Date(), in: s.viewContext)
        try s.viewContext.save()
        hits = try e.searchClips(parsed: ScopeParser.parse("basil"))
        #expect(hits.first?.status == "in 2 memories")
    }

    @Test func searchClips_composesTypeAndDate() throws {
        let (s, e) = make()
        looseClip(in: s, id: "voice-2023", transcript: "garden note", type: .voice, createdAt: date(2023, 6, 1))
        looseClip(in: s, id: "note-2024", text: "garden note", type: .note, createdAt: date(2024, 6, 1))
        looseClip(in: s, id: "voice-2024", transcript: "garden note", type: .voice, createdAt: date(2024, 6, 1))

        // type:voice + date:2023 → only the 2023 voice clip.
        let hits = try e.searchClips(parsed: ScopeParser.parse("garden type:voice date:2023"))
        #expect(hits.map { $0.ref.osIdentifier } == ["voice-2023"])
    }

    @Test func searchClips_matchesPhotoDescriptionAndNoteText() throws {
        let (s, e) = make()
        looseClip(in: s, id: "photo", desc: "sunset over the harbor", type: .image)
        looseClip(in: s, id: "note", text: "harbor cleanup plan", type: .note)
        looseClip(in: s, id: "other", transcript: "unrelated", type: .voice)

        let hits = try e.searchClips(parsed: ScopeParser.parse("harbor"))
        #expect(Set(hits.map { $0.ref.osIdentifier }) == ["photo", "note"])
    }

    @Test func searchClips_excludesRecycled() throws {
        let (s, e) = make()
        let gone = looseClip(in: s, id: "gone", transcript: "tomato")
        gone.recycledAt = Date()
        looseClip(in: s, id: "alive", transcript: "tomato")
        try s.viewContext.save()

        let hits = try e.searchClips(parsed: ScopeParser.parse("tomato"))
        #expect(hits.map { $0.ref.osIdentifier } == ["alive"])
    }

    @Test func memoryBoxYears_distinctDescending() throws {
        let (s, e) = make()
        for d in [date(2022, 3, 1), date(2024, 7, 1), date(2024, 1, 1)] {
            let m = try s.createEntry(content: "x", inputType: .typed)
            m.createdAt = d
        }
        try s.viewContext.save()
        #expect(e.memoryBoxYears(calendar: utc) == [2024, 2022])
    }
}

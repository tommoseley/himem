import Testing
import Foundation
import CoreData
@testable import HiMem

/// **A whole-table fetch that reads a non-optional `@NSManaged` accessor traps
/// on any row whose cell is nil — and `shouldDeleteInaccessibleFaults` is what
/// makes such a row reachable.**
///
/// **RETARGETED 2026-09-21.** This was written against `QAFixtureSeeder.clear`,
/// which fetched every `MediaReference` and called `isSeeded(ref.id)`. That
/// seeder is deleted with the bench — but **the defect class is not about the
/// seeder**, it is about any fetch that reads a non-optional `@NSManaged`
/// accessor on a row that may have nil cells, and there is a live one:
/// `RecordingsExport.snapshot`, which fetches every voice `MediaReference` to
/// copy her recordings out.
///
/// Retargeted rather than deleted because the reader moved, not the rule. The
/// export is also the worst place for this to bite — it is the operation that
/// must not die partway through, and it exists to protect two real libraries.
///
/// `MediaReference.id` is declared
/// `@NSManaged public var id: UUID` over an `optional="YES"` model cell (every
/// attribute in this model is optional, because `NSPersistentCloudKitContainer`
/// requires it). One nil cell traps with `EXC_BREAKPOINT` → SIGTRAP → signal 5.
///
/// **Why a nil cell is reachable rather than theoretical.**
/// `StorageService:165` sets `viewContext.shouldDeleteInaccessibleFaults = true`
/// so that a fault pointing at a CloudKit-deleted record does not throw. What
/// the flag actually does is mark the object deleted and **nil out every
/// property** — converting a catchable `NSObjectInaccessibleException` into a
/// silently nil-valued object. Deleting rows is what makes a cached fault
/// inaccessible, which is why both observed traps (2026-08-21, device) landed
/// immediately after a delete and never before one.
///
/// The fixture nils the cell directly through KVC rather than staging a
/// CloudKit deletion: the defect is the READ, and the route the nil arrived by
/// is not part of it. Staging the real route would need two devices.
///
/// **This test crashes the host against the unfixed code.** That is the
/// reproduction, not the guard — per CLAUDE.md § Test Concurrency, a failure
/// that takes the host down proves nothing about any assertion and buries
/// unrelated suites as collateral. After the fix it passes normally, and what
/// it then guards is that `clear` survives a foreign row it cannot identify.
@MainActor
@Suite(.serialized)
struct NilIdWholeTableReadTests {

    /// The money test: a row with a nil `id` must not stop the export from
    /// copying the rows that ARE readable.
    @Test func exportSurvivesARowWhoseIdCellIsNil() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext

        // A row whose id cell is nil — the shape
        // `shouldDeleteInaccessibleFaults` produces from a vanished record.
        // Voice, so it is inside the export's fetch predicate and genuinely
        // reaches the read under test; an `.image` row would be filtered out
        // before the trap could happen and the test would pass by not looking.
        let foreign = MediaReference(context: ctx)
        foreign.id = UUID()
        foreign.mediaType = MediaReference.MediaType.voice.rawValue
        foreign.osIdentifier = "foreign.m4a"
        foreign.createdAt = Date()
        try storage.save(context: ctx)
        foreign.setValue(nil, forKey: "id")
        #expect(foreign.value(forKey: "id") == nil, "precondition: the cell really is nil")

        // A readable row, so we can prove the export still did its work.
        let seeded = MediaReference(context: ctx)
        seeded.id = UUID(uuidString: "5EED0002-0000-0000-0000-000000000210")!
        seeded.mediaType = MediaReference.MediaType.voice.rawValue
        seeded.osIdentifier = "5EED-qa-000000000210.m4a"
        seeded.createdAt = Date()
        try storage.save(context: ctx)

        // Against a typed-accessor read this line does not fail — it TRAPS.
        let snap = RecordingsExport.snapshot(context: ctx, manifestClips: [])

        // Surviving is necessary; still doing the work is the other half.
        // A `return` on the first odd row would pass a trap test and export
        // nothing, which is the failure this whole feature exists to prevent.
        #expect(
            snap.recordings.contains { $0.id.uuidString.hasPrefix("5EED0002") },
            "the readable recording must still be exported — surviving the nil row is not enough if it stopped working"
        )
        #expect(
            snap.recordings.count == 1,
            "exactly the readable row: the nil-id row is skipped, not counted and not exported"
        )
    }
}

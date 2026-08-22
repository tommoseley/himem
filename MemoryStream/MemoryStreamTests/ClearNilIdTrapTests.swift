import Testing
import Foundation
import CoreData
@testable import HiMem

/// **A whole-table fetch that reads a non-optional `@NSManaged` accessor traps
/// on any row whose cell is nil — and `shouldDeleteInaccessibleFaults` is what
/// makes such a row reachable.**
///
/// `QAFixtureSeeder.clear` fetches EVERY `MediaReference` in the store — the
/// user's real clips, not just the fixtures — and calls `isSeeded(ref.id)`.
/// `isSeeded` takes a non-optional `UUID`, and `MediaReference.id` is declared
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
struct ClearNilIdTrapTests {

    /// The money test: a row with a nil `id` must not stop `clear` from doing
    /// its job, and must not be mistaken for a seeded row either.
    @Test func clearSurvivesARowWhoseIdCellIsNil() throws {
        let storage = StorageService(inMemory: true)
        let ctx = storage.viewContext

        // A foreign row — not seeded, and its id cell is nil. This is the shape
        // `shouldDeleteInaccessibleFaults` produces from a vanished record.
        let foreign = MediaReference(context: ctx)
        foreign.id = UUID()
        foreign.mediaType = MediaReference.MediaType.image.rawValue
        foreign.osIdentifier = "foreign.jpg"
        foreign.createdAt = Date()
        try storage.save(context: ctx)
        foreign.setValue(nil, forKey: "id")
        #expect(foreign.value(forKey: "id") == nil, "precondition: the cell really is nil")

        // A genuinely seeded row, so we can prove clear still did its work.
        let seeded = MediaReference(context: ctx)
        seeded.id = UUID(uuidString: "5EED0002-0000-0000-0000-000000000210")!
        seeded.mediaType = MediaReference.MediaType.image.rawValue
        seeded.osIdentifier = "5EED-qa-000000000210.jpg"
        seeded.createdAt = Date()
        try storage.save(context: ctx)

        // Against the unfixed code this line does not fail — it TRAPS.
        QAFixtureSeeder.clear(in: ctx)

        let remaining = try ctx.fetch(NSFetchRequest<MediaReference>(entityName: "MediaReference"))
        let ids = remaining.compactMap { $0.value(forKey: "id") as? UUID }
        #expect(
            !ids.contains(where: { $0.uuidString.hasPrefix("5EED0002") }),
            "clear must still remove seeded rows — surviving the nil row is not enough if it stopped working"
        )
        #expect(
            remaining.count == 1,
            "the foreign row is not seeded and must be left alone: clear owns 5EED- rows only"
        )
    }
}

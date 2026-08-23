import Testing
import Foundation
import CoreData
@testable import HiMem

/// **The scanner must be provable able to see the thing it looks for.**
///
/// `NilAttributeScan` exists to answer one question on Tom's device — does the
/// store contain a row whose Swift-non-optional attribute is actually nil
/// (Route A) — and the answer that matters most is the *negative* one. A
/// scanner that reports CLEAN by failing to look is the exact shape CLAUDE.md
/// names twice: the `head -8` that produced "no callers exist", and the
/// set-aside scanner that passed its own mutation. So the offender-visible
/// self-test is not optional here; it is the thing that makes a CLEAN reading
/// mean anything.
///
/// **SQLite, not in-memory, and that is load-bearing.** `id == nil` is a NULL
/// predicate, and `StorageService.makeSQLiteTestContainer`'s own doc records
/// that the in-memory store evaluates predicates through Foundation rather than
/// SQL, *"notably a NULL optional Bool under != YES"*. A NULL-predicate scanner
/// verified against a store with different NULL semantics would be verified
/// against the wrong thing.
@Suite(.serialized)
@MainActor
struct NilAttributeScanTests {

    private static func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    @discardableResult
    private static func insertRef(
        into ctx: NSManagedObjectContext,
        nilling attribute: String? = nil
    ) -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.osIdentifier = "scan-fixture.caf"
        ref.createdAt = Date()
        // KVC, because the non-optional accessor cannot express nil — which is
        // the whole defect this scanner is chasing.
        if let attribute { ref.setValue(nil, forKey: attribute) }
        return ref
    }

    /// **The control.** A well-formed store must read CLEAN — otherwise a HIT
    /// carries no information.
    @Test func aWellFormedStoreReadsClean() throws {
        let (container, url) = StorageService.makeSQLiteTestContainer()
        defer { Self.cleanup(url) }
        let ctx = container.viewContext
        Self.insertRef(into: ctx)
        Self.insertRef(into: ctx)
        try ctx.save()

        let result = NilAttributeScan.run(container: container)

        #expect(result.isClean, "a store with two well-formed rows must read CLEAN; got \(result.rows.count) hit(s)")
        #expect(result.totals["MediaReference"] == 2, "the scan must see both rows: got \(String(describing: result.totals["MediaReference"]))")
    }

    /// **The self-test.** Plant the exact offender and prove the scanner sees
    /// it. Without this, CLEAN on the device would be indistinguishable from
    /// a scan that never looked.
    @Test func theScanSeesARowWhoseIdCellIsNil() throws {
        let (container, url) = StorageService.makeSQLiteTestContainer()
        defer { Self.cleanup(url) }
        let ctx = container.viewContext
        Self.insertRef(into: ctx)                    // a healthy neighbour
        Self.insertRef(into: ctx, nilling: "id")     // the offender
        try ctx.save()

        let result = NilAttributeScan.run(container: container)

        #expect(!result.isClean, "the scanner failed to see a planted nil id — a CLEAN reading from it would be worthless")
        let hits = result.rows.filter { $0.entity == "MediaReference" && $0.nilAttribute == "id" }
        #expect(hits.count == 1, "expected exactly one nil-id hit, got \(hits.count)")

        // The Route A / Route B discrimination the device reading turns on:
        // a real persisted row is nil in ONE place with its neighbours intact.
        if let hit = hits.first {
            #expect(hit.allValues["id"] == "nil")
            #expect(hit.allValues["mediaType"] == MediaReference.MediaType.voice.rawValue,
                    "Route A's signature is that the OTHER attributes survive; got \(String(describing: hit.allValues["mediaType"]))")
            #expect(hit.allValues["osIdentifier"] == "scan-fixture.caf")
            #expect(hit.isDeleted == false, "a persisted Route A row is not a deleted object")
        }
    }

    /// The scan covers `mediaType` and `osIdentifier` too — both are read by
    /// non-optional accessors on the every-regroup path (`syntheticClip`,
    /// `benchKind`), so a CLEAN reading must mean clean on all three.
    @Test func theScanSeesANilMediaTypeAndANilOsIdentifier() throws {
        let (container, url) = StorageService.makeSQLiteTestContainer()
        defer { Self.cleanup(url) }
        let ctx = container.viewContext
        Self.insertRef(into: ctx, nilling: "mediaType")
        Self.insertRef(into: ctx, nilling: "osIdentifier")
        try ctx.save()

        let result = NilAttributeScan.run(container: container)

        let attrs = Set(result.rows.map(\.nilAttribute))
        #expect(attrs.contains("mediaType"), "nil mediaType not seen; scanned attrs found: \(attrs)")
        #expect(attrs.contains("osIdentifier"), "nil osIdentifier not seen; scanned attrs found: \(attrs)")
    }

    /// The walk must cover the entities it claims to. If a target is renamed or
    /// dropped, this fails rather than the scan quietly covering less.
    @Test func theScanCoversBothEntitiesAndAllSixAttributes() {
        let byEntity = Dictionary(uniqueKeysWithValues: NilAttributeScan.targets.map { ($0.entity, $0.attributes) })
        #expect(byEntity["MediaReference"] == ["id", "mediaType", "osIdentifier"])
        #expect(byEntity["MemoryClipEdge"] == ["id", "clipId", "memoryId"])
    }
}

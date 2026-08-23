import Testing
import Foundation
import CoreData
@testable import HiMem

/// **What `shouldDeleteInaccessibleFaults` actually does, measured rather than
/// quoted.**
///
/// The 2026-08-21 SIGTRAP root-cause rests on a claim about this flag: that it
/// *"marks the object deleted and NILS OUT EVERY PROPERTY"*, converting a
/// catchable `NSObjectInaccessibleException` into a silently nil-valued object.
/// That claim came from Apple's documentation plus one commit message. **No
/// test in this project had ever observed it**, and the whole provenance
/// discriminator for the trap class depends on it:
///
///   * **Route A** — a row genuinely carrying a nil `id` in the store. A live,
///     non-deleted object. Findable by a predicated `id == nil` fetch.
///   * **Route B** — an inaccessible fault nil'd by this flag. Transient,
///     context-scoped, findable by no query — but `isDeleted` should be `true`
///     on it, and that is the only thing separating the two at a call site.
///
/// If `isDeleted` is *not* set, the discriminator does not work and the
/// declaration fix cannot lean on it. Hence this probe: the assumption becomes
/// a pinned fact instead of a remembered one (CLAUDE.md § Non-Negotiables —
/// *where a rule can be replaced by a mechanism, replace it*).
///
/// **Substrate matters and is chosen deliberately.** `StorageService.init(inMemory:)`
/// sets neither `shouldDeleteInaccessibleFaults` nor `setQueryGenerationFrom`,
/// and the in-memory store evaluates predicates through Foundation rather than
/// SQL (see `makeSQLiteTestContainer`'s own doc). Faulting is a store-level
/// behaviour, so an in-memory store cannot answer this. These use the real
/// SQLite container and set the flag explicitly, mirroring `StorageService:165`.
///
/// **Scenario B is the one that matters**, because production sets *both* the
/// flag and `setQueryGenerationFrom(.current)`. A pinned query generation makes
/// the context read a fixed snapshot, which may mean a row deleted afterwards
/// stays readable and the inaccessible fault never arises at all. If so, Route B
/// is harder to reach on `viewContext` than the root-cause assumed — which
/// would move weight back onto Route A.
@Suite(.serialized)
@MainActor
struct InaccessibleFaultProbeTests {

    /// Builds a SQLite-backed stack, inserts one saved `MediaReference`, and
    /// returns everything needed to stale a fault against it.
    private static func makeStack(
        pinGeneration: Bool
    ) throws -> (container: NSPersistentContainer, url: URL, ref: MediaReference, oid: NSManagedObjectID) {
        let (container, url) = StorageService.makeSQLiteTestContainer()
        let ctx = container.viewContext
        // Mirror StorageService:165 — the production viewContext configuration
        // whose behaviour is under test.
        ctx.shouldDeleteInaccessibleFaults = true
        if pinGeneration {
            try? ctx.setQueryGenerationFrom(.current)
        }

        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = MediaReference.MediaType.voice.rawValue
        ref.osIdentifier = "probe.caf"
        ref.createdAt = Date()
        try ctx.save()

        return (container, url, ref, ref.objectID)
    }

    /// Deletes the row through a *second* context over the same coordinator, so
    /// the first context's cached fault is left pointing at a row that no longer
    /// exists — the situation a CloudKit import deletion produces on device.
    private static func deleteRowElsewhere(
        _ container: NSPersistentContainer,
        _ oid: NSManagedObjectID
    ) throws {
        let other = container.newBackgroundContext()
        var thrown: Error?
        other.performAndWait {
            do {
                let victim = try other.existingObject(with: oid)
                other.delete(victim)
                try other.save()
            } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }

    private static func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix)
            )
        }
    }

    /// **Scenario A — the flag alone, no query-generation pin.**
    ///
    /// This is the configuration the root-cause description assumes. If the
    /// claim holds, firing the stale fault yields an object that is marked
    /// deleted with every property nil.
    @Test func withTheFlagAStaleFaultComesBackDeletedAndNilValued() throws {
        let (container, url, ref, oid) = try Self.makeStack(pinGeneration: false)
        defer { Self.cleanup(url) }
        let ctx = container.viewContext

        // Turn the live object back into a fault so the next property access
        // must go to the store.
        ctx.refresh(ref, mergeChanges: false)
        #expect(ref.isFault, "precondition: the object must be a fault before the row is deleted")

        try Self.deleteRowElsewhere(container, oid)

        // Fire the fault. `value(forKey:)` is used rather than `ref.id` because
        // the non-optional accessor is the thing that TRAPS — reading it here
        // would take the host down and prove nothing (CLAUDE.md § Test
        // Concurrency: a crash is a diagnosis, never an assertion).
        let rawId = ref.value(forKey: "id")
        let rawType = ref.value(forKey: "mediaType")

        #expect(ref.isDeleted,
                "THE DISCRIMINATOR: shouldDeleteInaccessibleFaults must mark the object deleted. If this fails, isDeleted cannot separate Route A from Route B.")
        #expect(rawId == nil, "the flag is documented to nil every property; id came back \(String(describing: rawId))")
        #expect(rawType == nil, "mediaType came back \(String(describing: rawType))")
    }

    /// **Scenario B — the production configuration: flag + pinned generation.
    /// MEASURED 2026-08-22, and it does NOT behave like scenario A.**
    ///
    /// This assertion was written to match scenario A and **failed**. It is not
    /// flipped to go green — the expectation was a hypothesis and the hypothesis
    /// was wrong (CLAUDE.md § *a failing test is a question, not a chore*). What
    /// it now pins is the measurement:
    ///
    /// `StorageService:169` also calls `setQueryGenerationFrom(.current)`, which
    /// pins reads to a snapshot. **With the generation pinned, a row deleted
    /// afterwards stays fully readable from that generation.** The fault never
    /// becomes inaccessible, `shouldDeleteInaccessibleFaults` never fires, and
    /// no nil-valued object arises: observed `isDeleted == false` and
    /// `value(forKey: "id")` returning the original UUID intact.
    ///
    /// **Why this matters beyond curiosity.** The 2026-08-21 SIGTRAP root-cause
    /// named this flag as *"why a nil cell is reachable"*. On the very context
    /// that sets the flag, the pin set four lines later suppresses the mechanism
    /// in this scenario — which moves weight onto the other route (a row
    /// genuinely carrying a nil `id`) and means `isDeleted` cannot serve as the
    /// discriminator between them.
    ///
    /// **Stated limit, and it is the load-bearing one.** This deletes through a
    /// sibling context over the same coordinator. Production deletion arrives by
    /// CloudKit import through `NSPersistentCloudKitContainer` with
    /// `automaticallyMergesChangesFromParent = true` — and a merge may advance
    /// the pinned generation, restoring exactly the behaviour scenario A shows.
    /// This probe does **not** model that path. It narrows the question; it does
    /// not close it.
    @Test func aPinnedQueryGenerationKeepsTheDeletedRowReadable() throws {
        let (container, url, ref, oid) = try Self.makeStack(pinGeneration: true)
        defer { Self.cleanup(url) }
        let ctx = container.viewContext

        ctx.refresh(ref, mergeChanges: false)
        #expect(ref.isFault, "precondition: the object must be a fault before the row is deleted")
        let idBefore = ref.value(forKey: "id") as? UUID

        try Self.deleteRowElsewhere(container, oid)

        let rawId = ref.value(forKey: "id") as? UUID

        #expect(ref.isDeleted == false,
                "the pin suppresses the inaccessible fault; if this ever becomes true, Route B is reachable on viewContext after all and the trap class widens")
        #expect(rawId == idBefore,
                "the row must still read from the pinned generation; got \(String(describing: rawId))")
    }
}

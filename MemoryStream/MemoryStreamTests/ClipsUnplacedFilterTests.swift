import Testing
import Foundation
import CoreData
@testable import HiMem

/// Money test for the `ClipsTabView.newFilterContent:136`
/// `EXC_BREAKPOINT` crash Tom hit 2026-07-12 while tapping around
/// trying to edit one clip from the Clips tab.
///
/// > Thread 1: EXC_BREAKPOINT (code=1, subcode=0x1a0544c20)
/// > in `ClipsTabView.newFilterContent.getter`
/// > → 1 closure #1 in `ClipsTabView.newFilterContent.getter`
///
/// The trapping line was:
///
/// ```swift
/// let visibleUnplaced = unplacedRefs.filter {
///     !absorbedBus.absorbedRefIds.contains($0.id)
/// }
/// ```
///
/// `unplacedRefs` is `@State [MediaReference]` — Swift-strong. The
/// fetch that populates it is debounced 250ms (`unplacedReload`,
/// added task #148 to end main-thread thrash during CloudKit churn).
/// Between a clip's delete (locally via ClipDetail *Delete clip*, or
/// remotely via a CloudKit merge) and the next debounced fetch, the
/// array still holds the now-stale reference. SwiftUI re-renders the
/// parent freely during that window; `$0.id` on an invalidated Core
/// Data fault traps.
///
/// This test:
/// 1. Seeds a MediaReference in an in-memory context.
/// 2. Deletes it and saves — the ref is now `isDeleted`, the store
///    is gone, but the Swift array still points at it.
/// 3. Invokes the filter helper.
/// 4. Expects the deleted ref to be omitted.
///
/// Pre-fix (inline `refs.filter { !absorbed.contains($0.id) }`) would
/// either trap on `.id` (the production crash) or return the deleted
/// ref, meaning `#expect(result.isEmpty)` fails. Post-fix, the helper
/// guards `isDeleted` / detached before touching `.id` and the test
/// passes.
@MainActor
@Suite(.serialized)
struct ClipsUnplacedFilterTests {

    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        let model = NSManagedObjectModel.mergedModel(from: [Bundle.main])!
        let container = NSPersistentContainer(name: "test", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, err in loadError = err }
        if let loadError { throw loadError }
        return container.viewContext
    }

    private func makeRef(in ctx: NSManagedObjectContext, kind: MediaReference.MediaType = .image) throws -> MediaReference {
        let ref = MediaReference(context: ctx)
        ref.id = UUID()
        ref.mediaType = kind.rawValue
        ref.osIdentifier = "asset://test"
        ref.createdAt = Date()
        try ctx.save()
        return ref
    }

    // MARK: - Baseline — live ref stays

    @Test func visible_returns_live_refs_not_in_absorbed_set() throws {
        let ctx = try makeInMemoryContext()
        let a = try makeRef(in: ctx)
        let b = try makeRef(in: ctx)
        let result = ClipsUnplacedFilter.visible(refs: [a, b], absorbed: [])
        #expect(result.count == 2)
    }

    @Test func visible_drops_refs_absorbed_into_a_voice_session() throws {
        let ctx = try makeInMemoryContext()
        let a = try makeRef(in: ctx)
        let b = try makeRef(in: ctx)
        // b is absorbed into a session card; a is loose.
        let result = ClipsUnplacedFilter.visible(refs: [a, b], absorbed: [b.id])
        #expect(result.count == 1)
        #expect(result.first?.id == a.id)
    }

    // MARK: - Money test — the crash guard

    /// A ref that was deleted from Core Data between fetch and render
    /// must be dropped BEFORE the filter reads `.id`. Pre-fix inline
    /// filter would touch `.id` on the deleted ref and either trap or
    /// return the stale row.
    @Test func visible_drops_ref_deleted_from_context_without_touching_id() throws {
        let ctx = try makeInMemoryContext()
        let live = try makeRef(in: ctx)
        let doomed = try makeRef(in: ctx)
        // Simulate the mid-render race: user deletes a clip, Core
        // Data fires objectsDidChange, debounced re-fetch hasn't
        // run yet, SwiftUI re-renders the parent with the stale
        // Swift-strong array still holding the doomed ref.
        let snapshotBeforeDelete = [live, doomed]
        ctx.delete(doomed)
        try ctx.save()
        // The doomed ref is now Core-Data-invalidated. The filter
        // must not touch its `.id` — the guard sits before the
        // `absorbed.contains($0.id)` read.
        let result = ClipsUnplacedFilter.visible(refs: snapshotBeforeDelete, absorbed: [])
        #expect(result.count == 1, "the deleted ref must be omitted")
        // Prove the survivor is the live one (guard against any
        // accidental swap in the filter body).
        #expect(result.first?.id == live.id)
    }

    /// A ref whose Core Data context was torn down (detached — as
    /// happens on a CloudKit merge that removes the record) is also
    /// a `.id`-access trap. The guard covers both `isDeleted` and
    /// `managedObjectContext == nil`.
    @Test func visible_drops_ref_whose_context_was_reset() throws {
        let ctx = try makeInMemoryContext()
        let live = try makeRef(in: ctx)
        let detached = try makeRef(in: ctx)
        let snapshot = [live, detached]
        // Delete + save + refresh(mergeChanges: false) is the closest
        // reliable stand-in for CloudKit's "row went away under us"
        // invalidation. After this, `detached.managedObjectContext`
        // may still be non-nil (Core Data leniency), but `isDeleted`
        // is set — either guard catches it.
        ctx.delete(detached)
        try ctx.save()
        ctx.refresh(detached, mergeChanges: false)
        let result = ClipsUnplacedFilter.visible(refs: snapshot, absorbed: [])
        #expect(result.count == 1)
        #expect(result.first?.id == live.id)
    }
}

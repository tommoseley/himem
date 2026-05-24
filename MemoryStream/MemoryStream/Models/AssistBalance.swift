import Foundation
import CoreData

/// Single-row entity that holds a user's pricing state: tier, monthly AI
/// consumption, never-expiring pack balance, and starter-grant bookkeeping.
///
/// One record per Apple ID, CloudKit-synced via the private DB so:
///   • Reinstalls preserve the pack balance (consumable IAP terms in App
///     Store's eyes, but persistent in the user's eyes — the count goes
///     across reinstalls so packs feel like they "never expire")
///   • Multiple devices stay in lockstep (iPhone and iPad pull from the
///     same record)
///   • Future family sharing remains per-seat (each Apple ID has its own
///     record; pooling is a separate post-MVP decision)
///
/// Adding this entity requires a CloudKit schema deploy from the Dashboard
/// before the next TestFlight build (per `CLAUDE.md` — outbound sync silently
/// breaks otherwise).
@objc(AssistBalance)
public class AssistBalance: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var tier: String
    @NSManaged public var monthlyUsed: Int32
    @NSManaged public var packBalance: Int32
    @NSManaged public var starterUsed: Int32
    @NSManaged public var starterGranted: Bool
    /// One-time Project Assist starter grant — separate bucket from
    /// the 3 starter memory assists so projects don't feel like
    /// they're stealing from capture. Granted lazily on the first
    /// Project Assist tap by a Free user; consumed on the same tap.
    /// Per `docs/design/projects-mvp-spec.md` (Projects MVP, 2026-05).
    @NSManaged public var starterProjectAssistGranted: Bool
    /// Set to true once the Free user has spent their one starter
    /// Project Assist. After this, the second tap routes to the
    /// upsell sheet.
    @NSManaged public var starterProjectAssistUsed: Bool
    @NSManaged public var monthlyResetDate: Date?
    @NSManaged public var foundersBonusGranted: Bool
    /// User-set guardrail: auto-organize only fires while
    /// `totalAssistsRemaining > autoOrganizeThreshold`. 0 = auto-org
    /// uses everything; bigger numbers reserve more for manual taps.
    /// Settable in Settings → Your AI (Plus / Founders only — Free
    /// has no auto-org to gate).
    @NSManaged public var autoOrganizeThreshold: Int32
    @NSManaged public var lastUpdated: Date?
}

extension AssistBalance {
    static func fetchSingleton() -> NSFetchRequest<AssistBalance> {
        let request = NSFetchRequest<AssistBalance>(entityName: "AssistBalance")
        request.fetchLimit = 1
        return request
    }
}

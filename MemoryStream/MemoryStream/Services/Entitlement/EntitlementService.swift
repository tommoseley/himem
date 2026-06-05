import Foundation
import Combine
import CoreData

/// Single source of truth for HiMem's pricing state.
///
/// Views read `@Published` properties; consumption sites call
/// `tryConsumeAssist()`. The actual state lives in a CloudKit-synced
/// `AssistBalance` Core Data record (one row per Apple ID).
///
/// **Never** read the Core Data record directly from a view. Routing
/// everything through this service keeps the entitlement contract honest
/// and lets us swap the storage layer (CloudKit → server ledger, etc.)
/// without touching views.
///
/// Spec: `docs/design/pricing-model.md`.
@MainActor
final class EntitlementService: ObservableObject {
    static let shared = EntitlementService()

    // MARK: - Tier

    enum Tier: String {
        case free
        case plusMonthly = "plus_monthly"
        case plusYearly = "plus_yearly"
        case founders
    }

    @Published private(set) var tier: Tier = .free

    /// Used + remaining counts. All views observe these for their copy.
    @Published private(set) var monthlyUsed: Int = 0
    @Published private(set) var packBalance: Int = 0
    @Published private(set) var starterUsed: Int = 0
    @Published private(set) var monthlyResetDate: Date?

    /// Single-time grants — exposed for diagnostics and onboarding gates.
    @Published private(set) var starterGranted: Bool = false
    @Published private(set) var foundersBonusGranted: Bool = false
    /// Project Assist starter state (Free tier). The starter is one
    /// silent run, distinct from the 3 starter memory assists — the
    /// design rationale being that projects shouldn't feel like
    /// they're stealing from capture. Granted lazily on the user's
    /// first Project Assist attempt and consumed in the same call.
    @Published private(set) var starterProjectAssistUsed: Bool = false

    /// User-set guardrail for auto-organize. Plus / Founders auto-org
    /// only fires while `totalAssistsRemaining > autoOrganizeThreshold`.
    /// Default `0` matches the original "auto-org runs while any
    /// assists remain" behavior. The user changes this from
    /// Settings → Your AI (slider 0…monthlyAllowance).
    @Published private(set) var autoOrganizeThreshold: Int = 0

    /// Overlay state: the user is paying the voluntary Supporter
    /// subscription. Composes with any tier — a Plus + Supporter user
    /// sees both their plan and a small "You support HiMem" card. A
    /// Founder is never marked as Supporter because Founders includes
    /// everything Supporter would acknowledge.
    ///
    /// Storage is deferred to v1.1 along with the Supporter SKU
    /// purchase flow. This property currently reads from the debug
    /// override so the tier-aware UI can be wired and previewed; once
    /// the real SKU ships, replace with a StoreKit current-entitlements
    /// lookup for `com.himem.supporter.monthly` or `.yearly`.
    @Published var isSupporter: Bool = false

    // MARK: - Derived

    /// `50` for Plus/Founders, `0` for Free. The fair-use cap *is* the
    /// allowance — there is no hidden ceiling above it.
    var monthlyAllowance: Int {
        switch tier {
        case .free: return 0
        case .plusMonthly, .plusYearly, .founders: return 50
        }
    }

    var monthlyRemaining: Int { max(0, monthlyAllowance - monthlyUsed) }

    /// Free users' starter assists fold into the pack balance display.
    /// Spec rule: starter is granted once into `packBalance` then drawn
    /// from like any other pack assist. We still track `starterUsed` for
    /// the 3+5 upgrade-prompt trigger.
    var starterRemaining: Int { max(0, EntitlementService.starterTotal - starterUsed) }

    /// Total assists the user can still consume right now.
    var totalAssistsRemaining: Int { monthlyRemaining + packBalance }

    var isPlus: Bool {
        switch tier {
        case .plusMonthly, .plusYearly, .founders: return true
        case .free: return false
        }
    }

    var isFounders: Bool { tier == .founders }

    // MARK: - UI state cues (pure properties — driven by entitlement
    // values only, so tests can verify them without rendering. Each
    // corresponds to a beat in `docs/Pricing · QA test script.md`.)

    /// True when Free + exactly 1 spendable assist remaining. Drives
    /// the warn-color `1 LEFT · FREE` caption under the `1 ASSIST`
    /// pill on the idle Organize card (QA script A2).
    var showsOneLeftFreeCue: Bool {
        !isPlus && totalAssistsRemaining == 1
    }

    /// True when Plus has drained the monthly bucket and is now
    /// drawing from a purchased pack. Drives the `from your pack`
    /// micro-caption (QA script C5). False when monthly still has
    /// capacity even if pack > 0 (monthly drains first).
    var showsFromYourPackCaption: Bool {
        isPlus && monthlyRemaining == 0 && packBalance > 0
    }

    /// True for a free user at zero spendable assists. Drives the
    /// bundle sheet timestamp fallback + "Get AI title · 1 assist →"
    /// affordance (QA script A4).
    var isFreeNoAssists: Bool {
        !isPlus && totalAssistsRemaining == 0
    }

    static let starterTotal: Int = 3

    // MARK: - State

    enum ConsumeError: Error {
        case insufficient
    }

    /// Non-destructive precheck: would `tryConsumeAssist()` succeed
    /// right now? Callers gate the API call on this BEFORE invoking
    /// the AI pipeline. The actual decrement happens after a
    /// successful pass (per v2 pricing rule — failures cost zero).
    ///
    /// Manual organize-with-AI taps use this — manual taps are never
    /// gated by `autoOrganizeThreshold`. The threshold only affects
    /// the silent auto-org path.
    var canConsumeAssist: Bool {
        monthlyRemaining > 0 || packBalance > 0
    }

    /// Project Assist precheck: would the next Project Assist tap
    /// fire (silently or via paid bucket), or should it route to the
    /// upsell sheet? Three rules ordered by tier:
    ///
    ///   • Plus / Founders → consumes from the monthly/pack bucket,
    ///     same as memory assists. Available whenever `canConsumeAssist`.
    ///   • Free, starter not yet spent → silent run permitted; the
    ///     starter is the user's one taste.
    ///   • Free, starter spent → blocked. Caller routes to upsell.
    var canConsumeProjectAssist: Bool {
        if isPlus { return canConsumeAssist }
        return !starterProjectAssistUsed
    }

    /// Auto-organize precheck. Tier-gated **and** budget-gated:
    ///
    /// 1. **Free is always manual-only** per AI Organize spec § 9 and
    ///    pricing spec § 2 (`Idle (ambient hint + Organize)`). The 3
    ///    starter assists are tasted by an explicit user tap on the
    ///    Organize card — never silently burned by an auto-pass. Tom
    ///    saw the auto-burn happen 2026-05-27; this guard kills it.
    /// 2. **Plus / Founders auto-runs** consult the user's reserved-
    ///    for-manual threshold. At default `0` it's equivalent to
    ///    `canConsumeAssist` (auto-org uses everything until the
    ///    well is dry). When the user pulls the slider up, auto-org
    ///    pauses earlier; at `threshold >= totalAssistsRemaining` it
    ///    never fires.
    var canAutoOrganize: Bool {
        isPlus && totalAssistsRemaining > autoOrganizeThreshold
    }

    // MARK: - Storage

    private let storage: StorageService
    private var balanceRecord: AssistBalance?

    /// Debug-only override so the dev team isn't forced into Free state
    /// during development. Reads from UserDefaults. NEVER consulted in
    /// release builds.
    #if DEBUG
    @Published var developerOverrideTier: Tier? {
        didSet {
            UserDefaults.standard.set(developerOverrideTier?.rawValue, forKey: Keys.devOverride)
            recomputePublished()
        }
    }
    #endif

    private enum Keys {
        static let devOverride = "entitlement.developerOverrideTier"
    }

    // MARK: - Init

    init(storage: StorageService = .shared) {
        self.storage = storage
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: Keys.devOverride),
           let t = Tier(rawValue: raw) {
            self.developerOverrideTier = t
        }
        #endif
        loadOrCreate()
        resetMonthlyIfDue()
    }

    // MARK: - Public API

    /// Attempts to consume one assist. Drains monthly allowance first
    /// (for Plus/Founders), then packs. Throws `.insufficient` when
    /// everything is empty. Callers should branch on the throw to surface
    /// the hard-100% inline panel or pack-purchase sheet.
    func tryConsumeAssist() throws {
        if monthlyRemaining > 0 {
            mutate { $0.monthlyUsed += 1 }
            return
        }
        if packBalance > 0 {
            mutate { $0.packBalance -= 1 }
            // Track free-user starter consumption so the 3+5 upgrade
            // prompt knows when the starter is spent. Starter assists
            // live inside packBalance (granted once on first use); the
            // separate `starterUsed` counter is the trigger signal.
            if tier == .free, starterUsed < EntitlementService.starterTotal {
                mutate { $0.starterUsed += 1 }
            }
            return
        }
        throw ConsumeError.insufficient
    }

    /// Grants the one-time Free starter assists. Idempotent: subsequent
    /// calls do nothing once `starterGranted` is true.
    func grantStarterIfNeeded() {
        guard !starterGranted else { return }
        mutate {
            $0.starterGranted = true
            $0.packBalance += Int32(EntitlementService.starterTotal)
        }
    }

    /// Attempts to consume one Project Assist. Drains the monthly /
    /// pack bucket for Plus / Founders. For Free, spends the one-time
    /// starter (silent first run); after that, throws `.insufficient`
    /// so the caller can present the upsell sheet.
    ///
    /// Idempotent gate via `canConsumeProjectAssist` — production
    /// callers check before invoking.
    func tryConsumeProjectAssist() throws {
        if isPlus {
            try tryConsumeAssist()
            return
        }
        if !starterProjectAssistUsed {
            mutate {
                $0.starterProjectAssistUsed = true
            }
            return
        }
        throw ConsumeError.insufficient
    }

    /// Adds the Founders one-time bonus to pack balance. Idempotent.
    /// Called from StoreKitService on `founders_lifetime` purchase.
    func grantFoundersBonusIfNeeded() {
        guard !foundersBonusGranted else { return }
        mutate {
            $0.foundersBonusGranted = true
            $0.packBalance += 100
        }
    }

    /// Adds a purchased AI pack to balance. Pack assists never expire.
    func grantPack(size: Int) {
        guard size > 0 else { return }
        mutate { $0.packBalance += Int32(size) }
    }

    /// Updates tier from StoreKit transaction state. Source of truth for
    /// tier is StoreKit's `Transaction.currentEntitlements`; this method
    /// just persists the resolved state.
    func setTier(_ newTier: Tier) {
        mutate { $0.tier = newTier.rawValue }
    }

    /// Persists the user's auto-organize threshold (Settings → Your AI
    /// slider). Clamped to `[0, monthlyAllowance]` so the UI never
    /// stores nonsense; Free users (allowance 0) can write a 0 but
    /// the gate has no effect since they never auto-org anyway.
    func setAutoOrganizeThreshold(_ value: Int) {
        let clamped = max(0, min(monthlyAllowance, value))
        mutate { $0.autoOrganizeThreshold = Int32(clamped) }
    }

    /// Resets monthly allowance if the reset date has elapsed. Called on
    /// init and on scene-active.
    func resetMonthlyIfDue() {
        let now = Date()
        if let resetDate = monthlyResetDate, now < resetDate { return }
        mutate {
            $0.monthlyUsed = 0
            $0.monthlyResetDate = Self.nextResetDate(from: now)
        }
    }

    // MARK: - Internals

    /// Loads the singleton AssistBalance record, or creates it if missing.
    private func loadOrCreate() {
        let ctx = storage.viewContext
        let req = AssistBalance.fetchSingleton()
        let existing: AssistBalance?
        do {
            existing = try ctx.fetch(req).first
        } catch {
            // Fetch failure on this query means the Core Data stack
            // is in a corrupt state (the predicate is fixed, the
            // entity exists in the model). We can't recover: the
            // money ledger is unreachable, and silently creating a
            // fresh zero-balance record on top of an unfetchable
            // existing one would compound the corruption. Crash
            // loudly so the failure is visible in launch logs
            // rather than invisible debit-loss in production.
            fatalError("[HiMem][Pricing] AssistBalance fetch failed — Core Data store is corrupt: \(error)")
        }
        if let existing {
            balanceRecord = existing
        } else {
            let new = AssistBalance(context: ctx)
            new.id = UUID()
            new.tier = Tier.free.rawValue
            new.monthlyUsed = 0
            new.packBalance = 0
            new.starterUsed = 0
            new.starterGranted = false
            new.starterProjectAssistGranted = false
            new.starterProjectAssistUsed = false
            new.foundersBonusGranted = false
            new.autoOrganizeThreshold = 0
            new.monthlyResetDate = Self.nextResetDate(from: Date())
            new.lastUpdated = Date()
            do {
                try ctx.save()
            } catch {
                NSLog("[HiMem][Pricing] AssistBalance initial save failed: \(error.localizedDescription) — in-memory record published but not persisted; next mutation will retry the save")
            }
            balanceRecord = new
        }
        recomputePublished()
    }

    /// Applies `block` to the AssistBalance record, persists, and
    /// republishes derived state.
    private func mutate(_ block: (AssistBalance) -> Void) {
        guard let record = balanceRecord else { return }
        block(record)
        record.lastUpdated = Date()
        do {
            try storage.viewContext.save()
        } catch {
            // Save failure leaves the in-memory record dirty (the
            // block ran, the fields changed) but not persisted. We
            // re-publish the derived state anyway so the UI matches
            // the in-memory record; the next mutation will attempt
            // the save again and either succeed (transient HAL /
            // disk hiccup) or fail the same way (persistent). The
            // alternative — reverting the in-memory mutation mid-
            // flight — is itself a mutation that needs to persist,
            // and would require undoing the `block` we can't
            // introspect. Logging loudly is the honest middle path.
            NSLog("[HiMem][Pricing] AssistBalance mutate save failed: \(error.localizedDescription) — in-memory record advanced; next save will retry")
        }
        recomputePublished()
    }

    /// Republishes derived properties from the Core Data record + dev
    /// override. Views observing this service get the new state via
    /// `@Published`.
    private func recomputePublished() {
        guard let record = balanceRecord else { return }
        #if DEBUG
        if let override = developerOverrideTier {
            tier = override
        } else {
            tier = Tier(rawValue: record.tier) ?? .free
        }
        #else
        tier = Tier(rawValue: record.tier) ?? .free
        #endif
        monthlyUsed = Int(record.monthlyUsed)
        packBalance = Int(record.packBalance)
        starterUsed = Int(record.starterUsed)
        monthlyResetDate = record.monthlyResetDate
        starterGranted = record.starterGranted
        starterProjectAssistUsed = record.starterProjectAssistUsed
        foundersBonusGranted = record.foundersBonusGranted
        autoOrganizeThreshold = Int(record.autoOrganizeThreshold)
    }

    // MARK: - Debug helpers (DEBUG only)

    #if DEBUG
    /// Sets `monthlyUsed` directly. For dev only — production paths go
    /// through `tryConsumeAssist()`.
    func debugSetMonthlyUsed(_ value: Int) {
        mutate { $0.monthlyUsed = Int32(max(0, value)) }
    }

    /// Sets `packBalance` directly to the given value.
    func debugSetPackBalance(_ value: Int) {
        mutate { $0.packBalance = Int32(max(0, value)) }
    }

    /// Sets `starterUsed` directly.
    func debugSetStarterUsed(_ value: Int) {
        mutate { $0.starterUsed = Int32(max(0, min(EntitlementService.starterTotal, value))) }
    }

    /// Flips the `starterGranted` flag. Pair with `debugSetPackBalance`
    /// when fully resetting starter state.
    func debugSetStarterGranted(_ granted: Bool) {
        mutate { $0.starterGranted = granted }
    }

    /// Flips the `starterProjectAssistUsed` flag for testing the
    /// "second Find the thread tap routes to upsell" path. Use this
    /// to toggle the Free user between "starter available" and
    /// "starter spent."
    func debugSetStarterProjectAssistUsed(_ used: Bool) {
        mutate { $0.starterProjectAssistUsed = used }
    }

    /// Flips the `foundersBonusGranted` flag. Use when testing
    /// idempotency of the Founders bonus grant.
    func debugSetFoundersBonusGranted(_ granted: Bool) {
        mutate { $0.foundersBonusGranted = granted }
    }

    /// Bypasses the clamp on `setAutoOrganizeThreshold` so test scrubs
    /// can dial it past the allowance ceiling without the production
    /// guard rejecting the value.
    func debugSetAutoOrganizeThreshold(_ value: Int) {
        mutate { $0.autoOrganizeThreshold = Int32(max(0, value)) }
    }

    /// Wipes every entitlement counter back to defaults: Free tier,
    /// no starter granted, zero pack balance, zero monthly used. Use
    /// when you want to replay the entire onboarding/conversion flow.
    func debugResetAll() {
        mutate {
            $0.tier = Tier.free.rawValue
            $0.monthlyUsed = 0
            $0.packBalance = 0
            $0.starterUsed = 0
            $0.starterGranted = false
            $0.foundersBonusGranted = false
            $0.autoOrganizeThreshold = 0
            $0.monthlyResetDate = Self.nextResetDate(from: Date())
        }
        developerOverrideTier = nil
    }
    #endif

    // MARK: - Reset date math

    /// Returns the first second of the calendar month following `now`.
    /// All consumption counters reset at that boundary. Locale-sensitive
    /// (the user's calendar drives the boundary, not UTC).
    static func nextResetDate(from now: Date) -> Date {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: now)
        guard let startOfThisMonth = cal.date(from: components),
              let startOfNextMonth = cal.date(byAdding: .month, value: 1, to: startOfThisMonth) else {
            return now.addingTimeInterval(60 * 60 * 24 * 30)
        }
        return startOfNextMonth
    }
}

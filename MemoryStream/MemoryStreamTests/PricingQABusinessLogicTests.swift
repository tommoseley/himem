import Testing
import Foundation
@testable import HiMem

/// **Suite 1: Business logic tests** for the pricing surfaces.
///
/// Per Tom's 2026-05-28 architectural call: everything checked here
/// is **non-UX**. Inputs are entitlement state — tier, monthly used,
/// pack balance, starter used, etc. Outputs are the business
/// signals the UI consumes (`totalAssistsRemaining`,
/// `canConsumeAssist`, `canAutoOrganize`, the `OrganizeCardState`
/// resolver outputs, the cue/caption boolean conditions). Whether
/// the UX represents these signals correctly is a separate test
/// suite (Suite 2 — view rendering).
///
/// Each test maps to a beat in `docs/Pricing · QA test script.md`,
/// labeled in the test name. Together this suite covers Parts A,
/// C, D, G (the pure-logic subset) without rendering anything.
@MainActor
@Suite(.serialized)
struct PricingQABusinessLogicTests {

    /// Snapshot + restore so the singleton can't leak between tests.
    @MainActor
    private final class EntitlementSnapshot {
        let priorTier: EntitlementService.Tier
        let priorMonthlyUsed: Int
        let priorPack: Int
        let priorStarter: Int
        let priorStarterGranted: Bool
        let priorStarterProjectAssistUsed: Bool
        let priorFoundersBonus: Bool
        let priorThreshold: Int
        let priorSupporter: Bool

        init() {
            let e = EntitlementService.shared
            priorTier = e.tier
            priorMonthlyUsed = e.monthlyUsed
            priorPack = e.packBalance
            priorStarter = e.starterUsed
            priorStarterGranted = e.starterGranted
            priorStarterProjectAssistUsed = e.starterProjectAssistUsed
            priorFoundersBonus = e.foundersBonusGranted
            priorThreshold = e.autoOrganizeThreshold
            priorSupporter = e.isSupporter
        }

        func restore() {
            let e = EntitlementService.shared
            e.setTier(priorTier)
            e.debugSetMonthlyUsed(priorMonthlyUsed)
            e.debugSetPackBalance(priorPack)
            e.debugSetStarterUsed(priorStarter)
            e.debugSetStarterGranted(priorStarterGranted)
            e.debugSetStarterProjectAssistUsed(priorStarterProjectAssistUsed)
            e.debugSetFoundersBonusGranted(priorFoundersBonus)
            e.debugSetAutoOrganizeThreshold(priorThreshold)
            e.isSupporter = priorSupporter
        }
    }

    /// Builds a fresh entitlement state from named inputs. Mirrors
    /// the QA script's `Set:` lines so tests read 1:1 with the
    /// script. Leaves any unspecified field at the entitlement's
    /// current value.
    @MainActor
    private static func configure(
        tier: EntitlementService.Tier? = nil,
        monthlyUsed: Int? = nil,
        packBalance: Int? = nil,
        starterUsed: Int? = nil,
        starterProjectAssistUsed: Bool? = nil,
        autoOrganizeThreshold: Int? = nil
    ) {
        let e = EntitlementService.shared
        if let tier { e.setTier(tier) }
        if let monthlyUsed { e.debugSetMonthlyUsed(monthlyUsed) }
        if let packBalance { e.debugSetPackBalance(packBalance) }
        if let starterUsed { e.debugSetStarterUsed(starterUsed) }
        if let starterProjectAssistUsed {
            e.debugSetStarterProjectAssistUsed(starterProjectAssistUsed)
        }
        if let autoOrganizeThreshold {
            e.debugSetAutoOrganizeThreshold(autoOrganizeThreshold)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Part A · Free starter assist lifecycle
    // ─────────────────────────────────────────────────────────────

    @Test func a1_freshFreeUser_threeOfThree() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, monthlyUsed: 0, packBalance: 3, starterUsed: 0)
        let e = EntitlementService.shared

        #expect(e.isPlus == false)
        #expect(e.totalAssistsRemaining == 3)
        #expect(e.canConsumeAssist == true)
        // Urgency cue is OFF — 3 left, not 1.
        #expect(e.showsOneLeftFreeCue == false)
        // Free has no monthly bucket draining; auto-org is gated by
        // tier regardless of budget.
        #expect(e.canAutoOrganize == false)
        // State machine: idle card.
        let state = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        if case .idle = state { } else { Issue.record("expected .idle, got \(state)") }
    }

    @Test func a2_oneAssistRemaining_urgencyCueFires() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, packBalance: 1, starterUsed: 2)
        let e = EntitlementService.shared

        #expect(e.totalAssistsRemaining == 1)
        #expect(e.canConsumeAssist == true)
        // The signal the urgency cue listens for.
        #expect(e.showsOneLeftFreeCue == true)
    }

    @Test func a3_starterExhausted_freeVariantResolves() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, packBalance: 0, starterUsed: 3)
        let e = EntitlementService.shared

        #expect(e.totalAssistsRemaining == 0)
        #expect(e.canConsumeAssist == false)
        #expect(e.isFreeNoAssists == true)
        // Exhausted card variant resolves to free (driving the
        // STARTER USED pill + "Your 3 free starter assists are
        // spent…" body + Upgrade Hub route).
        let state = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        #expect(state == .exhausted(.freeExhausted))
        // Stale variant resolves the same way (F3 invariant — the
        // pill must read identically on idle and reorganize cards).
        let stale = OrganizeCardState.staleVariant(
            canRefresh: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        #expect(stale == .freeExhausted)
    }

    @Test func a4_bundleSheetFallbackCondition() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, packBalance: 0, starterUsed: 3)
        let e = EntitlementService.shared
        // The exact boolean that drives the timestamp pre-fill +
        // "Get AI title · 1 assist →" affordance.
        #expect(e.isFreeNoAssists == true)
    }

    // ─────────────────────────────────────────────────────────────
    // Part C · Plus included-assist lifecycle
    // ─────────────────────────────────────────────────────────────

    @Test func c1_plusFreshMonth_fullAllowance() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusMonthly, monthlyUsed: 0, packBalance: 0)
        let e = EntitlementService.shared

        #expect(e.isPlus == true)
        #expect(e.monthlyRemaining == 50)
        #expect(e.totalAssistsRemaining == 50)
        #expect(e.canConsumeAssist == true)
        #expect(e.canAutoOrganize == true)
        #expect(e.showsOneLeftFreeCue == false)        // Plus never sees it.
        #expect(e.showsFromYourPackCaption == false)   // Monthly has capacity.
    }

    @Test func c2_midMonth_thirteenLeft() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusMonthly, monthlyUsed: 37, packBalance: 0)
        let e = EntitlementService.shared

        #expect(e.monthlyRemaining == 13)
        #expect(e.totalAssistsRemaining == 13)
        #expect(e.canConsumeAssist == true)
    }

    @Test func c3_plusExhaustedNoPack_plusVariantResolves() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusMonthly, monthlyUsed: 50, packBalance: 0)
        let e = EntitlementService.shared

        #expect(e.totalAssistsRemaining == 0)
        #expect(e.canConsumeAssist == false)
        #expect(e.canAutoOrganize == false)
        #expect(e.isFreeNoAssists == false)            // Plus, not Free.
        // Exhausted card resolves to plus variant — driving the
        // MONTHLY USED pill + "This month's 50 assists are used…"
        // body + AIPackPurchaseSheet route.
        let state = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        if case .exhausted(.plusExhausted) = state {
        } else {
            Issue.record("expected .exhausted(.plusExhausted), got \(state)")
        }
        let stale = OrganizeCardState.staleVariant(
            canRefresh: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        if case .plusExhausted = stale {
        } else {
            Issue.record("expected .plusExhausted, got \(stale)")
        }
    }

    @Test func c5_packPurchased_fromPackCueFires() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusMonthly, monthlyUsed: 50, packBalance: 100)
        let e = EntitlementService.shared

        #expect(e.monthlyRemaining == 0)
        #expect(e.packBalance == 100)
        #expect(e.totalAssistsRemaining == 100)
        #expect(e.canConsumeAssist == true)
        #expect(e.canAutoOrganize == true)
        // The signal the "from your pack" micro-caption listens for.
        #expect(e.showsFromYourPackCaption == true)
        // State resolves back to idle (not exhausted) — total
        // remaining is positive so the card is active.
        let state = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        if case .idle = state { } else { Issue.record("expected .idle, got \(state)") }
    }

    @Test func c6_packAfterRollover_noFromPackCue() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusMonthly, monthlyUsed: 0, packBalance: 100)
        let e = EntitlementService.shared

        #expect(e.monthlyRemaining == 50)
        #expect(e.packBalance == 100)
        #expect(e.totalAssistsRemaining == 150)
        // Monthly drains first. No "from your pack" caption while
        // monthly has capacity — the next consume will pull from
        // monthly, not pack.
        #expect(e.showsFromYourPackCaption == false)
    }

    // ─────────────────────────────────────────────────────────────
    // Part D · Tier variants
    // ─────────────────────────────────────────────────────────────

    @Test func d1_plusYearly_behavesLikePlusMonthly() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusYearly, monthlyUsed: 25, packBalance: 0)
        let e = EntitlementService.shared

        #expect(e.isPlus == true)
        #expect(e.monthlyRemaining == 25)
        #expect(e.canConsumeAssist == true)
        // Stale variant on yearly Plus is the same plus-exhausted
        // shape (not freeExhausted) when budget is dry — yearly is
        // still Plus.
        e.debugSetMonthlyUsed(50)
        let stale = OrganizeCardState.staleVariant(
            canRefresh: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        if case .plusExhausted = stale { } else {
            Issue.record("expected .plusExhausted for yearly, got \(stale)")
        }
    }

    @Test func d2_foundersLifetime_isPlusAndAutoOrganizes() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .founders, monthlyUsed: 0, packBalance: 0)
        let e = EntitlementService.shared

        #expect(e.isPlus == true)
        #expect(e.isFounders == true)
        #expect(e.canAutoOrganize == true)
        // Founders never sees the Free starter pill — the variant
        // resolver maps to plus on exhaustion.
        e.debugSetMonthlyUsed(50)
        let stale = OrganizeCardState.staleVariant(
            canRefresh: e.canConsumeAssist,
            isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate
        )
        if case .plusExhausted = stale { } else {
            Issue.record("expected .plusExhausted for Founders, got \(stale)")
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Part G · Project Assist · starter + paywall
    // ─────────────────────────────────────────────────────────────

    @Test func g1_freeStarterAvailable_canConsume() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, starterProjectAssistUsed: false)
        let e = EntitlementService.shared

        #expect(e.canConsumeProjectAssist == true)
    }

    @Test func g2_freeStarterUsed_cannotConsume_routesUpsell() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, starterProjectAssistUsed: true)
        let e = EntitlementService.shared

        // Returns false — view layer reads this signal and presents
        // ProjectAssistUpsellSheet.
        #expect(e.canConsumeProjectAssist == false)
    }

    @Test func g3a_plusUser_starterFlagIrrelevant() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(
            tier: .plusMonthly,
            monthlyUsed: 0,
            packBalance: 0,
            starterProjectAssistUsed: true
        )
        let e = EntitlementService.shared

        // Plus pays from monthly; starter flag doesn't gate.
        #expect(e.canConsumeProjectAssist == true)
    }

    @Test func g3b_plusUserExhausted_cannotConsumeProjectAssist() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .plusMonthly, monthlyUsed: 50, packBalance: 0)
        let e = EntitlementService.shared

        // Plus + no budget → blocked from Project Assist too.
        #expect(e.canConsumeProjectAssist == false)
    }

    // ─────────────────────────────────────────────────────────────
    // F-invariants — derived assertions that hold across A–G
    // ─────────────────────────────────────────────────────────────

    /// F3 invariant codified: the pill must read identically on the
    /// idle exhausted card and the stale reorganize card. Loop
    /// every (tier, budget) combination producing exhaustion and
    /// confirm the resolvers agree.
    @Test func fInvariant_pillSwap_idleAndStaleAgree() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }

        // Free exhausted
        Self.configure(tier: .free, packBalance: 0, starterUsed: 3)
        var e = EntitlementService.shared
        var idle = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist, isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate)
        var stale = OrganizeCardState.staleVariant(
            canRefresh: e.canConsumeAssist, isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate)
        #expect(idle == .exhausted(.freeExhausted))
        #expect(stale == .freeExhausted)

        // Plus exhausted
        Self.configure(tier: .plusMonthly, monthlyUsed: 50, packBalance: 0)
        e = EntitlementService.shared
        idle = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist, isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate)
        stale = OrganizeCardState.staleVariant(
            canRefresh: e.canConsumeAssist, isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate)
        if case .exhausted(.plusExhausted) = idle { } else {
            Issue.record("Plus idle expected .exhausted(.plusExhausted), got \(idle)")
        }
        if case .plusExhausted = stale { } else {
            Issue.record("Plus stale expected .plusExhausted, got \(stale)")
        }

        // Founders exhausted (rare but possible)
        Self.configure(tier: .founders, monthlyUsed: 50, packBalance: 0)
        e = EntitlementService.shared
        idle = OrganizeCardState.idleOrExhausted(
            hasAssists: e.canConsumeAssist, isPlus: e.isPlus,
            monthlyResetDate: e.monthlyResetDate)
        if case .exhausted(.plusExhausted) = idle { } else {
            Issue.record("Founders idle expected .exhausted(.plusExhausted), got \(idle)")
        }
    }

    /// F5 invariant: Free users see no pack — `canConsumeAssist`
    /// for Free with starterUsed=3 and packBalance=0 is false even
    /// if someone accidentally set monthly used to a non-50 value
    /// (which Free shouldn't have anyway). Defensive.
    @Test func fInvariant_freeUserAtBudgetCap_neverConsumes() {
        let snap = EntitlementSnapshot(); defer { snap.restore() }
        Self.configure(tier: .free, monthlyUsed: 49, packBalance: 0, starterUsed: 3)
        let e = EntitlementService.shared

        #expect(e.canConsumeAssist == false)
        #expect(e.canAutoOrganize == false)
        #expect(e.isFreeNoAssists == true)
    }
}

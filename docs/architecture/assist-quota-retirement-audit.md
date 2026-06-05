# Assist-quota retirement · code audit

**Status:** Audit, June 5 2026. Inventory of every consumer of the assist-quota machinery, organized as the retirement cutover plan. Companion to `foundation-models-spike-findings.md` and the locked `docs/design/Pricing model · Capture-Connect-Create.md`.

**Outcome:** the retirement PR can work against this doc directly. Each item lists the action (delete / reshape / keep), the consumers, and what gates the deletion (must-replace-first or safe-to-remove).

---

## 1 · Core service layer

### `EntitlementService.shared`

**Decision: delete after cutover.** 21 external consumers across 19 files; 14 distinct methods.

| Method consumed | Replacement |
|---|---|
| `.tier` (Tier enum: `.free / .plusMonthly / .plusYearly / .founders`) | New `EntitlementProvider.isPlus: Bool` — single boolean, no Founders/Supporter |
| `.isPlus` | Same — `EntitlementProvider.isPlus` |
| `.isSupporter` | Delete — Supporter tier retired |
| `.tryConsumeAssist()` | Delete — no metering in new model |
| `.tryConsumeProjectAssist()` | Delete — Project Assist becomes a Plus-only capability, no debit |
| `.canConsumeProjectAssist` | Delete |
| `.canAutoOrganize` | Replaced by `isPlus` (auto-organize-on-capture is the Plus differentiator) |
| `.grantStarterIfNeeded()` | Delete — starter retired |
| `.grantFoundersBonusIfNeeded()` | Delete — Founders retired |
| `.grantPack()` | Delete — packs retired |
| `.resetMonthlyIfDue()` | Delete — monthly counter retired |
| `.setTier()` | Delete — replaced by StoreKit-driven `isPlus` |
| `.starterGranted`, `.starterUsed`, `.starterProjectAssistUsed`, `.starterRemaining` | Delete — starter retired |

**Consumers (read for each: how many call-sites need to be removed or rewritten):**

| File | Lines touched | Action after cutover |
|---|---:|---|
| `Services/Entitlement/EntitlementService.swift` | (self) | **DELETE** |
| `Services/Entitlement/StoreKitService.swift` | 12 | Reshape — keep, simplify |
| `Services/Processing/ProcessingEngine.swift` | 7 | Remove debit path (lines 36, 54, 186) |
| `Services/Projects/ProjectAssistViewModel.swift` | 2 | Reshape (Project Assist becomes Plus-gated, no debit) |
| `Services/Storage/EntryLifecycleService.swift` | 1 | Remove entitlement read |
| `Services/Entitlement/TenureTracker.swift` | 1 | **DELETE the whole file** |
| `App/HiMemShortcuts.swift` | 1 | Remove entitlement gating |
| `App/MemoryStreamApp.swift` | 2 | Remove init reference + warmup comment |
| `Views/Launch/LaunchScreenView.swift` | 6 | Remove migration sequence step that loads AssistBalance |
| `Views/Components/SettingsView.swift` | 1 | Replace tier display with simplified Plus/Not-Plus |
| `Views/Journal/EntryExpandedView.swift` | 3 | Remove inline assist UI gating |
| `Views/Journal/JournalView.swift` | 1 | Remove header tier dot |
| `Views/Projects/ProjectListView.swift` | 1 | Replace with `isPlus` check |
| `Views/Projects/ProjectDetailView.swift` | 1 | Replace with `isPlus` check |
| `Views/Inbox/CreateMemoryFromClipsSheet.swift` | 1 | Remove entitlement gating |
| `Views/Pricing/UpgradePromptSheet.swift` | 2 | **File deleted** |
| `Views/Pricing/UpgradeHubView.swift` | 1 | **File deleted** |
| `Views/Pricing/Soft75Banner.swift` | 1 | **File deleted** |
| `Views/Pricing/YourAIView.swift` | 1 | **File deleted** |
| `Views/Pricing/AISuggestionsCard.swift` | 2 | Rewrite as new chip/review surface |
| `Views/Pricing/OrganizeMemorySection.swift` | 1 | Reshape for Free manual / Plus auto |
| `Views/Pricing/OnboardingStarterCard.swift` | 2 | **File deleted** |
| `Views/Pricing/DebugPricingPanel.swift` | 5 | **File deleted** |
| `Views/Pricing/TierMark.swift` | 1 | Simplify to Plus marker only |

**Gating constraint:** `tryConsumeAssist()` is wired into `ProcessingEngine`'s post-success block. The Organizer abstraction (Job 2) must absorb its position before the function disappears, or organize stops working on Free.

---

### `AssistBalance` Core Data entity

**Decision: delete after cutover, with CloudKit schema ceremony.**

**Fields removed:**

```
id, tier, monthlyUsed, packBalance,
starterUsed, starterGranted,
starterProjectAssistGranted, starterProjectAssistUsed,
monthlyResetDate, foundersBonusGranted,
autoOrganizeThreshold, lastUpdated
```

**Files affected by deletion:**

| File | Status |
|---|---|
| `Models/AssistBalance.swift` | **DELETE** |
| `Models/MemoryStream.xcdatamodel/contents` | Remove `<entity name="AssistBalance">` block + all 12 attributes |
| `Services/Entitlement/EntitlementService.swift` | Deleted with EntitlementService itself (lines 9, 179, 312-377 reference it) |
| `App/MemoryStreamApp.swift:215` | Remove comment about the AssistBalance record |
| `Views/Launch/LaunchScreenView.swift:82, 234` | Remove comments + the migration step that touches AssistBalance |

**🚨 CloudKit Schema Changes ceremony (per `~/dev/himem/CLAUDE.md`)** — non-negotiable for the production sync to keep working after this PR ships:

1. Make the schema edit + remove `@NSManaged` properties.
2. Build Debug on a real device — `initializeCloudKitSchema(options:)` auto-pushes the new (smaller) schema to **Development** CloudKit.
3. Open https://icloud.developer.apple.com/dashboard/, container `iCloud.com.himem.app`, confirm the entity is gone from **Development**.
4. Click **Deploy Schema Changes** — review diff — deploy to **Production**.
5. Only then archive and upload to TestFlight.

**Symptom of skipping:** outbound sync silently breaks; local edits save and never propagate to other devices.

---

### `FoundersCounter.swift`

**Decision: DELETE.** Founders tier is retired. Only consumer is `EntitlementService` itself (deleted) and a CloudKit container call (also deleted). No external impact.

---

### `TenureTracker.swift`

**Decision: DELETE.** Tenure tracking was for Supporter trust-period gating. Retired.

---

### `ProjectAssistGate.swift`

**Decision: DELETE.** Project Assist gating logic moves to a simple `isPlus` check at the call site (Plus-only feature).

---

### `OrganizeCardState.swift`

**Decision: investigate then likely DELETE.** Enumerated tier-aware states like `.freeExhausted`, `.plusExhausted`. The new chip state machine is two states (`Draft organized` / `Organized`) tied to `OrganizePass.reviewed`, not tier. Most callers move directly off this state machine.

---

## 2 · The Pricing views directory (`Views/Pricing/`)

20 files. Reshape pass on the few that survive; delete the rest.

### Keep & reshape (5 files)

| File | Why kept | Reshape |
|---|---|---|
| `OrganizedChip.swift` (2 ext) | Chip rendering primitive | Reshape: `.draftOrganized` (review-state `false`) vs `.organized` (review-state `true`). Tracks `OrganizePass.reviewed`, not tier. |
| `OrganizeMemorySection.swift` (3 ext) | The Memory Detail "Organize this memory" surface | Reshape per `docs/design/pricing-screens-lifecycle.jsx`: Free shows manual Organize button; Plus auto-runs and shows the post-organize chip. |
| `OrganizeMemoryCard.swift` (3 ext) | The central organize-review card on Memory Detail | Heavy rewrite: remove tier-aware states (`.freeExhausted`, `.plusExhausted`, `STARTER USED`, `MONTHLY USED`); add the B2 dashed chip / B1 review-sheet copy from the new design. |
| `TierMark.swift` (3 ext) | Small tier indicator glyph | Simplify to "Plus" vs absent; remove Founders/Supporter variants. |
| `LegacyInferenceCardSlot.swift` (1 ext) | Bridges pre-v2 entries (no `OrganizePass`) to the legacy inline-inference flow | **Keep until** every pre-v2 entry has been touched and migrated — then delete. (`EntryExpandedView.swift:658` is the one external use.) |

### Delete outright (15 files)

| File | External refs | Why retired |
|---|---:|---|
| `AISuggestionsCard.swift` | 6 | 48 KB monster — assist-debited review UI; replaced by the new chip + review-sheet flow |
| `AIPackPurchaseSheet.swift` | 5 | Packs retired |
| `UpgradePromptSheet.swift` | 3 (+ `UpgradePromptCoordinator` singleton) | Replaced by C1 once-ever after-a-glance trigger |
| `UpgradeHubView.swift` | 7 | Replaced by new `PricingView` (Job 3) |
| `Soft75Banner.swift` | 1 (JournalView header) | Soft 75% banner retired |
| `YourAIView.swift` | 1 | Assist-counter Settings view — retired |
| `OnboardingStarterCard.swift` | 2 | Starter assist retired |
| `ProjectAssistUpsellSheet.swift` | 1 | Replaced by C1-style upsell at the Find-the-thread surface |
| `ProjectCapSheet.swift` | 4 | Replaced by the simple "3 reached" nudge (Job 2) |
| `FoundersDetailView.swift` | 2 | Founders tier retired |
| `SupporterDetailView.swift` | 2 | Supporter tier retired |
| `DebugPricingPanel.swift` | 5 (internal debug menu) | Debug surface for retired machinery |
| `PricingPrimitives.swift` | 0 | Primitives for retired model |
| `OrganizedSection.swift` | 0 | Unused |
| `FABWithCardSuppression.swift` | 1 | Compositional helper — likely retired with the FAB stack rework; verify before deletion |

---

## 3 · `OrganizePass.nextStepsMarkdown`

**Decision: remove from on-device schema; reintroduce as Plus-only field in Job 4.**

**Storage:** `Models/OrganizePass.swift:36` — `@NSManaged public var nextStepsMarkdown: String?`

**Consumers to retire alongside:**

| File | Lines | Action |
|---|---:|---|
| `Models/OrganizePass.swift` | 36, 139-148 | Delete the field + the `nextStepsItems` convenience parser |
| `Services/Processing/ProcessingEngine.swift` | 446, 451, 455 | Stop writing nextSteps in the on-device path |
| `Views/Pricing/OrganizedChip.swift` | 62, 67, 117 | Remove the `nextStepsCount` rendering variant |
| `Views/Pricing/AISuggestionsCard.swift` | 140, 147, 191, 206, 260, 265, 723-724, 805, 883 | File deleted entirely |

**CloudKit schema ceremony** required (same dance as AssistBalance removal — schema edit → Development → Production deploy → TestFlight). Bundle both schema changes in the same deploy to minimize ceremony overhead.

---

## 4 · `ProcessingEngine` debit path

**Decision: replace with the Organizer protocol (Job 2).**

**Current shape:**
```swift
consumeAssist: @escaping @MainActor () throws -> Void = {
    try EntitlementService.shared.tryConsumeAssist()
}
```

**Post-cutover shape:** `ProcessingEngine` either:
- (a) becomes one of the `Organizer` protocol implementations (call it `ServerOrganizer` if it stays as the Plus-tier frontier path), or
- (b) is refactored entirely into the new `Organizer` abstraction with the existing logic split into `OnDeviceOrganizer` + `ServerOrganizer`.

The `consumeAssist` parameter goes away. The post-success error-log block (line 186) goes away. Job 4 reintroduces the routing-to-frontier decision at the call site (entitlement + network state).

---

## 5 · `ProjectCapPolicy.swift`

**Decision: bump from 1 → 3 in Job 2; keep otherwise.** Only one external consumer (`ProjectListView.swift:122-124`).

```diff
- /// 1 active project (per `docs/design/pricing-model.md`).
+ /// 3 active projects (per `Pricing model · Capture-Connect-Create.md` §4).
```

Plus the cap value itself inside the enum (need to grep for the exact constant when making the edit).

---

## 6 · StoreKit pack-purchase paths

**Decision: simplify in Job 1.** Keep `StoreKitService` (it'll gate Plus); strip the pack-purchase surface.

`Services/Entitlement/StoreKitService.swift` — surgical cuts:

| Line | Concern | Action |
|---|---|---|
| 14 | Doc comment about `purchase(_:)` | Update for subscription-only |
| 85 | `func purchase(_ product: Product)` | Keep — but only the subscription path |
| 87 | `try await product.purchase()` | Keep — same StoreKit primitive |
| 135-137, 163 | `switch transaction.productID` — handles both subscription & pack | Remove the pack case |

Plus: remove every consumer of `AIPackPurchaseSheet.swift` (5 callers, retired with the file).

**Open question for the user before the PR:** are there any real users with consumable IAP purchases (packs) that need refund accounting? Per my memory of the project state (IAP setup blocked on Paid Apps Agreement / tax / banking), there should be **zero**. Verify before cutting the pack-handler code.

---

## 7 · Tests to update or delete (9 files)

| File | Status after cutover |
|---|---|
| `CostReportingAPITests.swift` | Likely **delete** — assist-pack cost reporting retired |
| `PricingQABusinessLogicTests.swift` | **delete** — assist-quota business logic retired |
| `PricingQAInvariantsTests.swift` | **delete** — same |
| `PricingV5DecisionTests.swift` | **delete** — assist-decision-tree from v5 |
| `ProcessingEngineAssistDebitTests.swift` | **delete** — debit path retired |
| `ProcessingEngineFallbackTests.swift` | Keep — but rework: tests fallback behavior, not assist gating |
| `ProjectAssistViewModelTests.swift` | Rework — Project Assist becomes Plus-gated, no debit |
| `ProjectsMVPTests.swift` | Update — bump project cap to 3 |
| `TopicRejectionTests.swift` | Spot-check — likely unaffected but worth a scan |

---

## 8 · Suggested PR shape for the retirement (Job 1)

This is too large for one PR. Recommended sequence (each its own PR):

### 8a · "Wire OnDeviceOrganizer behind a debug flag" (Job 2.1 — prep, no retirement)

- Add `import FoundationModels`.
- Port iter-5 prompt + `@Generable OrganizeOutput` from the spike.
- Define `Organizer` protocol; implement `OnDeviceOrganizer`.
- Wrap existing `ProcessingEngine` flow as a second `Organizer` implementation (`ServerOrganizer`).
- Add routing: entitlement + network check → which organizer.
- Behind a DEBUG-only `UserDefaults` flag — production still runs the old assist-debited path.
- Smoke test on simulator.

**No deletions.** Sets up the replacement.

### 8b · "Bump ProjectCapPolicy from 1 → 3" (Job 2.3)

Tiny PR, low risk. Lifts the free tier benefit and lays groundwork for the upgrade nudge.

### 8c · "Memory Detail chip state machine: Draft organized / Organized" (Job 2.2)

Reshape `OrganizedChip`, `OrganizeMemorySection`, `OrganizeMemoryCard` per the new design. Drops the tier-aware exhausted states (`STARTER USED`, `MONTHLY USED`). Free path now shows the manual Organize button; Plus path auto-runs.

**Still uses the old `EntitlementService.isPlus` for the Plus/Free split** — actual `EntitlementService` removal comes in 8e.

### 8d · "Reset Pricing surface — delete the obviously-retired views" (Job 1, phase 1)

Pure deletions, no logic changes:
- `AIPackPurchaseSheet.swift`, `UpgradePromptSheet.swift`, `UpgradeHubView.swift`, `Soft75Banner.swift`, `YourAIView.swift`, `OnboardingStarterCard.swift`, `ProjectAssistUpsellSheet.swift`, `ProjectCapSheet.swift`, `FoundersDetailView.swift`, `SupporterDetailView.swift`, `DebugPricingPanel.swift`, `PricingPrimitives.swift`, `OrganizedSection.swift`, `AISuggestionsCard.swift`.
- Remove every external reference (the audit above lists every callsite).
- Delete the corresponding tests (4 of the 9 test files).
- After: `Views/Pricing/` should contain only `OrganizedChip`, `OrganizeMemorySection`, `OrganizeMemoryCard`, `TierMark`, `LegacyInferenceCardSlot`.

### 8e · "Retire the assist-quota machinery + CloudKit schema deploy" (Job 1, phase 2)

The structural deletion + schema change. Single PR for atomicity:
- Flip the OnDeviceOrganizer flag default to true.
- Delete `EntitlementService`, `FoundersCounter`, `TenureTracker`, `ProjectAssistGate`, `OrganizeCardState` (the last after verifying no surviving uses).
- Delete `AssistBalance.swift`.
- Remove `AssistBalance` from the Core Data model + matching `@NSManaged` properties.
- Remove `nextStepsMarkdown` from `OrganizePass` + `nextStepsItems` parser.
- Strip pack-purchase paths from `StoreKitService` (keep subscription).
- Remove the debit hook from `ProcessingEngine`.
- Delete the remaining test files / rework the keepers.
- **CloudKit schema deploy:** Development → Production before the next TestFlight.

This is the "schema PR." Treat it carefully.

### 8f · "New PricingView" (Job 3) — separate concern, follows 8e

---

## 9 · What we are NOT doing in Job 1

- **Plus tier features.** Job 4. The retirement leaves `isPlus` accessible (via the new `EntitlementProvider`) but the actual Plus features (mention extraction, related memories, project suggestions, auto-organize-on-capture) don't ship in Job 1.
- **The new pricing canvas surface.** Job 3. The retirement leaves a temporary gap where the "Upgrade" path opens nothing — Job 3 fills it. In between, Settings shows a simple "Manage subscription via Apple ID" affordance.
- **Anthropic backend integration.** Job 4. `ServerOrganizer` continues to run the existing Claude path until Job 4 reworks it as `FrontierOrganizer` with the Plus prompt.

---

## Cross-reference

- `docs/architecture/foundation-models-spike-findings.md` — locked iter-5 prompt + `OrganizeOutput` Generable to port.
- `docs/design/Pricing model · Capture-Connect-Create.md` — locked pricing direction.
- `docs/design/AI Organize · spec.md` — chip-as-review-state, Free=editable-draft, Plus offline-grace.
- `~/dev/himem/CLAUDE.md` — CloudKit Schema Changes governance (non-negotiable for AssistBalance + nextStepsMarkdown removal).

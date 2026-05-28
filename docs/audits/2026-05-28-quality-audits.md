# Quality Audit Suite — 2026-05-28

_Codebase has roughly doubled since 2026-05-09: 141 production Swift files / 27,748 lines (was 75 / 15,152). 409 tests passing in `MemoryStreamTests`. Run after the three pre-launch checkpoint commits (`b82bc2b`, `4f53d4e`, `8c5f938`)._

---

## 1. Dead Code Audit

**Status: FINDINGS (3 markers, otherwise clean)**

Three new `// TODO` markers found; all other dead-code categories remain clean.

| Item | File:Line | Type |
|------|-----------|------|
| `// TODO: route to global search prefiltered to …` | `CreateMemoryFromClipsSheet.swift:69` | Incomplete TODO (UI flow planning) |
| `// TODO: invoke project assist (summary + suggestions)` | `ProjectDetailView.swift:300` | Feature flag (Project Assist post-MVP wiring) |
| Doc reference to `UIApplication.applicationIconBadgeNumber` | `InboxManifest.swift:229` | Documentation reference to deprecated API (not actual usage) |

All other dead-code categories remain clean:

- **`@Published` / `@State` unused:** No orphaned properties found in sampled files.
- **Placeholder files:** Only `TopicSlugHelper.swift` (9 lines) — verified to be a legitimate utility enum, not a stub.
- **`@NSManaged` orphans:** `audioFilePath` remains CloudKit-bound (documented in prior audits); no other fields truly orphaned.
- **Empty extensions:** None found.
- **Commented-out code blocks:** Extensive `// MARK` and doc comments present (300+ lines across files), but no commented-out *functional* code blocks (>5 lines) detected.

---

## 2. Dependency Audit

**Status: CLEAN**

- **Third-party packages:** Zero SPM, Podfile, or Cartfile dependencies — confirmed.
- **New frameworks since 2026-05-09:** `StoreKit` (3 imports, fully utilized; see breakdown). `StoreKitTest` not currently imported (was added briefly in the SKTestSession attempt; cleanly reverted).
- **Unused imports:** None detected across sampled files.

| Framework | Imports | Notable Use |
|-----------|---------|------------|
| SwiftUI | 61 | UI rendering (every view) |
| Foundation | 60 | Core APIs (every model + service) |
| CoreData | 36 | Persistence + CloudKit sync |
| AVFoundation | 13 | Audio capture + playback (SpeechService, AudioPlayerService, VoiceCaptureScreen) |
| UIKit | 9 | Photo pickers, orientation lock, application lifecycle |
| Combine | 7 | `@Published` bindings, debounce (JournalViewModel) |
| UserNotifications | 6 | Clip arrival + reminder notifications |
| Photos | 6 | Library integration (AlbumSyncService) |
| CoreLocation | 5 | Geotag capture + reverse geocoding |
| **StoreKit** | **3** | **Product loading, transaction verification via `Transaction.verify()` (NEW adoption)** |
| Speech | 2 | SpeechTranscriber (on-device transcription) |
| NaturalLanguage | 2 | Entity extraction locale handling |
| CryptoKit | 2 | Hash generation (EntryMapper) |
| CloudKit | 2 | Schema bootstrap (DEBUG only) |
| AuthenticationServices | 2 | Sign-in with Apple |
| AppIntents | 2 | Siri Shortcuts intent mapping |
| AVKit | 1 | Video playback shell (MediaViewerView) |
| Network | 1 | Connectivity gate (JournalViewModel) |
| Security | 1 | Keychain API (KeychainService) |
| WatchConnectivity | 1 | Watch clip sync (WatchSessionDelegate) |
| UniformTypeIdentifiers | 1 | Media type constants |
| PhotosUI | 1 | Modern photo picker (CameraPickerView) |

**StoreKit 2 adoption (NEW since 2026-05-09):** `StoreKitService.swift` imports StoreKit 2 only. No legacy `SKPaymentQueue` or receipt-blob fetching. Verified flow:

- `Product.products(for:)` loads SKUs (line 69)
- `product.purchase()` initiates the sheet (line 87)
- `VerificationResult<Transaction>` checked via `checkVerified()` — throws on `.unverified` (lines 186–191)
- `Transaction.currentEntitlements` walked at startup for subscription reconciliation (line 132)

---

## 3. Security Audit

**Status: FINDINGS (4 medium / low — same shape as 2026-05-09)**

| Category | Verdict | Note |
|----------|---------|------|
| Hardcoded secrets | CLEAN | No API keys, Bearer tokens, or embedded credentials. ClaudeAPIService auth via backend. |
| Keychain accessibility | CLEAN | All SecItem calls use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (KeychainService.swift:35). |
| Network | CLEAN | All HTTPS. No ATS exceptions. Standard cert validation. |
| Logging / PII | FINDINGS | See table below — UUID-format filenames still in NSLog. |
| Permissions | FINDINGS | `NSRemindersUsageDescription` still declared without EventKit usage. |
| 3rd-party data flow | CLEAN | Claude API, epigraphs over HTTPS; no embedded tokens. |
| CloudKit sensitivity | CLEAN | Entry content intentionally synced; no credentials stored in entities. |
| WebView / URL injection | CLEAN | No WKWebView or SFSafariViewController. `UIApplication.open()` calls use hardcoded HTTPS URLs / settings intents; no user-controlled input. |
| StoreKit receipt validation | CLEAN | On-device JWS via `Transaction.verify()`. No legacy receipt-blob path. Per HiMem memory, server-side validation is intentionally deferred until post-launch. |

| Finding | File:Line | Severity | Description |
|---------|-----------|----------|-------------|
| Audio filename in NSLog | `TranscriptionService.swift:84` | MEDIUM | Logs `audioURL.lastPathComponent`. UUID-format filename (low PII risk), but could reduce to duration + locale only. (Was line 76 in prior audit; line drift from file growth, content unchanged.) |
| Audio filename in NSLog | `SpeechService.swift:284` | MEDIUM | Logs `filename` on audio file creation. Same UUID-based format. |
| Loose `print()` in error paths | `AlbumSyncService.swift:116` | LOW | One remaining `print()` in error catch. Route through `ErrorState.shared.report` instead. |
| Loose `print()` in error paths | `AudioPlayerService.swift:29, 56` | LOW | Two `print()` calls on audio-file-not-found / playback failure. Route through `ErrorState.shared.report`. |
| Declared-but-unused permission | `project.pbxproj` (NSRemindersUsageDescription) | MEDIUM | Still declared; still no `EventKit` / `EKEventStore` usage found in source. Per Reminders integration memory, the feature is intentionally post-MVP — strip the key from `Info.plist` until then, or App Review will ask why. |

**Prior audit items — status:**

- `NSRemindersUsageDescription` — **still open** (carried from 2026-05-09).
- `TranscriptionService.swift:76` audio filename — **still present** (now line 84 due to file growth).
- `SpeechService.swift:128` + `AlbumSyncService.swift:116` `print()` — **still present**; `SpeechService` line 284 also logs filename. `AudioPlayerService` adds two new sites (lines 29, 56).

---

## 4. Accessibility Audit

**Status: FINDINGS (persistent patterns; minor growth from new pricing/voice surfaces)**

| Category | Severity | Count | Notes |
|----------|----------|-------|-------|
| Icon-only buttons w/o `.accessibilityLabel` | HIGH | 95+ | SettingsView (18), EntryExpandedView (13), UpgradeHubView (7), AISuggestionsCard (5). New pricing surfaces inherit the pattern. Some `chevron.right` are decorative and don't need a label. |
| Hardcoded `.system(size:)` (no Dynamic Type) | HIGH | 321 | UpgradeHubView (32), AISuggestionsCard (26), YourAIView (21), VoiceCaptureScreen (16). New pricing tier is the primary contributor. Intentional `.system(size:, design: .serif)` on project titles + voice composer wordmark is NOT flagged — that's per the "no `.font(.custom)` for unbundled fonts" rule and is the correct iOS New York fallback. |
| Tap targets < 44×44 pt | MEDIUM | 26+ | Watch app media dots (6×6, 3×3), watch pending-list checkmarks (28×28), watch recording-timer dots (7×7), phone media-type dots in EntryCardView (8×8). Several are essential for recognition but below WCAG AA. |
| Low-contrast interactive text | CLEAN | — | No tappable text below 0.4 opacity. |
| Missing `.accessibilityHint` on swipe / long-press | MEDIUM | 6 (same as 2026-05-09) | JournalView trailing swipe (delete/move), ChronologicalCaptureStream swipes (4 sites), ProjectListView trailing swipe. Only `AppendFAB` has a hint. |
| Missing semantic grouping on cards | LOW | 2 (improved from 3) | EntryCardView, ChronologicalCaptureStream pills lack `.accessibilityElement(children: .combine)`. SettingsView now has the modifier on at least one site. |
| Unlabeled placeholder images | LOW | 1 | `MediaThumbnailView:19` uses `Image(systemName: "photo.slash")` but the parent Button (`:41`) now has an `.accessibilityLabel`. `MediaViewerView` `.accessibilityHidden` checks look correct. |

**Net vs 2026-05-09:** the codebase doubled in size but accessibility gaps grew sub-linearly. The new pricing surfaces (UpgradeHub, AISuggestionsCard, OrganizeMemoryCard, OrganizedChip, ProjectAssistUpsellSheet) and the rewritten VoiceCaptureScreen inherit the same hardcoded-font + unlabeled-icon patterns from older surfaces — no new violation classes introduced. **Remediation status: still deferred** (consistent with prior audit's call).

---

## 5. Performance Audit

**Status: PRIOR ITEMS LARGELY FIXED, NO NEW REGRESSIONS**

### Fixed since 2026-05-09

| Issue | Status | Evidence |
|-------|--------|----------|
| `JournalView.groupedEntries` in body | FIXED | Moved to `JournalViewModel.recomputeFiltered`, called on observed changes. |
| Pagination via NotificationCenter debounce | FIXED | In place; `JournalViewModel.observeStorageChanges` controls re-compute frequency. |
| `@StateObject` wrapping singletons | FIXED | All views now use `@ObservedObject var name = Service.shared`. No `@StateObject(.shared)` found. |
| `FileManager.fileExists(atPath:)` in view bodies | PARTIALLY FIXED | Still present at `SessionListView:676`, `CreateMemoryFromClipsSheet:536/628`, `VoiceCaptureScreen:889`, `ProjectDetailView:537` — but **all are in `.onAppear`, init completion, or playback-action handlers**, not in `body` render. Previously flagged HIGH; current usage is acceptable. |
| `AVAudioSession.setActive` coordination | FIXED | `AudioPlayerService:35/66`, `SpeechService:259/407`, `MediaViewerView:65/87` all gate on state changes with proper `.notifyOthersOnDeactivation`. No churn detected. |
| `ClipInboxView.grouped()` per-render recompute | RESOLVED | `ClipInboxView` no longer exists; inbox surfaces moved to `SessionListView` + `CreateMemoryFromClipsSheet`, neither of which has the per-render `grouped()` pattern. |
| `EntryCardView.smartTags` re-filter per render | Still present | Substring match per render; negligible per row but multiplicative across feed. Low severity. |

### Open

| Issue | File:Line(s) | Severity | Status |
|-------|---|----------|--------|
| `Project.fetchAll()` has no `fetchLimit` | `Project.swift:52`, `ProjectViewModel.swift:31` | MEDIUM | Unbounded fetch, but projects are few (typically < 50 lifetime). Not in hot path (loaded on ProjectListView init, not scrolling). Consider defensive `fetchLimit = 1000`. |
| `DateFormatter()` constructed in compute functions | `JournalView:297`, `SessionListView:179/182/264`, `ChronologicalCaptureStream:246-258`, etc. | LOW | 14+ inline DateFormatter instances. Cache as `@State` or `static let`. Minor cost per instance but multiplicative across nested views. |

**No new HIGH-severity findings.** The codebase doubled in size without introducing new synchronous main-thread blocking patterns in hot paths. Watch video-compression tests show fast turnaround (5.2s in test). No new unbounded `NSFetchRequest` sites.

---

## 6. Test Coverage Audit

**Status: STRONG GROWTH (134 → 409 tests, +2.05×)**

- **Test run:** 409 tests passing, 19 `@Suite` blocks across 38 logical suites (includes watch + phone)
- **Duration:** 5.3 seconds end-to-end on iPhone 17 Simulator / iOS 26.4
- **Framework:** Swift Testing (`@Test`, `@Suite`, `#expect`)
- **All tests:** green

### New suites since 2026-05-09

| Suite | Coverage |
|-------|----------|
| `PricingQABusinessLogicTests` | 17 tests — entitlement state machine, assist budgets, free→plus→founders tier transitions |
| `PricingQAInvariantsTests` | 9 tests — cross-cutting lints (no `$` on Memory Detail surfaces, AI color discipline, voice spec banned phrases) |
| `PricingV5DecisionTests` | 36 tests — `OrganizeCardState` resolver, chip state logic, stale entry flow, project assist gate |
| `VoiceComposerBreathRotationTests` | breath caption rotation, roll-group ID consistency, next-clip offsets |
| `WatchClipIdempotencyTests` | watch clip arrival idempotency under rapid sync |
| `InboxManifestTranscriptionPreservesRollGroupIdTests` | inbox transcription preserves roll group ID through processing |
| `SingleClipPushGateTests` | push-notification threshold for single-clip entries |

### Coverage now spans

`EntryLifecycleService` (edit/delete/recycle/restore + media-ref deletion), `JournalViewModel` (append flows + voice fragments), `SearchEngine` (text/topic/type/date scope, snippet, recycled), `JournalEntry` (title derivation), `ProjectDetailView` (share-text composition), `EntryDisplayStatus`, `EntryHeaderRow`, `PlacemarkFormatter`, `SearchViewModelBucket`, `ScopeParser`, `ProcessingEngineFallback`, `FragmentMigration` (resurrection prevention + content dedup), `AudioCompressor` (compression ratio + transcription roundtrip), all pricing surfaces above, watch clip arrival + transcription.

### Gap candidates (known, deferred)

| Gap | Files | Notes |
|-----|-------|-------|
| StoreKit boundary | `StoreKitService.swift` | `SKTestSession` integration attempted 2026-05-28 and abandoned cleanly — `SKInternalErrorDomain Code=3` in this Xcode 26.4 / iOS 26.4 simulator combo blocked product loading. Documented in `project_iap_setup_gated.md` memory. Post-ASC review with real sandbox accounts. |
| FoundersCounter (CloudKit) | `FoundersCounter.swift` | CloudKit-backed counter hard to unit-test without live account. Logic tested indirectly via Pricing suites (counter state as input). |
| WatchSessionDelegate / WatchTransferService | `WatchSessionDelegate.swift`, `WatchTransferService.swift` | WCSession mocking complex; watch sync exercised end-to-end via `WatchClipIdempotencyTests` and `WatchClipArrivalTranscriptionTests`. Direct delegate unit tests deferred. |
| Tier sub-services | `ProjectAssistGate.swift`, `ProjectCapPolicy.swift`, `TenureTracker.swift` | No dedicated unit tests; behavior tested as inputs to PricingQA suites. Logic is deterministic (queries + comparisons). |

### Informed gaps (intentionally deferred per spec)

- **Pricing Suite 2 (view rendering):** view-binding tests deferred per Tom's 2026-05-28 call. Human QA covers the surface during final QA; revisit post-launch when pricing tweaks create real regression risk.
- **Pricing Suite 3 (StoreKit integration):** see StoreKit gap above.

---

## Remediation Priority

| # | Bucket | Effort | Notes |
|---|--------|--------|-------|
| 1 | Security: strip `NSRemindersUsageDescription` (or wire the Reminders integration) | 30 min | App Review will ask; integration is post-MVP per memory, so strip until then |
| 2 | Security: silence `TranscriptionService.swift:84` + `SpeechService.swift:284` filename logs; route `AlbumSyncService`, `AudioPlayerService` errors through `ErrorState.shared.report` | 1 h | Low-effort hygiene; closes the 2026-05-09 carryover |
| 3 | CRAP Batch 1: decompose `JournalView.body` — extract `JournalMemoriesView`, `JournalBannerStack`, `JournalErrorToasts` | 5-6 h | Lone smelly-function violation; see CRAP audit |
| 4 | CRAP Batch 3: split `EntryLifecycleService` — extract `EntryQueryService` | 3-4 h | Prevents 850+ line god-service trajectory |
| 5 | Accessibility pass: icon labels + Dynamic Type for top 3 surfaces (JournalView, EntryExpandedView, UpgradeHubView) | 6-8 h | High user impact, no architectural change |
| 6 | Cache `DateFormatter()` instances + cap `Project.fetchAll()` | 1 h | Pure hygiene; minor performance headroom |
| 7 | Post-ASC: revisit StoreKit integration tests with real sandbox accounts | TBD | Documented in `project_iap_setup_gated.md` memory |

---

_Audit run 2026-05-28 after the pre-launch checkpoint commits (`b82bc2b`, `4f53d4e`, `8c5f938`). Companion document: `2026-05-28-crap-audit.md`._

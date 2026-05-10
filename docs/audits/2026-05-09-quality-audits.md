# Quality Audit Suite — 2026-05-09

_Codebase has roughly doubled since 2026-04-18: 75 Swift files / 15,152 lines (was 46 / 6,800). 134 tests passing in `MemoryStreamTests`._

---

## 1. Dead Code Audit

**Status: CLEAN**

Phase 5 cleanup landed earlier this session and removed the last legacy field reads (`audioFilePath` in display layer, `TextSegmentDisplayItem`, `discardAudio`, `cleanUpText`/`isCleaningUp`, `createTextSegment`).

| Item | Action |
|------|--------|
| `EntryDisplayModel.audioFilePath` / `textSegments` fields | Removed |
| `TextSegmentDisplayItem` struct | Removed |
| `EntryExpandedView.editedText` / `cleanUpText` / `isCleaningUp` / `discardAudio` | Removed |
| `EntryLifecycleService.edit(discardAudio:)` parameter | Removed |
| `StorageService.createTextSegment` | Removed |
| `audioFilePath` parameter on save/append → renamed `voiceFilename` | Renamed |
| `Himem Watch Watch App/ContentView.swift` placeholder | Intentionally retained (group validity); not dead |

**Retained on purpose:** `JournalEntry.audioFilePath` `@NSManaged` slot + `TextSegment` Core Data class — CloudKit-bound schema; only `FragmentMigration.swift` is allowed to read them. No other consumers found.

No `// TODO`, `// FIXME`, or "remove later" markers in the codebase.

---

## 2. Dependency Audit

**Status: CLEAN**

- Zero third-party packages (no SPM, Podfile, Cartfile, Package.swift)
- 19 Apple frameworks imported across 75 files; all sampled and confirmed actively used
- No unused imports detected

| Framework | Notable Use |
|-----------|------------|
| SwiftUI / Foundation / CoreData | UI + persistence (every view + model) |
| CloudKit | `StorageService.initializeCloudKitSchema` (DEBUG only) |
| Speech, AVFoundation, AVKit | Voice capture + transcription |
| WatchConnectivity, WatchKit | Watch app + clip transfer |
| Photos, PhotosUI | Camera + library pickers |
| CoreLocation, Network | Location capture, connectivity gate |
| Security, CryptoKit | KeychainService + EntryMapper hash |
| AppIntents, UserNotifications | Siri shortcut + per-clip notifications |
| NaturalLanguage | LocalEntityExtractor |

---

## 3. Security Audit

**Status: FINDINGS (2 medium, 1 low)**

| Category | Verdict | Note |
|----------|---------|------|
| Hardcoded secrets | CLEAN | No API keys / Bearer tokens in source. ClaudeAPIService relies on backend auth. |
| Keychain | CLEAN | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on all SecItem calls. |
| Network | CLEAN | All HTTPS; no ATS exceptions; standard cert validation. |
| Logging / PII | FINDINGS | See below. |
| Permissions | FINDINGS | See below. |
| 3rd-party data flow | CLEAN | Claude API + epigraphs over HTTPS; no embedded tokens. |
| CloudKit sensitivity | CLEAN | Entry content is intentionally synced; no credentials in entities. |
| WebView / URL injection | CLEAN | No WebViews. Only `UIApplication.open` site is Apple Maps with percent-encoded coords. |

| Finding | File:Line | Severity | Description |
|---------|-----------|----------|-------------|
| Unused `NSRemindersUsageDescription` | `project.pbxproj` | MEDIUM | Permission declared but no EventKit usage anywhere. Either implement or strip the key. |
| Audio filename in NSLog | `TranscriptionService.swift:76` | MEDIUM | Logs `audioURL.lastPathComponent`. UUID-format filename so PII risk is low, but logging duration + locale alone is safer. |
| Loose `print()` in error paths | `SpeechService.swift:128`, `AlbumSyncService.swift:116` | LOW | Two remaining `print()` calls in error catches. Route through `ErrorState.shared.report` instead. |

---

## 4. Accessibility Audit

**Status: FINDINGS (broadened since 2026-04-18 — codebase grew)**

| Category | Severity | Count | Notes |
|----------|----------|-------|-------|
| Icon-only buttons w/o `.accessibilityLabel` | HIGH | 84 | EntryExpandedView (13), JournalView (8), ClipInboxView (6) lead. Some chevrons/checkmarks also affected. |
| Hardcoded `.system(size: ...)` (no Dynamic Type) | HIGH | 73 | EntryExpandedView (15), ClipInboxView (12), JournalView (8). `.body`/`.caption` would respect user settings. |
| Tap targets < 44×44 pt | MEDIUM | 22+ | Media-type dots (8×8), topic chip × buttons (28×28), inbox checkbox (22×22), MediaTile play overlay (24×24). |
| Low-contrast interactive text | CLEAN | — | No tappable text below 0.4 opacity. |
| Missing `.accessibilityHint` on swipe / long-press | MEDIUM | 6 sites | Only `AppendFAB` has a hint. Swipe-to-edit/delete in JournalView, ChronologicalCaptureStream, ProjectListView are silent. |
| Missing semantic grouping on cards | LOW | 3 | EntryCardView, ClipInboxView clip card, ChronologicalCaptureStream pills — should `.accessibilityElement(children: .combine)`. |
| Unlabeled placeholder images | LOW | mixed | `MediaThumbnailView`, `MediaViewerView` use `Image(systemName: "photo.slash")` without label or `.accessibilityHidden`. |

Remediation status: still **deferred**. Same files dominate as the 2026-04-18 audit — not made worse, but the new ClipInbox + Onboarding surfaces inherit the same hardcoded font / unlabeled icon pattern.

---

## 5. Performance Audit

**Status: FINDINGS (some prior items now mitigated, new ones added)**

### Fixed since 2026-04-18
- `JournalView.groupedEntries` no longer fetches in body — moved to `JournalViewModel.recomputeFiltered` (called on observed changes).
- Pagination via NotificationCenter debounce now in place (`JournalViewModel.observeStorageChanges`).

### Open
| Issue | File:Line | Severity | Note |
|-------|-----------|----------|------|
| `ClipInboxView.grouped()` recomputes per render | `ClipInboxView.swift:557` | HIGH | Sorts + groups all clips into 10-min buckets every render. Cache in `@State`. |
| `EntryCardView.smartTags` re-filters per render | `EntryCardView.swift:24` | MEDIUM | Substring match on every tag, every render. Negligible per row but multiplicative across feed. |
| Sync `FileManager.fileExists(atPath:)` in view bodies | `ClipInboxView`, `ProjectDetailView`, `MediaTile`, `AudioPlayerSheet` | HIGH | Main-thread disk hits inside body / init. Move to `.onAppear` + cache. |
| `Project.fetchAll()` has no `fetchLimit` | `Project.swift` | MEDIUM | Most other fetches now bounded; this one still unbounded. |
| `@StateObject` wrapping singletons | `JournalView.swift:8-9`, `EntryCardView`, `AudioPlayerSheet` | LOW | `TopicApprovalService.shared` / `AlbumSyncService.shared` / `AudioPlayerService.shared` should be `@ObservedObject` since `.shared` already manages lifetime. |

`fullImage` vs thumbnail loading is clean (uses `ThumbnailService.shared` cache). Feed renders use grouping/lazy stacks; no unbounded `ForEach`. Sequential async loops (transcription stream, processing queue) are intentional.

---

## 6. Test Coverage Audit

**Status: STRONG IMPROVEMENT**

- **134 tests passing** in `MemoryStreamTests` (was 8 on 2026-04-18). All pass on iPhone 17 Pro / iOS 26.4.1 sim.
- Coverage now spans: `EntryLifecycleService` (edit/delete/recycle/restore + media-ref deletion), `JournalViewModel` (append flows + voice fragments), `SearchEngine` (text/topic/type/date scope, snippet, recycled, forgotten card), `JournalEntry` (title derivation), `ProjectDetailView` (share-text composition), `EntryDisplayStatus`, `EntryHeaderRow`, `PlacemarkFormatter`, `SearchViewModelBucket`, `ScopeParser`, `ProcessingEngineFallback`.
- `ProcessingEngineFallbackTests` correctly uses `@Suite(.serialized)` per the CLAUDE.md rule on shared singletons.

### Gap candidates (next sprint)
- `FragmentMigration` — no test coverage. Would have caught the v2 crash this session before launch.
- `WatchSessionDelegate` / `WatchTransferService` — hard to unit-test but could mock WCSession.
- `InboxManifest` round-trip and notification scheduling.

---

## Remediation Priority

| # | Bucket | Effort | Notes |
|---|--------|--------|-------|
| 1 | Performance: cache `ClipInboxView.grouped()` + move `fileExists` calls out of view bodies | 2-3h | Hot path on inbox arrival surge |
| 2 | Security: strip `NSRemindersUsageDescription` (or build the integration); silence `TranscriptionService` filename log | 1h | Low-effort hygiene |
| 3 | `FragmentMigration` test coverage + per-entry try/catch | 3h | Money test for the crash that surfaced this session |
| 4 | Accessibility pass: icon labels + Dynamic Type for top 3 surfaces (Journal, ClipInbox, EntryExpanded) | 6-8h | High user impact, no architectural change |
| 5 | `@StateObject` → `@ObservedObject` for singletons | 30min | Pure semantics fix |
| 6 | View decomposition: split `EntryExpandedView` (903 lines) and `JournalView` (706 lines) — see CRAP audit | See CRAP doc |

---

_Audit run 2026-05-09 after Phase 5 cleanup. Companion document: `2026-05-09-crap-audit.md`._

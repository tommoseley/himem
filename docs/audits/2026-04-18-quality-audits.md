# Quality Audit Suite — 2026-04-18

## 1. Dead Code Audit

**Status: REMEDIATED**

| Item | Action |
|------|--------|
| `InputBarView.swift` — orphaned after Composer replaced it | Deleted file + pbxproj refs |
| Mock data system in JournalViewModel (`useMockData`, `saveMockEntry`, `loadMockData`) — always-false flag, ~70 lines | Deleted |
| Malformed `submitFeedback` indentation (artifact of mock guard removal) | Fixed |

**Commit:** `becc839` — Dead code audit: remove orphaned InputBarView + mock data system

---

## 2. Dependency Audit

**Status: CLEAN**

- Zero third-party dependencies (SPM, CocoaPods, Carthage)
- 15 Apple frameworks imported, all actively used
- No unnecessary imports found (UIKit needed for haptics/UIApplication, CoreData needed for viewContext ops)

---

## 3. Security Audit

**Status: REMEDIATED (1 fix)**

| Finding | Severity | Action |
|---------|----------|--------|
| `APIError.httpError` exposed raw server response body in UI | LOW | Fixed — now shows generic message |
| Keychain usage | CLEAN | Proper `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Network security | CLEAN | HTTPS only, no ATS exceptions |
| Hardcoded secrets | CLEAN | None found |
| Logging | CLEAN | No PII logged |
| Permissions | CLEAN | Camera, Microphone, Photos, Speech — all justified |

**Commit:** `a2c6c28` — Security audit: sanitize API error messages

---

## 4. Accessibility Audit

**Status: FINDINGS DOCUMENTED — remediation deferred**

| Category | Severity | Count |
|----------|----------|-------|
| Missing VoiceOver labels on icon buttons | HIGH | 15+ |
| Hardcoded `.system(size:)` (no Dynamic Type) | HIGH | 30+ |
| Tap targets < 44pt | MEDIUM | 7+ |
| Low contrast (opacity on interactive text) | MEDIUM | 8+ |
| Missing `.accessibilityHint` on complex gestures | MEDIUM | 3+ |
| Missing semantic grouping on cards | LOW | 3 |

**Key files:** JournalView, ComposerView, EntryExpandedView, EntryCardView

---

## 5. Performance Audit

**Status: FINDINGS DOCUMENTED — remediation deferred**

### Critical (will degrade with 200+ entries)

| Issue | File | Fix |
|-------|------|-----|
| `displayEntries`/`groupedEntries` recompute every render | JournalView | Move to ViewModel as @Published |
| Core Data fetch in view body (recycledCount) | JournalView | Cache in ViewModel |
| Unbounded fetches (no fetchLimit) | JournalViewModel.loadEntries, SearchEngine | Add fetchLimit + pagination |
| Synchronous disk read in `cachedThumbnail()` | ThumbnailService | Make async |

### Medium

| Issue | File | Fix |
|-------|------|-----|
| 8 @StateObject singletons triggering re-renders | JournalView | Use @ObservedObject for shared singletons |
| `fullImage()` called when thumbnail suffices | MediaThumbnailView | Use `cacheThumbnail()` fallback |
| Sequential task processing | ProcessingEngine | Concurrent processing |

---

## 6. Test Coverage Audit

**Status: MINIMAL**

- **8 tests** in `JournalViewModelAppendTests` — all passing
- **0 tests** for: edit, delete, recycle/restore, search, processing, topics, errors, feedback
- Default `MemoryStreamTests.swift` is empty placeholder

### Coverage gaps (priority order):

1. EntryLifecycleService — edit, delete, recycle, restore
2. SearchEngine — text search, entity type filter
3. ProcessingEngine — cloud/local paths, failure handling
4. TopicSlugHelper — slugify edge cases
5. ErrorState — auto-dismiss behavior

---

## Remediation Priority

1. **Done** — Dead code, security fix
2. **Next sprint** — Performance (computed properties, fetchLimit)
3. **Scheduled** — Test coverage for critical paths
4. **Backlog** — Accessibility pass, Dynamic Type

# CRAP Score Audit — Hi Mem iOS Codebase

_2026-05-28 · 141 Swift files · 27,748 lines (production code only; 182 / 34,540 incl. tests)_

---

## Overall Score: 12 (Acceptable with Caution — one body genuinely smelly, three large new view files holding the line on decomposition)

The codebase has nearly doubled since 2026-05-09 (75 → 141 production files; 15.2k → 27.7k lines). Three sizable new view files arrived (`AISuggestionsCard.swift` 1140, `SessionListView.swift` 696, `UpgradeHubView.swift` 607, `CreateMemoryFromClipsSheet.swift` 660) — each shipped well-decomposed despite the line counts. The previously-flagged smelly bodies have not all worsened: `JournalView.body` is now CC 20 (was 22, marginally better; file still dense), `EntryExpandedView.body` is CC 10 (was 18 — read/edit-mode split is real), and `EntryCardView.body` rose to CC 14 (was 12, density-driven branches multiplied). `EntryLifecycleService` crossed 750 lines without a hot function but is now a 9-section service. Net: no new critical (CC > 30) functions, but file-size growth on legacy mega-views is the structural risk worth tracking.

---

## Scorecard

| File | Lines | Funcs | Top CC | Grade | Note |
|------|-------|-------|--------|-------|------|
| EntryExpandedView.swift | **1248** | ~20 | 10 (body) | **C** | Grew 903→1248 (+38%); CC improved (read/edit split) but file size exploded as append+capture state landed |
| AISuggestionsCard.swift | **1140** | ~40 | 6 (body) | **B** | NEW. Unified AI suggestions card replacing v2 OrganizeDoneSections; rows extracted, editorSheet delegated |
| VoiceCaptureScreen.swift | 932 | ~25 | 8 (body) | **B** | Rewritten this session; tight cluster + live transcript spec; 15+ @State props is the density to watch |
| JournalView.swift | **856** | ~12 | **20** (body) | **C/D** | Root god-view; 410-line body, marginally better CC (22→20) but denser inline |
| EntryCardView.swift | 782 | ~10 | **14** (body) | **C** | Density-driven render; CC rose 12→14 as processing-status + inference-card variants per density landed |
| EntryLifecycleService.swift | **758** | ~30 | 6 (edit) | **B** | Grew 534→758 (+42%); still no hot function but now 9 sections (queries split is overdue) |
| SearchView.swift | 750 | ~12 | 8 (filterSuggestions) | **B** | Clean delegation to VoiceSearchView + ScopeChipsBar |
| SessionListView.swift | **696** | ~30 | 4 (body) | **B** | NEW. Session-first Captured Clips v2; collapsed/expanded paths cleanly separated |
| SettingsView.swift | 664 | ~15 | <8 | **B** | Form-driven; flat |
| CreateMemoryFromClipsSheet.swift | **660** | ~20 | 3 (body) | **B** | NEW. Destination toggle (new vs existing memory) + pickers; well-structured |
| OnboardingView.swift | 633 | ~8 | <8 | **A** | Linear page flow |
| UpgradeHubView.swift | **607** | ~25 | 7 (body) | **B** | NEW. Tier-aware hub; 7-branch body delegates to sub-cards |
| ProjectDetailView.swift | 585 | ~18 | <8 | **B** | Share-text composer extracted |
| CrucibleTheme.swift | 544 | ~35 | <8 | **B** | Color/font/spacing constants; still bundles TopicEditorSheet (2026-04-28 finding still open) |
| WatchInboxNotificationCoordinator.swift | 514 | ~12 | <8 | **B** | Watch → iPhone sync |
| SpeechService.swift | 511 | ~18 | <8 | **B** | Speech recognition pipeline |
| EntitlementService.swift | 451 | ~15 | <8 | **A** | Tier + assist + supporter state; clean predicates |
| ProcessingEngine.swift | 450 | ~15 | 6 (storeEntities) | **B** | Still well-decomposed |
| WatchSessionDelegate.swift | 426 | ~12 | <8 | **B** | Watch/iPhone messaging |
| StorageService.swift | 408 | ~22 | <8 | **B** | InMemory + cloud paths still co-located |

---

## Cross-File Top Functions by Cyclomatic Complexity

| Rank | Function | File | CC | Lines | Verdict |
|------|----------|------|-----|-------|---------|
| 1 | `body` | JournalView.swift | **20** | 410 | **Smelly** — view state machine; marginally better than baseline (was 22) |
| 2 | `body` | EntryCardView.swift | **14** | 140 | Borderline — density-driven branches |
| 3 | `body` | EntryExpandedView.swift | **10** | ~280 | Acceptable now (was 18); file still grew 38% |
| 4 | `body` | SearchView.swift | 8 | ~60 | Acceptable; clean delegation |
| 5 | `body` | VoiceCaptureScreen.swift | 8 | ~70 | Acceptable; density of @State is the risk, not CC |
| 6 | `handleCapturedItemForNewEntry` | JournalView.swift | ~8 | 100 | Acceptable (per-modality dispatch) |
| 7 | `body` | UpgradeHubView.swift | 7 | ~60 | Acceptable; tier branching delegates to sub-cards |
| 8 | `body` | AISuggestionsCard.swift | 6 | ~100 | Acceptable; conditional rows but extracted helpers |
| 9 | `edit` | EntryLifecycleService.swift | 6 | 40 | Acceptable |
| 10 | `storeEntities` | ProcessingEngine.swift | 6 | 24 | Acceptable |

---

## Critical Findings

### 1. JournalView.body Remains the Root God-View — CC 20

410-line body orchestrates: memory vs projects toggle → inbox banner visibility → topic filter → feed render vs project list → FAB (memory mode only) → error banner → undo toast → search navigation → detail navigation → inbox navigation → Siri intent handler → topic approval sheet → album sync alert → voice + camera error dialogs → speech + camera service authorization → quick action handler. Every new feature still converges here with minimal filtering.

**Change from baseline:** CC 22 → 20. The two-point drop reflects the read/edit split in `EntryExpandedView` removing some host-side conditionals — not a structural improvement to `JournalView` itself.

**Decomposition target:** extract `JournalMemoriesView` (memoriesList + capture handlers), `JournalBannerStack` (inbox + soft 75%), `JournalErrorToasts` (error + undo). Body becomes a 80-100 line coordinator.

### 2. EntryExpandedView File Grew 38% Even Though body CC Improved

Body CC dropped 18 → 10 — a real win from extracting `NotePanel`, `AudioPlayerSheet`, and the per-fragment read/edit split. But the file grew from 903 → 1248 lines (+345). New mass landed in:
- Per-panel edit/delete sheet targets (`audioPlayerForFile`, `noteEditorTarget`) tracked on the host
- FAB suppression logic when the AI Suggestions card is unfolded or in Review state
- `activeCaptureModality` state for the append spec
- Tier-aware routing for the AI pack purchase sheet vs Upgrade Hub

The detail view is absorbing capture-cycle state that previously lived only in `JournalView`. Verdict: CC win is real, file-size growth is the new concern.

**Decomposition target:** extract `EntryAppendCoordinator` (activeCaptureModality, FAB suppression, capture handlers). Move per-panel sheet state into `ChronologicalCaptureStream` so the host doesn't track it. File shrinks to ~1000 lines.

### 3. EntryCardView.body Crept Up — CC 12 → 14

Two new conditionals: `if density != .compact` for the processing status card, and `else if density == .standard` for the inference-card variant logic. The density logic is now three-way (rich shows inference always, standard shows only while pending, compact hides it).

**Watch for:** another density-specific feature could push this to 18+ quickly. Currently still in the acceptable band but eroding.

### 4. EntryLifecycleService Trending Toward God-Service — 758 Lines, 9 Sections

Was 534 (2026-05-09), now 758 (+42%, +224 lines). Max CC still 6 (no hot function). The file now spans nine sections: Create / Regenerate / Migrate / UpdateFragment / Append / Delete-Recycle / Feedback / Queries / Private helpers.

No new lifecycle operation is offensive on its own. The structural risk: one more landing without a split forces a god-service designation.

**Decomposition target:** extract `EntryQueryService` for `loadRecycledEntries`, `recycledCount`, `recycledCountForTopic`. File shrinks to ~600 lines, each file has a single responsibility verb.

### 5. Four NEW Files Shipped Over 600 Lines — All Well-Decomposed

| File | Lines | Top CC | Assessment |
|------|-------|--------|------------|
| AISuggestionsCard.swift | 1140 | body 6 | Rows extracted via `row()`, `header`, `footer` helpers; editor delegated to `editorSheet(for:)`. **Not smelly despite size.** |
| SessionListView.swift | 696 | body 4 | Collapsed/expanded card bodies cleanly separated via `@ViewBuilder`. Selection state isolated in `selectionFor()`. **Good model for large views.** |
| CreateMemoryFromClipsSheet.swift | 660 | body 3 | Destination-toggle branch is the only conditional; each path is a handful of pickers. **Well-structured.** |
| UpgradeHubView.swift | 607 | body 7 | Tier branching (`isFounders`, `isPlus`, `isSupporter`, `storeReady`, `foundersCapReached`) delegates to sub-cards (SupporterOverlayCard, plansSection, foundersSection, packsSection). **Necessary branching, not avoidable smell.** |

The honest read: line count is driven by **spec completeness** (multi-row UI, per-clip swipe actions, tier-aware copy), not by poor decomposition. The question for the next quarter is whether they stay decomposed as features land.

### 6. VoiceCaptureScreen — 932 Lines With 15+ @State Properties

Body CC is only 8, so it doesn't show up as smelly on the leaderboard. But the view is doing a lot: timer logic + waveform visualization (waveSamples) + REC dot animation + recording state machine (phase: breathing/recording/denied) + location capture + next-clip "on a roll" controller + AVAudioSession setup + audio level streaming from `SpeechService`.

The reason CC stays low: most logic is in `@State` properties and helpers, not the body. But **state density** is the risk metric here. If another modality lands (e.g., a "drift mode" or background ambient capture), this view will fracture.

**Decomposition target:** push more state into `@StateObject` controllers (like `NextClipController` already does). E.g., a `VoiceRecordingController` owning phase + timer + waveform. Doesn't lower CC, but localizes the state cluster.

### 7. No New CC > 30 Critical Functions

Confirmed across all 141 production files. Async lifecycle code in `EntryLifecycleService` and `ProcessingEngine` stays delegated rather than monolithic. The architectural discipline is holding at the function level.

### 8. CrucibleTheme.swift Still Bundles TopicEditorSheet

2026-04-28 finding still open. Theme file at 544 lines is mostly constants, but `TopicEditorSheet` continues to live here. Cosmetic; not urgent.

### 9. Append Spec Now Split Across Three Surfaces

Capture-modality dispatch lives in (a) `JournalView.handleCapturedItemForNewEntry`, (b) `EntryExpandedView.handleCapturedItemForAppend`, and (c) `CreateMemoryFromClipsSheet` (clips-to-memory). Three parallel switches per surface. Prior audit's `CaptureCoordinator` recommendation still open; the problem is mildly worse with the third surface.

### 10. Tier-Aware Branching Is Now Pervasive

`UpgradeHubView` (7 branches), `AISuggestionsCard` (tier-aware exhausted variants), `EntryExpandedView` (tier-routed sheet selection), `CreateMemoryFromClipsSheet` (Plus-only "add to existing" flow), `ProjectDetailView` ("Starter · free" label). The branching is necessary, but it's also unavoidable structural complexity. If tier logic changes, 5+ views need updating in lockstep.

**Mitigation:** `EntitlementService` already exposes the boolean cues (`isPlus`, `canConsumeAssist`, `showsOneLeftFreeCue`, `showsFromYourPackCaption`, `isFreeNoAssists`). Views should consume those rather than re-derive predicates. Confirmed they do today — keep this discipline.

---

## Governance Compliance vs CLAUDE.md Limits

| Limit | Status | Notes |
|-------|--------|-------|
| No function with cyclomatic complexity > 15 | **1 violation** | `JournalView.body` CC 20. (Was 2; `EntryExpandedView.body` dropped to 10.) |
| No view file > 400 lines | **9 violations** | EntryExpandedView, AISuggestionsCard, VoiceCaptureScreen, JournalView, EntryCardView, SearchView, SessionListView, SettingsView, CreateMemoryFromClipsSheet, OnboardingView, UpgradeHubView — actually 11 if counting strictly. Most have justifying spec density (see Finding 5). |
| No service/VM file > 300 lines | **2 violations** | `EntryLifecycleService` (758), `StorageService` (408). Neither has a hot function. |
| No silent `print()` in error paths | **Mostly compliant** | See Security audit § 3 for the remaining two `print()` sites in `AlbumSyncService` and `AudioPlayerService`. |
| No code pattern duplicated > 2× | **Compliant** | Append-spec dispatch is the closest call (3 sites); flagged in Finding 9. |

**Net vs 2026-05-09:** smelly-function count steady at 1 (was 2 by strict reading); view-file violations grew from 6 → 9; service violations grew from 1 → 2.

---

## Trends Since 2026-05-09

| Metric | 2026-05-09 | 2026-05-28 | Change |
|--------|------------|------------|--------|
| Production Swift files | 75 | 141 | +88% |
| Production lines | 15,152 | 27,748 | +83% |
| Smelly bodies (CC > 15) | 2 | 1 | -1 |
| View files > 400 lines | 6 | 9 | +3 |
| Service files > 300 lines | 1 | 2 | +1 |
| Largest file | 903 (EntryExpandedView) | 1248 (EntryExpandedView) | +38% |
| EntryLifecycleService | 534 | 758 | +42% |
| Top function CC | 22 (JournalView.body) | 20 (JournalView.body) | -2 |

---

## Remediation Plan (Bounded Batches)

| # | Batch | Effort | Notes |
|---|-------|--------|-------|
| 1 | Decompose `JournalView.body` — extract `JournalMemoriesView`, `JournalBannerStack`, `JournalErrorToasts`. Target body ≤ 100 lines, CC ≤ 8. | 5-6h | Lone smelly-function violation; do before the next root-level feature lands |
| 2 | Decompose `EntryExpandedView` — extract `EntryAppendCoordinator`; move per-panel sheets into `ChronologicalCaptureStream`. Target ~1000 lines. | 4-5h | File-size win, not CC win |
| 3 | Split `EntryLifecycleService` — extract `EntryQueryService` for recycled queries. Target ~600 lines per file. | 3-4h | Prevents the 850+ line god-service trajectory |
| 4 | Move `TopicEditorSheet` out of `CrucibleTheme.swift` | 30min | 2026-04-28 finding; keep the theme file pure |
| 5 | Extract `CaptureCoordinator` consolidating the three append-spec dispatch sites | 6-8h | Post-MVP; not urgent unless a fourth capture surface lands |
| 6 | `VoiceCaptureScreen` state review — push more @State into controllers | 2-3h | Not urgent; localizes the 15+ state cluster before the next modality |

---

_Companion document: `2026-05-28-quality-audits.md`. Both audits run after the pre-launch checkpoint commits (`b82bc2b`, `4f53d4e`, `8c5f938`)._

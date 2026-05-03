# Contribute Mode — Implementation Plan

Companion to `docs/design/contribute-mode.md`. Maps the spec onto the current code and breaks the work into ordered phases that can each ship independently behind a working build.

## What exists today

- **`ComposerFAB`** lives in `Views/Journal/JournalView.swift:536` and is rendered only on `JournalView`. Tap → `composer.open(withRecording: true)` (already starts voice on tap, matches the new spec). Long-press → `composer.open()`.
- **`ComposerViewModel`** at `ViewModels/ComposerViewModel.swift` owns the in-memory buffer for a new memory: `textContent`, `mediaCaptures`, `pendingTranscripts`, `selectedTopicName`. Commits as a single `lifecycle.save(...)` on Save.
- **`ComposerView`** at `Views/Input/ComposerView.swift` is presented as a `.medium`/`.large` sheet. It's already a multi-tile capture surface (audio waveform, photos, videos) — most of the visual primitives we need for the Action Box are here.
- **`EntryExpandedView`** at `Views/Journal/EntryExpandedView.swift` has its own append toolbar at line 399 with separate buttons for audio/text/photo/video/attach. Each routes through state on the view (`cameraMode`, `pendingMedia`, `pendingTranscripts`) and commits in batch via `onCommit`. There is no FAB on this screen.
- **`SettingsView`** at `Views/Components/SettingsView.swift` uses `@AppStorage` for boolean prefs (`saveVoiceEntries`, `voiceSilenceMode`, `tagMemoriesWithLocation`). Already the right place for the Confirmations section.
- **`CameraPickerView`** at `Views/Input/CameraPickerView.swift` and **`CameraService`** are reusable.
- **`SpeechService`** is the live transcription source.

## What's reusable vs. new

| Need | Reuse | New |
|---|---|---|
| Tile rendering (voice waveform, photo, video) | `ComposerMediaTile` (ComposerView.swift:509) | — |
| Voice recording state + transcript | `SpeechService`, existing wiring | — |
| Camera capture | `CameraPickerView` + `CameraService` | — |
| Photo library attach | existing `PhotosPicker` integration | — |
| Action Box buttons (large, four-up + recording-state-inline) | layout primitives from current toolbar | new view: `ContributeActionBox` |
| Mode lifecycle, session capture-ID tracking, lazy-create on first capture | — | new view model: `ContributeSessionViewModel` |
| Single Contribute button rendered globally | `ComposerFAB` (rename + relocate) | — |
| X confirmation with enumerated counts | — | new view: `DiscardSessionConfirmationView` |
| Settings → Confirmations | `SettingsView` Form | new section + new pref keys |

## Architecture

### `ContributeSessionViewModel` (new)

Replaces `ComposerViewModel`'s "buffer + commit" semantics with "live entry + session-capture-IDs."

```swift
@MainActor
final class ContributeSessionViewModel: ObservableObject {
    enum Anchor {
        case newMemory                 // lazy-create on first capture
        case existingMemory(UUID)      // append target
    }

    @Published private(set) var isPresented = false
    @Published private(set) var anchor: Anchor = .newMemory
    @Published private(set) var entryId: UUID?           // nil until first capture (new-memory anchor)
    @Published private(set) var sessionCaptureIds: [UUID] = []
    @Published private(set) var activeCapture: ActiveCapture? = nil   // .voice, .video, .text — drives Action Box state
    @Published var showDiscardConfirmation = false

    var speechService: SpeechService?
    var cameraService: CameraService?

    func enter(anchor: Anchor, autoStartVoice: Bool)
    func exitDone()                                     // applies silent-discard rule for trivial sessions
    func requestExitDiscard()                           // opens confirmation if non-empty + not muted
    func confirmDiscard()                               // deletes by ID, then exits
    func startVoice() / stopVoice()
    func startVideo() / stopVideo()
    func openTextEditor() / commitText(_ text: String)
    func openCamera(.photo / .video)
    func attachFromLibrary(localId: String, type: MediaReference.MediaType)
}
```

`sessionCaptureIds` is the audit list X uses. For text tiles, we represent them as `JournalEntry`-attached "draft text segments" — see "Open implementation question" below.

### `ContributeActionBox` (new view)

Pure presentation. Bound to `ContributeSessionViewModel`. Layout:

```
┌──────────────────────────────┐
│ [tiles ScrollView, top-down] │
│ [tile] [tile] [tile]         │
│ [tile]                       │
│                              │
├──────────────────────────────┤
│ [Voice]  [Photo]             │
│ [Video]  [Text]              │
└──────────────────────────────┘
```

- Bottom-anchored, fixed height for the buttons row (so it doesn't shift as tiles accumulate).
- Voice/Video buttons render the inline recording state (red dot, waveform/elapsed, tap to stop) when `activeCapture` matches.
- Tile area is a `LazyVStack` for the same perf-on-many-captures reasons we just baked into Search.
- Done lives in the host `NavigationStack` toolbar (trailing); X lives leading.

### `ContributeButton` (rename of `ComposerFAB`)

Same visual primitive. Rename the type and add the **mic glyph** in the idle state — currently it shows `plus`. Spec says default action is voice, so the glyph should communicate that.

```swift
Image(systemName: isContributing ? "xmark" : "mic.fill")
```

`isContributing` is the binding from `ContributeSessionViewModel.isPresented`. We also extend the `accessibilityHint` for long-press: "Long-press to choose a capture type."

The button must be hidden while Contribute Mode is active — per spec, entry/exit is via Action Box controls only. Trivially: `if !session.isPresented { ContributeButton(...) }`.

### Lazy-create on first capture (new-memory anchor)

The first capture method (`startVoice` / `startVideo` / `openCamera` for photo / `commitText` / `attachFromLibrary`) calls a single private helper:

```swift
private func ensureEntry() -> JournalEntry {
    if let id = entryId, let entry = lifecycle.fetchEntry(id: id) { return entry }
    let entry = lifecycle.createEmptyEntry(...)        // new factory method
    entryId = entry.id
    return entry
}
```

`lifecycle.createEmptyEntry()` is a small new factory on `EntryLifecycleService` that creates a `JournalEntry` row with no content and no media — this is the entry that lives or dies based on Done vs. X.

For the existing-memory anchor, `entryId` is set on enter and `ensureEntry` is a no-op fetch.

### Done — silent-discard rule

```swift
func exitDone() {
    if anchor == .newMemory {
        if shouldSilentlyDiscard() { performDiscardWithoutConfirmation() }
        // else: entry stays, captures stay, exit
    }
    isPresented = false
    reset()
}

private func shouldSilentlyDiscard() -> Bool {
    // Captures created this session
    let voiceCount = sessionCaptureIds.filter { mediaType(of: $0) == .voice }.count
    let videoCount = sessionCaptureIds.filter { mediaType(of: $0) == .video }.count
    let photoCount = sessionCaptureIds.filter { mediaType(of: $0) == .image }.count
    let textCount = sessionTextTiles.count

    // Silent-discard: <2s lone voice OR video clip + nothing else
    if photoCount == 0 && textCount == 0 && (voiceCount + videoCount) == 1 {
        if let onlyClip = sessionCaptureIds.first, mediaDuration(of: onlyClip) < 2.0 {
            return true
        }
    }
    return false
}
```

`mediaDuration(of:)` reads from the `MediaReference` row (existing column? if not, we already have access via `AVURLAsset` on the file).

### X — discard with confirmation

```swift
func requestExitDiscard() {
    if sessionIsEmpty { performDiscardWithoutConfirmation(); return }
    if UserDefaults.standard.bool(forKey: "confirmations.discardContribute.muted") {
        performDiscardWithoutConfirmation()
        return
    }
    showDiscardConfirmation = true
}

func confirmDiscard(muteFutureConfirmations: Bool) {
    if muteFutureConfirmations {
        UserDefaults.standard.set(true, forKey: "confirmations.discardContribute.muted")
    }
    performDiscardWithoutConfirmation()
}

private func performDiscardWithoutConfirmation() {
    for id in sessionCaptureIds { lifecycle.deleteMediaReference(id: id) }    // also deletes file
    if anchor == .newMemory, let entryId, entryHasNoOtherContent(entryId) {
        lifecycle.delete(entryId: entryId)
    }
    isPresented = false
    reset()
}
```

### Confirmations preference

Single `UserDefaults` key per muted prompt, namespace prefixed:
- `confirmations.discardContribute.muted: Bool`

`SettingsView` adds a Confirmations `Section` listing each muted-prompt as a `Toggle($value)` bound to `@AppStorage("confirmations.discardContribute.muted")`. Empty state ("No muted confirmations yet") if all are off.

## Phase plan

### Phase 1 — Skeleton, no behavior change visible

Goal: ship the new architecture wired to existing capture surfaces, without flipping the user-visible flow yet. Compile-time correct, tests green, no UI difference.

1. Add `ContributeSessionViewModel` skeleton with `Anchor`, `enter()`, `exitDone()`, `requestExitDiscard()`, but route everything through to today's `ComposerViewModel` / `EntryExpandedView` state internally. Effectively a thin facade.
2. Rename `ComposerFAB` → `ContributeButton`, swap the idle glyph from `plus` to `mic.fill`. Update the one call site in `JournalView`.
3. Add `EntryLifecycleService.createEmptyEntry()` factory + `recycledCount()` is already there. Add `deleteMediaReference(id:)` if not already present (check `StorageService`).
4. Money tests: `ContributeSessionViewModel` lifecycle (enter, exit, X with empty/non-empty session, silent-discard rule for `<2s lone voice`).

Ship: behavior unchanged on iPhone. CRAP score should be unchanged — we're just adding scaffolding.

### Phase 2 — Action Box on JournalView

Goal: replace the existing `ComposerView` sheet with the new `ContributeActionBox` for the new-memory flow. Append flow (`EntryExpandedView`) untouched in this phase.

1. Build `ContributeActionBox` view with the 2x2 button grid and tile area. Wire to `ContributeSessionViewModel`.
2. Replace `JournalView`'s `.sheet(isPresented: $composer.isPresented)` with a presentation of `ContributeActionBox` driven by `session.isPresented`. Keep the same presentation style for now (`.large` sheet) to scope the change; switch to `.fullScreenCover` in a later polish phase if that reads better.
3. Fold `ComposerViewModel` into `ContributeSessionViewModel` for the new-memory case. Delete `ComposerViewModel` once nothing references it.
4. Implement the silent-discard rule.
5. Implement X confirmation alert with enumerated counts and the "Don't ask me this" checkbox.
6. Add the `confirmations.discardContribute.muted` `@AppStorage` key.

Ship: new-memory capture goes through the Action Box; tiles persist as taken; X actually deletes; Done with trivial session is silently discarded.

Test: end-to-end — open from the Contribute button on the memory list, capture a voice + photo + text, hit Done, verify the entry exists with all three. Open again, capture a 1-second voice, hit Done, verify no entry was created.

### Phase 3 — Append flow on EntryExpandedView

Goal: replace `EntryExpandedView`'s media toolbar (line 399) with a Contribute button that opens the same Action Box, anchored at `.existingMemory(entry.id)`.

1. Remove the inline media toolbar from `EntryExpandedView`.
2. Add a `ContributeButton` to `EntryExpandedView` in the same bottom-trailing position as on `JournalView`.
3. Tap routes to `session.enter(anchor: .existingMemory(entry.id), autoStartVoice: true)`. Long-press to `autoStartVoice: false`.
4. Adapt `ContributeActionBox` to render against an existing-entry anchor — tiles from earlier sessions are *not* shown (only this session's captures), but on Done the entry refreshes and shows everything inline as it does today.
5. Migrate the existing `pendingMedia` / `pendingTranscripts` / `cameraMode` state on `EntryExpandedView` into the session view model.

Ship: round-trip pain in the gardener case is fixed. One open → many captures → one Done.

Test: open an existing entry, hit Contribute button, capture three audio clips and two photos in a row without exiting, hit Done, verify all five attached.

### Phase 4 — Modal text editor + polish

1. Replace inline text input with a full-screen `.fullScreenCover` text editor (modal). Done in the editor commits the text as a tile in the session.
2. Settings → Confirmations section. Empty state copy: "No muted confirmations yet."
3. Long-press haptic + accessibility hint refinement on the Contribute button.
4. Polish pass: animation transitions between Action Box states, recording-state visuals on Voice/Video buttons.

### Phase 5 — Cleanup

1. Delete `ComposerFAB` (renamed) and `ComposerViewModel` if any references remain.
2. Update tests touching `ComposerViewModel` to target `ContributeSessionViewModel`.
3. Remove the old `EntryExpandedView` toolbar + state (`pendingMedia`, `pendingTranscripts`, `cameraMode`, `showTextAppender`).
4. Session log entry summarising the Contribute Mode landing.

## Risks and mitigations

- **CloudKit schema unchanged.** Persistence model is "real `JournalEntry` rows from first capture, session list in memory only." No `INFOPLIST` or `.xcdatamodel` changes required, no production CloudKit dashboard step.
- **`ComposerViewModel` retirement breaks tests.** `ComposerViewModelTests.swift` exists. Mitigation: in Phase 1, build `ContributeSessionViewModel` next to it; migrate tests in Phase 5 once everything routes through the new model.
- **Existing in-flight composer sessions during a TestFlight upgrade.** If a user has a half-composed memory in the old composer when they upgrade, the buffer is lost. This is the same risk the app already takes on every upgrade (current composer state isn't persisted). Mitigation: ship Phase 2 in a quiet release, or write a one-time launch hook that recovers any state from `ComposerViewModel`'s defaults if needed. Probably overkill — accept the loss.
- **Killed-app recovery in v1 is "find your entry in the feed."** Spec calls this out explicitly. If it surfaces as friction in real usage, the v2 nicety of "tap an in-progress entry to resume" becomes a follow-up.

## Open implementation questions

- **Text tiles before commit.** Voice/photo/video each create a `MediaReference` immediately; what's the persistence shape for an in-session text tile? Options:
  - Write directly into `JournalEntry.content` with paragraph separators as the user commits each text editor session. Simple, but X needs to remember which paragraphs to peel back off.
  - Add a transient `TextDraft` Core Data entity attached to the entry. Cleaner separation, but a CloudKit schema change — violates the "no schema change" constraint.
  - Keep text tiles in memory only, written into `entry.content` on Done (only). Loses the persist-as-you-go guarantee for text but keeps text simple. Acceptable trade because text is rarely the long capture in a gardening session.

  Recommendation: option 3 for v1. Voice/photo/video are the persist-as-you-go captures (which is where the gardener-loss-risk lives anyway); text typed during the session lives in memory until Done. Spec stays accurate as long as we note the asymmetry.

- **`mediaDuration(of:)` for the silent-discard rule.** If `MediaReference` doesn't already store duration, read it from the file via `AVURLAsset.load(.duration)` at silent-discard-decision time. One file read on Done for the trivial-session check; cheap.

## Test plan

- `ContributeSessionViewModel` enter/exit lifecycle (both anchors).
- Silent-discard rule: 1.5s lone voice → discarded; 1.5s voice + 1 photo → kept; 5s lone voice → kept; 1.5s voice + 1.5s video → kept (rule is "exactly one trivial clip and nothing else").
- X path: empty session exits silent; non-empty session opens confirmation; muted confirmation skips dialog and discards.
- New-memory anchor: empty session creates no entry; first capture creates entry; Done leaves entry in place.
- Existing-memory anchor: pre-existing captures untouched after X; this-session captures deleted by ID.
- Confirmations preference: muting via the inline checkbox writes the key; Settings toggle reads/writes the same key.

UI verification (manual, per CLAUDE.md "For UI changes, start the dev server and use the feature in a browser before reporting the task as complete" — adapted for iOS sim/device):
- New memory via short-press from list: voice → photo → text → Done; verify entry on list with all three.
- Append via short-press from view: voice → photo → Done; verify the existing entry now has both new captures.
- X with non-empty session shows the enumerated confirmation; Discard removes only this session's captures.
- Mic glyph visible on the idle Contribute button; X glyph visible inside Contribute Mode (well — Contribute button hidden inside per spec; verify hidden).

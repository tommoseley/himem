# Session log · 2026-07-31 (pm) · F23 troika audit + Tier 1 start

Facts only. Immutable. **Written as a handoff for a context-free session.** Covers everything after `f0357a3` (the 07-31 session log).

## Repo state at time of writing

- Branch **`f8-overlay-and-wiring`** @ **`fcb378b`**.
- **46 ahead of `main`** (`5eec4ec`); **1 behind** — `main` holds the New-lens fix this branch never took. `ClipsTabView.swift` and `EntryExpandedView.swift` are the conflict-watch files and both were edited heavily this session, so that merge is harder than it was.
- **17 ahead of `origin/f8-overlay-and-wiring`** — nothing from 07-30 or 07-31 is pushed.
- Tag `v1.0-b27` is on `b282198`, far behind HEAD, and names a build number that never matched an upload (TestFlight processed build **28**; repo reads 28 as of `2a2662b`).

### Gate

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1147 tests / 160 suites** green **except** the deliberately-red F22 guard (see below) | sim iPhone 17 Pro Max `109A1381` |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed** | watch Series 11 46mm `B17233F6`, UITests skipped |

Toolchain **Xcode 27.0 beta 4 (`27A5228h`)**, run via `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` — no `sudo`; `xcode-select` still points at CommandLineTools. Xcode 26.6 is **not installed** (macOS 27.0 beta won't run it).

**Simulator health:** `281A473E` and `E3C0710E` are both unusable (`SBMainWorkspace` launch denials surviving `simctl shutdown all`); one run died with `Mach error -308`. Use `109A1381`. Diagnosis rule: a launch denial that survives a shutdown is device-specific — **switch simulators before erasing**.

### Committed vs uncommitted

**Committed since `f0357a3`:** exactly one — `fcb378b` (F23 T1.1, orphan-sweep disable).

**Uncommitted, tracked:** none. Working tree is clean of tracked code changes.

**Uncommitted, UNTRACKED — the F22 WIP:**
- `MemoryStream/MemoryStream/Services/Storage/FirstImportState.swift`
- `MemoryStream/MemoryStreamTests/FirstImportStateTests.swift`
- `MemoryStream/MemoryStream.xcodeproj/project.pbxproj` **is modified** (registers `FirstImportState.swift` — `Views/` and `Services/` use explicit file references, unlike the synchronized test group)

**The working tree contains one failing test on purpose.** `FirstImportStateTests.noSurfaceAssertsEmptyWithoutConsultingTheOwner` is red because no surface is gated yet. It is untracked, so `HEAD` is green. Verified this is the *only* failure before committing `fcb378b`.

Design-domain files under `docs/design/` remain modified/untracked (Tom's). Do not commit them. `git add -A docs/design/` nearly swept them into an unrelated commit on 07-31 — add design files by explicit path only.

---

## `fcb378b` · F23 T1.1 — orphan blob sweep disabled

**Data-loss path, found by audit not by a user.** `MediaBlobOrphanSweep` judges files in the **shared ubiquity container** against a keep-set that is partly **device-local**:

```
referencedFilenames = MediaReference.osIdentifier      (CloudKit-synced)
                    ∪ InboxManifest.referencedAudioFilenames  (sandbox, per-device)
gatherCandidates    includes store.inboxDirectory      (ubiquity, synced)
```

Unpromoted watch clips exist **only** as manifest rows, and the manifest is at `Documents/ClipInbox` in the sandbox — "per-device sync state, not user content" by its own source. So on a second device, or after a manifest reset, every staged clip in `Inbox/` is unreferenced **by construction**, ages past the 1-hour guard, and is coordinated-deleted. Once the watch has been acked and purged its copy, that staged file is the only copy.

Debug-only (`#if DEBUG`, Settings), so no shipped user could fire it — but the dogfood devices carry the real recordings.

Disabled, not deleted: the button survives, and the pure `orphans(...)` predicate + `MediaBlobPurgeTests` are untouched. The arithmetic was sound; the keep-set is not. **Re-enable only when the keep-set can see every device's staged clips** — that is the clip-storage seam rebuild, post-tag.

Guard `OrphanSweepReachabilityTests` — verified red first, naming `SettingsView.swift:397` and `:468`. Self-tests twice: predicate against a known call site, **and** the filesystem walk throws if it reaches no Swift source, so it cannot report "not reachable" by scanning nothing.

---

## F23 · the audit (three agents, report-only)

Commissioned to find recurring **defect classes**, not more instances of fixed bugs. Framing (Tom): six weeks of dogfood produced the same shapes repeatedly, each found by a user; and the codebase "feels spaghettified" the way the watch transfer code did before its rebuild — layers of individually-reasonable fixes each reasoning around the shape the last one left.

### Report 1 — silent no-ops and confident falsehoods

1. **`JournalView.swift:137` — systemic. The app has ONE error surface and most code that reports to it cannot reach it.** `JournalErrorBanner` is the only renderer of `ErrorState`; there are **59 `ErrorState.shared.report` call sites**. The banner sits in `JournalView`'s ZStack — absent from the Clips tab entirely (`HiMemTabView.swift:145`), underneath every `.sheet` / `.navigationDestination` (`JournalView.swift:140-160`), and `ErrorState.report` self-expires after 5s (`ErrorService.swift:69-74`) so nothing queues. **Most of the app's error handling is written correctly and never draws.** Illustration: `PlaceClipSheet.swift:344` deliberately keeps its sheet open and reports "Couldn't add this clip. Try again." — but that sheet is presented from `ClipEditorModal.swift:503`, itself a modal, so the banner renders two layers underneath. *Consequence: a user hits a real failure and sees nothing.*
2. **`CreateMemoryFromClipsSheet.swift:520,:575,:584` — "Start a Memory" can consume the session and create nothing.** `createMemoryFromExistingClips` returns nil when no ref resolved (`EntryLifecycleService.swift:786-791`, rolls back). On that path the `if let newId` block is skipped but `InboxManifest.shared.removeBatch(...)` and `dismiss()` run unconditionally. *Session vanishes from the bench, no memory, no error.*
3. **`ProcessingEngine.swift:512` + `OrganizeMemorySection.swift:417,:463` — Reorganize fails silently.** All three attempt paths swallowed with `try?`, ends at `guard let result else { return }`, no report. *Spinner runs, stops, text unchanged, no explanation — on a paid feature.*
4. **`CreateMemoryFromClipsSheet.swift:614`** — `guard written > 0 else { return }`. *"Add to memory" looks dead; sheet stays open, no message.*
5. **`PlaceClipSheet.swift:222,:227` — silent SUCCESS, worse than a no-op.** `addToExisting()` returns early on a fetch miss, but the caller at `:214-215` still fires `onPlaced?()` and `dismiss()` inside the `do`. Same shape at `:244`/`:253` (`removeFromSource`, `dropSourceEdge`). **The sibling `PlaceInboxClipSheet.commit()` at `:327-346` gets this exactly right** — checks the return code and reports. The older struct in the same file was never brought up to that contract. *The clip was not moved; the UI confirms placement.*
6. **`ManageMentionsSheet.swift:247`** — `guard let mention = try? storage.findOrCreateMention(...) else { return }`. *Draft text stays, nothing appears in the library.*
7. **`HiMemTabView.swift:485-486`** — `associate(entryId:withProject:)` returns silently if either fetch misses. *Low likelihood; a new memory would just not be in the chosen project.*
8. **`ClipEditorModal.swift:578`** — `Text(Self.formatPlaybackTime(audioDuration ?? 0))`. Reachable when the asset probe fails (file not down from iCloud yet); `:589` also floors the progress bar. *Elapsed time counts up against a stated total of **0:00** — same class as F6i, in a file that avoids it correctly two methods away (`:564`, and `TranscriptClipController.swift:229-232`).*
9. **`ClipsStatusSheet.swift:338,:347,:372`** — `(try? ctx.count(for: req)) ?? 0`. *A fetch failure renders "0 downloading / 0 loose" in the one sheet whose job is reporting what's in flight.*
10. **`RecycleBinView.swift:313`** — `guard let recycledAt else { return 30 }`. *A clip with no timestamp is told "30 days left." Low impact.*

**Class 2 is genuinely thin** — most `?? ""` hits are draft bindings/empty-state copy, and **`catch {}` is zero across the codebase**. Valuable negative result.

**Concentration:** error surfacing (finding 1, and the reason 3/4/5 are invisible), and the clip→memory commit path (2, 4, 5, partly 7) where `EntryLifecycleService` returns `UUID?`/`Int` status codes that some callers check and others ignore.

**Coverage:** mechanically swept 254 `try?`, 133 default-coercions, ternary nil-fallbacks (checked specifically after the earlier over-report), empty and log-only catches. All findings read, not just grepped. **Not covered:** ~50 `guard … else { return }` in `ClipsTabView`/`SessionListView` sampled not swept; watch targets, `Services/AI`, `Services/Watch` not audited for these classes; `ProjectDetailView` z-order unverified — if it is a pushed destination, the 8 `ProjectViewModel` error reports fall under finding 1 too.

### Report 2 — ownerless invariants and false-rationale deletes

1. **`UbiquityStore.swift:443,:455,:466` — the orphan sweep.** *Fixed in `fcb378b`.* Also noted: its false premise had propagated to `WatchSessionDelegate.swift:595` and `AcceptanceCriticalSectionTests.swift:46,:126`, which assert the sweep "is unwired". **It was wired.** Those three sites are still uncorrected (Tier 2).
2. **`InboxManifest.swift:1024` — corrupt-manifest reset.** `catch { clips = [] }` ("start fresh rather than block the user"). Any later mutation calls `persist()` (`:771`) writing an empty file, permanently discarding every pending clip's transcript, capturedAt, lat/lon, rollGroup. The comment establishes blocking is bad; it never establishes the rows are worthless. `backupManifestIfNeeded` (`:1097`) is gated on any `manifest.backup.*` existing, so it is a single lifetime snapshot, not a recovery point at corruption. *Metadata unrecoverable; audio survives but becomes unreferenced — and therefore was sweep-eligible.*
3. **`SessionListView.swift:1379-1411` — a hand-rolled second audio player.** Duplicates `AudioPlayerService` but omits its `AVAudioPlayerDelegate`, so a bench clip playing to its natural end never calls `stopPlayback()`: the `.playback` session stays active and `playingClipId` stays set. **Verbatim the bug `AudioPlayerService.swift:44-53` documents as fixed** ("made the device feel like it was refusing to sleep"); contravenes the CLAUDE.md wake-lock contract. The owner exists and is simply not used.
4. **`ClipsStatusSheet.swift:345,:370`** — loose-clip counts omit `recycledAt == nil`, which five other sites include (`ClipsTabView.swift:473,:1755`; `SessionListView.swift:266,:279`). *Recently-Deleted clips inflate the status sheet, so it disagrees with the bench it describes.* Owner idiom already exists: `MediaReference.noLiveMemoryConnectionPredicate` (`Models/MediaReference.swift:136`).
5. **`UbiquityStore.removeFromStore` bypassed at four sites** — `WatchSessionDelegate.swift:681`, `AudioPlayerService.swift:73`, `VoiceClipSplitter.swift:181`, and `UbiquityStore.swift:220` itself (where `moveIntoStore` deletes the destination *outside* the coordinator, unlike `copyIntoStore:318` and `writeData:373`). Its own doc (`:332-341`, RH-8) says a bare `removeItem` on a ubiquity file races iCloud's presenter.
6. **The 30-day retention window has three implementations** — `EntryLifecycleService.swift:1162` and `InboxManifest.swift:1009` use `Calendar.date(byAdding:)`; `ProjectViewModel.swift:107` uses `addingTimeInterval(-30*24*60*60)` (different DST behaviour). One policy governing three permanent purges, owned by nobody.
7. **Edge detach: four procedures, one unenforced side-effect.** `EntryLifecycleService.removeClipFromMemory` (`:907`, `:938`) record `PreviouslyConnectedStore`; `PlaceClipSheet.dropSourceEdge` (`:252`) deletes the edge directly and does not. Those two are the only callers of `PreviouslyConnectedStore.record`.
8. Smaller, same shape: two owners of the locked 16kHz/32kbps voice format (`WatchTransferAudioTranscoder.swift:43,:45`, `AudioCompressor.swift:49,:133`); `"watch"`/`"phone"` compared as raw literals (`ClipsStatusSheet.swift:310-311`, `ClipEditorModal.swift:625-626`) despite `JournalEntry.SourceDevice`; three near-duplicate topic-deletion procedures (`SettingsView.swift:567,:649`, `ManageTopicsSheet.swift:364`); **`SortBatchCommit.swift` has no production caller** but still carries a bare uncoordinated `fm.moveItem` (`:115`) and a fresh-UUID `createVoiceFragment` mint (`:146`) — the exact double-ref bug `ArrivedClipMaterializer` exists to prevent. Dead, but a live trap if rewired.

**Class 6 otherwise clean** — every `removeItem`/`context.delete`/batch delete read in app, Shared and watch targets. Verified sound: `EntryLifecycleService.delete(entryId:)`'s "clips survive" comment (edges are Cascade, `MemoryStream 3.xcdatamodel/contents:22`); `deleteOwnedBlob:1142` correctly refuses PhotoKit and note refs; **`WatchSessionDelegate.swift:681`'s post-split master delete is correctly justified** — fragments are named `<rollGroupId>-N.caf`, never the master's `<clipId>.caf`, and the throw path keeps the master.

**Concentration — the clip-storage seam:** `InboxManifest` ⇄ `ArrivedClipMaterializer` ⇄ `UbiquityStore` ⇄ `WatchSessionDelegate`. Findings 1, 2, 5, 6 all live there. Root cause is one unresolved split — **a device-local manifest describing device-shared files**, with two parallel Recently-Deleted implementations (manifest `recycledAt` vs `MediaReference.recycledAt`) reconciled only at the view layer (`RecycleBinView.swift:297-298`). **This is the deconstruct-and-rebuild candidate.**

**Coverage:** mechanical sweep of all deletes/moves/copies, all `MediaReference` predicates, `setCategory`/`setActive`, `AVAudioPlayer` instantiations, retention arithmetic, source-device literals, sample-rate/bitrate literals. **Not covered:** ~30 `switch ref.mediaTypeEnum` view mappings (plausible cluster, cosmetic, not read); CloudKit merge/conflict handling; walkthrough/onboarding; `ProcessingEngine`. One candidate chased and dropped for unprovable reachability: `deleteOwnedBlob`'s "only ref pointing at this filename" precondition (`FragmentMigration.swift:205` proves the codebase expects duplicates).

### Report 3 — hollow guards and phantom comments

**Tier 1 (safety / honesty / data):**

1. **`FirstImportState.swift:5,:52`** — "the one fact every surface reads before it claims to be empty" / "No surface may claim to be empty in this phase." **Zero production readers.** *A reader would believe F22 is fixed; the fresh-install path is unchanged.* (Accurate — this is the WIP state.)
2. **`ProcessingEngine.swift:264-266`, `OnDeviceOrganizer.swift:21-22`, `TruthReconciler.swift:33-36` — the honesty gate's `.strict` mode does not exist.** All three assert grounding is `.strict` on-device / `.relaxed` frontier. **It is hardcoded `.relaxed` on both tiers** (`ProcessingEngine.swift:292,293,297,298`); `strictness` now governs only the mention-drop, as the inline comment at `:280-286` correctly says. *Anyone auditing why the 3B model is safe to ship for Free reads a tighter check than exists.* **Report 3's author ranked this the one to fix first.**
3. **`TruthReconciler.swift:112-113`** — "the caller falls back BOTH summary and title to extractive, so a fabricated title can't survive either." Both callers fall back **independently** (`ProcessingEngine.swift:301-306`, `:527-535`), and the title falls back to `structuralTitle`, which the same file at `:173-176` says is "Deliberately NOT `extractiveTitle`." *Sits directly on the open P1-2 title-fabrication thread; trimming `titleViolates` on the strength of this comment reopens the invented-author defect.*
4. **`FragmentMigration.swift:24-26`** — "flag set ONLY when we've walked at least one entry and found nothing to do." Code sets it on any walk with `entriesFetched > 0` (`:91`). The v5 note (`:30-41`) explains the strict condition was **removed because it resurrected user-deleted notes every launch**. *Restoring the documented rule re-creates that data bug.*
5. **`WatchTransferAudioTranscoder.swift:66-67`** — "Throws so the caller keeps `source` and ships raw rather than losing audio." Raw can never ship: the only `transferFile` site is hard-gated on `isTransferReady` (`WatchTransferService.swift:227`), and `:114` asserts the opposite. *Real worst case is a clip permanently stranded in the pending manifest.*
6. **`WatchRecordingService.swift:19-21`** — names a `WKExtension` deactivate observer as the wrist-off auto-save owner. **No `WKExtension` reference exists in the watch target**; the net is SwiftUI `.onDisappear`. "Never discards" is also false — `handleDisappear` calls `stop(save: false)` for sub-1s / low-peak clips.
7. **`WatchSessionDelegate.swift:819-821`** — "`@Published` re-sets to the same value don't re-fire the sink." `@Published` has no equality check and there is no `.removeDuplicates()`; `WatchAckPipelineMultiClipTests.swift:31-35` explicitly forbids adding one. Benign outcome holds via a different mechanism.
8. **`SpeechService.swift:38-40`** — "UI gates the record button on this." `isModelReady` is written once and read only inside an `NSLog`.
9. **`TutorialOrchestrator.swift:7,:15`** — "only `markSeen` flips it." `markSeen` does not exist; two functions flip it, one being `retireOnePagersReplacedByWalkthrough` (`:138-141`), which marks tutorials seen that the user never saw — the exact second writer the comment denies.
10. **`InboxManifest.swift:1092-1094`** — backup "the first time `load` runs". `load()` (`:938-943`) deliberately moved it out to avoid the two-MOM crash. *The safety copy does not exist as early as documented.*

**Tier 2 (user-visible / dead contracts):** `NotificationService.swift:20-54` (documents Channel A in detail; class has no fire path — it lives in `WatchInboxNotificationCoordinator`; four specifics false) · `ProjectAssistGate.swift:9-14` ("ships gated off, production stays ≥3" — `:22` sets it `true`, production minimum is 1) · `AudioCompressor.swift:13-16` (premise retired under 4a per `WatchSessionDelegate.swift:476-481`) · `DraftReviewSheet.swift:215` ("caller hides the row" — caller gates on `!partition.new.isEmpty` at `:180`, so a sparkles glyph can render over empty text; `DraftReviewSheetCaptionTests.swift:77-80` pins the return value but nothing tests the hiding) · `WatchSessionDelegate.swift:805-843` (durability doc attached to `requestWatchPendingFlush`, which contradicts it at `:840-843`; the function that implements it, `sendConfirmation:954`, is undocumented) · `WatchTransferService.swift:278-281` ("suppressed by the retry-count map" — the map increments before scheduling, so three triggers stack three sleeping Tasks; the cap is real, the de-dup is fictional) · `WatchRecordingService.swift:29-33` (describes retired `averagePower` metering).

**Tier 3 (dead symbols / stale specifics, confirmed):** `WatchHomeView.swift:92-97,:125-135` · `WatchPendingListView.swift:52-53` · `WakeLock.swift:41-43` · **`DisplayModels.swift:27-30`** ("Drives the summary eyebrow" — no readers; the eyebrow reads Core Data, and it is the one field omitted from `==`) · `TutorialOrchestrator.swift:76-78,:81-83` · `WatchRecordingView.swift:9` ("34 rolling bars"; it is 24) · `WatchPendingManifest.swift:409` · `OnDeviceOrganizerCalibrationTests.swift:149`.

**Open cluster for ruling:** `summaryUserEdited` is read in no conditional anywhere (only `EntryExpandedView:918` for display). The no-clobber outcome holds only because `ProcessingEngine` never writes `entry.summary`. The same implication recurs at `JournalEntry.swift:53-61`, `EntryLifecycleService.swift:227-229`, `SummaryFieldMigration.swift:22-25,:67-70`.

**Class 4 — guards that don't guard (largely clean; whole yield is six):**

1. **`WatchClipIdempotencyTests.swift:60-76`** — the `wouldDrop` helper claims to mirror the live call site but **reimplements** the composition; the live site (`WatchSessionDelegate.swift:585-588`) uses `manifest.isRollGroupKnown(...)`, strictly stronger (also matches disposed tombstones). *A regression in the live composition fails nothing.*
2. **`WatchTransferAudioTranscoderTests`** — CLAUDE.md designates it as enforcing "the file handed to `transferFile` MUST be mono/16kHz/AAC … that test failing IS the oversized-transfer bug." It exercises the transcoder and `isTransferReady` in isolation, from the phone target; **nothing asserts `enqueueReadyTransfer` gates `transferFile` on the predicate.** The F18 lesson ("the invariant is one owner, not merely that the owner is correct") unapplied to the transfer path.
3. **`FirstImportStateTests.swift:106,:164-186` — TWO blind spots, both baked in.** (a) The predicate inspects only a ±window around a `var empty…State` declaration, so **`AddExistingClipsSheet.swift:109` is scored compliant forever** (no `isEmpty` in window). (b) **Inline empty-state renders are invisible entirely** — `ManageTopicsSheet.swift:177`, `ManageMentionsSheet.swift:128`, `AddMemoryToProjectSheet.swift:427`. The file's own doc claims seven surfaces; **the scanner can see five and judge four.** It also lacks the non-empty companion and the root-existence throw its siblings have.
4. **`InboxManifestBadgeSyncTests.swift:114`** — literally `#expect(true)`, under a doc claiming it proves `syncBadgeNow()` idempotency.
5. **Environment-gated cluster, 5 tests / 4 files** — `TranscriptionPipelineOutcomeTests.swift:97,116`, `TranscriptionMaxDurationTests.swift:56`, `WatchClipArrivalTranscriptionTests.swift:46`, `AudioCompressorTests.swift:62`, `WatchClipTranscriptionTests.swift:42` all `print` and `return` when the speech model isn't installed. Honestly disclosed, but **they are the only end-to-end coverage of the transcription round-trip**, so on a simulator without the asset that coverage is zero.
6. **Scanner-walk coverage** — of four source-scanning tests, only `SummaryAuthorshipTests` proves its walk reaches source. `ButtonHitRegionTests` and `CaptureAudioSessionConfigTests` throw on a missing root; `FirstImportStateTests` does neither. All four anchor on `#filePath`, so a directory move silently empties three.

**Adjacent live defect (neither class):** `EpigraphService.swift:127-132` — sets a non-recycled predicate on one `NSFetchRequest`, then counts a **different, predicate-less** request. Recycled memories inflate the count driving epigraph stage selection.

**Class 5 concentration — the watch subsystem** (9 of 17 tier-1/2 findings in `Himem Watch Watch App/` + `Shared/` + `Services/Watch/`). **This is comment drift, not structure**: the code moved three times (4a transcode, F18, the 07-29 master-delete fix) and the prose moved once. A comment pass, **not** a rebuild — rebuilding it would solve the wrong problem.

**Coverage:** mechanically swept every `#expect(...isEmpty)`, negative-filter, swallowed-error, exact-copy-string, loop-only-assertion, disabled and assertion-free test across both targets, then read every candidate. **Not covered:** `Views/` spot-checked only for render-claim comments; `SearchViewModel`, `SearchEngine`, `SpeechService` read only around grep hits; several `Models/*` grep-scanned without following named symbols; runtime-timing claims needing a device excluded rather than guessed.

---

## Tier ruling (Tom, 2026-07-31)

Attempt the whole list this pass; **stop at the boundary, not at a count.**

- **Tier 1 — must land:** orphan-sweep disable ✅ `fcb378b` · `PlaceClipSheet` silent success · "Start a Memory" unconditional dismiss · corrupt-manifest reset · **F22 completion**.
- **Tier 2 — if Tier 1 goes clean:** the `.strict` resolution (report which is cheaper first — fix the code or fix the docs) · the propagated `MediaBlobOrphanSweep` false-premise sites · `SessionListView:1379` hand-rolled player (delete it, use `AudioPlayerService`) · `EpigraphService:127-132` · `InboxManifestBadgeSyncTests:114` · the five silently-skipping transcription tests · `WatchTransferAudioTranscoderTests` asserting `enqueueReadyTransfer` gates on the predicate.
- **Tier 3 — if room:** watch comment pass · the F22 scanner's two blind spots · three self-audit doc corrections (`FirstImportState`, `summaryUserEdited`, and adding it to `==`).
- **NOT this pass, regardless:** the **error-surface rebuild** and the **clip-storage seam rebuild**. Both post-tag by ruling — starting a rebuild nine days out is how the window is missed.

**Constraints:** Bug-First on anything behavioural; **one commit per defect**; both schemes green before each commit; stop and report rather than pushing on if anything in Tier 1 surprises.

---

## Retractions this session (four, all mine, all caught before building on them)

1. **"P0-3 is unwired."** A `head -8` filled with one test file's matches. **Truth: P0-3 is fully wired and shipped** (`f938dbc`/`8b1f703`/`20ca598` + migration, all ancestors of HEAD and main).
2. **"The filled ochre primaries are broken."** Overrode Tom's framing. **Truth: they were never broken** — `.frame`/`.background` sit inside the label closure. Exactly one ochre button was stroke-only.
3. **"Plus auto-organize silently overwrites user summaries."** Read off a stale doc comment instead of the call sites. **Truth: all four writes to `entry.summary` are user-initiated**; an organize pass produces a draft awaiting review, and `renderedSummary` reads the stored summary first. **No no-clobber gate was built, because the path it would guard does not exist.**
4. **"`MediaBlobOrphanSweep` is unwired."** Grepped `.orphans(` and `orphans(candidates` while production calls `.plan(`/`.execute(`. **Truth: it was wired via Settings Debug.** This false premise propagated into `WatchSessionDelegate.swift:595` and `AcceptanceCriticalSectionTests.swift:46,:126` and into the F6d commit message and the 07-31 session log. **Correcting those three code sites is a Tier 2 item.** I created an instance of the phantom-comment class while fixing the false-rationale class.

Also over-reported twice: F17's first scan said 16 candidates when 7 were real (missed ternary fills); F18's first guard flagged three `.playback` sites while missing the real offender (the call wraps five lines).

**Common shape, all six:** a signal that looked authoritative because it was well-formed — a truncated grep, a stale comment, someone else's framing — trusted instead of the underlying source. Codified in `CLAUDE.md` under *Measurement Discipline* and *Identify the Red*.

---

## F22 state, precisely (for whoever resumes it)

**Built:** `FirstImportState` — `@MainActor`, `ObservableObject`, `Phase` = `importing`/`complete`, one question `mayAssertEmpty`. Latches on first `.import .succeeded`, 3s fallback (mirroring the proven net in `LaunchScreenView:268`), persists per install, injectable `UserDefaults`. Six state-machine tests pass: fresh install forbids empty claims, first success latches, later batches don't reopen, no-event fallback fires, completion survives relaunch, a different install starts importing again.

**Copy ruled (Tom), not wired:**
- Memories — "**Getting your memories from iCloud** / This can take a minute on a new device."
- Projects — "**Getting your projects from iCloud**" (no second line)
- Recently Deleted — "**Getting things from iCloud** / Anything you've deleted recently will appear here."
- Parallel construction across all three; "from iCloud" kept deliberately (names where her things are; the custody story).

**Open decision:** I proposed that **secondary surfaces render nothing at all while importing** — no empty state, no message, no spinner — so the copy surface stays at three while all ~14 gated surfaces are behind the owner. I took "land it" as approval; **confirm explicitly before wiring, it decides eleven surfaces.**

**Surfaces needing the gate (~14):** `JournalView:538/539` · `ProjectListView:33` · `RecycleBinView:117` · `SessionListView:419` · `ClipsTabView:1545,:1647` · `AddExistingClipsSheet:109` · `AddMemoryToProjectSheet:188,:204,:481` · `ProjectDetailView:208` · `ManageTopicsSheet:176,:263` · `ManageMentionsSheet:202`.

**Exempt (~13, each needs a STATED reason per ruling, not a bare EXEMPT):** form validation (`OnboardingView:518`, `PermissionWizardView:1137`) · StoreKit (`PricingView:61`) · in-flight transcript (`VoiceCaptureScreen:300`, `ClipAtomView:497/503/509`) · edit-field contents (`ClipEditorModal:352/430`) · current selection (`ManageMentionsSheet:127`, `AddMemoryToProjectSheet:426`) · computed maintenance plan (`SettingsView:464`).

**Two flagged as genuinely uncertain — mark EXEMPT with a findable reason rather than guessing:** `EntryExpandedView:1132` (a loaded memory's own media — the memory imported, its edges may not have) and `SettingsView:371` (`hits`, backing store not traced).

**The scanner must be fixed before wiring** (audit finding, Class 4 #3): it sees five surfaces and judges four. Needs the union of both shapes (named `empty…State` views **and** inline non-negated `.isEmpty` branches that render text), plus a non-empty companion assertion and a root-existence throw. Annotation convention is ruled: scope `Views/`, don't relax the discriminator to shrink the count (23 sites by the tightened rule, 29 by the union), and every `F22 EXEMPT:` must name why the collection cannot come from an unimported store.

---

## Open threads carried forward

- **Device pass (Tom's, the bottleneck)** — five items: reordered Memory Detail · the three summary eyebrow states · the F16 ring on the completed-walkthrough path · F18's iPad capture fixes (live preview **and** sane landscape now the clamp is gone) · **F6g's runtime-issue breakpoint stack**. Plus **T7**: re-test the three iPad symptoms after a completed sync (capture failure, non-tappable pill, walkthrough re-offering) — a device mid-import may explain some, and that result may shrink the list.
- **F6g** — off-main `objectWillChange`. Untouched by ruling. Outcome one (views observing `MediaReference` while a background context mutates it) → F6a pass-1 evidence, defer. Outcome two (CloudKit mirroring's own `NSCK*` objects) → log and stop.
- **App Store submission** — no release Xcode on this machine. Xcode Cloud / second Mac / macOS 26.6 (shipped 07-27). **TestFlight is unaffected** — beta-SDK builds are accepted there, established empirically by upload.
- **iPad screenshots** — submission-blocking metadata, parallelizable. F6k spot-check narrowed to three full-screen modals (walkthrough overlay via Settings → Learn, `ClipEditorModal`, `EntryExpandedView`).
- **F21** — three-state transcript affordance ruled ("Transcribe", no "again"); state 3 explicitly NOT built (Anthropic takes no audio; it would be Memory Polish §3 text repair, parked with a negative on-device spike).
- **Deferred with rulings:** `DraftReviewSheet` keep-mine option · F6e coordination asymmetry · shared button primitive · `duration` on `MediaReference` next schema batch · `v1.0-b27` re-cut and the `f8 → main` merge · `GET /himem/epigraphs` 404.
- **Tom's:** J3 · the bench action's name · the walkthrough copy cold-read.

## Risks

- **Everything since `f0357a3` is simulator-verified only.**
- **The working tree has a deliberate red** (F22 surface guard, untracked). Do not "fix" it by weakening the scanner.
- **Judi tests a beta-SDK binary**; the submitted build will use a different toolchain and SDK.
- **`.measurement` was live on the phone for two weeks** after being fixed on the watch — the next build's recordings should be measurably louder; if transcription coverage improves on comparable clips, that confirms the cost.
- **The project mixes filesystem-synchronized groups** (`MemoryStreamTests`, watch targets) **with explicit `project.pbxproj` references** (`Shared/`, app `Views/`, `Services/`). Where a file lives decides whether adding or renaming one is free; a `git mv` in `Shared/` broke the build until references were updated.
- **Two rebuild candidates are deliberately deferred** and will keep producing instances until done: the error surface (59 report sites, one unreachable renderer) and the clip-storage seam (device-local manifest describing device-shared files).

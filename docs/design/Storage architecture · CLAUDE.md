# Storage architecture · CLAUDE.md

> Locked architectural decisions for how HiMem stores and syncs user data.
> Locked 2026-06-07. If a decision here changes, mirror the change in
> `/CLAUDE.md` (project root) and `docs/design/CLAUDE.md` in the same PR.

---

## The model

HiMem stores user data in two layers, each with a different durability and sync mechanism.

| Layer | Lives in | Sync via | Cost paid by |
|---|---|---|---|
| **Durable memory** | CloudKit (Core Data + NSPersistentCloudKitContainer) | CloudKit | Us (CloudKit COGS) |
| **Originals** | iCloud Drive ubiquity container | iCloud Drive | User (iCloud quota) |

### The split, precisely

**Durable memory** is the canonical record of what the user captured:
- Transcript text
- Title / summary / topics / projects / mentions
- Timestamps, location metadata (lat/lon, place name)
- Memory-to-project relationships
- Per-clip metadata: `osIdentifier` (filename), `transcript`, `createdAt`, `placeName`, `latitude`, `longitude`

Durable memory **is the memory.** A user can lose every audio file, every photo, every video, and the journal entry — the thing they remember and reflect on — is intact. Transcripts survive; sentiment and synthesis survive; project membership survives.

**Originals** are the captured artifacts — the audio waveform, the photo, the video — that the user can choose to play back. They are:
- Not required for the memory to exist as a meaningful record
- Optional evidence the user can revisit
- Stored as opaque files in iCloud Drive ubiquity container

### Why this split

CloudKit is the right tool for **structured, queryable, relational data** that benefits from incremental sync, conflict resolution, and per-record subscriptions. It is the wrong tool for **large opaque byte blobs**, because the bytes count against our CloudKit COGS, sync semantics are not optimized for media, and the storage cost scales with every user.

iCloud Drive is the right tool for **user-owned files** that:
- The user can see and manage themselves (Files.app)
- Can be exported to other apps (Voice Memos, Photos, share sheet)
- Cost the user, not us
- Have well-defined lifecycle semantics across uninstall + reinstall

Mixing the two correctly gets HiMem the best of both: structured data flows through the database; bytes flow through the file system. The user pays for their own original recordings; we pay for the database that makes the journal work.

---

## Locked rules

### Rule 1 — All originals live in the iCloud Drive ubiquity container

**Path scheme:**
```
~/Library/Mobile Documents/iCloud~com.himem.app/Documents/
    Audio/<UUID>.caf
    Photos/<UUID>.jpg
    Videos/<UUID>.mov
```

This is the canonical home for every audio recording, photo, and video HiMem captures. Sandbox-Documents-based storage (`Documents/VoiceEntries/`, etc.) is retired for new captures and migrated for existing data.

**Info.plist requirement:** `NSUbiquitousContainerIsDocumentScopePublic = YES` on the iCloud container. This makes the "HiMem" folder visible in Files.app and makes the files **user-owned documents** that survive app uninstall.

### Rule 2 — MediaReference.osIdentifier is a relative path inside the ubiquity container

`osIdentifier` is a string like `"Audio/<UUID>.caf"` — the path from the ubiquity Documents root. Resolving to a URL: `ubiquityDocuments.appendingPathComponent(osIdentifier)`. **Never** store an absolute path or a sandbox-relative path; those don't survive uninstall.

### Rule 3 — Reads use NSFileCoordinator + download-on-demand

Code that opens a file at a ubiquity path **must** assume it may not yet be downloaded locally. The pattern:

1. Check `URLResourceValues.ubiquitousItemDownloadingStatus`.
2. If `.current` or `.downloaded`, read directly.
3. If `.notDownloaded`, call `FileManager.startDownloadingUbiquitousItem(at:)`, surface a "downloading" UI state, and re-check on `.NSMetadataQueryDidUpdate` or after a coordinated read.
4. Reads must use `NSFileCoordinator` to be safe against partial-write states from the sync process.

**UI implication:** every audio / photo / video render path must be able to show a "downloading from iCloud" placeholder. This is the same pattern PhotoKit uses for non-cached iCloud Photos today, so the UX vocabulary already exists.

### Rule 4 — Be honest in UX about where media lives

Never silently render "0:00" or a dead play button. The user must always know:

- **File downloaded and ready:** play normally, no banner needed.
- **File downloading:** show a small spinner with "Downloading from iCloud" label. Disable play until ready.
- **File present in iCloud but not on this device, no network:** show "Original audio is in your iCloud · connect to download" with a retry affordance.
- **File deleted from iCloud (rare):** show "Original audio was deleted" with the transcript still surfaced as the memory.

The Settings → About surface includes one persistent explainer:

> "Your transcripts, titles, summaries, and metadata sync via iCloud (CloudKit). Original audio, photos, and videos live in your iCloud Drive under the HiMem folder — visible in Files.app, exportable anywhere, durable across reinstalls. We don't store original recordings on our servers."

### Rule 5 — Voice Memos / Photos integration is user-driven, not programmatic

Voice Memos has no public API. We do not try to interop with it programmatically. Because originals live in iCloud Drive and are visible in Files.app, the user can:
- Open Files.app → HiMem → tap an audio file → "Open in Voice Memos" (system share sheet)
- Open Files.app → HiMem → share / export anywhere they want
- Drag files out in Files.app on iPad / macOS

No HiMem code or UI is required for this. Files.app handles it. HiMem simply doesn't get in the way.

### Rule 6 — Camera-captured photos and videos also save to the user's Photos library by default

When the user captures via HiMem's in-app camera, the file:
1. Always lands in the ubiquity container (this is the canonical copy HiMem references).
2. Also gets written to the user's Photos library via `PHPhotoLibrary.performChanges` (the default — users expect their photos to land in Photos).

The Photos library copy is a courtesy convenience for the user's existing photo workflow. The ubiquity container copy is what HiMem references.

A user-facing Settings toggle ("Also save HiMem captures to my Photos library") can disable the Photos-library write — defaults to on. The ubiquity write is never optional; that's where HiMem reads from.

### Rule 7 — Recording device preserves its own audio

Re-statement of the `c89bee1` fix and the `feedback_no_auto_reprocess` companion principle: code that runs at save time **never** deletes the file a `MediaReference` is about to be created against. The recording device is the source of truth for that file's first write to ubiquity; deleting it before the write happens orphans the user's memory at a phantom path.

`VoiceCaptureOrchestrator.shouldDeleteMaster(masterFilename:fragments:)` encodes the safe predicate: delete the master only when no fragment references it (i.e., a multi-clip split actually produced separate files).

### Rule 8 — No Binary Data attributes on MediaReference

Do not add `audioData`, `imageData`, `videoData`, or any other Binary Data attribute to `MediaReference` in the Core Data model. The bytes go through iCloud Drive, not CloudKit. This rule exists because the temptation will resurface in future "wouldn't it be cleaner to just sync everything via CloudKit" PRs — the answer is no, and the COGS-cost reasoning here is the reason.

---

## Durability properties (what the user gets)

Given the rules above, the following guarantees hold for the user:

1. **Uninstall + reinstall HiMem on the same device.**
   - Durable memory: survives (CloudKit re-syncs).
   - Originals: survive (`NSUbiquitousContainerIsDocumentScopePublic` keeps the iCloud Drive folder intact; local cache re-downloads on demand).
   - End state: full restoration of the user's journal.

2. **New device, same iCloud account.**
   - Durable memory: syncs down via CloudKit on first launch after iCloud sign-in.
   - Originals: appear in Files.app immediately; downloaded on-demand when opened.
   - End state: full restoration of the user's journal.

3. **User loses phone, replaces it.**
   - Same as case 2. The journal lives in the user's iCloud, not on the device.

4. **User explicitly deletes a file from Files.app → HiMem.**
   - Durable memory: intact (transcript still shows).
   - That original: gone. Memory Detail shows "Original was deleted" alongside the surviving transcript.

5. **User signs out of iCloud entirely.**
   - Durable memory: stops syncing; existing local copy remains until the persistent store is touched by a sign-back-in.
   - Originals: stops syncing. Local cached copies remain accessible until evicted.
   - HiMem becomes effectively a single-device experience again. Honest UX surfaces this state.

6. **User over iCloud quota.**
   - New writes queue locally and surface a "couldn't sync — iCloud full" affordance.
   - Existing data is unaffected.
   - Does not corrupt anything; just stalls forward progress.

---

## What this replaces

This document supersedes (or contradicts) the following earlier framings:

- **"Audio is local-only by design."** Audio is now durable across the user's devices via iCloud Drive. The honesty surface evolves from "stored on this device" to "stored in your iCloud Drive, available across your devices."
- **"Photos live in PhotoKit and HiMem just references."** PhotoKit is now an **import source** for the camera flow and PHPicker, not the canonical storage. HiMem owns its own copy in the ubiquity container.
- **"Binary Data on MediaReference, synced via CloudKit / CKAsset."** Explicitly rejected in favor of iCloud Drive. See Rule 8.

---

## Implementation status (as of 2026-06-07)

**Pre-launch:**
- [ ] Add iCloud Drive ubiquity entitlement + `NSUbiquitousContainers` Info.plist config (`NSUbiquitousContainerIsDocumentScopePublic = YES`, display name "HiMem").
- [ ] Migrate `SpeechService.audioURL(for:)` and `InboxManifest.audioURL(for:)` to resolve under the ubiquity container.
- [ ] Migration pass: move existing `Documents/VoiceEntries/*.caf` and `Documents/ClipInbox/audio/*.caf` into the ubiquity container at first launch on the new build, update no MediaReference rows (filenames stay the same).
- [ ] UI states: "downloading from iCloud" placeholder on `AudioPlayerSheet`, `MediaTile`, and any inline waveform render path.
- [ ] Settings → About explainer line per Rule 4.

**Post-launch (v1.1):**
- [ ] Photos + videos move from PhotoKit references to ubiquity-owned bytes. Storage-duplication question is settled separately (do not block launch on it).
- [ ] In-app camera "also save to my Photos library" toggle.
- [ ] Lazy-on-access migration for existing `PHAsset`-backed `MediaReference` rows.

**Not in scope (explicitly):**
- Programmatic Voice Memos integration.
- Binary Data attributes on `MediaReference`.
- CKAsset usage for media bytes.

---

## v2 direction (post-launch)

The v1 architecture (this document) splits responsibility cleanly: CloudKit for structured data; iCloud Drive for originals. That's a meaningful resilience win, and it's what ships at launch.

**v2.0 closes the remaining custody surface.** Per the principle locked 2026-06-07 ("HiMem keeps no user data — only indices on the user's device"), the data layer rebuilds so every memory is a JSON (or Markdown+YAML) file under the user's iCloud Drive HiMem folder. Topics and Projects also become files. Local SQLite becomes a derived cache: ephemeral, rebuilt from files on first launch of each device, never synced. CloudKit retires entirely.

**Why this is post-launch, not pre-launch:** it's a data-layer rebuild, not a refactor. The migration from CloudKit-structured-data to file-structured-data is its own multi-day design effort. NSMetadataQuery-based change watching, conflict-copy UX, file-versioning for schema evolution — all real engineering. v1 captures ~90% of the user-facing value of the principle by putting originals in iCloud Drive; v2 captures the rest by retiring CloudKit.

**The v2.0 release pitch:** "Your journal is a folder you own. We just read it." The marketing arc is worth a whole release.

See the memory entry `project_himem_v2_files_as_source_of_truth` for the locked thesis and design constraints.

---

## Companion docs

- `/CLAUDE.md` (project root) — overall governance.
- `docs/design/CLAUDE.md` — design-system source of truth.
- `~/.claude/projects/-Users-tom-dev-himem/memory/feedback_no_auto_reprocess.md` — once an organize runs, it sticks until the user reorganizes; analogous principle for *content* that complements this doc's principle for *media*.

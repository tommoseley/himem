# Captured Clips · watch → phone sync system

_How a single Apple Watch recording becomes one (or more) reviewable
session card in the iPhone's Captured Clips screen. Reference doc;
update when the actual code changes._

_Last revised: 2026-05-29 after sync-surface phases 1–5 landed._

---

## 1 · Goals

The watch is a **capture queue**: a recorder with a tiny pending list
and no review surface. Everything captured eventually surfaces on
the iPhone, where the user reviews and decides what becomes a Memory.

Two cardinal rules drive the design:

- **Never lose audio the user recorded.** A clip the user committed
  to must survive any single failure between the moment the tap
  ended and the moment it shows up on the phone — temporary
  unreachability, phone reboot, phone reinstall, model-install
  race, AAC encode failure, etc.
- **Never silently double-count or ghost-deliver.** If the user
  intentionally disposed of a clip, it stays disposed of even when
  iOS's WC layer redelivers the file from its system queue hours
  or days later. If the watch retries a transfer, the phone
  recognizes it as a redelivery.

The honest UX consequences live in the
`screens-captured-clips-sessions.jsx` § SYNC / INCOMING spec:
clips don't teleport in, they move through visible phases
(downloading → transcribing → ready) so the user can tell
"in progress" from "silently failed."

---

## 2 · End-to-end data flow

```
Apple Watch                                       iPhone
─────────────                                     ──────────────
WatchRecordingService                             SessionListView
   ↓ stop(save:)                                     ▲
WatchPendingClip + master.caf                       │ renders
   ↓ append                                        InboxArrivalTracker
WatchPendingManifest                                │ (in-flight)
   ↓ send(clip:)                                   InboxManifest
WatchTransferService ────────[sendMessage]──────►   │ (ready)
   ↓                          (pre-announce)        │
   └────[transferFile]──────►                     ──┴── WatchSessionDelegate
                              (durable)              ↓
                                                  session(_:didReceive:)
                                                     ↓
                                                  acceptArrivedClip
                                                     ↓ (split if On-a-roll)
                                                  VoiceClipSplitter
                                                     ↓
                                                  AudioCompressor
                                                     ↓
                                                  TranscriptionService
                                                     ↓
                                                  recordTranscriptionAttempt
                                                     ↓ ack ◄────────
                                                                  ────
                                                  user reviews, bundles
                                                     ↓
                                                  EntryLifecycleService.appendClips
                                                     ↓
                                                  InboxManifest.removeBatch
                                                     ↓
                                                  InboxProcessedClipIds.markProcessed
                                                     ↓ ack ────────►
                                                                  watch
                                                                  removes
                                                                  pending row
```

Every arrow is either:

- **WCSession.transferFile** — durable, OS retries, eventually
  delivers as `session(_:didReceive:)` on the iPhone.
- **WCSession.sendMessage** — best-effort, fires only when both
  apps are reachable. Used for pre-announce and ack delivery.
- **WCSession.transferUserInfo** — durable backup for messages,
  delivered as `session(_:didReceiveUserInfo:)` on the watch.

---

## 3 · Models

### 3.1 · Watch (`WatchPendingClip`)

The watch's source of truth for "audio that hasn't been delivered to
the iPhone yet." Persisted to `Documents/Pending/manifest.json`;
audio files at `Documents/Pending/audio/<clipId>.caf`.

```swift
struct WatchPendingClip {
    let clipId: UUID
    let capturedAt: Date
    let duration: TimeInterval
    let transcript: String          // always "" — watch never transcribes
    let latitude: Double?
    let longitude: Double?
    let audioFilename: String       // <clipId>.caf
    let rollGroupId: UUID?          // shared across all clips in one On-a-roll
                                    // session; nil for single-clip captures
    let nextTapOffsets: [TimeInterval]  // seconds from recording start;
                                        // empty for non-On-a-roll sessions
}
```

### 3.2 · Wire (`ClipMetadata`)

The dictionary the watch packs into `WCSessionFileTransfer.metadata`
and into the pre-announce `sendMessage` payload. All transport-layer
serialization goes through `ClipMetadata.asWireDict()` /
`ClipMetadata.fromWireDict(_:)`.

```swift
struct ClipMetadata {
    let clipId: UUID                // idempotency key, see § 7
    let capturedAt: Date
    let duration: TimeInterval
    let transcript: String          // always "" from watch
    let latitude: Double?
    let longitude: Double?
    let source: String              // "watch"
    let rollGroupId: UUID?
    let nextTapOffsets: [TimeInterval]
}
```

### 3.3 · iPhone — in-flight (`InboxArrivalTracker.InFlightClip`)

The iPhone's view of clips that are still arriving / transcribing —
before they become reviewable in the manifest. New 2026-05-29 (sync
surface phases 1–5); see § 6 for the phase machine.

```swift
struct InFlightClip {
    let clipId: UUID
    let capturedAt: Date
    let durationSeconds: TimeInterval
    let latitude: Double?
    let longitude: Double?
    let fileSizeBytes: Int64?
    let announcedAt: Date           // from pre-announce sendMessage time
    var phase: Phase                // .waiting | .downloading | .transcribing | .paused
}
```

### 3.4 · iPhone — ready (`InboxClip`)

A reviewable row in `InboxManifest`. Persisted to
`Documents/InboxManifest.json`; audio at `Documents/Inbox/audio/`.

```swift
struct InboxClip {
    let clipId: UUID
    let capturedAt: Date
    let duration: TimeInterval
    let transcript: String
    let latitude: Double?
    let longitude: Double?
    let source: String
    let audioFilename: String
    let transcriptionAttempted: Bool  // false until SpeechAnalyzer ran end-to-end;
                                      // see § 5.5 for the failure-mode contract
    let rollGroupId: UUID?
}
```

### 3.5 · iPhone — disposed (`InboxProcessedClipIds`)

A bounded persistent set (max ~2000) of clipIds the user has
disposed of — promoted to a memory, user-deleted, or
session-discarded. Survives launches via JSON at
`Documents/InboxProcessedClipIds.json`. Used to recognize and drop
ghost re-deliveries from iOS's WC queue. See § 7.3.

---

## 4 · Services

### 4.1 · Watch side

| Service | Role |
|---|---|
| `WatchRecordingService` | AVAudioEngine + writes `master.caf`. On `stop(save:)`, calls `WatchPendingManifest.append(clip)` |
| `WatchPendingManifest` | Persistent list of unsent clips. Dedupes on append by clipId. Tracks `lastConfirmedReceiptAt` for the sync-stuck banner. |
| `WatchTransferService` | Owns `WCSession`. `send(clip:)` does **(1)** pre-announce sendMessage, **(2)** `transferFile`. Handles incoming ack payloads via `handleAckPayload`. |
| `WatchAppCoordinator` | Subscribes to `transfer.$lastAckedClipId`, removes acked clips from the manifest. Triggers `retryPendingTransfers` on launch + reachability restoration. |

### 4.2 · iPhone side

| Service | Role |
|---|---|
| `WatchSessionDelegate` | The iPhone's `WCSessionDelegate`. Handles `session(_:didReceiveMessage:)` (pre-announce), `session(_:didReceive:)` (file arrival), `sessionReachabilityDidChange` (pause/resume). |
| `WatchPreAnnounceParser` | Pure parser for the pre-announce payload dict → `Parsed` struct. |
| `InboxArrivalTracker` | In-flight phase state per clipId. See § 6. |
| `VoiceClipSplitter` | Splits a master `.caf` into N per-clip files using `nextTapOffsets`. Used by On-a-roll sessions only. |
| `AudioCompressor` | PCM `.caf` → AAC `.m4a` in place. Roughly 20–50× size reduction on speech. Verified round-trip through `SpeechAnalyzer` via `AudioCompressorTests`. |
| `InboxManifest` | Source of truth for ready clips. `acceptClip`, `recordTranscriptionAttempt`, `remove`, `removeBatch`. Calls `InboxProcessedClipIds.markProcessed` on every removal. |
| `TranscriptionService` | Wraps `SpeechAnalyzer` + `SpeechTranscriber`. Returns an `Outcome` enum (see § 5.5). |
| `InboxTranscriptionDispatcher` | Pure function: given an `Outcome`, decide whether to flip `transcriptionAttempted` (only `.transcribed` does). |
| `InboxProcessedClipIds` | Bounded persistent dedup set. See § 7.3. |

### 4.3 · UI surfaces

`SessionListView` is the only Captured Clips entry point. It reads
from `InboxManifest` (ready clips, grouped into sessions) and
`InboxArrivalTracker` (in-flight clips, rendered as `IncomingCard`s).

| View | Role |
|---|---|
| `SyncStrip` | Top banner: "Receiving from your Watch · N of M" or "Waiting for your Watch" |
| `IncomingCard` | Per in-flight clip; meta row + `PhasePill` + phase-specific body |
| `PhasePill` | Waiting / Receiving / Transcribing / Paused with SF Symbol + label |
| `ShimmerLine` | Animated transcript placeholder under transcribing cards |
| `SessionCard` | Ready clips, grouped into `ClipGroup`s, with collapsed / expanded body |
| `CapturedClipsSubtitleBuilder` | Pure formatter for the header subtitle (cross-day aware, sync-aware) |

---

## 5 · Lifecycle phases

### 5.1 · Recording

User taps record on the watch. `WatchRecordingService` opens an
`AVAudioEngine` tap and writes float-32 PCM to `Documents/Pending/audio/<UUID>.caf`. On stop, builds a `WatchPendingClip` and calls
`WatchPendingManifest.append(_)`.

For On-a-roll sessions, the user can tap "Next" mid-recording — the
service records the offset in `nextTapOffsets` but **keeps writing
to the same master file**. The split into discrete clips happens on
the iPhone (§ 5.4), not on the watch.

The hard cap is 5 minutes per recording; recordings auto-stop at
the cap.

### 5.2 · Transfer to iPhone

`WatchTransferService.send(clip:)` runs at:

- The end of every successful recording.
- `retryPendingTransfers()` on watch app launch (drains any
  manifest rows whose ack got lost).
- `sessionReachabilityDidChange` true (re-queues every pending
  clip when the iPhone becomes reachable again).
- `flushPendingManifest()` in response to an iPhone-side
  `command: flushPending` message (the user's manual pull-to-refresh).

For each call:

1. **Pre-announce sendMessage** (2026-05-29+). A dictionary with
   `preAnnounce: true`, `clipId`, `capturedAt`, `duration`,
   `fileSizeBytes`, `latitude`, `longitude`. Sent only when
   `session.isReachable` (sendMessage requires both apps active).
2. **`session.transferFile(url, metadata:)`**. Durable. iOS
   queues the file and retries delivery indefinitely on its own
   schedule. The watch's local copy stays on disk until acked.

The pre-announce is best-effort. If it fails (phone backgrounded,
out of range, etc.), the file still arrives later — the iPhone
synthesizes an `InFlightClip` from the manifest when the file
lands (§ 5.4).

### 5.3 · iPhone-side reception

The iPhone has three relevant `WCSessionDelegate` entry points:

#### 5.3a · `session(_:didReceiveMessage:)` (pre-announce)

1. `WatchPreAnnounceParser.parse(message)` returns nil for any
   payload that isn't a complete pre-announce (missing or wrong
   `preAnnounce`, missing/malformed `clipId`, missing
   `capturedAt`/`duration`).
2. On a valid parse, `InboxArrivalTracker.recordPreAnnounce(...)`
   creates an `InFlightClip` in **`.downloading`** (if no other
   clip is currently downloading) or **`.waiting`** (if there is).
3. SwiftUI updates: `SessionListView` re-renders, an `IncomingCard`
   with the appropriate `PhasePill` shows up above the session list.

#### 5.3b · `sessionReachabilityDidChange`

Reachability ↓ → `recordReachabilityLost()` flips every
downloading/waiting clip to `.paused`. Transcribing clips are
unaffected (they're running on-device).

Reachability ↑ → `recordReachabilityRestored()` promotes the
oldest paused clip back to `.downloading`, the rest re-queue as
`.waiting`.

#### 5.3c · `session(_:didReceive: file:)` (file arrival)

1. Decode `metadata` via `ClipMetadata.fromWireDict(_:)`. Drop
   the transfer if malformed (better to lose one clip than corrupt
   the inbox).
2. **B5 dedup check**: if `clipId` is in
   `InboxProcessedClipIds.shared`, ack-and-drop. This catches iOS
   re-delivering files the user already disposed of from its
   system WC queue. § 7.3.
3. Move the file synchronously from the system-managed URL
   (deleted on delegate return) to `InboxManifest.audioURL(for:
   "<clipId>.caf")`. If the destination already exists, skip the
   copy (re-delivery edge — same file, different metadata, system
   redelivered).
4. **Send ack immediately**, before any async work. `sendMessage`
   ack on the fast path, `transferUserInfo` ack as durable
   backup. Acking before async work prevents a slow downstream
   step (AAC compression on a long clip) from leaving the watch
   in "Hasn't reached your phone in a day."
5. Hop to `@MainActor` and call `acceptArrivedClip(metadata:
   masterFilename:)`.

### 5.4 · `acceptArrivedClip` — split vs single

```
acceptArrivedClip(metadata, masterFilename)
   │
   ├── isMasterAlreadyProcessed(metadata, manifestClips)?
   │      yes → delete master file, send ack, return
   │
   ├── offsets.isEmpty?
   │      yes (single-clip path):
   │        - compress master in place
   │        - create one InboxClip with clipId = metadata.clipId
   │        - manifest.acceptClip(_)
   │        - done
   │
   └── (On-a-roll path):
        - VoiceClipSplitter.split(masterURL, nextTapOffsets, outputDir, rollGroupId)
            → N fragment files
        - compress each fragment in place
        - for each fragment: create InboxClip with NEW UUID
          clipId, but rollGroupId = master.rollGroupId
          (or master.clipId if rollGroupId was nil)
        - manifest.acceptClip(_) for each
        - delete the master file (its contents now live in the
          fragments)
        - on split error: fall back to one InboxClip pointing at
          the master (don't lose audio)
```

The split's per-clip `capturedAt`:
`clip[0] = sessionStart`; `clip[i] = sessionStart + offsets[i-1]`
for i > 0.

**Idempotency contract** (see `isMasterAlreadyProcessed`): the
master is treated as already processed if ANY manifest clip
matches by either `clip.clipId == metadata.clipId` (single-clip
path) OR `clip.rollGroupId == (metadata.rollGroupId ??
metadata.clipId)` (split-clip path — every fragment carries the
master's rollGroupId).

### 5.5 · Transcription

`WatchSessionDelegate.transcribePendingInboxClips()` runs from:

- After every `acceptArrivedClip` (per-clip).
- On `scenePhase → .active` (scene-active backstop).

For each clip where `transcript.isEmpty && !transcriptionAttempted`:

1. **Enter `.transcribing` phase** in the tracker (creates or
   updates the `InFlightClip`; falls back to the manifest's data
   if no pre-announce was recorded).
2. `TranscriptionService.transcribe(audioURL:)` returns an
   `Outcome` enum (introduced 2026-05-29 after a hero-path bug):
   - `.transcribed(Result)` — model ran end-to-end. `text` may
     be empty if genuine silence; `result.coverageSeconds` and
     `result.segmentCount` distinguish "scanned + heard nothing"
     from "rejected the audio."
   - `.modelNotInstalled` — SpeechTranscriber asset isn't on
     device yet (cold-launch race against the pre-warm task).
   - `.fileUnreadable(Error)` — `AVAudioFile(forReading:)` failed.
   - `.transcriberFailed(Error)` — `SpeechAnalyzer.start` threw.
3. `InboxTranscriptionDispatcher.shouldMarkAttempted(for:)`
   returns `true` only for `.transcribed`. The other three cases
   leave the clip with `transcriptionAttempted == false`, so the
   next sweep retries them.
4. On `true`, `manifest.recordTranscriptionAttempt(clipId:,
   transcript:)` writes the transcript onto the manifest row.
5. **Exit `.transcribing` phase** (regardless of outcome) —
   `tracker.clear(clipId:)`. Promotes the next waiting clip to
   `.downloading` if one exists.

Diagnostic logging on every transcribe call:

```
[Himem][Transcribe] start url=… duration=…s locale=…
[Himem][Transcribe] file open ok bytes=… frames=… fileFmt=… procFmt=…
[Himem][Transcribe] done segments=N coverage=Xs file=Ys textLen=Z [DIAG=…]
```

The `[DIAG=…]` tag explicitly tags the empty-result subcase:
`rejected` (segments=0, coverage<0.1) / `scanned-no-recognition`
(segments=0, coverage>0) / `segments-but-empty` (rare).

### 5.6 · User review + bundle

`SessionListView` groups manifest clips into `ClipGroup`s via
`ClipSessionGrouper`. The user expands a session card, selects
clips, taps "Make or Add To a memory." This routes through
`CreateMemoryFromClipsSheet`:

- New memory: `EntryLifecycleService.saveEntry(...)` →
  `manifest.removeBatch(clipIds:)`.
- Add to existing: `EntryLifecycleService.appendClips(entryId:,
  clips:)` → `manifest.removeBatch(clipIds:)`.

Either way, every removed clipId is passed through
`InboxProcessedClipIds.shared.markProcessed(_:)`. The same happens
on `manifest.remove(clipId:)` (single-clip user delete or
session discard).

### 5.7 · Ack delivery + watch-side removal

The iPhone-side ack flow is wired in two places:

- `WatchSessionDelegate.session(_:didReceive: file:)` — immediate
  per-clip ack via both `sendMessage` (best-effort fast path) and
  `transferUserInfo` (durable backup) on every file arrival.
- `WatchSessionDelegate.reconcileWatchAcks()` — re-broadcasts the
  ack for every clip currently in the manifest. Wired to:
  - per-clip arrival
  - `scenePhase → .active`
  - `JournalView` pull-to-refresh
  - `SessionListView.onAppear`

The watch side parses `confirmedClipId` payloads in
`WatchTransferService.handleAckPayload(_:)` and forwards to
`WatchPendingManifest.remove(clipId:, viaSync: true)`. That
removes the row, deletes the local audio, and updates
`lastConfirmedReceiptAt` so the "Hasn't reached in a day" chip
clears (logged as
`[Himem][WC] watch — performRemoval done clipId=… remaining=…
lastConfirmedReceiptAt=…`).

---

## 6 · The phase machine (sync surface)

The four-phase state model lives in `InboxArrivalTracker`. Each
in-flight clip moves through some subset of these states:

```
                  pre-announce
        (none) ──────────────────► .waiting
                  (other dl active)

                  pre-announce
        (none) ──────────────────► .downloading
                  (no dl active)

   .waiting ──── promoted ───────► .downloading
                  (peer transcribed)

   .downloading ── file arrived ─► .transcribing

   .transcribing ── transcribe done ► (cleared from tracker;
                                        clip becomes a ready
                                        InboxClip in the manifest)

   .downloading ── reachability ───► .paused
   .waiting      lost
   .paused ──── reachability ─────► .downloading (oldest)
                  restored               .waiting (rest)
```

Queue invariant: at most one clip in `.downloading` at a time,
matching how iOS's WC layer actually serializes `transferFile`.
`.transcribing` clips don't count against the queue — they're
running on-device.

The UI on each phase is in `IncomingCard.swift` and `PhasePill.swift`.
Spec source: `screens-captured-clips-sessions.jsx` § SYNC / INCOMING.

---

## 7 · Idempotency contracts

The two "never lose, never double" guarantees from § 1 live in
three orthogonal dedup layers.

### 7.1 · Watch-side pending dedup

`WatchPendingManifest.append(clip)` is idempotent on clipId:

```swift
guard !clips.contains(where: { $0.clipId == clip.clipId }) else { return }
```

A recording's clipId is generated at `stop(save:)` time and never
reused, so this only catches code paths that try to enqueue the
same clip twice (rare; a defensive belt).

### 7.2 · Phone-side in-manifest dedup

`WatchSessionDelegate.isMasterAlreadyProcessed(metadata,
manifestClips)`:

```swift
let dedupRollGroupId = metadata.rollGroupId ?? metadata.clipId
return manifestClips.contains { clip in
    clip.clipId == metadata.clipId
        || clip.rollGroupId == dedupRollGroupId
}
```

Catches two scenarios:

- **Single-clip redelivery**: the arrived clipId matches an
  existing `InboxClip.clipId`.
- **Split-clip redelivery**: any fragment in the manifest carries
  the same `rollGroupId` as the arriving master, even though the
  fragment clipIds differ.

When this returns true: delete the redelivered master file from
inbox audio dir, send the ack, return. Manifest is unchanged.

### 7.3 · Phone-side post-disposal dedup (B5)

iOS's WC delivery queue is a separate store from both apps'
manifests. The OS retries delivery on its own schedule for days,
independent of app state. So if the user discards a clip, iOS
later delivers the original `transferFile` from its system store,
the inbox is empty, `isMasterAlreadyProcessed` returns false, and
the clip silently re-files.

`InboxProcessedClipIds` closes that gap:

- Every `manifest.remove` and `manifest.removeBatch` calls
  `markProcessed(clipIds)`.
- The set is persistent (`Documents/InboxProcessedClipIds.json`),
  capped at 2000 entries (LRU evict on overflow), and observed
  before any file copy in `session(_:didReceive:)`.

When a re-delivery's clipId is in the set: ack + drop file +
return, no manifest change.

**Known gap.** For split-clip sessions, the children's clipIds
get marked on disposal (because those are the `InboxClip.clipId`
values), but the master's clipId is never added to the set (the
master clipId was never an inbox row). If the master re-arrives
after the user disposed of its children, B5 doesn't catch it via
clipId. § 7.2's `isMasterAlreadyProcessed` doesn't catch it either
(manifest is empty post-disposal). The master gets re-split, new
child clipIds, new manifest rows. **This is a real edge case worth
fixing** — add the master clipId (and `rollGroupId`) to the B5 set
on a split-clip removeBatch.

---

## 8 · Known gaps + open questions

### 8.1 · The split-master-after-disposal gap (§ 7.3)

Described above. Fix: extend `InboxManifest.removeBatch(clipIds:)`
to also mark `rollGroupId` values (when distinct from clipId) so
re-delivered masters can be matched. Open work.

### 8.2 · Possible race in `acceptArrivedClip` under double-delivery

`session(_:didReceive:)` is called from a `nonisolated` delegate,
then hops to `@MainActor`. The actor serializes work, but
`acceptArrivedClip` awaits on `VoiceClipSplitter.split` and
`AudioCompressor.compressInPlace` — releasing the actor between
the dedup check and the manifest mutation.

If two delegate calls arrive for the same `clipId` (e.g., from
the watch double-firing `send(clip:)` due to overlapping triggers
in `WatchAppCoordinator` — record-end + `retryPendingTransfers` +
`sessionReachabilityDidChange`), both Tasks can pass through
`isMasterAlreadyProcessed` before either writes to the manifest.
Both then split into N children with new UUIDs, manifest accepts
both batches, and the user sees duplicate fragments.

The observed symptom in QA 2026-05-29 (1 unsplit + 4 split clips,
each appearing twice on the second pass) is consistent with this
race. Mitigation options (not yet shipped):

- Wrap the dedup-check + manifest-write in a critical section
  per-clipId. A small `@MainActor` set of in-flight clipIds
  guarded around the split path.
- Switch `WatchTransferService.send(clip:)` to refuse to fire if
  iOS's `outstandingFileTransfers` already contains a transfer
  for the same clipId.

### 8.3 · No incoming-transfer progress on iPhone

`WCSession` doesn't expose `WCSessionFileTransfer.progress` on
the receiver. The `.downloading` phase uses an indeterminate
barber-pole because we don't know how much of the file has
arrived. A watch → iPhone progress ping protocol on top of
`sendMessage` could fill this, but the chattiness isn't worth it
for short clips. Time-elapsed-based progress is a possible
middle ground.

### 8.4 · Reachability ≠ proximity

`isReachable` requires both apps active simultaneously. False can
mean "watch out of range" OR "iPhone app is backgrounded." The
`.paused` state currently fires on both — false positives self-
correct on reachability return, but they're visible to the user
during the wrong window. A timer-based "no progress in N seconds"
stall detector would be more honest. Open work.

### 8.6 · Master clipId orphans in the tracker after split — **fixed 2026-05-30**

The watch sends a pre-announce keyed on the master clipId. The
file arrives; for an On-a-roll session, `acceptArrivedClip`'s
split-success branch writes N children to the manifest with
**brand-new UUIDs** (the master clipId is not preserved as any
InboxClip). `transcribePendingInboxClips` iterates manifest rows
and calls `recordTranscribingStarted` per row — for the
children's UUIDs, which weren't in the tracker, so each
synthesizes a new entry from fallback metadata.

The **master's** pre-announce tracker entry was never seen by
the transcribe sweep and never got `cleared`. It sat in
`.downloading` until the next reachability dip, then went to
`.paused`, then stayed there forever because no file delivery
was actually pending for that clipId — the master's content was
already split into children that processed normally.

Tom QA 2026-05-30 visible symptom: two paused `IncomingCard`s
("Waiting for your Watch") sitting above the ready
SessionCards they corresponded to. Durations slightly off
(0:26 paused ↔ 0:27 ready) because the watch's pre-announce
duration was measured live during recording, while the file's
actual duration came from the saved-file metadata.

Fix: `acceptArrivedClip`'s split-success branch explicitly calls
`InboxArrivalTracker.shared.clear(clipId: metadata.clipId)`
after writing the children. The duplicate-master dedup branch
also calls `clear`, in case a redelivery is the chance to clean
up a prior arrival's orphan. The pre-announce delegate gates
against the inverse race (file arrived + processed before
sendMessage was delivered) by checking `InboxManifest` and
`InboxProcessedClipIds` membership before calling
`recordPreAnnounce`.

### 8.7 · Phone-side delete didn't re-ack the watch — **fixed 2026-05-30**

`InboxManifest.remove(clipId:)` and `removeBatch(clipIds:)` cleared
the manifest, deleted the audio file, marked the disposal in B5,
and posted the notification-coordinator hook — but did **not**
re-broadcast an ack to the watch. The system relied on the original
file-arrival ack (`session(_:didReceive:)` →
`sendConfirmation(clipId:)`) to clear the watch's pending row. If
that ack was lost — sendMessage failed because the watch wasn't
reachable in the exact ms after the file landed, transferUserInfo
backup got stuck in iOS's delivery queue, etc. — the watch row
became permanently stuck.

Tom QA 2026-05-30 visible symptom: 4-second clip recorded on watch
→ landed on phone → user deleted on phone immediately → watch row
stayed.

Fix: `remove` and `removeBatch` now send `sendConfirmation` per
clipId. The ack is idempotent on the watch side (already-removed
rows are no-ops in `WatchPendingManifest.performRemoval`), so this
is safe even when the original arrival ack succeeded. For
**single-clip** sessions this works directly because
`InboxClip.clipId == metadata.clipId == watch row's clipId`. For
**split-clip** (On-a-roll) sessions where the child
`InboxClip.clipId` is a fresh UUID different from the master, the
re-ack is a no-op — the original arrival ack for `metadata.clipId`
is still the only signal that reaches the watch row, and § 7.2's
`isMasterAlreadyProcessed` dedup handles the persistence side. A
proper split-session fix would carry `master.clipId` on each child
InboxClip; queued as follow-up.

### 8.5 · Transcription false-negatives at duration extremes

QA 2026-05-29: 6-second and 5-minute clips of clear speech both
transcribed empty; mid-range (14–37s) succeeded. The B4 fix
(outcome enum) prevents *infrastructure* failures (model not
installed, file unreadable, transcriber threw) from being marked
as accidental, but doesn't help with `.transcribed(empty)` on
audible speech. `TranscriptionMaxDurationTests` reproduces the
6-minute case deterministically; the new `[DIAG=…]` log lines
distinguish the sub-cases. Investigation in progress; audio
format mismatch with `SpeechTranscriber`'s expectations
(post-compression) is the leading hypothesis.

---

## 9 · Test coverage at a glance

| Layer | Suite | Notes |
|---|---|---|
| Watch pending lifecycle | `WatchPendingManifestLoadSyncTests` (Watch target) | LRU + sync-stuck timer |
| Watch ack pipeline | `WatchAckPipelineMultiClipTests` (Watch target) | Multi-ack delivery + manifest debug seams |
| Pre-announce wire format | `WatchPreAnnounceParserTests` | 9 tests — valid + every malformed path |
| In-flight phase state | `InboxArrivalTrackerTests` | 12 tests — queue semantics, fallback, reachability |
| Manifest dedup contracts | `InboxProcessedClipIdsTests` | 7 tests — B5 persistence + cap eviction + hooks |
| Transcription outcomes | `TranscriptionPipelineOutcomeTests` | 8 tests — outcome dispatch + fixture classification |
| AAC round-trip | `AudioCompressorTests` | Compress ratio + transcribe still works |
| Long-form transcription | `TranscriptionServiceLongFormTests` | Existing >100s coverage |
| 6-minute boundary | `TranscriptionMaxDurationTests` | Reproduces the duration-extreme bug |
| Header subtitle | `CapturedClipsHeaderSubtitleTests` | 9 tests — cross-day + sync-aware |
| Session body variant | `SessionCollapsedBodyVariantTests` | "Transcribing…" vs "all accidental" vs preview |

---

## 10 · Where to look first when something breaks

- **Clip didn't arrive on phone.** Console log filter
  `[Himem][WC]`. Look for `phone — acceptArrivedClip` matching
  the watch-side `watch — transferFile queued`. If missing, the
  WC layer didn't deliver — check `session activated` reachability
  state and any `transferFile FAILED` lines.
- **Clip shows as duplicate.** Look for two
  `phone — acceptArrivedClip clipId=X` lines. If the rollGroupIds
  match but clipIds differ, that's the split race (§ 8.2). If
  clipIds match, `isMasterAlreadyProcessed` should have caught
  it — look for `duplicate master ignored`. If absent, the dedup
  predicate is buggy.
- **Clip marked "auto-excluded · no speech" on clear audio.**
  Look at the `[DIAG=…]` tag on the matching
  `[Himem][Transcribe] done` line. § 8.5.
- **Watch shows "Hasn't reached your phone in a day" even though
  phone has the clips.** Look for `performRemoval done` /
  `performRemoval no-op` on the watch side — those tell you
  whether the ack arrived and what the manifest did with it.
- **Pre-announce IncomingCard doesn't appear.** Check the iPhone
  console for `iPhone — pre-announce received for clipId=…`. If
  missing, either the watch's `pre-announce sendMessage`
  errored out (reachability false at send time) or the parser
  rejected the payload.

---

_See also `Captured Clips · session-first · spec.md` for the user-
facing design rules and `screens-captured-clips-sessions.jsx` for
the JSX mockups this implementation ports from._

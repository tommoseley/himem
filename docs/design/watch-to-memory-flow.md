# HiMem · Flow · Watch → Memory

_From wrist to memory box._

Source-of-truth spec for the captured-clip flow: Watch dictation → sync → iPhone inbox → user review → entry in the Memory Box. Time flows top to bottom in the original design canvas; this document mirrors that order. Surface colors: **Watch**, **Transit / Sync**, **Phone**, **User action**, **AI moment**, **Notification**.

Companion HTML design lives at `docs/Himem Flow _standalone_.html` (the visual canvas).

## MVP scope

**In:** Watch capture · sync · inbox · review → create / append / delete.

**Out (v2+):**
- On-device transcription on the watch — clips sync as audio only.
- AI-suggested titles & topic chips (both depend on transcripts).

---

## Flow

### 1 · Entry (Watch)

User taps complication or app icon. Wrist raise → tap the ochre mic glyph (corner, circular, or rectangular complication) → lands directly on the recording surface. ~2 seconds glance to ready-to-record.

### 2 · Recording (Watch)

Centered mic disc, timer, primary **Stop & save**. User speaks. Disc halo pulses with mic input. Counter ticks. Tap **Stop & save** to commit; corner ✕ cancels and discards. Wrist-off auto-stops and saves.

- Hard cap: 5 min
- Local storage cap: 50 clips

### 3 · Persist (Watch)

Audio written to local store. Atomic write: temp file → fsync → rename + manifest in one transaction. Clip is `{ audio, uuid, ts, loc? }` — **no transcript on watch in MVP**. Loss-of-power safe from this point.

### 4 · Sync (Transit / Watch)

#### 4A · Phone reachable — Sync over WatchConnectivity

Audio + metadata transfer in the background. The watch shows "removed from Pending" only when the phone confirms receipt — and that ack can lag minutes if the phone app is suspended. The transfer itself usually completes in < 2 s; the visible state change is bounded by iOS's background-wake cycle.

#### 4B · No phone — Queue in Pending

Clip stays on watch, visible in the Pending page. Background scan every ~2 min for the phone; sync resumes silently when it appears. Swipe to delete. Footer copy: "Will sync when phone is near."

### 5 · Ingest (Phone)

Audio lands in Captured Clips. Atomic write into `~/Library/Captured Clips/` + manifest update. **Audio only in MVP — no transcript field on the clip.**

Session grouping is computed phone-side as clips arrive: ~10 min and ~50 m proximity → same session. Phone is the authoritative source of order, even if clips arrive out of sequence from the watch.

- Local files, not CloudKit (v1)
- Grouping: phone-side, at arrival time (frozen once a clip is grouped)

### 6 · Awareness (Phone)

Badge always · push on three triggers. The app icon badge is **always live** and reflects the inbox count. A push fires only on three specific conditions (see Notifications spec below).

### 7 · App launch (User)

User opens HiMem. Cold start → launch sequence → CloudKit handshake → **always lands on Today**. No auto-open of the inbox in MVP.

### 8 · Today + banner (Phone)

> "2 new from Apple Watch · Tap to review"

Inbox status surfaces as a banner card pinned at the top of the Today feed, between the segmented control and the topic filter chips. Tap routes to Captured Clips. Banner appears only when count > 0; hidden otherwise.

- Always lands on Today
- Banner = the only nag

### 9 · Review (User)

Multi-select clips. User taps the selection circle on each clip. Action bar surfaces with **Create memory · Add to… · Trash**. Each row shows audio + capture time + duration — **no transcript preview in MVP**. Selection persists across capture-session groups; the bar tracks total selected.

### 10 · Disposition (User)

| Branch | Action |
|---|---|
| **10A · Create** | New memory sheet. User types a title, optionally taps a topic chip. **No AI title or topic suggestion in MVP** — both depend on transcripts. v2+: AI pre-fills both, tagged with a small AI marker. |
| **10B · Add** | Pick existing memory. Picker shows Recent first, then the full library (searchable). Before/after preview confirms "14 → 17 clips." |
| **10C · Delete** | Discard clips. iOS confirm sheet: "This audio is only on this iPhone — it can't be recovered." → clip files deleted. Manifest updated. |

### 11 · End states

- **11A · New entry** — Clips become media on a new Entry, ordered by capture time. Inbox count decrements; banner hides when count reaches 0.
- **11B · Appended** — Clips inserted at the bottom of the chosen Entry's media list, capture-order preserved.
- **11C · Deleted** — Removed from disk + manifest. No tombstone, no recovery.

---

## Notifications · timing & copy

### Triggers

A push fires when **one** of these conditions is met. The badge is always live and independent of push behavior. Only one push can fire per day; see the timing rules.

| Trigger | Condition | Copy |
|---|---|---|
| **BURST** | ≥ 3 clips arrive in a 5-min window | "4 voice clips ready to organize" |
| **THRESHOLD** | Inbox crosses 10 clips (unreviewed = still in inbox) | "You have 12 voice clips waiting" |
| **STALE** | Clip in inbox > 24h · per-clip scheduled trigger, re-evaluates at fire time | "Some clips are still waiting to be organized" |

### Coalescing & timing

- **Daily cap.** Maximum 1 push per day across all triggers. Badge is unaffected. Resets at midnight local.
- **4-hour suppression.** After any push fires, no further push for 4 hours even if a new trigger condition is met. Badge keeps incrementing.
- **Quiet hours.** 10 PM – 7 AM local; pushes deferred to the next morning's first eligible window.
- **Focus modes.** Respected via the *Sync & capture* notification channel; the user can mute this channel independently.
- **App in foreground.** No push fires — the banner on Today is already doing the work.
- **Burst coalescing.** Clips that arrive within 5 min of a previous burst are added to that session's count without re-firing.
- **Stale repeat cap.** Stale fires at most 7 times for a single clip, then stops; badge keeps the count visible. Never nag forever.
- **Deferred pushes re-evaluate at fire time.** If quiet hours suppressed a stale push and the user reviewed everything before 7 AM, the suppressed push is cancelled — never fires empty.

### Tap behavior

- **Tap notification** → opens the app directly to Captured Clips, skipping Today and the banner.
- **Inline action · "Snooze 4h"** → suppresses this channel for 4 hours (`UNNotificationAction`; iOS does not surface swipe-to-dismiss to the app).
- **Inline action · "Mute for today"** → suppresses through midnight local; auto-unmutes at midnight to match the action name.
- **Long press → Manage** → jumps to iOS settings for the *Sync & capture* channel.

### Anatomy

```
[H]  HiMem                                            now
     4 voice clips ready to organize
```

Body is a single line, count-leading. No emoji. No app subtitle. The badge on the app icon does the math; the push tells the user it's worth opening.

---

## Edge cases

### A · Watch power off mid-record

Audio is preserved up to the cutoff. Atomic-write pattern means partial buffers do not corrupt the manifest. On boot, watch checks the temp directory: anything finalized appears in Pending; in-flight buffers are discarded with no UI for them. Better to lose 8 s than poison the queue.

### B · Local storage cap (50 clips)

Warning at 45, hard block at 50. Watch home shows a warning chip (amber) on Pending row at 45+ unsynced clips. At 50, complication shows the small red sync-issue dot; recording is allowed but commits as a draft until count drops — rare-but-possible during long off-phone trips.

> **Note:** the draft state at 50 is a deliberate product decision; alternative would be a hard-block. Both are valid; current spec keeps drafts.

### C · Sync stuck > 24 h

Sync-issue indicator surfaces. Complication grows the small red dot; tapping routes to Pending list with an explainer ("Hasn't reached your phone since Tuesday."). Phone-side notification fires once per day until resolved or dismissed.

### D · Phone backgrounded mid-sync

Visible ack lags the actual file landing. If the iPhone is asleep or the HiMem app is suspended, the watch transfer can complete before the phone wakes to confirm receipt. The clip exists on disk on the phone; only the watch's "removed from Pending" state change waits for the round-trip. iOS schedules the wake within minutes; user sees Pending clear when that completes. The file is safe the whole time.

### E · User cancels mid-record

Hard discard, no manifest entry. Tapping the corner ✕ deletes the in-flight buffer immediately. Confirmed by haptic + half-second toast ("Discarded"). Wrist-off does **not** cancel — it saves. (We never throw away work the user walked away from.)

### F · Phone receives duplicate

Idempotent by clip UUID. Each clip gets a UUID at creation on the watch. If retransmit happens (e.g., sync failed mid-confirm), the phone's manifest dedupes by UUID. Audio file is overwritten only if bytes differ.

---

## Implementation status (2026-05-14)

| Step | State |
|---|---|
| 1 · Entry | ✅ Built |
| 2 · Recording | ✅ Built (haptic on start/stop, mic-level meter ring, cancel under 1s or silent-audio = silent discard) |
| 3 · Persist | ✅ Built (JSON manifest writes; atomicity worth verifying) |
| 4A · Sync | ✅ Built (transferFile + dual-path ack + reconcile-on-foreground) |
| 4B · Pending | ✅ Built (3-page TabView LATEST/RECORD/PENDING; swipe-to-delete via native `List`) |
| 5 · Ingest | ✅ Built (`InboxManifest` + on-device transcription via `TranscriptionService`); **session grouping is new** |
| 6 · Awareness | ⚠️ Partial — fires on every clip arrival today; notification coordinator with burst/threshold/stale rules is **new work** |
| 7 · App launch | ✅ Built (always lands on Today) |
| 8 · Today + banner | ❌ **New work** |
| 9 · Review | ⚠️ Partial — multi-select + action bar refresh is **new work** |
| 10A · Create | ⚠️ Partial — sheet exists; no AI fill (correct for MVP) |
| 10B · Add | ✅ Built (`AddClipsToMemorySheet`) |
| 10C · Delete | ⚠️ Built but the iOS confirm sheet copy needs updating to the spec |
| 11A/B/C · End states | ✅ Built |

| Edge | State |
|---|---|
| A · Watch power-off mid-record | ⚠️ Audio is written atomically by `AVAudioRecorder`; the watch's boot-time temp-dir sweep isn't explicit yet |
| B · 50-clip cap UI | ❌ Constant exists (`WatchPendingManifest.storageCap`); UI surfacing is **new work** |
| C · Sync stuck > 24 h | ❌ **New work** (last-confirmed-receipt timestamp + complication state + daily phone push) |
| D · Phone backgrounded mid-sync | ✅ Documented; behaviour matches spec |
| E · Discard toast | ⚠️ Haptic done; half-second toast is **new work** |
| F · UUID dedup | ✅ `InboxManifest.acceptClip` dedupes by `clipId` |

---

## Build order

When the team moves from spec to code, the recommended sequence:

1. **Banner on Today** — replaces the no-auto-open behavior with a count-only nag.
2. **Notification coordinator** — burst/threshold/stale with all the timing rules. Replaces the per-clip `notifyInboxArrival`.
3. **Multi-select action bar** + Create/Add/Delete flow refresh (steps 9 / 10A–C).
4. **50-cap UI on watch** + sync-stuck-24h indicator (both add complication state).
5. **"Discarded" half-second toast** on cancel (Edge E).

Most of the heavy lifting is in step 2; everything else is layout work on code that's already there.

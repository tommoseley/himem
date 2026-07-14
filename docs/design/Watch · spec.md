# Watch · spec

Watch surface. Capture-first. May 20 2026. Locked for v1.

> **What this is.** A single source of truth for the watch app: entry points, capture UI, on-a-roll behavior, pending list, complications, and the architectural rules. Replaces scattered notes across `Himem · Watch.html`, `CLAUDE.md`, and `On a roll · spec.md` (the watch-specific portions). Where this contradicts older drafts, this wins.

## Why the watch matters

The watch is the **fastest path from thought to capture** HiMem has. Two seconds from wrist to recording — faster than any phone flow, because the device is already in position. Lose that lead and you lose the product's reason to exist on the wrist.

The whole watch surface earns its existence by being faster, calmer, and more forgiving than the phone. If it adds friction, it loses to the user just opening their phone.

## Scope

**In MVP:**
- Audio capture (clip recording, on-a-roll splitting)
- Pending list (locally-stored, unsynced clips)
- Five complication families covering modern faces
- Three entry points: complication, app icon, Siri
- Wrist-off auto-save, hard caps, palm-cover gesture

**Out of MVP (v2+):**
- On-device transcription
- Text, photo, video capture on watch
- Browsing Memory Box on watch
- AI features on watch (titles, topic suggestions)
- Push-to-talk complications (press-and-hold to record)

The watch is a **capture queue**, not a Memory Box viewer. Browsing happens on phone.

## Architectural locks (background — see CLAUDE.md)

These are locked at the product level and aren't up for debate inside this spec:

- **Audio only.** No text, photo, or video composition on watch.
- **No on-device transcription in MVP.** Audio syncs to phone; transcription runs there.
- **Workout-style nav.** Two horizontal pages: **Capture · Pending**. Capture is the default landing page; Pending sits one swipe right.
- **Swipe is locked during recording.** Only exits are *Stop & save*, *Cancel ✕*, or wrist-off (auto-save).
- **Wrist-off auto-stops and saves.** We never discard work the user walked away from.
- **Hard cap: 5 min per recording, 50 unsynced clips local storage.**
- **Counter never pauses mid-recording.** It's the user's contract that audio is rolling.

## 1 · Entry points

Three ways the user starts a recording. Listed in order of speed.

| Entry point | Speed | Primary status |
|---|---|---|
| **Complication tap** | ~2 seconds from glance to recording | Goal state. The reason to ship a watch app. |
| **App icon** | ~4 seconds. Always available, always works. | Fallback. |
| **Siri** | Hands-free. Imprecise but liberating. | Optional v1 if scope is tight. |

**Complication launch routes directly into the Recording screen** — skips the app's home page. Designed for the corner-complication faces (Modular, Infograph, Wayfinder).

## 2 · Capture · the recording screen

**This is the most important surface in the watch app.** Every design decision here cashes the "2 seconds from wrist to capture" promise.

### Fresh-start countdown (revised May 27 2026)

Before recording begins on a fresh start, the watch shows a one-second "breath" — same model as the phone, scaled for the smaller surface. Replaces the previous 3·2·1 countdown, which felt slow for a watch interaction.

**Single phase, ~1 second.** A bright ochre ring (`var(--accent)`, 10pt stroke on watch / 14pt on phone) **fills clockwise from 12 o'clock** over ~800ms, then holds for a 200ms tail. When the ring reaches the top, recording begins. No second phase, no number countdown.

**Caption inside the ring.** Source Serif 4 italic, weight 400. 15pt on watch / 22pt on phone. Centered, single line. The caption gives the user a gentle beat to gather a thought without feeling like the app is waiting on them.

**Caption rotates across recordings.** Index persisted in `UserDefaults` (watch) / shared via the App Group with the phone where practical. **Advance the index on commit**, not on cancel — otherwise canceling cycles through captions the user never read. Rotation array (13 entries, locked):

```
"Ready when you are."
"Start anywhere."
"Whenever it comes."
"Take your time."
"Go ahead."
"Say it naturally."
"When you're ready."
"Hold the thought."
"Here when you need it."
"Catch the thought."
"Don't lose it."
"We're ready."
"Speak freely."
```

**Haptic pattern.** One soft `.click` at the start of the breath, one slightly stronger `.success` at the moment recording begins. No tick-tick-tick. The end haptic is the "go."

**Tap anywhere to cancel.** The whole screen is the cancel target. Returns to the previous surface (Capture page on watch, Today on phone, parent Memory on append). Sub-1-second user reaction is unlikely but supported.

**Fresh-start only.** Tapping the mic complication, app icon, or Siri opens into the breath. On-a-roll **Next** bypasses it — the whole point of Next is the mic never pauses, and any wait would kill that contract.

**Settings opt-out.** Power users can disable in *Settings → Capture → Skip the breath*. Default on. Reduced Motion users see the caption + filled ring without the fill animation; recording still starts after the same total duration (~1 second), so the rhythm of "you have a beat before mic-hot" is preserved.

Why: the previous 3-second countdown felt like theater for an interaction the user had already committed to. One beat is enough to gather a thought; more is wait time.

### Canonical layout (V1 · shipping)

```
┌───────────────────────────┐
│ ✕               9:41      │   ← Cancel corner glyph (top-left) + system time
│                           │
│                           │
│        ● REC              │   ← Recording status indicator (ochre)
│                           │
│         0:23              │   ← Big centered timer (display-weight, tabular)
│     Clip 2 · on a roll    │   ← Persistent state line (when in a roll)
│                           │
│  ▁▃▅▇▆▄▂▃▅▇▆▄▂▃▅▇▆▃▁    │   ← Live waveform (audio-as-rolling contract)
│                           │
│ ┌─────────────┐ ┌───┐    │
│ │ Stop & save │ │ → │    │   ← Stop hero pill + Next-clip glyph (side by side)
│ └─────────────┘ └───┘    │
└───────────────────────────┘
```

### Why this layout (vs the old "mic disc with counter inside")

The previous canonical (per the on-a-roll spec, May 2026 v0) put the counter inside a pulsing ochre mic disc, with Next as a separate button below the disc. That design has been retired. Reasons:

1. **The waveform is a better "audio is rolling" signal than a pulsing disc.** It responds to the user's voice. A disc just throbs on a timer. The first time someone records and sees the wave move with their words, the contract clicks.
2. **The big timer is the hero.** Recording-app convention. Reads from across the room.
3. **Stop and Next belong together at the bottom.** They're the two commit actions of a roll. Next sitting below the disc made it feel like a chrome element, not a peer to Stop.
4. **The persistent "Clip 2 · on a roll" line beats a 1.5s eyebrow.** A user mid-thought won't see a 1.5s flash. A persistent line gives them confidence without competing for attention.
5. **Cancel ✕ stays in the corner.** Always one tap away, but visually demoted. Never sits beside Stop & save as a peer pill — that's the V3 anti-pattern (see Rejected variants).

### Components, top to bottom

- **System time** (top-right). watchOS handles this. We don't draw over it.
- **Cancel ✕** (top-left, 28×28 hit target). Pure glyph, no background, ink2 weight. Tap → confirm sheet: "Discard this clip? Earlier clips in this recording are already saved." Two-tap confirm (no immediate destructive action). Stays visible during recording — swipe is locked, but the corner ✕ is the explicit escape.
- **Recording indicator** (`● REC`, ochre). Small but unambiguous. Pulses subtly (~1.4s ease-in-out) to reinforce that audio is being captured.
- **Big timer** (`0:23`). Display-weight (300), tabular numerals, 48pt+. Centered. Cream on black.
- **State line** (when in a roll): `Clip N · on a roll` — 13pt, ochre, weight 600, centered. Hidden during the first clip (i.e., when N=1 and the user hasn't tapped Next yet). Appears the instant Next is tapped for the first time, and stays until Stop & save or Cancel.
- **Live waveform** — full-width band, 34 bars (or however many fit at 2pt bar + 1pt gap), centered on the vertical axis. Bars respond to live audio level. Past samples scroll left; newest sample is the right edge. Ochre at full opacity for active bars, ochre at 25% for the tail. **Never resets across Next** (mic-never-pauses contract).
- **Stop & save pill** (cream, flex:1). The hero. Cream `#F1ECE3` background, ink `#000` text, 52pt height. Cream-on-dark contrast — the visually heaviest element on the screen.
- **Next-clip glyph button** (ochre, 52×52, paired right of Stop). Round, ochre `#C64A1C` fill, cream icon. Glyph: forward chevron with trailing dot (`→ .`). NOT a reload ⟳ — that's wrong; it implies undo. Tap = commits current clip, resets counter, increments `Clip N` state line.

### Recording rules

- **Stop & save** is the only intentional commit path. Explicit, never ambiguous.
- **Cancel ✕** (corner) is the explicit discard path. Two-tap confirm. Discards only the current clip; earlier Next-clips in this roll are already saved.
- **Palm-cover (watchOS gesture)** dims the watch *but does not discard.* Wrist-off rules still apply — earlier behavior of "palm = cancel" is retired; it was destructive and undiscoverable. Today the palm gesture just dims/sleeps; clips persist.
- **Wrist-off auto-stops and saves** the current clip. Earlier Next-clips in the roll were already committed.
- **5-minute hard cap per clip** (not per roll). At 4:45, the timer color shifts toward warn-amber and a small label appears: "30s left." At 5:00, auto-stop fires with `Stop & save` semantics. The roll continues — the user can tap Next any time to chain another 5-minute clip.
- **50 unsynced clips local cap.** At 49, the Next button dims and changes the small label below it to "Sync soon." Stop & save still works. At 50, recording is blocked — the user must connect to phone or delete clips from the pending list. Surfaced as a screen-level warning before launch.
- **Counter is the signal capture is alive.** Never pause it mid-recording. Driving the counter off `Date()` since the current clip's start, not the recorder's `currentTime`.

### Rejected variants (kept here so they don't come back)

- **V2 · single hero Stop pill, no Cancel control.** "Palm = cancel" loses the visible escape hatch. Discoverability cost too high.
- **V3 · Stop and Cancel side by side as peers.** Two adjacent pills make wrong-taps trivial. Stop is a commit action; Cancel is destructive. Peer-action rule (Crucible) says no.
- **Counter inside the mic disc (v0 on-a-roll design).** Disc-as-mic was a Mercedes ornament — not a functional signal. Waveform is.
- **"Clip 2 · ROLLING" all-caps transient eyebrow (v0 on-a-roll).** 1.5s flash that disappears. Replaced by persistent `Clip N · on a roll` line.
- **Walkie-talkie press-and-hold to record on the complication.** Fast but accidental-prone. Rejected.

### Audio format & pre-transfer transcode (locked 2026-07-14)

**The watch transcodes every clip to mono · 16 kHz · AAC (~32 kbps, `.m4a`) before `transferFile`. It never ships the raw recording.** The hardware input is 3-channel 48 kHz Float32 PCM (~576 KB/s of audio), so a 59 s clip is **~33 MB** raw — which over WatchConnectivity takes minutes to reach the phone (dogfood 2026-07-14: 33 MB still transferring after 3 min; `reachable=true`). Compressed, the same clip is **~230 KB — ~144× smaller** — and lands in seconds. This is the fix for the "capture feels broken" slowness; it keeps the perishability promise that a caught thought reaches the phone quickly.

- **Encoding, not transport.** WatchConnectivity stays; the payload shrinks. This is *not* a move to an iCloud/CloudKit transport — compression removes any need for one.
- **Whole-file, after stop — never per-callback.** The transcode runs once on the finished file before enqueueing. Per-callback / inline-converter resampling inside the record tap starves the resampler's continuity filter and produces silence — the July 5 2026 audio saga, shipped twice and reverted twice. Do not reintroduce it. The proven shape is a single stateful `convert()` over the whole file (as the phone's `TranscriptionService` does).
- **Downmix to mono explicitly — do not assume the recording is already mono.** `setVoiceProcessingEnabled(false)` does **not** collapse the watch input to mono (dogfood 2026-07-14: the input node reports 3 channels even after disabling VPIO). The transcode averages to one channel; the earlier "mono after VPIO disable" assumption is false on device.
- **Assertion (the guard): the file handed to `transferFile` is mono, 16 kHz, AAC.** An automated test asserts this; **that test failing IS the oversized-transfer bug.** It is the regression lock so the format can't silently drift back to raw PCM.

Encoder options + rollout: `docs/architecture/2026-07-14-watch-audio-compression.md`. Encoder: **AVAudioConverter, whole-file, post-stop** (locked 2026-07-14).

### Transport (locked 2026-07-14)

**Watch→phone transfer is WatchConnectivity, permanently.** The watch **never** writes to CloudKit or an iCloud container. It hands clips to the phone over `transferFile`; **the phone is the sole iCloud writer** — media → iCloud Files, metadata → the private DB — at its leisure, off the capture path. The watch is a capture device, not an iCloud client. The "watch uploads to CloudKit directly" idea is **retired, not deferred**: once clips ship compressed (~230 KB), WatchConnectivity is fast enough that the transport never needed replacing, and keeping the watch off iCloud preserves the phone-as-sole-writer custody model. Do not reopen this as a "someday" path.

## 3 · On a roll · Next-clip

The most precious state in capture is **on a roll** — one thought unspooling into the next. Next is the primitive that protects it.

This section captures **watch-specific** behavior. For the cross-platform model (clip = file, session = group, rollGroupId, phone equivalents), see `On a roll · spec.md`.

### Watch-specific specifics

- **Where it sits.** Bottom-right, paired with Stop & save. 52×52 ochre disc. NOT below the timer; NOT in the chrome.
- **Tap.** Single `.click` haptic. The current clip commits, counter resets `1:42 → 0:00`, `Clip N · on a roll` state line increments. No screen change, no confirm, mic never pauses.
- **Minimum clip length: 2 seconds.** Sub-2s taps are silently debounced (no haptic, no save, no reset). Protects against rolling-thumb double-taps.
- **5-minute cap is per clip, not per roll.** Chain as many as you want.
- **Cancel during a roll** discards only the current (in-progress) clip. Confirm copy is specific: *"Discard this clip? Earlier clips in this recording are already saved."* Never "this recording."
- **Wrist-off during a roll** auto-stops the current clip. Earlier clips are already safe.
- **49/50 storage state.** Next dims to 40% opacity, label below it changes to "Sync soon." Stop & save still works at full strength.
- **AOD (Always-On Display).** Next remains tappable in dimmed AOD state. The persistent `Clip N · on a roll` line shows; the waveform may pause animation under AOD power rules — confirm with watchOS engineering. Counter still updates.

### Glyph spec

Forward chevron with trailing dot. Reads as "advance, mark." NOT:
- Reload ⟳ (implies undo)
- Plus + (implies "add new thing")
- Skip forward ⏭ (implies fast-forward, time-skip)

Cream-on-ochre. Drawn at 18×18 inside the 52×52 disc.

## 4 · Pending list

Reachable by swiping right from Capture, or from a failure-state CTA. Lists **only locally-stored, unsynced clips** — once synced, they leave this list (they live on phone from then on).

- **Empty state**: "All caught up. Recordings appear here when phone isn't near."
- **Populated**: one row per clip, time-stamped, duration shown. Tappable to play (single tap → inline audio playback).
- **Swipe-left → Delete.** Confirm sheet: "Delete this recording? 0:14 · not synced yet." Two-tap confirm.
- **Pending count** surfaces on complications **only when > 0**. Calm by default.
- **Sync indicator**: when phone is reachable and clips are mid-upload, a small ochre progress glyph appears at the top of the list. Doesn't block interaction.

### Storage near full state

At 49/50 unsynced clips, a banner appears at the top of the Pending list: *"Sync soon — 49 of 50 saved."* At 50, a screen-level warning blocks new recording: *"Storage full. Sync to phone or delete clips to record again."* The Capture page is dimmed.

## 5 · Complications

The watch face is the only HiMem affordance outside the app. **One job:** from glance to recording in one tap.

### What ships

Mic glyph slotted into **five complication families** — covers every modern face:

- Corner (Modular, Infograph)
- Circular (Modular Compact)
- Rectangular (Wayfinder, Modular Ultra)
- Inline (Utility)
- Graphic (Graphic Bezel, Graphic Circular)

**Visual rules:**
- Glyph and ochre only. No live transcription preview, no battery state, no duration on face.
- Pending count appears **only when > 0**. Calm by default.
- Recording-in-progress state: pulsing red-ochre ring around the glyph. Rare — only when app is actively recording in the background.

### Tap behavior

- **Standard tap → opens app directly into Recording screen** (skip home). 2-second goal state.
- **Press-and-hold to record immediately** (walkie-talkie style). **Rejected for v1.** Faster, but risks accidental recordings on wrist bumps. The 2-tap cost is acceptable.

## 6 · Two-page nav (Workout-style)

The watch app uses horizontal-page nav, defaulting to Capture (left).

| Page | Content | Notes |
|---|---|---|
| **Capture** (left, default) | The recording screen (Section 2). All entry points route here. | This is the center of gravity. |
| **Pending** (right) | The pending list (Section 4). | Always reachable; never buried. |

**Swipe is locked during recording.** Outside recording, swipe between pages is standard watchOS horizontal-page nav.

### Why not three pages

The earlier model was three pages — **Latest · Capture · Pending** — with Latest as the left page showing the most recent Memory created on phone. That's been retired. The watch is a capture queue, not a Memory Box viewer; even a read-only single-Memory replay surface created an expectation of browsing that the watch can't carry through (no list, no search, no editing). It also competed for the user's attention in the seconds after they raised their wrist — the time we most need them landing on Capture without a moment's drift. Cut.

Browsing the Memory Box happens on phone. Always.

## 7 · Tier behavior

| Tier | Watch |
|---|---|
| Free | Fully available. 50-clip local storage cap is the same ceiling for everyone. |
| Plus | Same. |
| Studio (post-launch) | Same. |

Capture is always free. The watch is the purest capture surface — gating any of it would punish the people we want most to retain.

## 8 · Vocabulary (locked)

| Use | Don't use |
|---|---|
| **Stop & save** (the commit button) | Save, Done, End |
| **Cancel ✕** (corner glyph; explicit discard) | Discard, Trash |
| **Next** (button label; "on a roll" affordance) | Split, Section, Mark, New |
| **On a roll** (internal name for the multi-clip state) | Roll, Recording session, Chain |
| **Clip** (one audio file) | Segment, Take, Recording |
| **Memory** (the eventual phone-side container) | Entry, Note |
| **Pending** (the on-watch unsynced list) | Inbox, Queue, Drafts |
| **All caught up** (empty pending state) | Nothing pending, Empty, Inbox zero |

## 9 · Hardware constraints

- **Designed for 49mm Ultra.** Designs flex down to 45mm without rework.
- **44mm (older Series)** loses ~20% vertical real estate. The waveform compresses to 24 bars; everything else holds. Test at this size before shipping.
- **AOD (Always-On Display)** is supported. Waveform dims/pauses under watchOS power rules. Counter still updates. Next remains tappable.

## 10 · What this is *not*

- **Not a Memory Box browser.** No browsing on watch — not even read-only. To see Memories, use phone.
- **Not a transcription surface.** Audio captures; transcripts happen on phone.
- **Not a text-entry surface.** No dictation-to-text, no scribble, no keyboard.
- **Not a Siri-first product.** Siri is the third entry point, not the primary.
- **Not a "recording session" UI.** The word *session* applies to the on-phone consolidation surface (Captured Clips). On watch, we have Clips and Rolls. Don't import "session" vocabulary.

## 11 · Open questions

- **AOD waveform behavior.** Pause / dim / freeze last sample? Defer to watchOS engineering; doesn't block shipping.
- **44mm waveform bar count.** 24 vs 28 — pick after seeing it on hardware.
- **"Sync soon" label position** below Next button — verify it doesn't crash into safe area on 41mm/45mm.
- **Complication walkie-talkie press-and-hold** — rejected for v1, but revisit in v2 if telemetry shows users wishing for it.

## Files

- `Himem · Watch.html` — design canvas (matches this spec — Section 2 + 2b show canonical V1 + on-a-roll specimens).
- `On a roll · spec.md` — cross-platform Next behavior. Watch sections superseded by Section 3 of this spec; phone sections still canonical.
- `Captured Clips · session-first · spec.md` — what happens to watch clips once they reach phone.
- `CLAUDE.md` — locked architectural rules.
- This spec is the source of truth for v1 watch.

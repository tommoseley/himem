# Watch audio compression — decision doc (2026-07-14)

**Status:** LOCKED 2026-07-14 — **encoder = Option 1 (AVAudioConverter, whole-file, post-stop)**; **transport = WatchConnectivity, permanently.** 4a shipped. **Capture-gain P0 RESOLVED 2026-07-15** (`.measurement` → `.default`, §4e) — watch clips are now audible and transcribe.
**Owner:** CC (implementation) · **Decision:** Tom (both *whats* locked).

## 1 · Problem + evidence

The "~50× too slow" watch→phone sync P0 is a **payload-size** problem, not a transport problem. Dogfood 2026-07-14, `[XferPerf]` instrumentation (branch `watch-transfer-speed-instrumentation`):

| Clip | Audio | Payload | Rate |
|---|---|---|---|
| 8CCA15BA | 58.5s | **33,757,696 B (~33 MB)** | 576,809 B/s |
| E6C12B37 | 21.9s | **12,560,896 B (~12 MB)** | 574,657 B/s |

The rate is exactly **3 ch × 48,000 Hz × 4 B (Float32) = 576,000 B/s**, confirmed against the recorder log:

```
[HiMem][REC] input node format: <AVAudioFormat: 3 ch, 48000 Hz, Float32, deinterleaved>
```

`reachable=true` at enqueue in both cases — so this is *not* even the worst-case backgrounded throttle; a 33 MB file is simply slow over any watch link. For voice, the correct target is **mono · 16 kHz · AAC ~32 kbps ≈ 4,000 B/s** — the 33 MB clip becomes **~230 KB, ~144× smaller**, and lands in seconds on the existing pipe.

## 2 · Verdict — compress, don't migrate

**Fix the encoding on the watch; keep WatchConnectivity.** A ~230 KB clip is near-instant over WCSession, so the encoding fix alone resolves the P0.

**Transport locked (2026-07-14): watch→phone is WatchConnectivity, permanently.** The watch never writes to CloudKit or an iCloud container — it hands clips to the phone over `transferFile`, and **the phone is the sole iCloud writer** (media → iCloud Files, metadata → the private DB) at its leisure, off the capture path. The watch is a capture device, not an iCloud client. The "watch uploads to CloudKit directly" idea is **retired, not deferred**: compression makes WCSession fast enough that the transport never needed replacing, and keeping the watch off iCloud preserves the phone-as-sole-writer custody model. Do not reopen this as a "someday ceiling-remover."

## 3 · The invariant (now locked)

Locked into `Watch · spec.md` §2 and `HiMem · Locked Decisions.html`:

> **The watch transcodes every clip to mono · 16 kHz · AAC (`.m4a`) before `transferFile`. It never ships the raw recording.** Whole-file, after stop — never per-callback. The transcode must explicitly downmix to mono. **Assertion test: the file handed to `transferFile` is mono / 16 kHz / AAC — that test failing IS the oversized-transfer bug.**

## 4 · Three sub-items (the last two are their own work)

### 4a · The compression (this fix — awaiting encoder pick)
Transcode the finished PCM `.caf` → mono 16 kHz AAC `.m4a` **after stop, before enqueueing the transfer**, and transfer the `.m4a`.

### 4b · The 3-channel / mono premise — CORRECTED (2026-07-15, see §4e)
> **Correction (2026-07-15):** the "still 3 channels" observation below was **under `.measurement` session mode.** `.measurement` was *itself* selecting the raw 3-channel hardware input. Switching the record mode to **`.default`** (capture-gain P0, §4e) resolves the input to **processed mono** on device (dogfood: `input node format: 1 ch`). So the 3-channel downmix problem is **dissolved at the source**, not merely handled. The manual downmix (now **pick-hottest**, not average — see below) is **retained as defensive, tested code** for any future multichannel route; it is not ripped out.

`WatchRecordingService` disables VPIO expecting mono ("future recordings are mono", July 5 Troika fix #1). **Under `.measurement` mode the input node still reported 3 channels after `setVoiceProcessingEnabled(false)`** (dogfood 2026-07-14). Consequences (now historical — see the correction above):
- The transcode (4a) **must not assume mono** — it downmixes N→1 by **extracting the hottest channel** (revised 2026-07-15 from per-frame average: the device's channels were live but uncorrelated, so averaging cancelled misaligned peaks and lost ~2× — pick-hottest recovers it). **`AVAudioConverter`'s built-in downmix does NOT combine an unlabeled/discrete >2ch source — it emits pure silence** (P0 2026-07-15: `in_peak=0.3 → out_peak=0.0`). Never hand N-channel straight to the converter. The invariant test pairs mono/16k/AAC with **hottest-channel output energy from a ≥3ch fixture** so format-correct-but-silent fails.
- Separately, the July 5 transcription fix's premise ("mono after VPIO disable") is now true again *because of the `.default` mode change* — clips arrive as clean mono AAC and transcribe (dogfood 2026-07-15: 122- and 192-char transcripts, full coverage).

### 4e · Capture-gain P0 — RESOLVED (2026-07-15): `.measurement` → `.default`
Watch clips transferred fast (4a) but arrived **silent — no speech, no playback, nothing transcribed.** Root cause was NOT the transcode: the loud-clip dogfood `[Amp]` line showed `in_peak` pinned at **~0.01 (−40 dBFS) regardless of how loud the user spoke** — the *capture* was under-gained.

The cause: the watch recorded in **`.measurement`** session mode, which by design **minimizes system input processing, including input GAIN**. The phone's `SpeechService` uses the same `.measurement` mode and captures fine only because the phone mic is hotter; the watch mic isn't, so with no gain applied it sat at ~0.01. `.measurement` predates and is independent of the July-5 VPIO/clean-channel fix.

**Fix (knob 1, the only knob needed):** record in **`.default`** mode, which applies normal input gain. Dogfood A/B, same device/voice:

| mode | srcCh | in_peak | outcome |
|---|---|---|---|
| `.measurement` (3 clips) | 3 | ~0.0086–0.0103 | silent, no transcription |
| `.default` (40.4s) | **1** | **0.1000** | **transcribed, 122 chars** |
| `.default` (13.1s) | 1 | 0.0332 | **transcribed, 192 chars, full coverage** |

`.default` also collapsed the input to **mono** (see §4b correction) — one change fixes both the level bug and the 3-channel problem. Knobs 2 (digital gain multiplier) and 3 (re-enable VPIO) were **not** needed and not applied. The mode is now a named constant (`WatchAudioSessionConfig.recordMode`) with a standing invariant test (`WatchAudioSessionConfigTests`) so a refactor can't silently revert to `.measurement`.

**Carry-forward (both off the capture-gain critical path):** §4c ack-storm (still active in dogfood); §4d skip-if-AAC — now with teeth: the phone re-compresses the already-AAC watch clip (AAC→AAC) and it **measurably attenuates** (watch out 0.0746 → phone probe peak 0.0273), so it's mildly *lossy*, not just wasteful — worth doing.

### 4c · Duplicate-ack storm — own item, later
The dogfood log shows **dozens** of repeated:
```
[HiMem][WC] watch — handleAckPayload accepted clipId=…
[HiMem][WC] watch — remove(clipId:) buffered ack for unknown clipId=… (will replay on next manifest mutation)
```
for the *same* clipIds, via both `didReceiveMessage` and `didReceiveUserInfo`, plus `WCFileStorage … could not load user info data … ENOENT`. Looks like an ack loop / re-delivery churn (the buffered-ack "replay on next mutation" may be self-perpetuating). **Separate investigation — not part of the compression fix.** Logged here so it isn't lost.

### 4d · Phone-side skip-if-AAC — own follow-up (logged 2026-07-14)
Once the watch ships AAC (4a wiring), `WatchSessionDelegate.compressIfPossible` on the phone would **re-encode an already-AAC clip** (AAC→AAC). It's harmless (AVFoundation sniffs by magic bytes, so a `.caf`-named AAC still decodes) but wasteful and **measurably lossy — now with teeth (dogfood 2026-07-15):** the watch handed over a clip at `conv_out_peak=0.0746`, and the phone's post-recompress probe read `peak=0.0273` — the AAC→AAC pass **attenuates the level ~2.7×**. So it's not just wasted CPU; it quiets an already-quiet watch clip. **Fix (separate change):** sniff the arrived file's format and skip compression if it's already AAC. Not blocking 4a; logged here so it isn't lost.

## 5 · Encoder options — **Option 1 chosen (locked 2026-07-14)**

All keep WatchConnectivity; all target mono/16k/AAC. `AudioCompressor` (the phone's compressor) is **not** an option — it uses `AVAssetWriter`/`AVAssetReader`, which are **unavailable on watchOS**.

| # | Shape | How | Pro | Con |
|---|---|---|---|---|
| **1 (rec.)** | **AVAudioConverter, whole-file, single stateful convert** | Leave the record path (engine+tap → PCM `.caf`) untouched. After stop, one `convert()` pass over the whole file → mono 16k AAC `.m4a`; enqueue that. | Record path **untouched** (lowest risk to the fragile capture); mirrors the phone's proven `TranscriptionService` single-`convert()` pattern; watchOS-native (AVFAudio). **Downmix is manual** (per-frame channel average) — the converter does NOT downmix a discrete >2ch source (it silences it, P0 2026-07-15); it only resamples mono→mono. | Adds a ~1s post-stop transcode + temp file (CPU/battery). |
| 2 | **ExtAudioFile (AudioToolbox)** | Post-stop whole-file convert via ExtAudioFile: client PCM in, AAC `.m4a` file out. | watchOS-native; robust classic file transcode. | C-style API, more boilerplate; less idiomatic than #1. |
| 3 | **Record direct-to-AAC (AVAudioRecorder)** | Replace engine+tap with `AVAudioRecorder` configured mono/16k/AAC. No transcode step. | Smallest file from the start; no second pass. | **Changes the record path** — the exact fragile area (July 5 reverts); loses the tap-driven live waveform (metering via `averagePower` is coarser); loses all-channel PCM. Highest risk. |

**Recommendation: Option 1.** It confines the change to a new *post-stop* step and leaves the touchy recording tap alone, and it reuses a pattern already proven on the phone. But this is your call.

### The July-5 rule (binding on all options)
**Never resample per-callback inside the record tap.** The inline-converter-in-the-tap approach starves the resampler's continuity filter and produces silence — shipped twice, reverted twice (see `feedback_avaudioconverter_nodatanow_starves_resampler`). The transcode is **whole-file, once, after stop** — a single stateful `convert()` signalling `.endOfStream` at EOF.

## 6 · Acceptance / the assertion test (Bug-First, written with the fix)

When the fix is built (encoder chosen), write it red-first:
- **Money test:** given the file `send(clip:)` is about to hand to `transferFile`, assert `channelCount == 1 && sampleRate == 16_000 && commonFormat is AAC (.m4a / kAudioFormatMPEG4AAC)`. Fails on today's 3ch/48k/Float32 PCM; passes after the transcode. **This is the invariant's guard — its failure is the bug.**
- **Size sanity:** transcoded `bytesPerAudioSec` ≲ ~6,000 (AAC ~32 kbps) vs today's ~576,000.
- **Dogfood:** the `[XferPerf]` `delivered` line's `bytes` drops ~144× and `elapsed` to seconds — measured on the **P1-merged** build so wait-to-begin isn't folded in.

## 7 · Sequencing
1. This doc + the two spec locks land (docs only).
2. Tom picks the encoder shape (§5).
3. Then implement 4a on its own branch, Bug-First (§6 test red→green), device-dogfood the `[XferPerf]` delta.
4. 4b (transcription re-verify) and 4c (ack storm) are separate follow-ups.

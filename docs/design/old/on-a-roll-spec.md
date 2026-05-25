# On a roll · spec

Capture · MVP. May 2026.

## Why this exists

The most precious state in a capture app is **on a roll** — when one thought is unspooling into the next, and any friction kills it. "Stop. Go back. Start a new recording" is four taps, two screen changes, and a broken thought. Most people don't restart.

The fix is one button: **end this clip, start a new one, don't disturb the flow.** No screen change. No confirm. No counter pause. The user keeps talking; the system splits the recording behind them.

This is **platform-agnostic.** Anywhere HiMem makes a voice clip — watch, phone, iPad — Next is available with the same gesture, the same haptic, the same model. The user shouldn't have to learn it twice.

## What it is, in one line

A persistent in-record control: **Next**. Tap mid-record → the current clip commits, a new clip starts immediately, the counter resets to `0:00`, and recording never pauses.

## Naming

- **Internal / spec name**: "on a roll" (the user state we're protecting).
- **Button label**: **Next**.
- **Each tap produces**: a *Clip*.
- Avoid: "Split" (implies surgery), "Section" (implies structure), "Mark" (implies bookmarking what's still rolling).

## Model

Same on every surface:

- **Each tap of Next = one new Clip.** *Not* a new Memory.
- Clips group into one **Memory** by the existing session rules (deterministic on time + location, plus the new `rollGroupId` stamped at recording start — see Implementation).
- Cancel during a roll discards **only the current, in-progress clip.** Earlier clips in the roll were committed at each Next tap; they're safe.
- Stop & save commits the current clip and ends the roll. Grouping happens normally afterward.

The model is the same across surfaces. The **routing** of the resulting Memory differs:

| Capture surface | Where the resulting Memory lands |
|---|---|
| Watch | Captured Clips inbox on phone (existing behavior) |
| Phone · direct voice (FAB on Today) | Direct to Memory Box (existing behavior, no inbox) |
| Phone · append to existing Memory | Appended to the same Memory as a new segment group |
| iPad | Direct to Memory Box (when iPad capture ships) |

Next doesn't change routing. It just changes how many clips comprise the Memory.

## Surfaces

| Surface | Status | Layout notes |
|---|---|---|
| **Watch · recording screen** | MVP | Below the counter, centered, paired with the mic disc. One-thumb mid-record use. The hardest surface — drives the visual language. |
| **Phone · direct-voice composer** | MVP | Satellite circle to the right of the centered Stop button, same horizontal axis. Larger hit target (56×56). |
| **Phone · append-to-memory composer** | MVP | Same affordance, same placement. Memory title surfaces in a header pill so the user knows which Memory Next is appending to. |
| **iPad · capture** | When iPad ships (post-MVP) | Same. |

All four ship together when they ship. Don't release Next on watch while phone records still force the user back to the previous screen — half-applied capture rules are worse than uniformly-missing ones.

## The interaction

### Resting state — recording, Next available

**Where it sits, by surface:**

- **Watch.** *Not* in the top-right corner — that's where watchOS shows the system time during recording, and Next would overlap it. Instead, Next sits **just below the unified mic disc, centered horizontally**. The counter (`0:14`) lives *inside* the pulsing mic disc rather than floating above it — they're conceptually one element ("audio is rolling, this much has been captured"), so they're drawn as one. Reading order top-to-bottom on the watch face: time (system) → **mic disc with counter inside** → **Next button** → Stop & save pill. The corner ✕ (cancel) stays in its current top-left position. This unified-disc treatment also resolves the 44mm vertical-real-estate constraint without shrinking the mic indicator.

- **Phone · direct-voice composer.** Matching the shipping layout (Cancel-Voice-Done header, transcript card mid, big ochre stop button bottom, counter beneath it): Next is a **smaller circular satellite button** to the right of the centered Stop button, on the same horizontal axis. **56pt diameter**, positioned so its center sits at `Stop.center + Stop.radius + 36pt` — i.e. a constant 36pt gap between the two button edges, regardless of how big Stop is. Below the Stop button, the counter (`00:11`) stays centered. Below Next specifically, a small "Next" label sits at the same vertical position as the counter. The left mirror position stays empty — we considered putting a "Pause" there and explicitly rejected it (see *What this is not*). On iPhone SE widths (~320pt), this layout leaves ~36pt right-edge margin — verified.

- **Phone · append-to-memory composer.** Same layout as direct-voice, with an additional header pill at the top: *"Adding to · [Memory title]"* so the user knows which Memory Next is appending to. Stop and Next sit identically.

- **iPad** (post-MVP). Same bottom-row pairing as phone.

**Visual specs (all surfaces):**
- Round button, ochre-tinted background (`rgba(198,74,28,0.18)`).
- Sizes by platform: watch **30×30**, phone **56×56**, iPad **56×56** (the watch is the floor; bigger screens get larger hit targets, not smaller).
- Glyph: forward chevron with a trailing dot. Reads as *"advance, mark."*
- Label below the glyph: **Next** — 8.5px on watch, 11px on phone/iPad, 0.4px tracking, ochre `#E07A4E`.
- Visible from the moment recording starts. No onboarding card, no first-use tooltip — it earns discovery on its own.

### Tap

- **Haptic**: single short pulse (`.click` on watch; `UIImpactFeedbackGenerator.medium` on phone/iPad).
- **Visual confirmation**: button briefly fills solid ochre with a 3px tint halo, then returns to resting tint after ~250ms.
- **Counter**: resets `1:42` → `0:00` instantly. Never pauses, never animates the digits — the reset is the signal.
- **Eyebrow**: a small uppercase line appears under the mic disc for ~1.5s on watch / under the Stop button row on phone: `CLIP 2 · ROLLING`. Ochre, 9.5px on watch / 11px on phone/iPad, 1.4px tracking, weight 700. Fades.
- **Mic indicator**: never pauses. The pulsing ochre disc (or waveform on phone/iPad) is the user's contract that audio is being captured; we don't break that contract for a transition.
- **No screen change.** No sheet, no toast, no confirm.

### Subsequent taps

- Same animation, eyebrow updates to `CLIP 3 · ROLLING`, etc.
- No max number of Next taps per roll. Storage cap is the actual ceiling (see edge cases).

## Visual states

| State | Trigger | Look |
|---|---|---|
| **Available** | Recording, storage OK | Ochre-tinted round button, "Next" label |
| **Tapped** | The ~250ms after tap | Solid ochre fill, halo, counter resetting |
| **Rolling** | 1.5s after tap | "CLIP N · ROLLING" eyebrow under counter |
| **Dimmed · watch** | At 49/50 unsynced clips | 40% opacity, label changes to "Sync soon"; tap ignored. Stop & save still works. |
| **Dimmed · phone/iPad** | Free tier at memory-cap (post-MVP, when caps land) | Same treatment. Memory in progress is never blocked from saving. |

Drawn in:
- `Himem · Watch.html · §2b` — N1 available, N2 mid-tap, N3 storage-near-full.
- `Himem · Captured Clips.html` — phone direct-voice composer with Next; phone append composer with Next.

## Edge cases

### Minimum clip length: 2 seconds

A Next tap below 2 seconds since the recording started (or since the last Next) is silently debounced:
- No haptic
- No save
- No counter reset
- Nothing in pending

Rolling-thumb / accidental-double-tap protection. It must be silent — surfacing "too short!" would punish the user for a behavior they didn't intend.

### 5-minute hard cap is per-clip, not per-roll

The existing 5-min cap on watch bounds local-storage per file. Phone doesn't have a hard per-clip cap. Either way: Next works *with* the cap. A user genuinely on a roll can chain seven 4-minute Next taps on watch. The cap doesn't shrink because of Next.

### Cancel during a roll

Cancel discards **only the current, in-progress clip.** Earlier Next-clips were committed at each tap and are in pending. Confirmation copy must be specific:

> **Discard this clip?**
> Earlier clips in this recording are already saved.

Never "this recording" — that misrepresents the model and could panic a user who just split.

### Interruptions

- **Watch · wrist-off**: existing rule, auto-stops and saves the current clip. Earlier clips in the roll already committed.
- **Phone · incoming call**: audio session interrupts. Current clip flushes and commits as if Stop & save fired; earlier clips already committed. On call end, recording does not auto-resume — the user explicitly tapped to record once, we don't restart silently.
- **Phone · backgrounded**: depends on existing background-audio entitlement. If we have it (recommended for this feature), Next works in background just like Record does. If not, backgrounding pauses recording — same as today, Next inapplicable while paused.
- **Watch · backgrounded**: existing open question. Same recovery applies; earlier clips in the roll are committed and safe.

### Storage / tier limits

- Watch: at 49/50 unsynced clips, Next dims to "Sync soon."
- Phone/iPad: today there's no equivalent ceiling. If memory caps land for Free tier post-MVP, the same dimming pattern applies. Stop & save is **never blocked** — we always let the user commit what they're saying.

## What this is *not*

- **Not pause.** No way to pause and resume one continuous clip. Two flows is one flow too many.
- **Not bookmark.** Next ends the current clip and starts a new one. A "mark this moment but keep rolling" feature is a different, post-MVP idea.
- **Not a new Memory per tap.** Clips group into Memories via existing session rules + `rollGroupId`.
- **Not a tier-gated feature.** Free users get this everywhere. Gating it would punish the people we want most to retain — the ones with thoughts coming faster than the UI can keep up.

## Tier behavior

| Tier | Next |
|---|---|
| Free | Fully available on every surface. |
| Plus / Founders | Same. |
| Studio (post-MVP) | Same. |

This is a capture affordance, not an AI or organizational feature. The Honest pricing line: *capture is always free; AI helps organize what you've captured.* Next is on the capture side of that line.

## Implementation notes

For the cross-platform team.

- **Mic never pauses across Next.** Audio session stays active; the new audio file/recorder starts before the previous one finishes flushing to disk. Tolerable: sub-100ms gap on tap. Not tolerable: a perceptible silence in playback.
- **Counter is cosmetic during the swap.** Drive it off `Date()` since the new clip's start, not from the recorder's `currentTime` (which may briefly be 0 before the new recorder is hot). Same on watch and phone.
- **`rollGroupId` UUID.** Stamp at recording-session start; preserve across Next taps. On grouping (phone-side for watch clips, in-process for phone clips), `rollGroupId` is a deterministic override over time+location heuristics. Split clips always land in one Memory even if location drifts during a long walk.
- **Sync semantics unchanged.** Each clip is its own upload unit. No "transaction" wrapping the whole roll. If 3 of 5 watch-clips sync and 2 fail, the 3 land as a partial Memory on phone with 3 segments; the 2 retry independently and append when they succeed.
- **Min-clip debounce is enforced in the UI handler**, not in the storage layer. We don't want a debounce-failure to leave a 0-byte file in pending.
- **Shared component, platform-thin.** The button visual and behavior should be one component per platform (one SwiftUI view for iOS/iPadOS, one for watchOS), wrapping a shared `NextClipController` that owns the gesture-to-action mapping, debounce, haptic call, and recorder swap. Don't fork the state machine twice.

## Phone-specific UX details

- **Append composer**: when adding to an existing Memory, the Memory's title is visible in the top header pill (e.g. *"Adding to · Saturday garden walkthrough"*). Next during append adds clips to *that* Memory. The user can't accidentally split into a new Memory by tapping Next a lot.
- **Direct-voice composer**: starts a fresh Memory. Next during direct-voice adds clips to *that fresh Memory*. Same rule.
- **Audio levels meter** stays visible across Next taps. The waveform doesn't reset to flat — it keeps rolling, matching the mic-never-pauses contract.

## Watch-specific UX details

- **Counter lives inside the mic disc**, not above it. The pulsing ochre disc grows slightly (~72pt) to host a centered tabular-numerals counter. One unit, one contract: "audio is rolling, this much has been captured." This is a small change to the existing recording screen; commit it as part of the on-a-roll work, not as a separate task.
- **✕ stays in its corner; Next sits in the body, not the chrome.** The escape (✕) and the on-a-roll affordance (Next) live in different zones — visually paired only by being the two non-Stop controls.
- **No bottom-of-screen Cancel during a roll**, per existing recording-screen rules. The corner ✕ remains the only escape.
- **Always-On display**: Next remains tappable in dimmed AOD state. The counter-inside-disc shows; the post-tap eyebrow doesn't (AOD doesn't animate text).

## Open questions

- **A small persistent "Clip 1 · 2 · 3" indicator** when not actively rolling — useful for awareness or chrome we don't need? Default: no. The eyebrow on each tap is enough.
- **Should accidental sub-2s taps log telemetry?** Useful for tuning the debounce. Belongs in v1 instrumentation, not in the spec.
- **AOD on watch**: confirm Next is tappable on the dimmed face, or whether users have to wake first. Defer to watchOS engineering reality.

## Files

- `Himem · Watch.html · §2b` — three watch specimens + Next rules block.
- `Himem · Captured Clips.html` — phone direct-voice + append composers with Next (to add).
- `CLAUDE.md` — locked rules under Watch + capture sections.
- This spec.

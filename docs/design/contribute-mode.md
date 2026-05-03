# Contribute Mode — Design Spec

## Context

Capture is currently scattered. The composer for new entries is good — multi-media tiles accumulate, the user stays in one surface until commit. But appending to an existing entry round-trips back to the read view after every capture, which is the actual gardening pain: glove on, sun on screen, thought happening now, and every photo or voice clip drops you out and forces you to reach for the next button. Contribute Mode unifies new and append captures behind one universal entry point.

## Problem

The current model has implicit modes that the UI doesn't make explicit:

- **New entry capture** — composer sheet, multi-media accumulates, single Save commits. This works.
- **Append to existing entry** — buttons in the entry's toolbar each open a separate capture flow that returns to the entry view on completion. Repeat captures round-trip every time. This is the icky part.
- **Quick voice capture from anywhere** — exists via Siri, but on-device the only way is to navigate into a composer first.

These three flows want to be the same flow.

## Model

Two modes:

- **View Mode** — reading, browsing, scrolling. No capture surface dominates the screen. Current behavior.
- **Contribute Mode** — Action Box owns the screen. Captures accumulate as tiles. The user stays here until **Done** (commit) or **X** (discard).

One entry point: a **universal Contribute button** present on every screen. Two gestures:

- **Short press** → enter Contribute Mode and immediately start voice recording. The garden gesture.
- **Long press** → enter Contribute Mode showing the Action Box, no auto-start. Deliberate, choose your capture type.

> **Note on naming.** This is not a FAB in the Material/Android sense. There is no bottom bar competing with it for affordance space, and it is not strictly a "create" button — it is a mode-toggle that is also context-aware. Calling it the **Contribute button** keeps that framing intact and avoids importing FAB-pattern assumptions about hidden affordances or floating action sheets.

Context is implicit, determined by the current screen:

- From the memory list → Contribute Mode against a **new memory**.
- From the View/Edit memory screen → Contribute Mode **against that memory** (append).

Same gesture, same destination, anchor differs by screen.

### Visual hint replaces tooltip

The Contribute button shows a small **microphone glyph** in its idle state to communicate that the default action is voice. Users learn "tap = voice" without a one-shot tooltip; long-press becomes the discoverable "I want something other than the default" gesture once a user has been in Contribute Mode at least once.

We do not ship a first-time tooltip. The mic icon is the durable hint.

## Contribute Mode UI

### Action Box

The Action Box is the entire capture surface inside Contribute Mode. It contains:

- **Capture-type buttons**, large enough for gloved/one-handed use:
  - Voice
  - Photo
  - Video
  - Text
- **Tiles area** above the buttons, showing captures accumulated this session in chronological order.
- **Done** button (top toolbar, trailing nav position) — exits Contribute Mode. The entry stays as-is.
- **X** button (top toolbar, leading nav position) — discards the session with confirmation, exits.

Anchored at the bottom of the screen so the Action Box never moves as tiles accumulate. Thumb position is consistent across the session.

### Recording state lives inside the Action Box

When voice or video recording is active, the corresponding capture-type button shows the recording state inline:

- Red dot
- Waveform (voice) or recording-time pill (video)
- Elapsed time
- Tap to stop

There is no floating recording UI elsewhere on screen. The Action Box is the source of truth for whatever capture is active. Stopping recording leaves the user in Contribute Mode with the new capture as a tile.

### Text capture is a modal full-screen editor

Text is the odd one out — voice/photo/video accumulate as "tap → capture → tile lands," but text needs the keyboard up and vertical room for real thinking. Symmetric with how camera takes the full screen during photo capture, **tapping Text opens a full-screen editor**. Done in the editor returns the user to the Action Box with the text as a tile.

This avoids the Action Box and the keyboard fighting for vertical space, and matches the modal pattern already used for camera and video.

## Persistence model

Captures persist as they are taken. The "in-progress" state is a UI/session concept, not a persisted schema flag.

### Lifecycle

- **Entering Contribute Mode against a new memory** does not create a `JournalEntry` immediately. The entry is created lazily on the **first** capture (any type). Done with zero captures is just "exit" — nothing to clean up, no orphan empty entry.
- **Entering Contribute Mode against an existing memory** uses that entry directly. Captures append to it as they're taken.
- The session tracks the **IDs of captures it created** in memory (a list of `MediaReference.id`s and any text-tile draft IDs). This list is what **X** deletes if the user discards.

### Done

- Exits Contribute Mode.
- The entry is already on disk; no commit step. The user returns to the screen they came from.

### X (Cancel)

- Deletes every capture this session created (by ID), including their on-disk files.
- For new-memory case: if every capture in the entry was created in this session (i.e. no pre-existing content), the entry itself is also deleted.
- For append case: pre-existing captures are untouched.
- Confirmation copy enumerates exact counts:

  > "You've added 1 voice clip and 3 photos to this memory. Discard them?"
  >
  > [ ] Don't ask me this
  > _You can re-enable this in Settings → Confirmations._

- Empty session (zero new captures) → exits silently, no confirmation.

### Why no schema flag

CloudKit-synced schema changes require a manual production deploy (per CLAUDE.md governance) and gate every TestFlight upload. An "in-progress" boolean would buy us nothing the in-memory session list doesn't already buy: every capture is real from the moment it lands, sync works as normal, recovery from background or crash is the no-op of "the entry is just a normal entry now." The user can re-find an unfinished session in the journal feed and edit it like any other memory.

### Backgrounding

Contribute Mode is sticky across backgrounding within a single app run. Phone call, screen timeout, swipe-to-another-app — return to the app and the Action Box is where the user left it, with the same tiles, against the same entry. The session-capture list is held in memory.

If the app is **killed** while in Contribute Mode, the session list is lost but the entry and its captures remain on disk (because they were persisted as taken). On next launch, the entry shows up in the journal feed as a normal entry; the user can resume editing it or delete it. We do not persist the session list to disk for the v1 build — recovery is "find your entry in the feed."

A future v2 nicety: tapping an in-progress entry from the feed re-enters Contribute Mode against it. Out of scope for now.

## Mis-tap protection

Short-press auto-starting voice means a stray pocket tap could create an orphan memory with a one-second voice clip. Mitigation: **silent-discard rule for trivial sessions**.

A new-memory session that, on Done, contains:

- Only **one** voice or video capture
- That capture is **shorter than 2 seconds**
- And **no** other captures (no photos, no text)

…is silently discarded — entry deleted, files deleted, no confirmation, no journal entry. This handles the dominant mis-tap failure mode (orphan one-second clip) without forcing every short-press to wait through a grace period.

We do **not** ship an armed-recording grace period (QuickTake-style hold-to-confirm) in v1. It changes the gesture model from tap to hold and is more polish than fix. Reconsider if telemetry or feedback shows mis-taps producing real noise despite the silent-discard rule.

## Settings → Confirmations

A new Settings section listing every "Don't ask me this" preference the user has muted, in plain language, each with a toggle.

Example entries:

- **Confirm before discarding a Contribute session** — Toggle: ON / OFF
- _(future muted prompts go here as the app grows)_

This is the single home for all such preferences. Any inline "Don't ask me this" checkbox in the app appears here; the user can flip it back on without re-encountering the prompt that disabled it.

The inline caption under each "Don't ask me this" checkbox is small, low-emphasis type — _"You can re-enable this in Settings → Confirmations."_ It is not a separate dialog or toast.

## Edge cases

### The Contribute button is not present inside Contribute Mode

Entry and exit are via the Action Box controls only (Done, X, and the capture-type buttons). The Contribute button does not render while Contribute Mode is active, so there is no path by which an in-progress recording can be interrupted by a stray tap on the button on the underlying screen.

### Append during processing or sync

Short-press on the View/Edit screen of an entry that's mid-sync or mid-processing should not block. Appended captures land in Core Data and the existing processing pipeline picks them up. Last-write-wins via Core Data's standard semantics.

### Stop recording without exiting Contribute Mode

Tapping the active recording button (voice or video) stops that capture and returns the user to the Action Box, ready for the next capture. The session is not committed (Contribute Mode does not have a "commit" action — Done is just "exit").

### Switching capture type mid-session

The user can voice → photo → voice → text within one session. Each capture lands as a tile. Order is preserved chronologically.

### Empty session + Done

For the new-memory case, no `JournalEntry` was ever created (lazy creation on first capture), so Done with zero captures is a silent no-op exit. For the append case, Done with zero new captures returns to View Mode unchanged.

## Watch implication

Contribute Mode is the natural primitive for the eventual watchOS app: raise wrist, audio starts, tap to stop, capture again, lower wrist (or tap Done). The phone version is the larger-screen expression of the same pattern. We design the phone version first; the watch version reuses the model when we get there. We do **not** let speculative watchOS requirements force phone-side architecture decisions today.

## What this supersedes

- The current Contribute button short-press / long-press behavior on the memory list (long-press currently opens a media selector). This design replaces that.
- Per-button capture flows on the View/Edit memory toolbar that round-trip after each capture. These get folded into the same Contribute Mode.

## Resolved decisions (from review)

- **Name**: "Contribute button," not FAB.
- **Mis-tap protection**: silent-discard rule (`<2s lone voice/video clip + nothing else` → no entry created). Grace period deferred to v2.
- **Long-press discoverability**: persistent mic-icon glyph on the button, no first-time tooltip.
- **Text capture**: modal full-screen editor, symmetric with camera.
- **Destructive copy**: "discard," not "forget."
- **Persistence**: capture-as-you-go to real `JournalEntry` rows, no schema flag, session tracks its own capture IDs in memory.

## Out of scope for v1

- Watch app implementation.
- Resuming a previously-killed Contribute session by tapping the entry in the feed.
- Armed-recording grace period (QuickTake-style hold-to-confirm).

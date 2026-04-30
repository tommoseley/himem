# Launch Screen — Design Specification

## Concept

A warm, slow blink before the day's bin opens. The launch screen is a functional sync-status indicator, not a static billboard. It greets the user, performs the CloudKit handshake, and dissolves into the feed as a single continuous surface.

~1.5 seconds minimum. Lands on Today when the connection is up. Never artificially lengthened for the sake of animation.

## Anatomy

### 1. Greeting (top)
- Time-aware: "Good morning, {first name}" / "Good afternoon" / "Good evening"
- Small, secondary text. Warm but not performative.
- Ochre dot precedes the greeting — a tiny "you're seen" beat.

### 2. Wordmark (center)
- "Hi" in Iowan Old Style bold, ink color
- "Mem" in Iowan Old Style italic, ochre (#D4A574 light / #EC7442 dark)
- The only color on the screen. Anchors the eye.

### 3. Daily Epigraph (below wordmark)
- Pulled from a curated list. Rotates daily (not randomly — date-seeded).
- Italic, small, secondary text. Centered below the wordmark.
- Sets the tone: opening the app is an intentional act of composition, not data entry.
- See **Epigraph Curation** section below.

### 4. Cloud Handshake (bottom area)
- Minimal status text:
  - "Syncing..." → while CloudKit import is active
  - "Ready" → CloudKit reports up-to-date (fades quickly, transitions to feed)
  - "Offline — showing local entries" → no network, stays as footer on feed
- No spinner. Status text only.

### 5. Progress Hairline
- Thin line below the wordmark area.
- Fills left-to-right during sync. Approximate — CloudKit doesn't give precise progress, so animate smoothly over expected duration.
- Disappears on completion.
- Feels like a precision instrument priming, not a computer hanging.

### 6. "Today" Anchor (bottom)
- The word "Today" positioned exactly where the feed's "Today" section header will sit.
- This is the transition anchor — it stays in place as the splash becomes the feed.

## States of Launch

### Cold Start (~1.5-3s)
- Full sequence: greeting, wordmark, epigraph, sync status, progress hairline.
- "Today" anchor visible at bottom.
- Transition to feed when sync completes or times out (3s max — show local data).

### Warm Start (immediate)
- App was backgrounded recently, context still in memory.
- Skip the splash entirely. Go straight to feed.
- The foreground reload observer handles sync silently.

### First Launch (extended)
- Full CloudKit initial sync may take 5-10 seconds.
- Same splash but progress hairline runs longer.
- "Syncing..." stays visible until first entries arrive.
- If no entries exist yet, transition to empty state with "Tap + to create a memory."

## Transition: Splash → Feed

Matched geometry transition. The splash doesn't dismiss — it *becomes* the feed.

1. **Wordmark and epigraph** fade out (0.3s ease-out)
2. **"Today" label stays put** — anchored via `matchedGeometryEffect` with the feed's "Today" section header. Same position, same font, same size. No movement.
3. **Feed content fades in** around the anchored "Today" (0.3s ease-in)
4. **Background crossfades** from splash warm tone to feed paper color
5. **Progress hairline** fades out with the wordmark

The user's eye stays on "Today" throughout. The app feels like it was always showing today's view — the splash was just the feed before the entries loaded.

### SwiftUI Implementation Notes
- Use `@Namespace` shared between splash and feed views
- Apply `.matchedGeometryEffect(id: "today-header", in: namespace)` to the "Today" text in both views
- Splash and feed are layers in a `ZStack`, not separate navigation destinations
- Transition controlled by a single `@State var splashComplete: Bool`

## Visual Design

### Light Mode
- Background: Crucible paper (#FAF8F5 or similar warm off-white)
- Wordmark "Hi": Crucible ink
- Wordmark "Mem": Ochre #D4A574
- All other text: Crucible ink3/ink4 (secondary)
- Progress hairline: Ochre, 1pt height

### Dark Mode
- Background: Crucible dark paper
- Wordmark "Hi": Crucible dark ink
- Wordmark "Mem": Ochre #EC7442 (boosted for dark mode legibility)
- Progress hairline: Ochre #EC7442

## Epigraph Curation

### Purpose
Each line should feel like something a thoughtful person would say to frame the act of remembering. Not motivational quotes. Not fortune cookies. Moments of intention.

### Selection Criteria
- Under 60 characters (must fit on one line on iPhone SE)
- Present tense or imperative — not past tense nostalgia
- About observation, attention, memory, or noticing — not productivity
- No attribution shown (keeps the screen clean; attribution stored in data)
- Tone: quiet confidence, not whimsy

### Rotation
- Date-seeded: `Calendar.current.ordinality(of: .day, in: .year, for: Date())` mod collection count
- Same line all day, different tomorrow
- No randomness — users on multiple devices see the same epigraph

### Storage & Sync
- Stored in the backend database (Postgres on `api.thecombine.ai`)
- Table: `epigraphs(id, text, source, active, created_at)`
- App fetches the full list via `GET /himem/epigraphs` on launch
- Cached locally in `UserDefaults` (lightweight — 30-50 short strings)
- Cache refreshed on each cold start; stale cache used if offline
- This means new epigraphs can be added server-side without an app update
- Start with 30-50 lines. Grow over time.
- Review quarterly — remove any that feel stale or generic

### Seed Examples (candidates — need curation pass)
```
"We do not remember days, we remember moments."
"Pay attention. Be astonished. Tell about it."
"The art of seeing has to be learned."
"What you notice becomes your life."
"Memory is the diary we all carry about with us."
"To look at a thing is very different from seeing it."
"Write it down. It will not come this way again."
"The present moment is filled with joy and happiness."
"Every day is a collection of moments."
"Notice what you notice."
```

### Adding New Epigraphs
- Propose in a batch (10+), curate down to the ones that pass all criteria
- Test on device at smallest screen size to verify line length
- No duplicates in meaning (two lines about "paying attention" — pick the stronger one)

## What This Screen Is NOT

- Not a marketing screen. No tagline, no feature callout.
- Not a loading screen. It does real work (sync), but if sync is instant, the screen is instant.
- Not a meditation. 1.5 seconds, not 5. Respect the user's time.
- Not a place for animation beyond the progress hairline. No breathing dots, no particle effects. The waveform lives on the capture screen.

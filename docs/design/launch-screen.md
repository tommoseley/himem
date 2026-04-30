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

## Epigraph System

### Purpose
Epigraphs are a progression arc, not decoration. They quietly teach: capture → reflect → create. Users won't consciously notice the evolution, but they'll feel it — like seasons, not switches.

### Selection Criteria
- Under 60 characters (must fit on one line on iPhone SE)
- No attribution shown on screen (stored in data for internal reference)
- Must earn its place next to literary quotes — no marketing copy, no fortune cookies
- Tone: quiet confidence, intention, observation
- No original/branded lines unless they pass the read-aloud test: read the original line immediately after a Pavese or Wilde quote. If it sounds like a tagline, cut it.

### Stages

The epigraph pool progresses with the user's journey. Stages blend — no hard cutoffs.

**Stage 1 — Awareness (0-9 memories)**
Theme: notice and capture. The act of remembering matters.

```
"We do not remember days, we remember moments." — Cesare Pavese
"Pay attention. Be astonished. Tell about it." — Mary Oliver
"The art of seeing has to be learned." — Marguerite Duras
"To look at a thing is very different from seeing it." — Oscar Wilde
"The world is full of magic things, patiently waiting." — W.B. Yeats
"Notice what you notice." — unknown
"Write it down. It will not come this way again." — unknown
"What you notice becomes your life." — Jenny Offill
"Every exit is an entry somewhere else." — Tom Stoppard
"The eye sees only what the mind is prepared to comprehend." — Robertson Davies
```

**Stage 2 — Habit (10-39 memories)**
Theme: you're building something. The collection has weight.

```
"Memory is the diary that we all carry about with us." — Oscar Wilde
"Your memory and your senses nourish your creative impulse." — Arthur Rimbaud
"The things you own end up owning you. The things you notice end up shaping you." — unknown
"A writer is someone for whom writing is harder than for other people." — Thomas Mann
"How we spend our days is how we spend our lives." — Annie Dillard
"The imagination needs moodling." — Brenda Ueland
"You can't use up creativity. The more you use, the more you have." — Maya Angelou
"Collect the details. They are the only things that matter." — unknown
"What is remembered, lives." — traditional
"The harvest of old age is the memory of abundant blessings." — Cicero
```

**Stage 3 — Meaning (40+ memories)**
Theme: you have material — shape it. Transition to creation mindset.

```
"Write what should not be forgotten." — Isabel Allende
"Inspiration exists, but it has to find you working." — Pablo Picasso
"There is no such thing as a new idea. We simply combine old ones." — Mark Twain
"There is no greater agony than bearing an untold story inside you." — Maya Angelou
"The desire to create is one of the deepest yearnings of the soul." — Dieter F. Uchtdorf
"Start writing, no matter what. The water does not flow until the faucet is turned on." — Louis L'Amour
"You don't start out writing good stuff. You start out writing crap." — Octavia Butler
"Arrange whatever pieces come your way." — Virginia Woolf
"Every secret of a writer's soul is written in his works." — Virginia Woolf
"The scariest moment is always just before you start." — Stephen King
```

### Stage Selection Logic (client-side)

```
let memoryCount = entries.count

// Blend stages — weighted random from eligible pools
// Stage 1 always available (foundational)
// Stage 2 fades in at 5, fully present by 15
// Stage 3 fades in at 25, fully present by 50

func eligibleStages(memoryCount: Int) -> [(stage: Int, weight: Double)] {
    var stages: [(Int, Double)] = [(1, 1.0)]

    if memoryCount >= 5 {
        let stage2Weight = min(1.0, Double(memoryCount - 5) / 10.0)
        stages.append((2, stage2Weight))
    }
    if memoryCount >= 25 {
        let stage3Weight = min(1.0, Double(memoryCount - 25) / 25.0)
        stages.append((3, stage3Weight))
    }

    // Fade out earlier stages as later ones strengthen
    if memoryCount >= 15 { stages[0].1 = 0.3 } // Stage 1 fades
    if memoryCount >= 50 { stages[1].1 = 0.5 } // Stage 2 fades

    return stages
}
```

### Rotation
- Date-seeded within the selected stage pool
- `Calendar.current.ordinality(of: .day, in: .year)` determines the day
- Day seed selects stage (weighted), then selects line within that stage
- Same line all day across all devices (deterministic from day + memory count range)
- No repeat within 7 days — track last 7 shown in UserDefaults

### Storage & Sync
- Stored in the backend database (Postgres on `api.thecombine.ai`)
- Table: `epigraphs(id, text, source, stage, active, created_at)`
- API: `GET /himem/epigraphs` returns full catalog
- Cached locally in `UserDefaults` (lightweight — 30 short strings)
- Cache refreshed on each cold start; stale cache used if offline
- New epigraphs added server-side without app update
- App ships with bundled seed set as fallback for first-ever launch
- Stage selection logic lives in the app (server doesn't know user state)

### Adding New Epigraphs
- Propose in a batch (10+), curate down to those that pass all criteria
- Test on device at smallest screen size to verify line length
- No duplicates in meaning — if two lines say the same thing, keep the stronger one
- Minimum 10 lines per stage to keep daily rotation feeling fresh
- Read-aloud test: read the candidate after a strong literary quote. Does it hold up?

## What This Screen Is NOT

- Not a marketing screen. No tagline, no feature callout.
- Not a loading screen. It does real work (sync), but if sync is instant, the screen is instant.
- Not a meditation. 1.5 seconds, not 5. Respect the user's time.
- Not a place for animation beyond the progress hairline. No breathing dots, no particle effects. The waveform lives on the capture screen.

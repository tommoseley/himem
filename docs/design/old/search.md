# Search — Implementation Plan

## Context

Search is how users return to the Memory Box. One field, three powers: free text, typed scopes, and scope chips. Four core states plus two voice overlays. Design spec extracted from `docs/Himem Search _offline_.html`.

## What Exists Today

- `SearchEngine.swift` — basic text search, entity type search, topic search against Core Data
- `SearchViewModel.swift` — holds query text, selected entity types, results
- `SearchView.swift` — simple search field + entity type toggles + results list
- `SpeechService.swift` — live transcription (used in Composer)
- Search is presented as a sheet from JournalView (magnifying glass icon in header)

## What We're Building

A complete replacement of the current search with the design system spec.

---

## Phase 1: Search Data Layer

### Scope Parser
**New file:** `Services/Search/ScopeParser.swift`

Parse typed scopes from the search field text:
- `topic:garden` → filter by topic
- `type:voice` / `type:text` / `type:photo` / `type:video` → filter by input type
- `date:today` / `date:this-week` / `date:last-month` / `date:2024` / `date:before:apr-1` → date range
- Scopes compose: `topic:garden type:voice tomato` → topic filter + type filter + text search "tomato"
- Returns: `SearchQuery { text: String, topicScope: String?, typeScope: InputType?, dateRange: DateRange? }`

### Enhanced SearchEngine
**Modified file:** `Services/AI/SearchEngine.swift`

- Accept `SearchQuery` from ScopeParser (not just raw text + entity types)
- Add date range filtering
- Add input type filtering
- Return snippet with match range for highlighting
- Add result counting by topic and type (for scope chip counts)
- Add "Forgotten" card query: random entry older than 6 months, not opened in >3 months

### Recent Searches
**New:** Store in UserDefaults as `[String]` (preserves typed-scope syntax). Max 10. "Forget all" clears.

---

## Phase 2: Search UI — Core States

### SearchView Rewrite
**Modified file:** `Views/Search/SearchView.swift`

Complete rewrite. Four states driven by `searchState` enum:

```
enum SearchState {
    case preSearch
    case typing
    case results
    case noResults
}
```

### State 1: Pre-Search
Shown when search field is empty and not focused.

- **Recent searches** — list with typed-scope syntax preserved, "Forget all" button
- **Browse by topic** — horizontal scroll of topic pills with entry counts
- **"Forgotten" card** — single random old memory in italic serif, topic pip, age label
  - "From your Memory Box · 14 months ago"
  - Tapping opens the entry

### State 2: Typing
Shown when search field is focused and has text.

Two columns:
- **Top: text matches** — live search results as user types (debounced 300ms)
  - "ato seedlings" → "in entries" / "from book club" / "person mentioned"
- **Bottom: Filter by** — scope suggestions based on partial input
  - `topic: Garden (28 entries)` / `topic: Cooking (19 entries)` / `type: voice notes`
  - Tapping a suggestion appends the scope to the search field as a chip

### State 3: Results
Shown after search executes (user taps search/return or selects a scope).

- **Scope chips** below the search field — faceted filters on current results
  - Topic chips (Garden, Cooking) + type chips (Voice, Notes) with counts
  - Tapping narrows, tapping again widens
- **Result count** — "7 entries · last 14 months"
- **Results grouped by relative date:**
  - Today / Yesterday
  - This week
  - Last month / (Month name)
  - Earlier in YYYY
  - Older
- **Each result card:**
  - Topic pill + relative time + media type icon
  - Title
  - Matched snippet with warm-yellow highlight `rgba(255,213,110,.55)`
  - Tapping opens EntryExpandedView

### State 4: No Results
- Italic serif: "Nothing in your Memory Box matches '{query}'."
- Warm subtitle: "Maybe it's not a memory yet — just a thought looking for a place to land."
- **Hero CTA:** Ochre card — `Capture "{query}" now` → opens Composer with query pre-filled
- **Fallback paths:**
  - "Search just '{shorter term}'" — if query has multiple words
  - "Browse {related topic}" — if a topic matches part of the query

---

## Phase 3: Voice Search Overlays

### Voice Listening
**New file:** `Views/Search/VoiceSearchView.swift`

- Full-screen takeover with warm background
- "Listening" label at top
- Breathing waveform (reuse from Composer)
- Italic serif transcript builds live as user speaks
- Back chevron exits without committing
- Ochre "Done" pill confirms
- Silence detection auto-confirms after 2s pause

### Voice Interpreted
Shown after voice input is processed.

- "Heard" section — the raw transcript in quotes
- "Looking for" section — parsed query terms + inferred scope chips
- "What HiMem thinks you mean" — brief natural language summary + result count
- **Edit** button — returns to search field with parsed query pre-filled
- **Search** button (ochre) — executes the search
- Never auto-fires in v1 — transparency wins

### Voice Intent Parsing
**Modified file:** `Services/AI/ClaudeAPIService.swift` (or new endpoint)

Send voice transcript to API for intent extraction:
```
POST /himem/search-intent
{ "transcript": "Find the memory about the tomato trellis I saw last spring" }
→ { "terms": "tomato trellis", "scopes": { "topic": "garden", "date": "spring" } }
```

OR parse locally with keyword extraction (simpler, no API dependency):
- Strip filler words ("find", "the", "memory", "about", "I", "saw")
- Detect topic names from existing topics
- Detect date references ("last spring", "yesterday", "March")

---

## Phase 4: Highlighting & Polish

### Match Highlighting
- Warm-yellow highlight: `rgba(255,213,110,.55)` — NOT ochre
- Applied to matched terms in result snippets
- Use `AttributedString` or `Text` with inline styling

### Snippet Extraction
- Find match position in entry content
- Extract ~150 chars centered on the match
- Prefix/suffix with "…" if truncated
- Highlight all occurrences of the search term

### "Forgotten" Card Logic
- Query: entries where `createdAt` > 6 months ago AND not opened in > 3 months
- Need a `lastViewedAt` field on JournalEntry (new Core Data attribute)
- Random selection: pick one at random, rotate daily (date-seeded like epigraphs)
- Shows in pre-search only

---

## Files to Create
- `Views/Search/SearchView.swift` (rewrite)
- `Views/Search/VoiceSearchView.swift`
- `Services/Search/ScopeParser.swift`

## Files to Modify
- `Services/AI/SearchEngine.swift` — enhanced query support, snippets, forgotten card
- `ViewModels/SearchViewModel.swift` — new states, scope management, recent searches
- `Models/JournalEntry.swift` — add `lastViewedAt` attribute (for Forgotten card)
- `Models/MemoryStream.xcdatamodeld` — add `lastViewedAt` to JournalEntry entity

## Dependencies
- Voice search reuses `SpeechService` from Composer
- Search intent parsing: decide local vs API (recommend local for v1)
- Forgotten card needs `lastViewedAt` tracking — update when user opens an entry

## Design Tokens (from spec)
- Highlight color: `rgba(255, 213, 110, 0.55)` (warm yellow)
- Pre-search background: Crucible paper
- Forgotten card: italic serif quote, topic pip, muted age text
- Voice overlay: full-screen, breathing waveform, ochre Done pill
- No-results hero: ochre background card for capture CTA

## Build Order
1. ScopeParser + enhanced SearchEngine (data layer, testable)
2. Pre-search state (recent + topics + forgotten card)
3. Typing state (live suggestions)
4. Results state (grouped, highlighted, scope chips)
5. No-results state (capture CTA)
6. Voice listening overlay
7. Voice interpreted overlay

## Verification
- Type "tomato" → results grouped by date with yellow highlights
- Type "topic:garden tomato" → scoped results
- Tap topic chip → narrows results, count updates
- Empty search → pre-search with recents + topics + forgotten card
- No results → capture CTA works, fallback paths work
- Voice: say "find garden notes from last month" → parsed correctly → results
- Forgotten card shows a genuine old memory, changes daily

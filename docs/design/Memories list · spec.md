# Memories list · spec

**Status:** first spec for this surface. June 4 2026.

**Why now.** The Memories list is HiMem's main browsing surface — the index to the Memory Box — and it had never been spec'd or drawn in design; shipped iOS ran ahead of it. This locks the model after retiring the three-mode (concise / regular / full) toggle.

---

## 1 · Purpose & posture

The Memories list exists for **recognition and selection**, not reading. The user scans, recognizes a memory, and taps to open it. Reading the whole thing happens in **Memory Detail**, never in the list.

This is a **reflective** surface (cream paper, editorial restraint) — but it's the *index* to the gallery, not the gallery itself. So it borrows one reflective signal (serif titles) and stays operationally efficient everywhere else. Calm, opinionated, never a database dump.

---

## 2 · The mode decision (locked)

**One card. No user-facing density toggle.** The retired model had three modes (Concise / Regular / Full); all three are gone:

- **Full is removed.** Inlining a multi-page memory turns the list into the detail screen and creates a scroll swamp as memories grow. Tap already does this, better.
- **Concise is removed** as a global mode. One thin line per memory makes the product feel like a database, not a memory keeper.
- **No "Show more"** in the list. Expansion is a destination (tap → Detail), not an inline action.

**Density is contextual, not user-selected.** The same memory renders at different densities depending on *where* it appears — because each context needs it, never because the user flipped a switch:

| Context | Density |
|---|---|
| Memories list (this spec) | Balanced recognition card |
| Search results | Denser rows, match-highlighted |
| Project add / select | Concise selection rows |
| Memory Detail | Full content |

If a power-user need for raw density ever proves real, it lives as a quiet Settings option (Comfortable / Compact) — **not** shipped as a prominent mode. Default ships without it.

---

## 3 · Card anatomy (locked)

Top to bottom, tight:

1. **Title** — Source Serif, ~17px. The one reflective signal. The card's primary recognition handle.
2. **Meta line** — SF Pro ~13px, ink3: `time · optional place`.
3. **Media indicators** — glyph + count per type (see §5).
4. **Topic chips** — max 2, `+N` overflow pill beyond that.
5. **Gist** — up to **3 lines**, hard clamp, **~15px** (close to the title so it reads as primary content, not a caption). Content follows the fallback chain (§4).

Nothing else. **No** thumbnails as routine furniture, **no** next-step indicators, **no** project links, **no** 4-line+ summaries, **no** "Show more". Recognition needs a title and a few true lines, not a dashboard.

**Tap targets:** the whole card → Memory Detail. There is no secondary tap target inside the card.

---

## 4 · The content-fallback chain (the unlock)

The gist line always says something **true**, regardless of how mature the memory is. Resolve in order:

1. **AI summary** — if the memory is organized. Preceded by a small AI-blue sparkle glyph (provenance, costs no line). Sentence case, SF Pro.
2. **First meaningful transcript excerpt** — if raw / unorganized. Rendered in **italic serif** to signal *these are the user's own words, verbatim*. No sparkle.
3. **Media description** — if there's no useful text yet (e.g. photo-only). Plain ink3: *"3 photos captured near the West Garden."* No sparkle.

This chain is what makes one card sufficient — the card adapts to the memory instead of the user adapting the view.

**Provenance rule:** the AI-blue sparkle is the *only* AI-blue on the card and the only thing that marks AI authorship. Raw excerpts and media descriptions never get it.

---

## 5 · Media indicators & the dot legend (fix)

Shipped iOS used colored dots including **blue** — a violation, since blue is reserved for AI. Categorical color is also unavailable (green / amber / red are semantic-only per Crucible). **Resolution: media types are differentiated by glyph *shape*, not color.**

| Type | Glyph | Color |
|---|---|---|
| Audio | waveform | **ochre** (audio = ochre is locked; the one legitimate tint) |
| Photo | camera | warm ink (ink3) |
| Video | film frame | warm ink (ink3) |
| Note / text | text lines | warm ink (ink3) |

Format: `‹glyph› 4  ‹glyph› 1` with type counts. **Cap:** past ~3 distinct types or very high counts, collapse to a single summary (`12 items`) — never a dot-soup row.

---

## 6 · Sectioning & sticky headers (fixes)

- **Time sections**: Today, Yesterday, then `Weekday, Month D`, then by month, then by year as you descend.
- **Sticky headers must be opaque.** Shipped iOS let the date header go transparent mid-scroll so card text bled through it. Section headers carry a solid cream background.
- **No orphan headers.** A date section with zero visible memories never renders its header.
- Section headers are Source Serif, quiet — they're orientation, not titles.

---

## 7 · Filters (locked)

- Topic filter chips above the list: `All · ‹topics›`. **Single-select.** Selecting one filters the list to that topic; it does **not** change density.
- Chips derive from the topics actually present in the library. Topic dot colors come from the topic palette (never AI blue / never the action ochre).
- No per-chip counts in the bar — they shift and add noise.
- **Search** is the other reduction path and owns needle-finding; the list owns browsing. Search results get their own denser, match-highlighted row shape (§2).

---

## 8 · Load behavior at scale (architecture)

The 500-memory ceiling and CloudKit's sequential-cursor limits only bite if the *list* is driven by live CloudKit queries. **It isn't.** Split the data:

- **List index = local (Core Data).** Date sections, titles, topic chips, media counts, AI summary text — all read from the local store. Instant, all 500, no CloudKit round-trip. The 500 cap becomes a *sync/storage* concern, not a *rendering* one.
- **Heavy content = lazy from CloudKit.** Full transcripts, audio, photos, video fetch on demand as a card nears the viewport. Off-screen cards reserve height but don't fetch.

This makes lazy-load real **and** makes a future time-scrubber feasible (it seeks a local index, not CloudKit cursors).

- **A real ending.** At the bottom of the list: *"The beginning — your first memory, ‹month year›."* A Memory Box has a bottom; reaching it should feel like arrival, not a spinner that gave up. This is the anti-doomscroll signal — the list is finite and you've seen all of it.

---

## 9 · Crucible compliance fixes (locked, carried into the build)

These were violations in shipped iOS; the design corrects them and they ride the same pre-TestFlight AI-color sweep noted in `CLAUDE.md`:

1. **Header chrome de-blued.** Search / settings / any header glyphs are warm ink, never iOS system blue. (The `AI SUMMARY` provenance mark stays AI-blue — that one's correct.)
2. **Media dots de-blued** → glyph-shape differentiation (§5).
3. **Sticky headers opaque** (§6).
4. **Orphan date headers suppressed** (§6).

---

## 10 · Open / deferred

- **Time-scrubber rail** (Photos-style fast-seek on the right edge) — feasible on the local-index architecture, deferred until the single-card list ships and we see whether scroll-at-scale actually hurts.
- **Comfortable / Compact Settings option** — only if a real power-user need surfaces post-launch. Not in MVP.
- **Media-first thumbnail** — a single small visual cue is *allowed* when a memory is photo/video-dominant and has no useful text, but thumbnails are never routine card furniture. Exact treatment to be drawn if/when media-first memories are common.

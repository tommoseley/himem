// screens-memories.jsx
// The Memories list — HiMem's main browsing surface. One card, no density
// toggle (Concise/Regular/Full retired). Density is contextual: this list,
// search results, and project-select each get their own shape.
//
// See "Memories list · spec.md".
//
// Loads after crucible-primitives.jsx and screens-projects.jsx (for TOPIC,
// topicVar, TopicChip, Seg, HiMemMark).

// ─────────────────────────────────────────────────────────────
// Media glyphs — differentiated by SHAPE, not color (blue dots were an
// AI-reservation violation; green/amber/red are semantic-only). Audio
// gets the one legitimate tint: ochre. Everything else is warm ink.
// ─────────────────────────────────────────────────────────────
function MediaAudio({ c = PX.accent }) {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke={c} strokeWidth="1.5" strokeLinecap="round">
      <path d="M2 8v0M5 5.5v5M8 3v10M11 5.5v5M14 8v0" />
    </svg>
  );
}
function MediaPhoto({ c = PX.ink3 }) {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke={c} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <rect x="1.5" y="3.5" width="13" height="10" rx="2" /><circle cx="8" cy="8.5" r="2.4" /><path d="M5 3.5l1-1.5h4l1 1.5" />
    </svg>
  );
}
function MediaVideo({ c = PX.ink3 }) {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke={c} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <rect x="1.5" y="4" width="9" height="8" rx="1.6" /><path d="M10.5 7l4-2.2v6.4L10.5 9" />
    </svg>
  );
}
function MediaNote({ c = PX.ink3 }) {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke={c} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 3.5h10M3 6.5h10M3 9.5h7" />
    </svg>
  );
}

// media: { audio, photo, video, note } counts. Renders glyph+count groups,
// or collapses to "N items" past ~3 distinct types.
function MediaRow({ media }) {
  const entries = [
    ['audio', media.audio, MediaAudio, PX.accent],
    ['photo', media.photo, MediaPhoto, PX.ink3],
    ['video', media.video, MediaVideo, PX.ink3],
    ['note',  media.note,  MediaNote,  PX.ink3],
  ].filter(([, n]) => n);
  const total = entries.reduce((s, [, n]) => s + n, 0);

  if (entries.length > 3) {
    return (
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>
        <MediaAudio c={PX.accent} />
        <span>{total} items</span>
      </div>
    );
  }
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 13 }}>
      {entries.map(([key, n, Glyph, c]) => (
        <span key={key} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12, color: PX.ink2, fontVariantNumeric: 'tabular-nums' }}>
          <Glyph c={c} />{n}
        </span>
      ))}
    </div>
  );
}

// Tiny AI-blue sparkle — provenance for an organized summary. The ONLY
// AI-blue on the card, and the only marker of AI authorship.
function AISpark() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill={PX.ai} style={{ flexShrink: 0, transform: 'translateY(2px)' }}>
      <path d="M8 1l1.4 4.1 4.1 1.4-4.1 1.4L8 12l-1.4-4.1L2.5 6.5l4.1-1.4z" />
    </svg>
  );
}

// Topic chips capped at 2, with a +N overflow pill.
function TopicChips({ topics }) {
  const shown = topics.slice(0, 2);
  const extra = topics.length - shown.length;
  return (
    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
      {shown.map(k => (
        <span key={k} style={{
          display: 'inline-flex', alignItems: 'center', gap: 5,
          height: 22, padding: '0 9px', borderRadius: 11,
          background: PX.wash1, fontSize: 11.5, fontWeight: 500, color: PX.ink2, letterSpacing: -0.1,
        }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: topicVar(TOPIC[k].slug) }} />
          {TOPIC[k].label}
        </span>
      ))}
      {extra > 0 && (
        <span style={{ fontSize: 11.5, fontWeight: 600, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>+{extra}</span>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// THE memory card. One card, contextual gist via fallback chain.
//   gist.kind: 'summary' (AI sparkle) | 'excerpt' (italic serif) | 'media'
// ─────────────────────────────────────────────────────────────
function MemoryCard({ title, time, place, media, topics, gist }) {
  const meta = place ? `${time} · ${place}` : time;
  let gistEl;
  if (gist.kind === 'summary') {
    gistEl = (
      <div style={{ display: 'flex', gap: 7, alignItems: 'flex-start' }}>
        <AISpark />
        <span style={{
          fontSize: 15, color: PX.ink2, lineHeight: 1.5, letterSpacing: -0.05,
          display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden',
        }}>{gist.text}</span>
      </div>
    );
  } else if (gist.kind === 'excerpt') {
    gistEl = (
      <div style={{
        fontFamily: PX.serif, fontStyle: 'italic', fontSize: 15.5, color: PX.ink2, lineHeight: 1.5,
        display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden',
      }}>&ldquo;{gist.text}&rdquo;</div>
    );
  } else {
    gistEl = (
      <div style={{
        fontSize: 15, color: PX.ink3, lineHeight: 1.5, letterSpacing: -0.05,
        display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden',
      }}>{gist.text}</div>
    );
  }
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 9,
    }}>
      <div>
        <div style={{ fontFamily: PX.serif, fontSize: 17.5, fontWeight: 500, color: PX.ink, letterSpacing: -0.2, lineHeight: 1.2, textWrap: 'pretty' }}>
          {title}
        </div>
        <div style={{ fontSize: 13, color: PX.ink3, marginTop: 3, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.05 }}>
          {meta}
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
        <MediaRow media={media} />
        <span style={{ flex: 1 }} />
        <TopicChips topics={topics} />
      </div>
      {gistEl}
    </div>
  );
}

// Sticky, OPAQUE date section header (shipped header bled through; fixed).
function DateHeader({ label }) {
  return (
    <div style={{
      position: 'sticky', top: 0, zIndex: 2, background: PX.paper,
      padding: '10px 4px 8px',
      fontFamily: PX.serif, fontSize: 15, fontWeight: 400, color: PX.ink2, letterSpacing: -0.2,
    }}>
      {label}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Header: HiMem wordmark (left) · search + settings (right).
// The canonical top bar — identical across Clips / Memories / Projects.
// Object switching lives in the BOTTOM TabBar, not a top Seg. The old
// 2-object "Memories|Projects" segmented control is retired (it omitted
// Clips and duplicated the bottom nav). See HiMem · Home.html.
// ─────────────────────────────────────────────────────────────
function MemoriesHeader({ activeFilter = 'All' }) {
  const filters = ['All', 'content', 'tech', 'garden', 'howWeWork'];
  return (
    <div style={{ paddingTop: 6, background: PX.paper }}>
      <div style={{ padding: '8px 16px 10px', display: 'flex', alignItems: 'center' }}>
        <HiMemMark />
        <span style={{ flex: 1 }} />
        {/* de-blued action glyphs — search + settings. */}
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 16, color: PX.ink }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" />
          </svg>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
          </svg>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8, padding: '6px 14px 12px', overflow: 'hidden', whiteSpace: 'nowrap' }}>
        {filters.map(f => (
          f === 'All'
            ? <span key="All" style={{
                display: 'inline-flex', alignItems: 'center', height: 26, padding: '0 12px', borderRadius: 13,
                background: activeFilter === 'All' ? PX.accentTint2 : 'transparent',
                border: '1px solid ' + (activeFilter === 'All' ? 'transparent' : PX.hairline),
                fontSize: 13, fontWeight: 500, color: activeFilter === 'All' ? PX.accentPress : PX.ink2, letterSpacing: -0.1,
              }}>All</span>
            : <TopicChip key={f} k={f} active={activeFilter === TOPIC[f].label} />
        ))}
      </div>
    </div>
  );
}

// The "you've reached the bottom" end-state.
function BeginningMarker({ first = 'March 2024' }) {
  return (
    <div style={{ padding: '26px 14px 30px', textAlign: 'center' }}>
      <div style={{ width: 30, height: 1, background: PX.hairline, margin: '0 auto 14px' }} />
      <div style={{ fontFamily: PX.serif, fontSize: 15, fontStyle: 'italic', color: PX.ink2, lineHeight: 1.5 }}>
        The beginning
      </div>
      <div style={{ fontSize: 12, color: PX.ink3, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>
        Your first memory, {first}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Sample data — the three fallback types from the spec examples.
// ─────────────────────────────────────────────────────────────
const M_SUMMARY = {
  title: 'Content creator capture platform concept',
  time: '2:22 PM', place: 'Marsh Walk',
  media: { audio: 2, photo: 1 },
  topics: ['content', 'tech'],
  gist: { kind: 'summary', text: 'A product idea for capturing creative fragments from Watch, phone, and iPad, then using AI to organize them into scripts, essays, and longer-form projects over time.' },
};
const M_EXCERPT = {
  title: 'Untitled memory',
  time: '11:28 AM',
  media: { audio: 1 },
  topics: ['tech'],
  gist: { kind: 'excerpt', text: 'The nice part about the application is that you can be just about anywhere and have a thought and record it, and you don’t have to worry about losing it later on…' },
};
const M_MEDIA = {
  title: 'Photos from the garden',
  time: '4:13 PM', place: 'West Garden',
  media: { photo: 3 },
  topics: ['garden'],
  gist: { kind: 'media', text: '3 photos captured near the West Garden.' },
};
const M_LONG = {
  title: 'Long-form knowledge capture architecture',
  time: '9:04 AM',
  media: { audio: 9, photo: 1, video: 1 },
  topics: ['tech', 'content', 'howWeWork'],
  gist: { kind: 'summary', text: 'Notes toward a system that turns scattered voice clips into structured, searchable knowledge — clips become sessions, sessions become memories, and the AI keeps the through-line intact.' },
};
const M_COOK = {
  title: 'Sourdough timing notes',
  time: 'Yesterday · 7:40 PM', place: 'Home',
  media: { audio: 1, note: 1 },
  topics: ['cooking'],
  gist: { kind: 'excerpt', text: 'Levain at 9pm, mix by 7 the next morning — the long cold proof is what gives it the open crumb…' },
};

// ─────────────────────────────────────────────────────────────
// SCREEN 1 · the list, single mode
// ─────────────────────────────────────────────────────────────
function ScrMemoriesList() {
  return (
    <PhoneScreen>
      <MemoriesHeader activeFilter="All" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 14px' }}>
        <DateHeader label="Today" />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingBottom: 12 }}>
          <MemoryCard {...M_SUMMARY} />
          <MemoryCard {...M_EXCERPT} />
          <MemoryCard {...M_MEDIA} />
        </div>
        <DateHeader label="Yesterday" />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingBottom: 12 }}>
          <MemoryCard {...M_COOK} />
        </div>
      </div>
      <TabBar active="memories" />
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 2 · filtered + the beginning end-state
// ─────────────────────────────────────────────────────────────
function ScrMemoriesFiltered() {
  return (
    <PhoneScreen>
      <MemoriesHeader activeFilter="Technology" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 14px' }}>
        <DateHeader label="Today" />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingBottom: 12 }}>
          <MemoryCard {...M_LONG} />
          <MemoryCard {...M_SUMMARY} />
          <MemoryCard {...M_EXCERPT} />
        </div>
        <BeginningMarker first="March 2024" />
      </div>
      <TabBar active="memories" />
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// CONTEXT VARIANTS — same memory, different density. Proves density is
// contextual, not a user mode.
// ─────────────────────────────────────────────────────────────

// Search result row — denser, with a highlighted match.
function SearchRow({ title, time, snippet, match }) {
  const parts = snippet.split(match);
  return (
    <div style={{ padding: '11px 4px', borderBottom: '1px solid ' + PX.divider }}>
      <div style={{ fontFamily: PX.serif, fontSize: 15, fontWeight: 500, color: PX.ink, letterSpacing: -0.15 }}>{title}</div>
      <div style={{ fontSize: 13, color: PX.ink2, marginTop: 3, lineHeight: 1.4 }}>
        {parts[0]}<mark style={{ background: PX.accentTint, color: PX.accentPress, fontWeight: 600, borderRadius: 3, padding: '0 1px' }}>{match}</mark>{parts[1]}
      </div>
      <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>{time}</div>
    </div>
  );
}
function ScrSearchContext() {
  return (
    <PhoneScreen>
      <div style={{ paddingTop: 6, background: PX.paper }}>
        <div style={{ padding: '10px 16px 8px' }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 9, height: 40, padding: '0 14px',
            background: PX.card, border: '1px solid ' + PX.accent, borderRadius: 12,
            boxShadow: '0 0 0 3px ' + PX.accentTint,
          }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={PX.ink3} strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" /></svg>
            <span style={{ fontSize: 15, color: PX.ink, letterSpacing: -0.1 }}>capture</span>
          </div>
        </div>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, padding: '8px 18px 4px' }}>
          12 results
        </div>
      </div>
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 16px' }}>
        <SearchRow title="Content creator capture platform concept" time="Today · 2:22 PM" snippet="…fragments from Watch, phone, and iPad capture flow…" match="capture" />
        <SearchRow title="Long-form knowledge capture architecture" time="Today · 9:04 AM" snippet="…turns scattered voice clips into a capture pipeline…" match="capture" />
        <SearchRow title="Untitled memory" time="Yesterday · 11:28 AM" snippet="…anywhere and have a thought and capture it on the…" match="capture" />
        <SearchRow title="Quick capture from the trail" time="May 31 · 8:15 AM" snippet="…wanted to capture this before I lost the thread…" match="capture" />
      </div>
    </PhoneScreen>
  );
}

// Project add/select rows — concise, with a selection ring (ring = selection,
// per Crucible; not a check, which means completion).
function SelectRow({ title, time, media, selected }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 4px', borderBottom: '1px solid ' + PX.divider }}>
      <span style={{
        width: 20, height: 20, borderRadius: 10, flexShrink: 0,
        border: '2px solid ' + (selected ? PX.accent : PX.ink4),
        background: selected ? PX.accent : 'transparent',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {selected && <span style={{ width: 7, height: 7, borderRadius: 4, background: PX.accentInk }} />}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: PX.serif, fontSize: 14.5, fontWeight: 500, color: PX.ink, letterSpacing: -0.15, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
        <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 2, fontVariantNumeric: 'tabular-nums' }}>{time}</div>
      </div>
      <MediaRow media={media} />
    </div>
  );
}
function ScrSelectContext() {
  return (
    <PhoneScreen>
      <div style={{ paddingTop: 6, background: PX.paper }}>
        <div style={{ display: 'flex', alignItems: 'center', padding: '14px 18px 12px' }}>
          <span style={{ fontSize: 15, color: PX.ink2, width: 56 }}>Cancel</span>
          <span style={{ flex: 1, textAlign: 'center', fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>Add to project</span>
          <span style={{ fontSize: 15, fontWeight: 600, color: PX.accent, width: 56, textAlign: 'right' }}>Add</span>
        </div>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, padding: '4px 18px 6px' }}>
          2 selected
        </div>
      </div>
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 16px' }}>
        <SelectRow title="Content creator capture platform concept" time="Today · 2:22 PM" media={{ audio: 2, photo: 1 }} selected />
        <SelectRow title="Long-form knowledge capture architecture" time="Today · 9:04 AM" media={{ audio: 9 }} selected />
        <SelectRow title="Untitled memory" time="Yesterday · 11:28 AM" media={{ audio: 1 }} />
        <SelectRow title="Sourdough timing notes" time="Yesterday · 7:40 PM" media={{ audio: 1, note: 1 }} />
        <SelectRow title="Photos from the garden" time="May 31 · 4:13 PM" media={{ photo: 3 }} />
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  MemoryCard, MediaRow, AISpark, TopicChips, DateHeader, MemoriesHeader, BeginningMarker,
  ScrMemoriesList, ScrMemoriesFiltered, ScrSearchContext, ScrSelectContext,
  SearchRow, SelectRow,
});

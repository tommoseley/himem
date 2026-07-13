// screens-memory-detail.jsx
// Memory Detail · v3 (May 22 2026)
//
// Targeted changes to production:
//   1. Every clip header shows date + time + location, always.
//      Format: "Sun May 17 · 6:12 PM · Bishop St, Bluffton"
//      Year appears only when not the current year (e.g. "Sun May 17, 2025").
//   2. Mentions is promoted out of the collapsed expander and rendered as a
//      visible row, sitting between the clips and the Organized · review card.
//
// Existing visual design otherwise unchanged.

const CURRENT_YEAR = 2026;

// Pretty format for clip headers. Pass year only when not current.
function clipHeader({ day, date, year, time, location }) {
  const dateStr = year && year !== CURRENT_YEAR
    ? `${day} ${date}, ${year}`
    : `${day} ${date}`;
  return `${dateStr} · ${time} · ${location}`;
}

// ─────────────────────────────────────────────────────────────
// Top nav · cream pill back-button + four action icons
// ─────────────────────────────────────────────────────────────
function MDIconBtn({ children }) {
  return (
    <span style={{
      width: 30, height: 30, borderRadius: 15,
      background: PX.card, border: '1px solid ' + PX.hairline,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      color: PX.ink2, flexShrink: 0,
    }}>{children}</span>
  );
}

function MDNav({ date = 'Sunday, May 17' }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '8px 12px 14px',
    }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 4,
        height: 30, padding: '0 12px 0 10px', borderRadius: 15,
        background: PX.card, border: '1px solid ' + PX.hairline,
        color: PX.accent, fontSize: 13.5, fontWeight: 500, letterSpacing: -0.1,
      }}>
        <svg width="8" height="13" viewBox="0 0 8 13" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M6 1L1 6.5l5 5"/></svg>
        {date}
      </span>
      <div style={{ display: 'flex', gap: 5 }}>
        <MDIconBtn>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V7z"/><line x1="12" y1="11" x2="12" y2="17"/><line x1="9" y1="14" x2="15" y2="14"/></svg>
        </MDIconBtn>
        <MDIconBtn>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>
        </MDIconBtn>
      </div>
    </div>
  );
}

// Full-width Delete — the ONE deletion affordance (June 12 2026). Sits at the
// very bottom of an opened item, below ALL content. Replaces the red swipe:
// the user must open the item and scroll past everything to reach it, which IS
// the deliberation — no confirm dialog. Danger red, full width. `verb`/`noun`
// adapt the label (Delete memory / Delete clip / Delete project; Remove from
// project uses verb="Remove").
function MDDeleteButton({ verb = 'Delete', noun = 'memory', recoverable = true }) {
  return (
    <div style={{ paddingTop: 10 }}>
      <button style={{
        width: '100%', minHeight: 50, borderRadius: 14, cursor: 'pointer',
        background: 'transparent', border: '1.5px solid ' + PX.danger, color: PX.danger,
        fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 9,
      }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>
        {verb} {noun}
      </button>
      {recoverable && (
        <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 8, lineHeight: 1.4 }}>
          Moves to Recently Deleted · kept for 30 days.
        </div>
      )}
    </div>
  );
}

// Title (serif, hero)
function MDTitle({ children }) {
  return (
    <div style={{
      fontFamily: PX.serif, fontWeight: 500, fontSize: 26, lineHeight: 1.1,
      color: PX.ink, letterSpacing: -0.4,
    }}>{children}</div>
  );
}

// Topic chip — top of content. Pass `slug` matching the 10-swatch Crucible
// topic palette (see palette spec); falls back to ink3 if absent.
// Managed content → solid pill + leading dot, 44px-class tap target
// (affordance vocabulary, CLAUDE.md June 8 2026).
function MDTopicChip({ label, slug }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 7,
      minHeight: 40, boxSizing: 'border-box',
      fontSize: 14, color: PX.ink, letterSpacing: -0.1,
      padding: '0 15px', borderRadius: 12,
      background: PX.wash1,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 4, background: slug ? topicVar(slug) : PX.ink3 }}/>
      {label}
    </span>
  );
}

// Memory-level meta line: "May 17 · 6:12 PM"
function MDMemoryMeta({ children }) {
  return (
    <div style={{ fontSize: 12.5, color: PX.ink3, letterSpacing: -0.05 }}>
      {children}
    </div>
  );
}

// Memory-level location pill
function MDLocationPill({ location }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '7px 14px 7px 10px', borderRadius: 18,
      background: PX.card, border: '1px solid ' + PX.hairline,
      fontSize: 13.5, color: PX.ink, letterSpacing: -0.1,
      width: 'fit-content',
    }}>
      <svg width="10" height="13" viewBox="0 0 16 20" fill={PX.accent}><path d="M8 0C3.6 0 0 3.5 0 7.9c0 5.4 7 11.4 7.3 11.7.2.2.5.2.7 0C8.4 19.3 16 13.3 16 7.9 16 3.5 12.4 0 8 0zm0 11a3 3 0 110-6 3 3 0 010 6z"/></svg>
      {location}
      <svg width="6" height="10" viewBox="0 0 6 10" fill="none" stroke={PX.ink3} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l3.5 4-3.5 4"/></svg>
    </span>
  );
}

// Summary card
function MDSummary({ children }) {
  return (
    <div>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8,
        fontSize: 11, fontWeight: 700, color: PX.ai,
        letterSpacing: 1.6, textTransform: 'uppercase',
      }}>
        <svg width="11" height="11" viewBox="0 0 24 24" fill={PX.ai}><path d="M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4L12 2z"/></svg>
        Summary
      </div>
      <div style={{ fontSize: 14.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
        {children}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CANONICAL CLIP CONTENT (locked July 11 2026)
// A clip's rendered body — transcript + the quiet evidence control — is ONE
// component, used identically by a Full clip card AND by an expanded Compact
// row. A clip must look like a clip everywhere it appears: same transcript
// type (15 / 1.5), same evidence control, NO bold repeated lead sentence.
// The evidence control is media-aware: audio → "Original recording",
// video → "Video", photo → a thumbnail chip, note → nothing (text IS the clip).
// ─────────────────────────────────────────────────────────────
// Reflective evidence control. Audio/video delegate to the ONE canonical
// ClipEvidence (screens-clip-model.jsx); photo keeps the reflective thumbnail
// chip (a photo clip in a memory has no inline thumbnail, so the chip IS its
// evidence marker); note → nothing.
function MDClipEvidence({ media = 'audio', duration }) {
  if (media === 'note') return null;
  if (media === 'photo') {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: PX.ink3, paddingTop: 2 }}>
        <span style={{
          width: 34, height: 34, borderRadius: 8, background: PX.wash1, border: '1px solid ' + PX.hairline,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={PX.ink3} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="5" width="18" height="15" rx="2.5"/><circle cx="12" cy="12.5" r="3.2"/><path d="M8 5l1.5-2h5L16 5"/></svg>
        </span>
        <span style={{ fontSize: 12, letterSpacing: -0.05 }}>Photo</span>
      </div>
    );
  }
  return <ClipEvidence media={media} duration={duration} register="reflective" />;
}

// The clip body, shared by every expanded presentation of a clip.
function MDClipContent({ transcript, media = 'audio', duration }) {
  return (
    <React.Fragment>
      <div style={{ fontSize: 15, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
        {transcript}
      </div>
      <MDClipEvidence media={media} duration={duration}/>
    </React.Fragment>
  );
}

// Full clip card · transcript-first. Header (date+time+location) + the shared
// clip content. (Unified editing model, June 9 2026.)
function MDClip({ day, date, year, time, location, transcript, media, duration }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 16, padding: '14px 16px 14px',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div style={{
        fontSize: 12, color: PX.ink3,
        fontVariantNumeric: 'tabular-nums',
        letterSpacing: -0.05,
        fontWeight: 500,
      }}>
        {clipHeader({ day, date, year, time, location })}
      </div>
      <MDClipContent transcript={transcript} media={media} duration={duration}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Mentions row · NEW visible placement, between clips and Organize Review
// ─────────────────────────────────────────────────────────────
function MDMentions({ items }) {
  return (
    <div>
      <div style={{
        fontSize: 11, fontWeight: 700, color: PX.ink3,
        letterSpacing: 1.6, textTransform: 'uppercase', marginBottom: 10,
      }}>Mentions</div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        {items.map(([label, slug], i) => (
          <span key={i} style={{
            display: 'inline-flex', alignItems: 'center', gap: 7,
            minHeight: 40, boxSizing: 'border-box',
            padding: '0 15px', borderRadius: 12,
            background: PX.wash1,
            fontSize: 14, color: PX.ink, letterSpacing: -0.1,
          }}>
            <span style={{ width: 7, height: 7, borderRadius: 4, background: slug ? topicVar(slug) : PX.ink3 }}/>
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}

// Organize review card — collapsed header (matching production look)
function MDOrganizedReview({ collapsed = true }) {
  return (
    <div style={{
      background: PX.aiTint,
      border: '1px solid ' + PX.aiEdge,
      borderRadius: 14,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '14px 16px', minHeight: 48, boxSizing: 'border-box',
      }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, color: PX.ai, fontWeight: 600, fontSize: 14, letterSpacing: -0.1 }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill={PX.ai}><path d="M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4L12 2z"/></svg>
          Organized · review
        </span>
        <svg width="14" height="9" viewBox="0 0 14 9" fill="none" stroke={PX.ai} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d={collapsed ? "M1 1l6 6 6-6" : "M1 8l6-6 6 6"}/>
        </svg>
      </div>
    </div>
  );
}

// FAB
function MDFAB() {
  return (
    <div style={{
      position: 'absolute', bottom: 22, right: 18,
      width: 52, height: 52, borderRadius: 26,
      background: PX.accent, color: PX.accentInk,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: PX.shadowFabAccent,
    }}>
      <svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round"><path d="M10 4v12M4 10h12"/></svg>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Full Memory Detail · single tall artboard so the whole page is visible
// at once for design review.
// ─────────────────────────────────────────────────────────────
function ScrMemoryDetailFull() {
  return (
    <div style={{
      width: 340, minHeight: 1280,
      background: PX.paper, position: 'relative',
      fontFamily: PX.sans, color: PX.ink,
      overflow: 'hidden',
    }}>
      {/* simulated status time */}
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
        <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
          <span style={{ fontSize: 11 }}>●●●</span>
        </span>
      </div>

      <MDNav date="Sunday, May 17"/>

      <div style={{ padding: '0 18px 80px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <MDTitle>Ordering replacement lemon trees</MDTitle>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
          <MDTopicChip label="Garden" slug="pine"/>
        </div>
        <MDMemoryMeta>May 17 · 6:12 PM</MDMemoryMeta>
        <MDSummary>
          Linked to a garden project to replace two lemon trees lost in winter. After navigating citrus import restrictions, identified a pink Eureka and Lisbon lemon tree (4–5 feet tall) from Simply Trees with a 10% discount, expected to arrive by end of next week for planting.
        </MDSummary>

        {/* Clips with NEW date+location headers */}
        <MDClip
          day="Tue" date="May 13"
          time="10:21 AM"
          location="Bishop St, Bluffton"
          transcript="I need to start looking around for 2 Lisbon lemon trees. Period. The winter took our other ones."
        />
        <MDClip
          day="Wed" date="May 14"
          time="4:40 PM"
          location="Bishop St, Bluffton"
          transcript="They're hard to find, surprisingly, but because of the rules around citrus and importing into certain states and exporting from other states, it makes it difficult to find the proper trees.  Oh, and instead of two Lisbon lemons, we need one Lisbon lemon and one Eureka lemon."
        />
        <MDClip
          day="Sun" date="May 17"
          time="6:12 PM"
          location="Bishop St, Bluffton"
          transcript="Well, after a lot of searching, I found A pink Eureka lemon tree and a Lisbon lemon tree.  4 to 5 feet tall each from a company called Simply Trees out in Texas.  And I got a 10% discount on it.  So there.  It says that the order will ship within one to 5 days.  And I assume they're not going to dawdle when it's on the truck.  So we should be having new trees ready to plant by the end of next week.  Maybe the following week."
        />

        {/* NEW Mentions placement — between clips and Organized review */}
        <MDMentions items={[
          ['Lemon tree replacement', 'pine'],
          ['Winter tree loss', 'pine'],
          ['Citrus import restrictions', 'slate'],
          ['Simply Trees', null],
          ['Pink Eureka', 'pine'],
        ]}/>

        <MDOrganizedReview collapsed/>

        <MDDeleteButton verb="Delete" noun="memory"/>
      </div>

      <MDFAB/>
    </div>
  );
}

// Annotated callout card — what changed
function MDChangesCard() {
  const item = { padding: '14px 22px', borderBottom: '1px solid ' + PX.hairline };
  const eyebrow = {
    fontSize: 10.5, fontWeight: 700, color: PX.ink3,
    letterSpacing: 1.6, textTransform: 'uppercase', marginBottom: 6,
  };
  return (
    <div style={{
      width: 520, minHeight: 320, background: PX.card, overflow: 'hidden',
      fontFamily: PX.sans, color: PX.ink,
    }}>
      <div style={{ padding: '22px 22px 8px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 24, fontWeight: 500, color: PX.ink, letterSpacing: -0.4, lineHeight: 1.1 }}>
          Two changes.
        </div>
        <div style={{ fontSize: 13, color: PX.ink3, marginTop: 6, lineHeight: 1.5 }}>
          Surgical edits to the existing Memory Detail. No structural redesign.
        </div>
      </div>
      <div style={item}>
        <div style={eyebrow}>1 · Clip headers</div>
        <div style={{ fontSize: 14, lineHeight: 1.55, color: PX.ink, letterSpacing: -0.1 }}>
          Always show date + time + location. Format: <span style={{ fontFamily: PX.mono, fontSize: 12.5 }}>Sun May 17 · 6:12 PM · Bishop St, Bluffton</span>. Year appears only when ≠ current year (<span style={{ fontFamily: PX.mono, fontSize: 12.5 }}>Sun May 17, 2025</span>). Less ambiguity than the previous time-only header.
        </div>
      </div>
      <div style={item}>
        <div style={eyebrow}>2 · Mentions</div>
        <div style={{ fontSize: 14, lineHeight: 1.55, color: PX.ink, letterSpacing: -0.1 }}>
          Promoted from the collapsed <span style={{ fontFamily: PX.mono, fontSize: 12.5 }}>MENTIONS ⌄</span> expander at the bottom of the page to a visible row, between the clips and the Organized · review card. All chips visible.
        </div>
      </div>
      <div style={{ padding: '14px 22px' }}>
        <div style={eyebrow}>Unchanged</div>
        <div style={{ fontSize: 14, lineHeight: 1.55, color: PX.ink, letterSpacing: -0.1 }}>
          Title, topic chip, memory-level date + location pill, summary card, Organize · review card, FAB. All visual treatments held.
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// LONG-MEMORY NAVIGATION · Full ⇄ Compact transcript toggle
//
// Problem: a 25-min lecture → 14 clips / 3,581 words / 11 pages. Reading is
// fine; *finding* is painful. Fix: the transcript section gets a density
// toggle (same mental model as the retired Memories control, but scoped to
// ONE memory's transcript — it governs the transcript, not a list).
//   · Full    — continuous clip cards, scroll to read (default). Nothing lost.
//   · Compact — one row per clip (time + first line), the 14-row index you
//               scan and jump from. Tapping a row opens that clip.
// Audio + summary stay first-class; the transcript is the derived thing that
// becomes navigable. (Crucible: derived content never demotes primary media.)
// ═════════════════════════════════════════════════════════════

// The lecture — 14 clips. `lead` is the first-line shown in Compact.
const LECTURE_CLIPS = [
  { time: '6:22 PM', lead: 'Wow, what a warm welcome — thank you all for having me here today.', transcript: 'Wow, what a warm welcome — thank you all for having me here today. Like Len said, our environment is incredibly important to me, and one of the main things that drew me to the county is that we all share the same landfill and recycling facilities.' },
  { time: '6:24 PM', lead: 'Why I focus so much on the landfill comes down to cost and time.', transcript: 'Why I focus so much on the landfill comes down to cost and time. Whenever we shorten its life cycle, we all end up paying more — it becomes a household expense as much as a county one.' },
  { time: '6:26 PM', lead: 'So in 2023 we launched the first in-vessel composting program…', transcript: 'So in 2023 we launched the first in-vessel composting program in South Carolina state government. It was a small pilot at first — two convenience centers and a lot of hope.' },
  { time: '6:28 PM', media: 'photo', lead: 'The numbers this year genuinely surprised us.', transcript: 'The numbers this year genuinely surprised us. We diverted more than sixteen thousand pounds of food waste from the landfill — material that would otherwise have cost us in tipping fees and capacity.' },
  { time: '6:31 PM', lead: 'Here is how the in-vessel system actually works.', transcript: 'Here is how the in-vessel system actually works. Food scraps go in one end, the vessel maintains temperature and turning, and finished compost comes out the other end in about three to four weeks.' },
  { time: '6:34 PM', lead: 'The hardest part was never the machine — it was contamination.', transcript: 'The hardest part was never the machine — it was contamination. A single bag of the wrong plastic can spoil an entire batch, so education matters more than equipment.' },
  { time: '6:37 PM', lead: 'Which brings me to community education, the heart of phase two.', transcript: 'Which brings me to community education, the heart of phase two. We want every resident to know what can and cannot go in the green bin, and to feel like a participant rather than a rule-follower.' },
  { time: '6:40 PM', lead: 'We piloted a school program this spring and it worked beautifully.', transcript: 'We piloted a school program this spring and it worked beautifully. Kids took the message home far more effectively than any mailer we could send.' },
  { time: '6:43 PM', media: 'photo', lead: 'On distribution — the finished compost goes back to the community.', transcript: 'On distribution — the finished compost goes back to the community. Parks, school gardens, and a giveaway program for residents who bring their own buckets.' },
  { time: '6:46 PM', lead: 'The volunteer program is small but mighty right now.', transcript: 'The volunteer program is small but mighty right now — about fifteen regulars. We would like to triple that this year and give them real ownership of a site.' },
  { time: '6:49 PM', lead: 'Let me be honest about what has not worked.', transcript: 'Let me be honest about what has not worked. Our first signage was confusing, the drop-off hours were too narrow, and we underestimated how much hand-holding the first month takes.' },
  { time: '6:52 PM', lead: 'Funding is the question everyone asks, so let me address it.', transcript: 'Funding is the question everyone asks, so let me address it. The diversion savings already cover the operating cost; expansion is what needs a one-time capital commitment.' },
  { time: '6:55 PM', media: 'video', lead: 'My ask of this room is specific.', transcript: 'My ask of this room is specific: help us reach two more districts this year, and lend your voice when we bring the expansion proposal to council.' },
  { time: '6:58 PM', lead: 'Thank you — and please, come see the site for yourself.', transcript: 'Thank you — and please, come see the site for yourself. Smell it, turn a pile, take home a bucket. That is when people stop being skeptical and start being advocates.' },
];

// No magic for SHOWING the control: the header + toggle appears for any
// memory with more than one clip (an index is meaningful only when there's
// more than one thing to index). Size drives the DEFAULT only — larger
// memories open fully compressed (Compact), so a long lecture lands as a
// scannable index, never an 11-page wall. Small multi-clip memories open Full.
const TRANSCRIPT_COMPACT_DEFAULT_CLIPS = 6;
const TRANSCRIPT_COMPACT_DEFAULT_WORDS = 1500;
// Whether a memory is "large" enough to OPEN compressed.
function transcriptOpensCompact(count, words) {
  return count > TRANSCRIPT_COMPACT_DEFAULT_CLIPS || words > TRANSCRIPT_COMPACT_DEFAULT_WORDS;
}
function defaultTranscriptMode(count, words) {
  return transcriptOpensCompact(count, words) ? 'compact' : 'full';
}

// Transcript section header — eyebrow count + Full/Compact icon toggle.
function MDTranscriptHeader({ mode, onMode, count, words }) {
  const seg = (active) => ({
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    width: 42, height: 34, borderRadius: 9, cursor: 'pointer',
    background: active ? PX.card : 'transparent',
    color: active ? PX.ink : PX.ink3,
    boxShadow: active ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
  });
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      <div style={{
        fontSize: 11, fontWeight: 700, color: PX.ink3,
        letterSpacing: 1.4, textTransform: 'uppercase',
      }}>
        Transcript · {count} clips · {words.toLocaleString()} words
      </div>
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 2,
        padding: 3, borderRadius: 11, background: PX.sunk,
      }}>
        {/* Full — text lines (continuous reading) */}
        <span style={seg(mode === 'full')} title="Full" onClick={() => onMode && onMode('full')}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <path d="M4 6h16M4 11h16M4 16h11"/>
          </svg>
        </span>
        {/* Compact — stacked rows w/ leading dots (clip index) */}
        <span style={seg(mode === 'compact')} title="Compact" onClick={() => onMode && onMode('compact')}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="4.5" cy="6.5" r="1.4" fill="currentColor" stroke="none"/><path d="M9 6.5h11"/>
            <circle cx="4.5" cy="12" r="1.4" fill="currentColor" stroke="none"/><path d="M9 12h11"/>
            <circle cx="4.5" cy="17.5" r="1.4" fill="currentColor" stroke="none"/><path d="M9 17.5h11"/>
          </svg>
        </span>
      </div>
    </div>
  );
}

// One Compact index row — an EXPANDER. Collapsed: time + first line.
// Open: the full transcript drops in below, in place. Single-open accordion
// (opening one closes any other), so the index never explodes into a wall.
// A compact row is still a CLIP — open it (tap) to read in place; its delete
// is a full-width Delete button at the bottom of the expanded body (June 12
// 2026 — swipe-to-delete retired everywhere).
// Media-type icon for a compact row's leading edge. Tells the user at a glance
// what KIND of clip each entry is (voice / photo / video / note) without opening
// it. Audio is the default and most common; photo/video/note are flagged.
function MDClipMediaIcon({ media = 'audio' }) {
  const common = { width: 15, height: 15, viewBox: '0 0 24 24', fill: 'none', stroke: PX.ink3, strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const glyph = {
    photo: <svg {...common}><rect x="3" y="5" width="18" height="15" rx="2.5"/><circle cx="12" cy="12.5" r="3.2"/><path d="M8 5l1.5-2h5L16 5"/></svg>,
    video: <svg {...common}><rect x="2.5" y="6" width="13" height="12" rx="2.5"/><path d="M16 10l5-3v10l-5-3z"/></svg>,
    note: <svg {...common}><path d="M5 3h10l4 4v14a0 0 0 010 0H5a0 0 0 010 0z"/><path d="M15 3v4h4"/><path d="M8 12h8M8 16h5"/></svg>,
    audio: <svg {...common}><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>,
  }[media] || null;
  return (
    <span style={{ width: 22, flexShrink: 0, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }} title={media}>
      {glyph}
    </span>
  );
}

function MDClipCompactRow({ time, lead, transcript, media, duration, open, last, editing, onClick }) {
  const header = (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 10,
      minHeight: 52, boxSizing: 'border-box', padding: '8px 4px',
      cursor: 'pointer', background: PX.card,
    }}>
      <MDClipMediaIcon media={media}/>
      <span style={{
        fontSize: 12, color: open ? PX.accent : PX.ink3, fontVariantNumeric: 'tabular-nums',
        fontWeight: 600, letterSpacing: -0.1, width: 54, flexShrink: 0,
      }}>{time}</span>
      <span style={{
        flex: 1, minWidth: 0, fontSize: 14, color: PX.ink, lineHeight: 1.35,
        letterSpacing: -0.1, fontWeight: open ? 600 : 400,
        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
      }}>{open ? '' : lead}</span>
      {/* chevron: right when collapsed, down when open */}
      <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke={open ? PX.accent : PX.ink3} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}><path d="M4 1l6 6-6 6"/></svg>
    </div>
  );
  return (
    <div style={{ borderBottom: last && !open ? 'none' : '1px solid ' + PX.hairline, position: 'relative', overflow: 'hidden' }}>
      {header}
      {open && !editing && (
        // The SAME clip content as a Full card — transcript + evidence control.
        // The row's own icon·time line above is the header; no repeated lead.
        <div style={{ padding: '2px 4px 14px', background: PX.card, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <MDClipContent transcript={transcript} media={media || 'audio'} duration={duration}/>
        </div>
      )}
      {open && editing && (
        // EDIT STATE — the ONE canonical ClipEditor (field="transcript"). In
        // flow, pushes siblings, never overlays. No "Move to…" in the compact
        // index (that lives on the full card). FAB hidden at the screen level.
        <div style={{ padding: '2px 4px 14px', background: PX.card }}>
          <ClipEditor field="transcript" value={transcript} media={media || 'audio'} duration={duration || '0:42'} showLabel={false} showMove={false} scope="memory" />
        </div>
      )}
    </div>
  );
}

// Shared scaffold for the lecture. The toggle switches whole-view mode
// (Full = all clips as continuous cards; Compact = the index). In Compact,
// each row is a single-open expander — tap to read that clip in place.
// `initialMode` overrides the threshold default so the canvas can show both;
// real screens use defaultTranscriptMode().
function ScrMemoryLecture({ initialMode, initialOpen = null, editingOpen = false }) {
  const count = LECTURE_CLIPS.length, words = 3581;
  const multiClip = count > 1;
  const [mode, setMode] = React.useState(initialMode || defaultTranscriptMode(count, words));
  // single-open accordion: index of the expanded compact row (or null)
  const [openIdx, setOpenIdx] = React.useState(initialOpen);
  const toggleRow = (i) => setOpenIdx(prev => prev === i ? null : i);

  return (
    <div style={{
      width: 340, minHeight: mode === 'compact' ? 1340 : 3120,
      background: PX.paper, position: 'relative',
      fontFamily: PX.sans, color: PX.ink, overflow: 'hidden',
    }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>11:32</span>
        <span style={{ fontSize: 11 }}>●●●</span>
      </div>

      <MDNav date="Yesterday"/>

      <div style={{ padding: '0 18px 80px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <MDTitle>Beaufort County Composting Program Launch &amp; Community Education</MDTitle>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
          <MDTopicChip label="Garden" slug="pine"/>
        </div>
        <MDMemoryMeta>Jun 8 · 6:22 PM</MDMemoryMeta>
        <MDSummary>
          A passionate presentation about Beaufort County's newly launched in-vessel composting program — the first in South Carolina state government. Covers food-waste challenges, program achievements (16,000+ pounds diverted), and next steps: community education, finished-compost distribution, and growing the volunteer program.
        </MDSummary>

        {/* Header + toggle for any multi-clip memory (no size gate on showing). */}
        {multiClip && (
          <MDTranscriptHeader mode={mode} onMode={setMode} count={count} words={words}/>
        )}

        {mode === 'compact' ? (
          <div style={{
            background: PX.card, border: '1px solid ' + PX.hairline,
            borderRadius: 16, padding: '4px 14px',
          }}>
            {LECTURE_CLIPS.map((c, i) => (
              <MDClipCompactRow key={i} time={c.time} lead={c.lead} transcript={c.transcript} media={c.media}
                open={openIdx === i} editing={editingOpen && openIdx === i}
                last={i === LECTURE_CLIPS.length - 1} onClick={() => toggleRow(i)} />

            ))}
          </div>
        ) : (
          LECTURE_CLIPS.map((c, i) => (
            <MDClip key={i} day="Mon" date="Jun 8" time={c.time} location="Okatie Creek, Bluffton" transcript={c.transcript}/>
          ))
        )}

        <MDMentions items={[
          ['In-vessel composting', 'pine'],
          ['16,000 pounds diverted', 'slate'],
          ['Community education', 'pine'],
          ['Volunteer program', null],
        ]}/>

        <MDOrganizedReview collapsed/>

        <MDDeleteButton verb="Delete" noun="memory"/>
      </div>

      {!editingOpen && <MDFAB/>}
    </div>
  );
}

// Default (threshold-driven): a long memory opens in Compact, one row pre-opened
// to show the expander behavior.
function ScrMemoryLectureCompact() { return <ScrMemoryLecture initialMode="compact" initialOpen={3}/>; }
// Compact + a row mid-edit: field expands in flow, Cancel/Done is a real row
// beneath, FAB hidden. The correct target for the June-9 build collisions.
function ScrMemoryLectureCompactEditing() { return <ScrMemoryLecture initialMode="compact" initialOpen={3} editingOpen/>; }
// Full: every clip as a continuous card, for reading straight through.
function ScrMemoryLectureFull()    { return <ScrMemoryLecture initialMode="full"/>; }

// ═════════════════════════════════════════════════════════════
// UNIFIED EDITING MODEL (locked June 9 2026)
//   · All text (title, summary, transcript) → TAP to edit in place.
//   · Media → tap to consume (photo opens, video/audio play).
//   · Deletion (clip, memory, project) → open it, scroll past all content, a
//     full-width Delete button at the bottom. No swipe, no confirm dialog.
//   · Metadata (topics, mentions) → identical inline pattern: tap a chip
//     to manage, dashed "+ Add" to add.
//   No pen button. No persistent edit mode — edit one thing, return to view
//   (the Draft Review philosophy). Editing is unambiguous because Play is its
//   own control, so tapping transcript text always means "edit."
// ═════════════════════════════════════════════════════════════

// Nav without the pen. Editing variant swaps to Cancel / Done (the one place
// bare-text actions live, per the Buttons & Actions standard).
function MDNavV2({ date = 'Yesterday', editing = false }) {
  if (editing) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 16px 14px' }}>
        <span style={{ fontSize: 15, color: PX.ink2, letterSpacing: -0.1 }}>Cancel</span>
        <span style={{ fontSize: 13, fontWeight: 700, color: PX.ink3, letterSpacing: 1, textTransform: 'uppercase' }}>Editing</span>
        <span style={{ fontSize: 15, fontWeight: 600, color: PX.accent, letterSpacing: -0.1 }}>Done</span>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 12px 14px' }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 4,
        height: 30, padding: '0 12px 0 10px', borderRadius: 15,
        background: PX.card, border: '1px solid ' + PX.hairline,
        color: PX.accent, fontSize: 13.5, fontWeight: 500, letterSpacing: -0.1,
      }}>
        <svg width="8" height="13" viewBox="0 0 8 13" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M6 1L1 6.5l5 5"/></svg>
        {date}
      </span>
      <div style={{ display: 'flex', gap: 5 }}>
        {/* Trash = delete the whole memory. The only memory-delete path. */}
        <MDIconBtn>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>
        </MDIconBtn>
        <MDIconBtn>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V7z"/><line x1="12" y1="11" x2="12" y2="17"/><line x1="9" y1="14" x2="15" y2="14"/></svg>
        </MDIconBtn>
        <MDIconBtn>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>
        </MDIconBtn>
      </div>
    </div>
  );
}

// Active in-place text editor. MUST mirror the displayed text exactly —
// same font-size, line-height, weight, and width — and auto-grow to show the
// ENTIRE value. Never a shorter fixed-height box the user scrolls inside.
// The caret is inline at the end of the text flow so wrapping/height match
// the read view 1:1 (see long-memory-navigation spec · editing acceptance).
function MDEditField({ children, serif }) {
  return (
    <div style={{
      border: '1px solid ' + PX.hairline, background: PX.card, borderRadius: 12,
      padding: serif ? '12px 13px' : '11px 13px',
      boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.04)',
      fontSize: serif ? 26 : 15, lineHeight: serif ? 1.18 : 1.5,
      fontFamily: serif ? PX.serif : PX.sans, fontWeight: serif ? 500 : 400,
      color: PX.ink, letterSpacing: serif ? -0.4 : -0.1,
    }}>
      {children}
      <span style={{
        display: 'inline-block', width: 2,
        height: serif ? '0.86em' : '1.05em',
        verticalAlign: serif ? '-0.12em' : '-0.18em',
        background: PX.accent, marginLeft: 1.5,
      }}/>
    </div>
  );
}

// Dashed "+ Add" chip — add affordance (dashed = add, per the standard).
function MDAddChip({ label = 'Add' }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      minHeight: 40, boxSizing: 'border-box', padding: '0 15px', borderRadius: 12,
      border: '1px dashed ' + PX.accent, color: PX.accent, fontSize: 14, fontWeight: 600,
    }}>
      <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10"/></svg>
      {label}
    </span>
  );
}

// Transcript-first clip card. The transcript is the working object (tap to
// edit); the recording is evidence, demoted to a quiet Play control.
function MDClipV2({ day, date, year, time, location, transcript, editing }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 16, padding: '14px 16px 14px',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div style={{ fontSize: 12, color: PX.ink3, fontVariantNumeric: 'tabular-nums', fontWeight: 500, letterSpacing: -0.05 }}>
        {clipHeader({ day, date, year, time, location })}
      </div>
      {editing ? (
        // EDIT STATE — the ONE canonical ClipEditor (field="transcript"). The
        // full card includes "Move to…" (relocate the clip); the card header
        // above already carries the date, so no label inside the editor.
        <ClipEditor field="transcript" value={transcript} media="audio" duration="0:48" showLabel={false} showMove scope="memory" />
      ) : (
        <MDClipContent transcript={transcript} media="audio" duration="0:48"/>
      )}
    </div>
  );
}

// Section header (eyebrow) for topics/mentions.
function MDFieldLabel({ children }) {
  return (
    <div style={{ fontSize: 11, fontWeight: 700, color: PX.ink3, letterSpacing: 1.6, textTransform: 'uppercase' }}>{children}</div>
  );
}

// Unified Memory Detail. `editingClip` puts one clip's transcript into the
// in-place editor (the typo-fix case — the only reason this user edits).
function ScrMemoryUnified({ editingClip = false }) {
  const CLIPS = [
    { day: 'Tue', date: 'May 13', time: '10:21 AM', location: 'Bishop St, Bluffton', transcript: 'I need to start looking around for 2 Lisbon lemon trees. The winter took our other ones.' },
    { day: 'Wed', date: 'May 14', time: '4:40 PM', location: 'Bishop St, Bluffton', transcript: editingClip ? 'They\u2019re hard to find because of citrus import rules between states. And instead of two Lisbon lemons, we need one Lisbon and one Eureka.' : 'They\u2019re hard to find because of citrus import rules between states. And instead of two Lisbon lemons, we need one Lisbon and one Eureka.' },
    { day: 'Sun', date: 'May 17', time: '6:12 PM', location: 'Bishop St, Bluffton', transcript: 'Found a pink Eureka and a Lisbon, 4\u20135 feet each, from Simply Trees. Got 10% off. Ships within five days.' },
  ];
  return (
    <div style={{ width: 340, minHeight: 1240, background: PX.paper, position: 'relative', fontFamily: PX.sans, color: PX.ink, overflow: 'hidden' }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
        <span style={{ fontSize: 11 }}>●●●</span>
      </div>

      <MDNavV2 date="Sunday, May 17" editing={false}/>

      <div style={{ padding: '0 18px 80px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <MDTitle>Ordering replacement lemon trees</MDTitle>

        <div>
          <MDFieldLabel>Topics</MDFieldLabel>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 }}>
            <MDTopicChip label="Garden" slug="pine"/>
            <MDAddChip/>
          </div>
        </div>

        <MDSummary>
          Replacing two lemon trees lost over winter. After navigating citrus import rules, found a pink Eureka and a Lisbon from Simply Trees, arriving by end of next week.
        </MDSummary>

        {CLIPS.map((c, i) => (
          <MDClipV2 key={i} {...c} editing={editingClip && i === 1}/>
        ))}

        <div>
          <MDFieldLabel>Mentions</MDFieldLabel>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
            {[['Lemon tree replacement', 'pine'], ['Simply Trees', null], ['Pink Eureka', 'pine']].map(([label, slug], i) => (
              <span key={i} style={{
                display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 40, boxSizing: 'border-box',
                padding: '0 15px', borderRadius: 12, background: PX.wash1, fontSize: 14, color: PX.ink, letterSpacing: -0.1,
              }}>
                <span style={{ width: 7, height: 7, borderRadius: 4, background: slug ? topicVar(slug) : PX.ink3 }}/>
                {label}
              </span>
            ))}
            <MDAddChip/>
          </div>
        </div>

        <MDOrganizedReview collapsed/>

        <MDDeleteButton verb="Delete" noun="memory"/>
      </div>

      {!editingClip && <MDFAB/>}
    </div>
  );
}

function ScrMemoryUnifiedRest()    { return <ScrMemoryUnified/>; }
function ScrMemoryUnifiedEditing() { return <ScrMemoryUnified editingClip/>; }

// The "Organize this memory" card — the AI CTA on a not-yet-organized memory.
// Blue (invokes AI), on-device. The whole card is the tap target.
function MDOrganizePrompt() {
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, padding: '15px 16px', display: 'flex', gap: 13, alignItems: 'flex-start' }}>
      <span style={{ width: 40, height: 40, borderRadius: 11, background: PX.ai, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <svg width="19" height="19" viewBox="0 0 24 24" fill="#fff"><path d="M12 2l1.6 5.4L19 9l-5.4 1.6L12 16l-1.6-5.4L5 9l5.4-1.6z"/></svg>
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 15.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Organize this memory</div>
        <div style={{ fontSize: 13, color: PX.ink3, lineHeight: 1.45, marginTop: 3 }}>Suggests a title, summary, and topics — drafted right on your device.</div>
        <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 9, fontWeight: 600 }}>On-device · private · free</div>
      </div>
    </div>
  );
}

// A memory the MOMENT it's created from a session — before any Organize pass.
// The whole point: a new memory is NEVER empty. It contains its included
// clip(s) as the body (transcript + Play) right away, with empty Topics/Mentions
// and the Organize card. Fixes CC's July 12 bug (screenshot 7 rendered the
// memory with NO clip body). Memory = clips + derived; the clips come first.
function ScrMemoryFresh() {
  return (
    <div style={{ width: 340, minHeight: 900, background: PX.paper, position: 'relative', fontFamily: PX.sans, color: PX.ink, overflow: 'hidden' }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
        <span style={{ fontSize: 11 }}>●●●</span>
      </div>

      <MDNavV2 date="Today" editing={false}/>

      <div style={{ padding: '0 18px 80px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <MDTitle>New</MDTitle>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: -6, letterSpacing: -0.1 }}>Sun Jul 12 · 3:27 PM · 18 Columbus Cir, Bluffton</div>

        <div>
          <MDFieldLabel>Topics</MDFieldLabel>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 }}>
            <MDAddChip/>
          </div>
        </div>

        {/* THE FIX — the included clip IS the memory's content, present immediately */}
        <MDClipV2 day="Sat" date="Jul 11" time="10:32 AM" location="18 Columbus Cir, Bluffton" transcript="Here picture of my new camera." />

        <div>
          <MDFieldLabel>Mentions</MDFieldLabel>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
            <MDAddChip/>
          </div>
        </div>

        <MDOrganizePrompt/>

        <MDDeleteButton verb="Delete" noun="memory"/>
      </div>

      <MDFAB/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// MENTION · managed-chip edit state (mentions only — topics keep their sheet)
//   Rest:   solid pill + leading dot (managed content).
//   Active: label becomes an inline text field (ochre caret) AND a trailing
//           ✕ appears WITHIN the chip. Label = rename, ✕ = remove. Commit on
//           return / tap-away. The ✕ exists ONLY in the active state — a
//           resting chip never carries a delete affordance.
// ─────────────────────────────────────────────────────────────
function MDMentionChip({ label, slug, editing }) {
  if (editing) {
    return (
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 8, minHeight: 40, boxSizing: 'border-box',
        padding: '0 8px 0 13px', borderRadius: 12, background: PX.card,
        border: '1px solid ' + PX.accent, boxShadow: '0 0 0 3px ' + PX.accentTint,
      }}>
        <span style={{ width: 7, height: 7, borderRadius: 4, background: slug ? topicVar(slug) : PX.ink3, flexShrink: 0 }}/>
        <span style={{ fontSize: 14, color: PX.ink, letterSpacing: -0.1 }}>{label}</span>
        <span style={{ width: 2, height: 18, background: PX.accent, borderRadius: 1, flexShrink: 0 }}/>
        {/* trailing remove — ONLY present in edit state */}
        <span style={{
          width: 22, height: 22, borderRadius: 11, background: PX.sunk, color: PX.ink2,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginLeft: 2,
        }}>
          <svg width="9" height="9" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M2 2l8 8M10 2l-8 8"/></svg>
        </span>
      </span>
    );
  }
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 40, boxSizing: 'border-box',
      padding: '0 15px', borderRadius: 12, background: PX.wash1, fontSize: 14, color: PX.ink, letterSpacing: -0.1,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 4, background: slug ? topicVar(slug) : PX.ink3 }}/>
      {label}
    </span>
  );
}

// Focused demo: the Mentions row, one chip in the active edit state, the
// rest resting, plus the dashed + Add — showing wrap + the two-target chip.
function ScrMentionEditState() {
  return (
    <div style={{ width: 340, minHeight: 360, background: PX.paper, fontFamily: PX.sans, color: PX.ink, padding: '22px 18px' }}>
      <MDFieldLabel>Mentions</MDFieldLabel>
      <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.5, margin: '8px 0 16px' }}>
        Tap any mention to edit it in place — the label becomes a field and a ✕ appears to remove it. Tap away to save.
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        <MDMentionChip label="Lemon tree replacement" slug="pine"/>
        <MDMentionChip label="Simply Trees" slug={null} editing/>
        <MDMentionChip label="Pink Eureka" slug="pine"/>
        <MDMentionChip label="Citrus import rules" slug="slate"/>
        <MDAddChip/>
      </div>

      <div style={{ marginTop: 26, paddingTop: 16, borderTop: '1px solid ' + PX.divider, fontSize: 11.5, color: PX.ink3, lineHeight: 1.6 }}>
        <strong style={{ color: PX.ink2, fontWeight: 600 }}>Two targets, one tap:</strong> the label renames (ochre caret), the ✕ removes. The ✕ shows only while editing — a resting chip never looks deletable. Topics don’t use this; they open the management sheet.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CLIP RELOCATION — "Move to…" (covers move AND remove)
//   A clip always lives somewhere: inside a memory, or loose on the
//   Captured Clips bench. So one primitive covers both asks —
//   move to another memory, pull into a new memory, or "Remove from
//   this memory" = move back to the bench (the clip survives).
//   Parallel to Projects' Delete vs Remove-from-project.
// ─────────────────────────────────────────────────────────────
function MoveDestRow({ title, meta, glyph, tone = 'ink', sub }) {
  const color = tone === 'accent' ? PX.accent : PX.ink;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, minHeight: 56, boxSizing: 'border-box',
      padding: '9px 4px',
    }}>
      <span style={{
        width: 38, height: 38, borderRadius: 10, flexShrink: 0,
        background: tone === 'accent' ? PX.accentTint : PX.wash1,
        color: color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        border: tone === 'accent' ? '1px dashed ' + PX.accent : '1px solid ' + PX.hairline,
      }}>{glyph}</span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 15, fontWeight: 600, color, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</span>
        {(meta || sub) && <span style={{ display: 'block', fontSize: 12, color: PX.ink3, letterSpacing: -0.05, marginTop: 1 }}>{meta || sub}</span>}
      </span>
      {tone !== 'accent' && (
        <svg width="8" height="13" viewBox="0 0 10 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 1l6 6-6 6"/></svg>
      )}
    </div>
  );
}

function ScrClipMoveSheet() {
  return (
    <div style={{ width: 340, height: 735, position: 'relative', background: PX.paper, fontFamily: PX.sans, overflow: 'hidden' }}>
      {/* dimmed memory behind */}
      <div style={{ position: 'absolute', inset: 0, filter: 'saturate(0.9)', opacity: 0.5, pointerEvents: 'none' }}>
        <ScrMemoryUnifiedRest/>
      </div>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(26,22,18,0.28)' }}/>

      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        background: PX.paper, borderRadius: '20px 20px 0 0',
        boxShadow: '0 -10px 40px rgba(0,0,0,0.18)', padding: '10px 18px 22px',
        display: 'flex', flexDirection: 'column', maxHeight: '86%',
      }}>
        <div style={{ width: 38, height: 5, borderRadius: 3, background: PX.hairline, alignSelf: 'center', margin: '2px 0 12px' }}/>

        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 4 }}>
          <span style={{ fontFamily: PX.serif, fontSize: 21, fontWeight: 500, color: PX.ink, letterSpacing: -0.4 }}>Where does this belong?</span>
          <span style={{ flex: 1 }}/>
          <span style={{ fontSize: 15, color: PX.ink2, letterSpacing: -0.1 }}>Cancel</span>
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink3, letterSpacing: -0.05, marginBottom: 12 }}>
          “They’re hard to find because of citrus import rules…”
        </div>

        {/* search */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, height: 40, padding: '0 12px',
          background: PX.wash1, borderRadius: 11, border: '1px solid ' + PX.hairline, marginBottom: 6,
        }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={PX.ink3} strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/></svg>
          <span style={{ fontSize: 14, color: PX.ink4, letterSpacing: -0.1 }}>Search memories</span>
        </div>

        <MoveDestRow tone="accent" title="New memory" sub="Pull this clip out on its own"
          glyph={<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>}/>

        <div style={{ fontSize: 10.5, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', margin: '10px 4px 2px' }}>Recent memories</div>
        <div style={{ overflow: 'hidden' }}>
          <MoveDestRow title="Ordering replacement lemon trees" meta="3 clips · May 13–17"
            glyph={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3h9l5 5v13a1 1 0 01-1 1H6a1 1 0 01-1-1V4a1 1 0 011-1z"/><path d="M14 3v5h5"/></svg>}/>
          <MoveDestRow title="Garden plans for spring" meta="5 clips · May 2"
            glyph={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3h9l5 5v13a1 1 0 01-1 1H6a1 1 0 01-1-1V4a1 1 0 011-1z"/><path d="M14 3v5h5"/></svg>}/>
          <MoveDestRow title="Citrus care notes" meta="2 clips · Apr 28"
            glyph={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3h9l5 5v13a1 1 0 01-1 1H6a1 1 0 01-1-1V4a1 1 0 011-1z"/><path d="M14 3v5h5"/></svg>}/>
        </div>

        {/* the unfile / remove case — visually distinct, the clip survives */}
        <div style={{ borderTop: '1px solid ' + PX.divider, marginTop: 8, paddingTop: 4 }}>
          <MoveDestRow title="Remove from this memory" sub="Returns to Captured Clips, unfiled"
            glyph={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 0115-6.7L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 01-15 6.7L3 16"/><path d="M3 21v-5h5"/></svg>}/>
        </div>
      </div>
    </div>
  );
}

// After moving out a memory's LAST clip, the memory is empty. Decision (a):
// offer to delete the now-empty memory (recoverable via Recently Deleted).
function ScrClipEmptyAfterMove() {
  return (
    <div style={{ width: 340, height: 735, position: 'relative', background: PX.paper, fontFamily: PX.sans, overflow: 'hidden' }}>
      <div style={{ position: 'absolute', inset: 0, opacity: 0.4, pointerEvents: 'none' }}>
        <ScrMemoryUnifiedRest/>
      </div>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(26,22,18,0.32)' }}/>

      <div style={{
        position: 'absolute', left: 18, right: 18, top: '50%', transform: 'translateY(-50%)',
        background: PX.paper, borderRadius: 18, padding: '22px 20px 18px', boxShadow: '0 20px 60px rgba(0,0,0,0.25)',
      }}>
        <div style={{ fontFamily: PX.serif, fontSize: 21, fontWeight: 500, color: PX.ink, letterSpacing: -0.4, marginBottom: 8 }}>
          Nothing left in this memory
        </div>
        <div style={{ fontSize: 14, lineHeight: 1.5, color: PX.ink2, letterSpacing: -0.1, marginBottom: 20 }}>
          You moved the last clip out. Delete this now-empty memory? You can restore it from Recently Deleted for 30 days.
        </div>
        <div style={{
          height: 50, borderRadius: 13, background: PX.dangerTint || 'rgba(184,49,30,0.08)',
          border: '1px solid ' + PX.danger, color: PX.danger,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, marginBottom: 8,
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>
          Delete empty memory
        </div>
        <div style={{
          height: 46, display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 15, fontWeight: 600, color: PX.ink2, letterSpacing: -0.1,
        }}>
          Keep it empty
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  ScrMemoryDetailFull, MDChangesCard, MDDeleteButton,
  ScrMemoryLectureFull, ScrMemoryLectureCompact, ScrMemoryLectureCompactEditing,
  defaultTranscriptMode, transcriptOpensCompact,
  ScrMemoryUnifiedRest, ScrMemoryUnifiedEditing,
  ScrClipMoveSheet, ScrClipEmptyAfterMove, MoveDestRow,
  MDNavV2, MDEditField, MDAddChip, MDClipV2,
  MDMentionChip, ScrMentionEditState,
  MDOrganizePrompt, ScrMemoryFresh,
});

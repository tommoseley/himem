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
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>
        </MDIconBtn>
        <MDIconBtn>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V7z"/><line x1="12" y1="11" x2="12" y2="17"/><line x1="9" y1="14" x2="15" y2="14"/></svg>
        </MDIconBtn>
        <MDIconBtn>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12v7a2 2 0 002 2h12a2 2 0 002-2v-7"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>
        </MDIconBtn>
        <MDIconBtn>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 113 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
        </MDIconBtn>
      </div>
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

// Topic chip — small, top of content
function MDTopicChip({ label, color }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      fontSize: 11.5, color: PX.ink2,
      padding: '4px 10px', borderRadius: 11,
      background: 'rgba(26,22,18,0.04)',
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 4, background: color }}/>
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
// Clip card · header NOW carries date + time + location, always.
// ─────────────────────────────────────────────────────────────
function MDClip({ day, date, year, time, location, transcript }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 16, padding: '14px 16px 16px',
      display: 'flex', flexDirection: 'column', gap: 8,
    }}>
      <div style={{
        fontSize: 12, color: PX.ink3,
        fontVariantNumeric: 'tabular-nums',
        letterSpacing: -0.05,
        fontWeight: 500,
      }}>
        {clipHeader({ day, date, year, time, location })}
      </div>
      <div style={{ fontSize: 15, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
        {transcript}
      </div>
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
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {items.map(([label, color], i) => (
          <span key={i} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '5px 12px', borderRadius: 12,
            background: 'rgba(26,22,18,0.04)',
            fontSize: 13, color: PX.ink, letterSpacing: -0.1,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: color || PX.ink3 }}/>
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
      background: 'rgba(30,92,142,0.06)',
      border: '1px solid rgba(30,92,142,0.12)',
      borderRadius: 14,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '12px 14px',
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
      background: PX.accent, color: '#FFFCF6',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: '0 8px 20px rgba(166,60,21,0.32), 0 2px 6px rgba(0,0,0,0.10)',
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
        <MDTopicChip label="Garden" color="#3FA877"/>
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
          ['Lemon tree replacement', '#3FA877'],
          ['Winter tree loss', '#3FA877'],
          ['Citrus import restrictions', '#B87322'],
          ['Simply Trees', null],
          ['Pink Eureka', '#3FA877'],
        ]}/>

        <MDOrganizedReview collapsed/>
      </div>

      <MDFAB/>
    </div>
  );
}

// Annotated callout card — what changed
function MDChangesCard() {
  const item = { padding: '14px 22px', borderBottom: '1px solid rgba(26,22,18,0.10)' };
  const eyebrow = {
    fontSize: 10.5, fontWeight: 700, color: 'rgba(26,22,18,0.45)',
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

Object.assign(window, { ScrMemoryDetailFull, MDChangesCard });

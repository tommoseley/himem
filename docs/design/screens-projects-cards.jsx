// screens-projects-cards.jsx
// Project card, memory card, project-detail header. Shared by the screen views.

// ─────────────────────────────────────────────────────────────
// Reusable: project list card
// ─────────────────────────────────────────────────────────────
function ProjectCard({ title, topics, count, date }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 14, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 18, fontWeight: 600, color: PX.ink, letterSpacing: -0.3, lineHeight: 1.15 }}>
            {title}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
          <span style={{
            minWidth: 24, height: 22, padding: '0 7px', borderRadius: 11,
            background: PX.sunk, color: PX.ink2,
            fontSize: 12, fontWeight: 600, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontVariantNumeric: 'tabular-nums',
          }}>{count}</span>
          <span style={{ fontSize: 11, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>{date}</span>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {topics.map(k => (
          <span key={k} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12, color: PX.ink2 }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: topicVar(TOPIC[k].slug) }} />
            {TOPIC[k].label}
          </span>
        ))}
      </div>
    </div>
  );
}

// Reusable: memory card inside a project (simplified — no inline AI block)
function ProjectMemoryCard({ title, time, audio, photo, topics, sub }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 14, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div>
        <div style={{ fontSize: 16, fontWeight: 600, color: PX.ink, letterSpacing: -0.2, lineHeight: 1.2 }}>{title}</div>
        <div style={{ fontSize: 12, color: PX.ink3, marginTop: 3, fontVariantNumeric: 'tabular-nums' }}>{time}</div>
      </div>
      {sub && (
        <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.45 }}>{sub}</div>
      )}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ display: 'inline-flex', gap: 3 }}>
          {/* media-type indicator dots: audio=accent, photo=warn, text=confirmed */}
          {[PX.accent, PX.warn, PX.confirmed].slice(0, (audio ? 1 : 0) + (photo ? 1 : 0) + 1).map((c,i) => (
            <span key={i} style={{ width: 6, height: 6, borderRadius: 3, background: c }} />
          ))}
        </div>
        <span style={{ fontSize: 12, color: PX.ink2, fontVariantNumeric: 'tabular-nums' }}>
          {[audio && `${audio} audio`, photo && `${photo} photo`].filter(Boolean).join(' · ')}
        </span>
        <span style={{ flex: 1 }} />
        <div style={{ display: 'flex', gap: 6 }}>
          {topics.map(k => <TopicPipChip key={k} k={k} />)}
        </div>
      </div>
    </div>
  );
}

// Project detail nav: back + (+ / share / edit) on the right
function ProjectDetailNav({ pill = true }) {
  return (
    <div style={{ paddingTop: 6, padding: '10px 14px 8px', display: 'flex', alignItems: 'center' }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 4,
        height: 32, padding: '0 12px 0 10px', borderRadius: 16,
        background: pill ? PX.card : 'transparent',
        border: pill ? '1px solid ' + PX.hairline : 'none',
        color: PX.accent, fontSize: 15, fontWeight: 500,
      }}>
        <svg width="9" height="14" viewBox="0 0 9 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M7 1L1 7l6 6"/>
        </svg>
        Projects
      </span>
      <span style={{ flex: 1 }} />
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 14,
        height: 32, padding: '0 12px', borderRadius: 16,
        background: PX.card, border: '1px solid ' + PX.hairline,
      }}>
        <Plus size={15} color={PX.accent} />
        <svg width="14" height="16" viewBox="0 0 16 18" fill="none" stroke={PX.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M8 1v11"/><path d="M4 5l4-4 4 4"/><path d="M2 12v3a2 2 0 002 2h8a2 2 0 002-2v-3"/>
        </svg>
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke={PX.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M11 2l3 3-8 8-4 1 1-4 8-8z"/>
        </svg>
      </div>
    </div>
  );
}

// Project detail title block
function ProjectTitleBlock({ title, topics, count, goal }) {
  return (
    <div style={{ padding: '10px 18px 0' }}>
      <div style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, lineHeight: 1.1, letterSpacing: -0.5, color: PX.ink }}>
        {title}
      </div>
      {goal && (
        <div style={{ fontSize: 13, color: PX.ink2, marginTop: 8, lineHeight: 1.45, fontStyle: 'italic', fontFamily: PX.serif }}>
          {goal}
        </div>
      )}
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 12 }}>
        {topics.map(k => <TopicPipChip key={k} k={k} />)}
      </div>
      <div style={{ fontSize: 12, color: PX.ink3, marginTop: 10, fontVariantNumeric: 'tabular-nums' }}>
        {count}
      </div>
    </div>
  );
}

Object.assign(window, { ProjectCard, ProjectMemoryCard, ProjectDetailNav, ProjectTitleBlock });

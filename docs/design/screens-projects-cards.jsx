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

// (ProjectMemoryCard removed June 10 2026 — the canonical journal `MemoryCard`
// from screens-memories.jsx is the single memory-card definition everywhere,
// including inside projects. One card, one source of truth.)

// Project detail nav: back + share only. Delete moved to a bottom full-width
// red "Delete Project" button (deletion lock); add moved to the in-project FAB;
// editing is the ✎ Edit button beside the header (ProjectTitleBlock).
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
        {/* Share only. No trash (→ bottom Delete Project), no + (→ FAB). */}
        <svg width="14" height="16" viewBox="0 0 16 18" fill="none" stroke={PX.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M8 1v11"/><path d="M4 5l4-4 4 4"/><path d="M2 12v3a2 2 0 002 2h8a2 2 0 002-2v-3"/>
        </svg>
      </div>
    </div>
  );
}

// Project detail title block. Serif title with an explicit ✎ Edit button
// beside it (the one edit affordance — opens the Edit Project sheet; matches
// the boxed ✎ used on every clip surface, never tap-the-title-text).
function ProjectTitleBlock({ title, topics, count, goal }) {
  return (
    <div style={{ padding: '10px 18px 0' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <div style={{ flex: 1, minWidth: 0, fontFamily: PX.serif, fontSize: 30, fontWeight: 400, lineHeight: 1.1, letterSpacing: -0.5, color: PX.ink }}>
          {title}
        </div>
        {/* ✎ Edit — boxed blue button, standard edit affordance */}
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 5, flexShrink: 0, marginTop: 4,
          minHeight: 34, padding: '0 12px', borderRadius: 9,
          border: '1px solid ' + PX.ai, color: PX.ai, fontSize: 13.5, fontWeight: 600, letterSpacing: -0.05,
        }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={PX.ai} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4z"/></svg>
          Edit
        </span>
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

Object.assign(window, { ProjectCard, ProjectDetailNav, ProjectTitleBlock });

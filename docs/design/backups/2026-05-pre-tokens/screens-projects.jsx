// screens-projects.jsx
// Shared primitives for the Projects canvas. Imports PX from crucible-primitives.jsx.

// ─────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────

// Topic palette — derived from existing topic-pip colors used elsewhere.
const TOPIC = {
  content:  { label: 'Content',     pip: '#B4593C' },
  tech:     { label: 'Technology',  pip: '#C64A1C' },
  cooking:  { label: 'Cooking',     pip: '#7E5E2C' },
  garden:   { label: 'Garden',      pip: '#4E7A3F' },
  global:   { label: 'Global Cuisine', pip: '#9B5430' },
  howWeWork:{ label: 'How We Work', pip: '#1E5C8E' },
};

function TopicChip({ k, active }) {
  const t = TOPIC[k];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 26, padding: '0 10px', borderRadius: 13,
      background: active ? '#E4D9CF' : 'transparent',
      border: '1px solid ' + (active ? 'transparent' : PX.hairline),
      fontSize: 13, fontWeight: 500, color: active ? '#7A3A14' : PX.ink2,
      letterSpacing: -0.1, whiteSpace: 'nowrap',
    }}>
      {t.label}
    </span>
  );
}

function TopicPipChip({ k }) {
  const t = TOPIC[k];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 24, padding: '0 9px', borderRadius: 12,
      background: 'rgba(198,74,28,0.08)',
      fontSize: 12, fontWeight: 500, color: '#7A3A14', letterSpacing: -0.1,
    }}>
      <span style={{ width: 6, height: 6, borderRadius: 3, background: t.pip }} />
      {t.label}
    </span>
  );
}

// HiMem wordmark — small, spaced caps in muted ink
function HiMemMark() {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      fontSize: 11, fontWeight: 600, letterSpacing: 2.2, color: PX.ink3,
    }}>
      HIMEM
      <span style={{ width: 6, height: 6, borderRadius: 3, background: PX.accent, display: 'inline-block' }} />
    </span>
  );
}

// Segmented control — pill style, "Memories | Projects"
function Seg({ active }) {
  return (
    <div style={{
      display: 'inline-flex', background: PX.sunk, padding: 2, borderRadius: 9,
      fontSize: 13, fontWeight: 600,
    }}>
      {['Memories','Projects'].map(label => (
        <span key={label} style={{
          padding: '5px 12px', borderRadius: 7,
          background: active === label ? PX.card : 'transparent',
          color: PX.ink, letterSpacing: -0.1,
          boxShadow: active === label ? '0 1px 2px rgba(0,0,0,0.06)' : 'none',
        }}>{label}</span>
      ))}
    </div>
  );
}

// De-blued icon trio — search, compress, settings — in warm ink.
function IconTrio() {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 14, color: PX.ink }}>
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M6 9l6-6 6 6"/><path d="M6 15l6 6 6-6"/></svg>
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>
    </div>
  );
}

// Top chrome shared across the Projects tab (header + seg + topic strip)
function ProjectsTabHeader({ activeTopic = 'Content' }) {
  return (
    <div style={{ paddingTop: 6 }}>
      <div style={{ padding: '8px 16px 10px', display: 'flex', alignItems: 'center' }}>
        <HiMemMark />
        <span style={{ flex: 1 }} />
        <Seg active="Projects" />
        <span style={{ flex: 1 }} />
        <IconTrio />
      </div>
      <div style={{
        display: 'flex', gap: 8, padding: '8px 14px 12px',
        overflow: 'hidden', whiteSpace: 'nowrap',
      }}>
        <TopicChip k="content" active={activeTopic === 'Content'} />
        <TopicChip k="cooking" />
        <TopicChip k="garden" />
        <TopicChip k="global" />
      </div>
    </div>
  );
}

Object.assign(window, { TOPIC, TopicChip, TopicPipChip, HiMemMark, Seg, IconTrio, ProjectsTabHeader });

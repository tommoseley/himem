// crucible-primitives.jsx
// Canonical Crucible iOS primitives. Used by every page that mocks Himem screens.
// PhoneScreen, Sheet, plus the PX token set (cream paper, ochre accent, Source Serif 4 + SF Pro).
// Sized for design-canvas artboards (340×735).
//
// PX is a thin proxy over CSS custom properties declared in crucible.css.
// Every page that uses these primitives MUST load crucible.css. Dark/light
// flips by setting [data-theme] on <html> — values automatically resolve.
// Hardcoded hex/rgba in this file are a bug; add a token to crucible.css instead.

const PX = {
  // surfaces
  paper:        'var(--paper)',
  card:         'var(--card)',
  sunk:         'var(--sunk)',
  // type & lines
  ink:          'var(--ink)',
  ink2:         'var(--ink2)',
  ink3:         'var(--ink3)',
  ink4:         'var(--ink4)',
  hairline:     'var(--hairline)',
  divider:      'var(--divider)',
  // accent
  accent:       'var(--accent)',
  accentPress:  'var(--accent-press)',
  accentBright: 'var(--accent-bright)', // brighter accent (countdown ring etc.)
  accentDim:    'var(--accent-dim)',    // darker accent (unfilled track)
  accentInk:    'var(--accent-ink)',     // fg on solid accent or solid ink bg
  accentTint:   'var(--accent-tint)',
  accentTint2:  'var(--accent-tint-2)',
  // ai
  ai:           'var(--ai)',
  aiTint:       'var(--ai-tint)',
  aiEdge:       'var(--ai-edge)',
  // semantic
  warn:         'var(--warn)',
  warnTint:     'var(--warn-tint)',
  warnInk:      'var(--warn-ink)',       // fg on warn-tint
  confirmed:    'var(--confirmed)',
  confirmedTint:'var(--confirmed-tint)',
  confirmedInk: 'var(--confirmed-ink)',  // fg on confirmed-tint
  danger:       'var(--danger)',
  // focus + scrim
  focus:        'var(--focus)',
  scrim:        'var(--scrim)',
  // ink washes (chip bgs, etc.)
  wash1:        'var(--wash-1)',
  wash2:        'var(--wash-2)',
  // shadows
  shadowCard:     'var(--shadow-card)',
  shadowElevated: 'var(--shadow-elevated)',
  shadowFloating: 'var(--shadow-floating)',
  shadowModal:    'var(--shadow-modal)',
  shadowFabAccent:'var(--shadow-fab-accent)',
  shadowSheet:    'var(--shadow-sheet)',
  // typography
  serif:        'var(--serif)',
  sans:         'var(--sans)',
  mono:         'var(--mono)',
};

// Topic palette accessor. slug must be one of the 10 strings in the
// topic palette spec; unknown slugs return the var() string anyway so the
// fallback is a no-op (the chip renders unstyled rather than crashing).
// See "Crucible · topic palette spec.md".
function topicVar(slug) {
  return `var(--topic-${slug})`;
}

// Deterministic auto-color for topics without an explicit colorSlug.
// MUST stay byte-identical to the Swift implementation — see palette spec.
// Order matters: changing the order changes every auto-hashed assignment.
const TOPIC_PALETTE = [
  'ember', 'terracotta', 'clay',  'amber',   // row 1 · warms
  'wheat', 'sage',       'moss',  'pine',    // row 2 · yellows & greens
  'sea',   'tide',       'indigo','violet',  // row 3 · blues
  'plum',  'rose',       'sand',  'slate',   // row 4 · purples, roses, neutrals
];
function topicSlugFor(name) {
  const s = (name || '').trim().toLowerCase();
  let h = 5381 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(h, 33) + s.charCodeAt(i)) >>> 0;
  }
  return TOPIC_PALETTE[h % TOPIC_PALETTE.length];
}

// ─────────────────────────────────────────────────────────────
// PhoneScreen — fits exactly in a 340×735 artboard.
// Renders status bar, optional nav, content, optional home indicator.
// Scrim variant: dimmed parent screen visible behind a bottom sheet.
// ─────────────────────────────────────────────────────────────
function PhoneScreen({ children, bg = PX.paper, statusDark = false, time = '9:41', notch = true, homeInd = true, statusTint }) {
  return (
    <div style={{
      width: 340, height: 735, background: bg, position: 'relative', overflow: 'hidden',
      fontFamily: PX.sans, color: PX.ink,
    }}>
      {/* status bar */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 48,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 26px 6px', zIndex: 10,
        fontSize: 14, fontWeight: 600, color: statusDark ? '#fff' : PX.ink,
        background: statusTint,
      }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>{time}</span>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
          <Sig dark={statusDark} />
          <Wifi dark={statusDark} />
          <Battery dark={statusDark} />
        </span>
      </div>
      {/* notch */}
      {notch && <div style={{
        position: 'absolute', top: 9, left: '50%', transform: 'translateX(-50%)',
        width: 116, height: 32, background: '#0a0807', borderRadius: 20, zIndex: 11,
      }} />}
      {/* content */}
      <div style={{ position: 'absolute', inset: 0, paddingTop: 48, display: 'flex', flexDirection: 'column' }}>
        {children}
      </div>
      {/* home indicator */}
      {homeInd && <div style={{
        position: 'absolute', bottom: 7, left: '50%', transform: 'translateX(-50%)',
        width: 124, height: 4, borderRadius: 2, background: statusDark ? 'rgba(255,255,255,0.5)' : 'rgba(26,22,18,0.30)', zIndex: 12,
      }} />}
    </div>
  );
}

function Sig({ dark }) {
  const c = dark ? '#fff' : PX.ink;
  return (
    <svg width="16" height="11" viewBox="0 0 16 11">
      <rect x="0" y="7" width="2.7" height="4" rx="0.5" fill={c}/>
      <rect x="4.3" y="4.5" width="2.7" height="6.5" rx="0.5" fill={c}/>
      <rect x="8.6" y="2" width="2.7" height="9" rx="0.5" fill={c}/>
      <rect x="13" y="-0.2" width="2.7" height="11.2" rx="0.5" fill={c}/>
    </svg>
  );
}
function Wifi({ dark }) {
  const c = dark ? '#fff' : PX.ink;
  return (
    <svg width="14" height="10" viewBox="0 0 14 10">
      <path d="M7 2.6c1.9 0 3.6.7 4.9 2L13 3.6C11.4 2 9.3 1 7 1S2.6 2 1 3.6l1.1 1.1C3.4 3.4 5.1 2.6 7 2.6Z" fill={c}/>
      <path d="M7 5.6c1.1 0 2.1.4 2.9 1.2l1-1.1C9.8 4.7 8.5 4.1 7 4.1s-2.8.6-3.9 1.6l1 1.1C5 6 6 5.6 7 5.6Z" fill={c}/>
      <circle cx="7" cy="8.7" r="1.2" fill={c}/>
    </svg>
  );
}
function Battery({ dark }) {
  const c = dark ? '#fff' : PX.ink;
  return (
    <svg width="22" height="11" viewBox="0 0 22 11">
      <rect x="0.5" y="0.5" width="19" height="10" rx="2.6" stroke={c} strokeOpacity="0.4" fill="none"/>
      <rect x="2" y="2" width="16" height="7" rx="1.5" fill={c}/>
      <path d="M20.6 3.6v3.8c.7-.3 1.2-1.1 1.2-1.9s-.5-1.6-1.2-1.9Z" fill={c} fillOpacity="0.4"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// NavBar — back chevron + centered title + optional trailing
// ─────────────────────────────────────────────────────────────
function NavBar({ title, back = 'Settings', trailing, large, paperBg = true }) {
  return (
    <div style={{ flexShrink: 0, paddingTop: 4 }}>
      <div style={{
        display: 'flex', alignItems: 'center', height: 36,
        padding: '0 14px',
      }}>
        {back && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15, fontWeight: 400 }}>
            <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M8 1L1 8l7 7"/>
            </svg>
            <span style={{ marginLeft: 1 }}>{back}</span>
          </span>
        )}
        <span style={{ flex: 1 }} />
        {!large && title && <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.2, position: 'absolute', left: 0, right: 0, textAlign: 'center', pointerEvents: 'none' }}>{title}</span>}
        {trailing}
      </div>
      {large && (
        <div style={{ padding: '6px 18px 8px', fontFamily: PX.serif, fontSize: 30, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, lineHeight: 1.1 }}>
          {title}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// ListGroup / ListRow — inset rounded grouped list
// ─────────────────────────────────────────────────────────────
function ListGroup({ header, footer, children, style }) {
  const items = React.Children.toArray(children);
  return (
    <div style={{ ...style }}>
      {header && (
        <div style={{
          fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
          color: PX.ink3, padding: '0 22px 6px',
        }}>{header}</div>
      )}
      <div style={{
        background: PX.card, margin: '0 14px', borderRadius: 14,
        border: '1px solid ' + PX.hairline,
        overflow: 'hidden',
      }}>
        {items.map((c, i) => React.cloneElement(c, { isLast: i === items.length - 1, key: i }))}
      </div>
      {footer && (
        <div style={{
          fontSize: 11, color: PX.ink3, padding: '8px 22px 0', lineHeight: 1.4,
        }}>{footer}</div>
      )}
    </div>
  );
}

function ListRow({ icon, iconBg, title, detail, chevron = true, value, isLast, accent, multiline }) {
  return (
    <div style={{
      display: 'flex', alignItems: multiline ? 'flex-start' : 'center',
      minHeight: 44, padding: '10px 14px', position: 'relative',
      fontSize: 15, color: accent ? PX.accent : PX.ink, letterSpacing: -0.2,
    }}>
      {icon && (
        <div style={{
          width: 26, height: 26, borderRadius: 6,
          background: iconBg || PX.accentTint, color: iconBg ? PX.accentInk : PX.accent,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          marginRight: 12, flexShrink: 0,
          marginTop: multiline ? 1 : 0,
        }}>{icon}</div>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: accent ? 500 : 400 }}>{title}</div>
        {detail && <div style={{ fontSize: 12, color: PX.ink3, marginTop: 2, lineHeight: 1.35 }}>{detail}</div>}
      </div>
      {value && <span style={{ fontSize: 14, color: PX.ink3, marginRight: 4, fontVariantNumeric: 'tabular-nums' }}>{value}</span>}
      {chevron && !accent && (
        <svg width="7" height="12" viewBox="0 0 7 12" fill="none" style={{ flexShrink: 0, marginLeft: 4 }}>
          <path d="M1 1l5 5-5 5" stroke={PX.ink4} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      )}
      {!isLast && (
        <div style={{ position: 'absolute', left: icon ? 52 : 14, right: 0, bottom: 0, height: 0.5, background: PX.divider }} />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────
function Btn({ kind = 'primary', children, sub, leading, full = true, size = 'lg', style }) {
  const sizes = {
    lg: { height: 50, fontSize: 16, padding: '0 18px', radius: 14 },
    md: { height: 42, fontSize: 15, padding: '0 16px', radius: 12 },
    sm: { height: 34, fontSize: 13, padding: '0 12px', radius: 10 },
  };
  const sz = sizes[size];
  const kinds = {
    primary:   { bg: PX.ink, fg: PX.accentInk, border: 'none' },
    accent:    { bg: PX.accent, fg: PX.accentInk, border: 'none' },
    secondary: { bg: PX.card, fg: PX.ink, border: '1px solid ' + PX.hairline },
    ghost:     { bg: 'transparent', fg: PX.accent, border: 'none' },
    danger:    { bg: 'transparent', fg: PX.danger, border: 'none' },
  };
  const k = kinds[kind];
  return (
    <button style={{
      ...sz, width: full ? '100%' : 'auto',
      background: k.bg, color: k.fg, border: k.border, borderRadius: sz.radius,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      fontFamily: PX.sans, fontWeight: 600, letterSpacing: -0.2, cursor: 'default',
      flexDirection: sub ? 'column' : 'row', paddingTop: sub ? 6 : undefined, paddingBottom: sub ? 6 : undefined,
      height: sub ? sz.height + 12 : sz.height,
      ...style,
    }}>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
        {leading}
        <span>{children}</span>
      </span>
      {sub && <span style={{ fontSize: 12, fontWeight: 400, opacity: 0.75, letterSpacing: 0 }}>{sub}</span>}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────
// Sheet — bottom modal over a dimmed parent screen
// ─────────────────────────────────────────────────────────────
function Sheet({ behind, children, height = '78%', scrimOpacity = 0.55 }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 20 }}>
      {/* dimmed behind */}
      <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', filter: 'saturate(0.7) brightness(0.85)' }}>
        {behind}
      </div>
      <div style={{ position: 'absolute', inset: 0, background: PX.scrim, opacity: scrimOpacity / 0.55 }} />
      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height,
        background: PX.paper, borderRadius: '20px 20px 0 0',
        boxShadow: PX.shadowSheet,
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        <div style={{ width: 32, height: 4, borderRadius: 2, background: PX.ink4, margin: '8px auto 0' }} />
        {children}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Toast — small inline pill at the top of a screen
// ─────────────────────────────────────────────────────────────
function Toast({ children, kind = 'warn' }) {
  const tone = kind === 'warn'
    ? { bg: PX.warnTint, fg: PX.warnInk, dot: PX.warn }
    : { bg: PX.accentTint, fg: PX.accent, dot: PX.accent };
  return (
    <div style={{
      margin: '0 14px', padding: '11px 14px',
      background: tone.bg, color: tone.fg, borderRadius: 12,
      display: 'flex', alignItems: 'flex-start', gap: 10,
      fontSize: 13, lineHeight: 1.4, fontWeight: 500, letterSpacing: -0.1,
    }}>
      <span style={{ width: 6, height: 6, borderRadius: 3, background: tone.dot, marginTop: 6, flexShrink: 0 }} />
      <div style={{ flex: 1 }}>{children}</div>
      <span style={{ color: tone.fg, opacity: 0.5, fontSize: 16, marginTop: -2 }}>×</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Sparkles glyph — small AI icon (no emoji)
// ─────────────────────────────────────────────────────────────
function Spark({ size = 16, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <path d="M8 1l1.4 4.2L13.6 6l-4.2 1.4L8 11.6 6.6 7.4 2.4 6l4.2-0.8L8 1z" fill={color || 'currentColor'}/>
      <path d="M13 10l0.6 1.6 1.6 0.6-1.6 0.6L13 14.4 12.4 12.8 10.8 12.2l1.6-0.6L13 10z" fill={color || 'currentColor'} opacity="0.55"/>
    </svg>
  );
}

// Project glyph
function Proj({ size = 16, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color || 'currentColor'} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 4.5a1.5 1.5 0 011.5-1.5h3l1.5 1.5h4.5A1.5 1.5 0 0114 6v6a1.5 1.5 0 01-1.5 1.5h-9A1.5 1.5 0 012 12V4.5z"/>
    </svg>
  );
}

// Memory entry glyph (book ribbon)
function Mem({ size = 16, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color || 'currentColor'} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 2.5v11l5-2 5 2v-11A1.5 1.5 0 0011.5 1h-7A1.5 1.5 0 003 2.5z"/>
    </svg>
  );
}

// Check
function Check({ size = 16, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color || 'currentColor'} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 8.5l3.2 3.2L13 5"/>
    </svg>
  );
}

// Plus glyph
function Plus({ size = 14, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none" stroke={color || 'currentColor'} strokeWidth="2" strokeLinecap="round">
      <path d="M7 2v10M2 7h10"/>
    </svg>
  );
}

Object.assign(window, {
  PX, topicVar, topicSlugFor, TOPIC_PALETTE,
  PhoneScreen, NavBar, ListGroup, ListRow, Btn, Sheet, Toast,
  Spark, Proj, Mem, Check, Plus,
});

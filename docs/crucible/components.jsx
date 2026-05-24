// Crucible — core components
// Button, Field, Card, Sheet, Nav, Icon. iOS-first, adapt-everywhere.

const Cc = window.Crucible;
const C = window.Crucible;

// ───────── Icon ─────────
// Minimal stroke icon set. 24×24 viewbox, 1.6 stroke, round caps.
const Icons = {
  plus:     <path d="M12 5v14M5 12h14"/>,
  check:    <path d="M5 13l4 4L19 7"/>,
  x:        <path d="M6 6l12 12M18 6L6 18"/>,
  chevronR: <path d="M9 6l6 6-6 6"/>,
  chevronL: <path d="M15 6l-6 6 6 6"/>,
  search:   <g><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></g>,
  mic:      <g><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></g>,
  camera:   <g><rect x="3" y="7" width="18" height="13" rx="2"/><circle cx="12" cy="13.5" r="3.5"/><path d="M8 7l1.5-3h5L16 7"/></g>,
  sparkle:  <path d="M12 3l2 6 6 2-6 2-2 6-2-6-6-2 6-2zM19 15l1 2 2 1-2 1-1 2-1-2-2-1 2-1z"/>,
  calendar: <g><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/></g>,
  clock:    <g><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></g>,
  bolt:     <path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>,
  alert:    <g><path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.5"/></g>,
};

function Icon({ name, size = 20, color = 'currentColor', stroke = 1.6, filled = false }) {
  const g = Icons[name];
  if (!g) return null;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={filled ? color : 'none'}
      stroke={filled ? 'none' : color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      {g}
    </svg>
  );
}

// ───────── Button ─────────
// variants: primary · secondary · ghost · destructive
// sizes: sm · md · lg
// states: default · hover · pressed · loading · disabled
function Button({
  variant = 'primary', size = 'md', state = 'default',
  icon, iconOnly, children, dark = false, fullWidth,
}) {
  const SIZE = {
    sm: { h: 32, px: 12, fs: C.type.subhead, radius: Cc.radius.sm, gap: 6 },
    md: { h: 44, px: 18, fs: C.type.body, radius: Cc.radius.sm, gap: 8 },
    lg: { h: 56, px: 24, fs: C.type.headline, radius: Cc.radius.md, gap: 10 },
  }[size];

  const neutral = dark ? Cc.color.cardD : Cc.color.card;
  const ink = dark ? Cc.color.inkD : Cc.color.ink;

  const VAR = {
    primary:     { bg: Cc.color.accent,         fg: Cc.color.accentInk,       border: 'transparent' },
    secondary:   { bg: neutral,                 fg: ink,                      border: dark ? Cc.color.dividerD : Cc.color.divider },
    ghost:       { bg: 'transparent',           fg: Cc.color.accent,          border: 'transparent' },
    destructive: { bg: Cc.color.danger,         fg: '#fff',                   border: 'transparent' },
  }[variant];

  let bg = VAR.bg, fg = VAR.fg, opacity = 1, shadow = 'none';
  if (variant === 'primary') shadow = Cc.elevation[1];
  if (state === 'hover' && variant === 'primary') bg = Cc.color.accentPressed;
  if (state === 'hover' && variant === 'secondary') bg = dark ? Cc.color.sunkD : Cc.color.sunk;
  if (state === 'hover' && variant === 'ghost') bg = Cc.color.accentTint;
  if (state === 'pressed') { opacity = 0.85; shadow = 'none'; }
  if (state === 'disabled') opacity = 0.4;

  const isLoading = state === 'loading';

  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      height: SIZE.h,
      padding: iconOnly ? 0 : `0 ${SIZE.px}px`,
      width: iconOnly ? SIZE.h : (fullWidth ? '100%' : undefined),
      background: bg, color: fg,
      borderRadius: SIZE.radius,
      border: '1px solid ' + VAR.border,
      gap: SIZE.gap,
      boxShadow: shadow,
      opacity,
      cursor: state === 'disabled' ? 'not-allowed' : 'pointer',
      ...typeStyle(SIZE.fs),
      fontWeight: 600,
      whiteSpace: 'nowrap',
      transition: 'background 160ms',
    }}>
      {isLoading ? (
        <div style={{
          width: 16, height: 16, borderRadius: 8,
          border: '2px solid ' + fg, borderTopColor: 'transparent',
          animation: 'crucible-spin 800ms linear infinite',
        }}/>
      ) : icon && <Icon name={icon} size={size === 'lg' ? 22 : 18} color={fg}/>}
      {!iconOnly && children}
    </div>
  );
}

// ───────── Field (text input) ─────────
function Field({
  label, value, placeholder = 'Placeholder',
  state = 'default', helper, icon, trailing,
  dark = false, size = 'md',
}) {
  const H = { sm: 36, md: 44, lg: 52 }[size];
  const bg = dark ? Cc.color.cardD : Cc.color.card;
  const ink = dark ? Cc.color.inkD : Cc.color.ink;
  const ink3 = dark ? Cc.color.inkD3 : Cc.color.ink3;
  const border = state === 'focus' ? Cc.color.accent
    : state === 'error' ? Cc.color.danger
    : (dark ? Cc.color.dividerD : Cc.color.divider);
  const ring = state === 'focus' ? `0 0 0 3px ${Cc.color.focus}` : 'none';
  const isEmpty = !value;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      {label && <div style={{ ...typeStyle(C.type.footnote), color: dark ? Cc.color.inkD2 : Cc.color.ink2, fontWeight: 500 }}>{label}</div>}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        height: H, padding: '0 14px',
        background: bg, borderRadius: Cc.radius.sm,
        border: '1px solid ' + border,
        boxShadow: ring,
        color: ink, ...typeStyle(C.type.body),
        transition: 'border 140ms, box-shadow 140ms',
      }}>
        {icon && <Icon name={icon} size={18} color={ink3}/>}
        <div style={{ flex: 1, color: isEmpty ? ink3 : ink }}>{value || placeholder}</div>
        {trailing}
        {state === 'focus' && <div style={{ width: 1.5, height: 20, background: Cc.color.accent, animation: 'crucible-caret 1s steps(2) infinite' }}/>}
      </div>
      {helper && <div style={{ ...typeStyle(C.type.caption1), color: state === 'error' ? Cc.color.danger : (dark ? Cc.color.inkD3 : Cc.color.ink3) }}>{helper}</div>}
    </div>
  );
}

// ───────── Card ─────────
function Card({ children, elevation = 1, dark = false, style = {}, padding = 20 }) {
  return (
    <div style={{
      background: dark ? Cc.color.cardD : Cc.color.card,
      borderRadius: Cc.radius.lg,
      padding,
      boxShadow: Cc.elevation[elevation],
      border: elevation === 0 ? '1px solid ' + (dark ? Cc.color.dividerD : Cc.color.divider) : 'none',
      ...style,
    }}>{children}</div>
  );
}

// ───────── Chip / Badge ─────────
function Chip({ children, tone = 'neutral', size = 'md', icon, dark = false }) {
  const H = { sm: 22, md: 26 }[size];
  const TONE = {
    neutral: { bg: dark ? Cc.color.sunkD : Cc.color.sunk, fg: dark ? Cc.color.inkD : Cc.color.ink },
    accent:  { bg: Cc.color.accentTint, fg: Cc.color.accentPressed },
    success: { bg: 'rgba(47,125,79,0.12)', fg: Cc.color.success },
    warn:    { bg: 'rgba(184,115,34,0.14)', fg: Cc.color.warning },
    danger:  { bg: 'rgba(184,49,30,0.12)',  fg: Cc.color.danger },
  }[tone];
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      height: H, padding: '0 10px',
      background: TONE.bg, color: TONE.fg,
      borderRadius: Cc.radius.pill,
      ...typeStyle(C.type.caption2), fontWeight: 600,
      textTransform: 'uppercase', letterSpacing: 0.6,
    }}>
      {icon && <Icon name={icon} size={12} color={TONE.fg}/>}
      {children}
    </div>
  );
}

// ───────── Toggle / Switch ─────────
function Toggle({ on = false, dark = false }) {
  return (
    <div style={{
      width: 51, height: 31, borderRadius: 16,
      background: on ? Cc.color.accent : (dark ? Cc.color.sunkD : '#E4DFD6'),
      position: 'relative', transition: 'background 180ms',
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? 22 : 2,
        width: 27, height: 27, borderRadius: 14, background: '#fff',
        boxShadow: '0 2px 4px rgba(0,0,0,0.15)',
        transition: 'left 200ms cubic-bezier(0.2, 1.3, 0.3, 1)',
      }}/>
    </div>
  );
}

// ───────── Segmented control ─────────
function Segmented({ items, active = 0, dark = false }) {
  const bg = dark ? Cc.color.sunkD : '#E7E2D9';
  return (
    <div style={{
      display: 'inline-flex', background: bg,
      borderRadius: 10, padding: 2, gap: 0,
    }}>
      {items.map((it, i) => (
        <div key={i} style={{
          padding: '7px 14px',
          background: i === active ? (dark ? Cc.color.cardD : Cc.color.card) : 'transparent',
          borderRadius: 8,
          color: dark ? Cc.color.inkD : Cc.color.ink,
          boxShadow: i === active ? '0 1px 2px rgba(0,0,0,0.1)' : 'none',
          ...typeStyle(C.type.subhead), fontWeight: 600,
        }}>{it}</div>
      ))}
    </div>
  );
}

// ───────── List row (iOS) ─────────
function CListRow({ title, detail, icon, trailing = 'chevron', isLast, dark = false, destructive }) {
  const ink = destructive ? Cc.color.danger : (dark ? Cc.color.inkD : Cc.color.ink);
  const ink2 = dark ? Cc.color.inkD2 : Cc.color.ink2;
  const sep = dark ? Cc.color.dividerD : Cc.color.divider;
  return (
    <div style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px', minHeight: 52 }}>
      {icon && (
        <div style={{ width: 30, height: 30, borderRadius: 7, background: Cc.color.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <Icon name={icon} size={16} color="#fff"/>
        </div>
      )}
      <div style={{ flex: 1, color: ink, ...typeStyle(C.type.body) }}>{title}</div>
      {detail && <div style={{ color: ink2, ...typeStyle(C.type.body) }}>{detail}</div>}
      {trailing === 'chevron' && <Icon name="chevronR" size={14} color={dark ? Cc.color.inkD3 : Cc.color.ink3}/>}
      {trailing === 'toggle' && <Toggle on dark={dark}/>}
      {!isLast && <div style={{ position: 'absolute', bottom: 0, left: icon ? 58 : 16, right: 0, height: 1, background: sep }}/>}
    </div>
  );
}

// ───────── Sheet (bottom) ─────────
function Sheet({ title, children, dark = false, width = 390, height = 500 }) {
  return (
    <div style={{
      width, height, background: Cc.color.paper,
      borderRadius: Cc.radius.xl,
      position: 'relative', overflow: 'hidden',
      boxShadow: Cc.elevation[4],
    }}>
      <div style={{ padding: '12px 0 8px', display: 'flex', justifyContent: 'center' }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: Cc.color.ink4 }}/>
      </div>
      {title && (
        <div style={{ padding: '4px 20px 16px' }}>
          <div style={{ ...typeStyle(C.type.title3), color: Cc.color.ink }}>{title}</div>
        </div>
      )}
      {children}
    </div>
  );
}

Object.assign(window, { Icon, Button, Field, Card, Chip, Toggle, Segmented, CListRow, Sheet });

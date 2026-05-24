// Crucible — primitives
// Low-level building blocks: Swatch, TypeSpecimen, TokenRow, Stack, Row, Label.
// These are used by the system's own reference pages — not consumer components.

window.C = window.Crucible;
const C = window.Crucible;

// ── Swatch ──
function Swatch({ value, name, token, size = 72, textured = false }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, width: size + 24 }}>
      <div style={{
        width: size, height: size, borderRadius: C.radius.md,
        background: value,
        boxShadow: 'inset 0 0 0 1px ' + C.color.hairline,
        position: 'relative',
      }}/>
      <div style={{ ...typeStyle(C.type.caption2), color: C.color.ink, fontWeight: 600, textTransform: 'uppercase' }}>{name}</div>
      <div style={{ ...typeStyle(C.type.caption1), color: C.color.ink2, fontFamily: C.type.mono }}>{token}</div>
    </div>
  );
}

// ── Type specimen row ──
function TypeSpecimen({ label, token, sample = 'The quick brown fox' }) {
  const t = C.type[token];
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 24, padding: '12px 0', borderBottom: '1px solid ' + C.color.hairline }}>
      <div style={{ width: 90, flexShrink: 0 }}>
        <div style={{ ...typeStyle(C.type.caption2), color: C.color.ink, fontWeight: 700, textTransform: 'uppercase' }}>{label}</div>
        <div style={{ ...typeStyle(C.type.caption1), color: C.color.ink3, fontFamily: C.type.mono }}>
          {t.size}/{t.line} · {t.weight}
        </div>
      </div>
      <div style={{ ...typeStyle(t), color: C.color.ink, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{sample}</div>
    </div>
  );
}

// ── Token row (space, radius, etc.) ──
function TokenRow({ name, token, value, preview }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '8px 0', borderBottom: '1px solid ' + C.color.hairline }}>
      <div style={{ width: 80, ...typeStyle(C.type.caption1), fontFamily: C.type.mono, color: C.color.ink }}>{name}</div>
      <div style={{ width: 40, ...typeStyle(C.type.caption1), color: C.color.ink2, textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{value}</div>
      <div style={{ flex: 1 }}>{preview}</div>
    </div>
  );
}

// ── Section label ──
function SectionLabel({ children }) {
  return (
    <div style={{
      ...typeStyle(C.type.eyebrow),
      color: C.color.ink3,
      textTransform: 'uppercase',
      marginBottom: 12,
    }}>{children}</div>
  );
}

// ── Editorial title (serif) ──
function EditorialTitle({ children, size = 'serif2', color }) {
  return (
    <div style={{ ...typeStyle(C.type[size]), color: color || C.color.ink }}>{children}</div>
  );
}

// ── Do / Don't card ──
function GuidanceCard({ verdict, children, caption }) {
  const isYes = verdict === 'do';
  const accent = isYes ? C.color.success : C.color.danger;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div style={{
        position: 'relative',
        background: C.color.card,
        borderRadius: C.radius.md,
        padding: 20,
        border: '1px solid ' + C.color.hairline,
        borderTop: '3px solid ' + accent,
        minHeight: 120,
      }}>
        {children}
      </div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
        <div style={{
          ...typeStyle(C.type.caption2),
          color: accent,
          fontWeight: 700,
          textTransform: 'uppercase',
          flexShrink: 0,
          paddingTop: 2,
        }}>{isYes ? 'Do' : "Don't"}</div>
        <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2 }}>{caption}</div>
      </div>
    </div>
  );
}

Object.assign(window, { Swatch, TypeSpecimen, TokenRow, SectionLabel, EditorialTitle, GuidanceCard });

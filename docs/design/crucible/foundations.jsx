// Crucible — Foundations artboards
// Color · Type · Space · Radii · Elevation · Motion · Iconography

const Cf = window.Crucible;
const C = window.Crucible;

// ───────── Color palette artboard ─────────
function FoundationColor() {
  const neutrals = [
    ['Paper', Cf.color.paper, 'color.paper'],
    ['Card', Cf.color.card, 'color.card'],
    ['Sunk', Cf.color.sunk, 'color.sunk'],
    ['Ink', Cf.color.ink, 'color.ink'],
  ];
  const ink = [
    ['Ink', Cf.color.ink, 'color.ink'],
    ['Ink-2', 'rgba(26,22,18,0.64)', 'color.ink2'],
    ['Ink-3', 'rgba(26,22,18,0.42)', 'color.ink3'],
    ['Ink-4', 'rgba(26,22,18,0.22)', 'color.ink4'],
  ];
  const accent = [
    ['Accent', Cf.color.accent, 'color.accent'],
    ['Pressed', Cf.color.accentPressed, 'color.accentPressed'],
    ['Tint', Cf.color.accentTint, 'color.accentTint'],
    ['On Dark', Cf.color.accentOnDark, 'color.accentOnDark'],
  ];
  const semantic = [
    ['Success', Cf.color.success, 'color.success'],
    ['Warning', Cf.color.warning, 'color.warning'],
    ['Danger',  Cf.color.danger,  'color.danger'],
    ['Info',    Cf.color.info,    'color.info'],
  ];
  const dark = [
    ['Paper', Cf.color.paperD, 'color.paperD'],
    ['Card', Cf.color.cardD, 'color.cardD'],
    ['Sunk', Cf.color.sunkD, 'color.sunkD'],
    ['Ink', Cf.color.inkD, 'color.inkD'],
  ];
  const Group = ({ label, items }) => (
    <div style={{ marginBottom: 28 }}>
      <SectionLabel>{label}</SectionLabel>
      <div style={{ display: 'flex', gap: 20, flexWrap: 'wrap' }}>
        {items.map(([n, v, t]) => <Swatch key={n} name={n} value={v} token={t}/>)}
      </div>
    </div>
  );
  return (
    <div style={{ padding: 40, background: Cf.color.paper, height: '100%', fontFamily: Cf.type.sans }}>
      <EditorialTitle size="serif3">Color</EditorialTitle>
      <div style={{ ...typeStyle(Cf.type.footnote), color: Cf.color.ink2, maxWidth: 420, marginBottom: 28, marginTop: 4 }}>
        Warm neutrals, one accent. Dark mode is an inversion, not a recolor.
      </div>
      <Group label="Surface (light)" items={neutrals}/>
      <Group label="Ink — text layers" items={ink}/>
      <Group label="Accent — ember" items={accent}/>
      <Group label="Semantic" items={semantic}/>
      <Group label="Surface (dark)" items={dark}/>
    </div>
  );
}

// ───────── Type artboard ─────────
function FoundationType() {
  const ramp = ['display', 'title1', 'title2', 'title3', 'headline', 'body', 'callout', 'subhead', 'footnote', 'caption1'];
  return (
    <div style={{ padding: 40, background: Cf.color.paper, height: '100%', fontFamily: Cf.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Typography</EditorialTitle>
      <div style={{ ...typeStyle(Cf.type.footnote), color: Cf.color.ink2, maxWidth: 460, marginBottom: 24, marginTop: 4 }}>
        SF for interface. Source Serif for editorial moments — hero titles, empty states, quotes.
      </div>
      <SectionLabel>Sans ramp</SectionLabel>
      <div style={{ marginBottom: 28 }}>
        {ramp.map(t => <TypeSpecimen key={t} label={t} token={t}/>)}
      </div>
      <SectionLabel>Editorial serif</SectionLabel>
      <div>
        <TypeSpecimen label="serif1" token="serif1" sample="Begin where you are."/>
        <TypeSpecimen label="serif2" token="serif2" sample="A quiet start is still a start."/>
        <TypeSpecimen label="serif3" token="serif3" sample="Small things, over time, become large things."/>
      </div>
    </div>
  );
}

// ───────── Space & grid artboard ─────────
function FoundationSpace() {
  const spaceKeys = ['1','2','3','4','5','6','8','10','12','16','20'];
  return (
    <div style={{ padding: 40, background: Cf.color.paper, height: '100%', fontFamily: Cf.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Space & grid</EditorialTitle>
      <div style={{ ...typeStyle(Cf.type.footnote), color: Cf.color.ink2, maxWidth: 420, marginBottom: 24, marginTop: 4 }}>
        4pt baseline. Eleven named steps — don't improvise.
      </div>
      <div style={{ background: Cf.color.card, borderRadius: Cf.radius.md, padding: 20 }}>
        {spaceKeys.map(k => (
          <TokenRow key={k}
            name={`space-${k}`}
            value={Cf.space[k] + 'px'}
            preview={<div style={{ height: 10, width: Cf.space[k] * 4, background: Cf.color.accent, borderRadius: 2 }}/>}/>
        ))}
      </div>
    </div>
  );
}

// ───────── Radii & elevation artboard ─────────
function FoundationRadiiElevation() {
  const radii = [['xs',4],['sm',8],['md',12],['lg',16],['xl',22],['pill',32]];
  return (
    <div style={{ padding: 40, background: Cf.color.paper, height: '100%', fontFamily: Cf.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Radii & elevation</EditorialTitle>
      <div style={{ ...typeStyle(Cf.type.footnote), color: Cf.color.ink2, maxWidth: 460, marginBottom: 28, marginTop: 4 }}>
        Soft but not cartoon. Shadows are warm — tinted toward ember, never cold gray.
      </div>
      <SectionLabel>Radii</SectionLabel>
      <div style={{ display: 'flex', gap: 16, marginBottom: 32 }}>
        {radii.map(([n, v]) => (
          <div key={n} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 64, height: 64, background: Cf.color.card, borderRadius: v === 32 ? 32 : v, border: '1px solid ' + Cf.color.hairline }}/>
            <div style={{ ...typeStyle(Cf.type.caption2), color: Cf.color.ink, fontWeight: 700, textTransform: 'uppercase' }}>{n}</div>
            <div style={{ ...typeStyle(Cf.type.caption1), color: Cf.color.ink3, fontFamily: Cf.type.mono }}>{v}px</div>
          </div>
        ))}
      </div>
      <SectionLabel>Elevation</SectionLabel>
      <div style={{ display: 'flex', gap: 20 }}>
        {[1, 2, 3, 4].map(l => (
          <div key={l} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 80, height: 80, background: Cf.color.card, borderRadius: Cf.radius.md, boxShadow: Cf.elevation[l] }}/>
            <div style={{ ...typeStyle(Cf.type.caption2), color: Cf.color.ink, fontWeight: 700 }}>Level {l}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ───────── Motion artboard ─────────
function FoundationMotion() {
  const [tick, setTick] = React.useState(0);
  React.useEffect(() => { const t = setInterval(() => setTick(x => x + 1), 2000); return () => clearInterval(t); }, []);
  const on = tick % 2 === 0;
  const rows = [
    ['fast',    120,  Cf.motion.ease.standard],
    ['base',    200,  Cf.motion.ease.standard],
    ['slow',    320,  Cf.motion.ease.emphasized],
    ['pageful', 520,  Cf.motion.ease.emphasized],
    ['spring',  320,  Cf.motion.ease.spring],
  ];
  return (
    <div style={{ padding: 40, background: Cf.color.paper, height: '100%', fontFamily: Cf.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Motion</EditorialTitle>
      <div style={{ ...typeStyle(Cf.type.footnote), color: Cf.color.ink2, maxWidth: 420, marginBottom: 24, marginTop: 4 }}>
        Four durations, four easings. Everything feels haptic — spring on commit, standard on entry.
      </div>
      <div style={{ background: Cf.color.card, borderRadius: Cf.radius.md, padding: 20 }}>
        {rows.map(([n, d, e]) => (
          <div key={n} style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '10px 0', borderBottom: '1px solid ' + Cf.color.hairline }}>
            <div style={{ width: 80, ...typeStyle(Cf.type.caption1), fontFamily: Cf.type.mono, color: Cf.color.ink }}>{n}</div>
            <div style={{ width: 54, ...typeStyle(Cf.type.caption1), color: Cf.color.ink3, fontVariantNumeric: 'tabular-nums' }}>{d}ms</div>
            <div style={{ flex: 1, height: 28, position: 'relative', background: Cf.color.sunk, borderRadius: 14 }}>
              <div style={{
                position: 'absolute', top: 2, left: on ? 'calc(100% - 26px)' : 2,
                width: 24, height: 24, borderRadius: 12, background: Cf.color.accent,
                transition: `left ${d}ms ${e}`,
              }}/>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ───────── Iconography artboard ─────────
function FoundationIcons() {
  const names = ['plus','check','x','chevronR','chevronL','search','mic','camera','sparkle','calendar','clock','bolt','alert'];
  return (
    <div style={{ padding: 40, background: Cf.color.paper, height: '100%', fontFamily: Cf.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Iconography</EditorialTitle>
      <div style={{ ...typeStyle(Cf.type.footnote), color: Cf.color.ink2, maxWidth: 420, marginBottom: 28, marginTop: 4 }}>
        24 × 24 grid, 1.6pt stroke, round caps. SF-Symbols-adjacent, not a custom set.
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 16 }}>
        {names.map(n => (
          <div key={n} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, padding: 16, background: Cf.color.card, borderRadius: Cf.radius.md, border: '1px solid ' + Cf.color.hairline }}>
            <Icon name={n} size={24} color={Cf.color.ink}/>
            <div style={{ ...typeStyle(Cf.type.caption1), color: Cf.color.ink2, fontFamily: Cf.type.mono }}>{n}</div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 24 }}>
        <SectionLabel>Sizes</SectionLabel>
        <div style={{ display: 'flex', gap: 32, alignItems: 'flex-end' }}>
          {[16,20,24,32].map(s => (
            <div key={s} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
              <Icon name="sparkle" size={s} color={Cf.color.accent}/>
              <div style={{ ...typeStyle(Cf.type.caption2), color: Cf.color.ink2 }}>{s}pt</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { FoundationColor, FoundationType, FoundationSpace, FoundationRadiiElevation, FoundationMotion, FoundationIcons });

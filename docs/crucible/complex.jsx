const C = window.Crucible;
// Crucible — Complex components
// Lists, Tables, Command Palette, Date Picker

// ───────── Grouped list (iOS-style) ─────────
function ComplexList() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Lists</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Grouped (inset) is default for settings and detail. Plain for collections that read as a stream.
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 28 }}>
        <div>
          <SectionLabel>Grouped inset</SectionLabel>
          <div style={{ ...typeStyle(C.type.caption1), color: C.color.ink3, textTransform: 'uppercase', padding: '0 16px 6px' }}>Appearance</div>
          <div style={{ background: C.color.card, borderRadius: C.radius.lg, overflow: 'hidden', border: '1px solid ' + C.color.hairline }}>
            <CListRow icon="sparkle" title="Theme" detail="Warm" trailing="chevron"/>
            <CListRow icon="clock" title="Reminders" detail="On" trailing="toggle"/>
            <CListRow icon="mic" title="Voice capture" detail="Hold" trailing="chevron"/>
            <CListRow icon="bolt" title="Shortcuts" isLast trailing="chevron"/>
          </div>
        </div>
        <div>
          <SectionLabel>Plain</SectionLabel>
          <div style={{ background: C.color.card, borderRadius: C.radius.md, overflow: 'hidden', border: '1px solid ' + C.color.hairline }}>
            <div style={{ padding: '14px 16px', borderBottom: '1px solid ' + C.color.hairline }}>
              <div style={{ ...typeStyle(C.type.headline), color: C.color.ink }}>A lane of late light</div>
              <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, marginTop: 2 }}>Today · 11:28 am · Voice</div>
            </div>
            <div style={{ padding: '14px 16px', borderBottom: '1px solid ' + C.color.hairline }}>
              <div style={{ ...typeStyle(C.type.headline), color: C.color.ink }}>Grocery, but ginger</div>
              <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, marginTop: 2 }}>Yesterday · 8:04 pm</div>
            </div>
            <div style={{ padding: '14px 16px' }}>
              <div style={{ ...typeStyle(C.type.headline), color: C.color.ink }}>Bridge conversation — D</div>
              <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, marginTop: 2 }}>Nov 14 · Voice · 3:41</div>
            </div>
          </div>

          <div style={{ height: 20 }}/>
          <SectionLabel>Destructive row</SectionLabel>
          <div style={{ background: C.color.card, borderRadius: C.radius.lg, overflow: 'hidden', border: '1px solid ' + C.color.hairline }}>
            <CListRow title="Delete account" destructive isLast trailing={null}/>
          </div>
        </div>
      </div>
    </div>
  );
}

// ───────── Table (web/iPad) ─────────
function ComplexTable() {
  const rows = [
    ['A lane of late light', 'Voice · 12s', 'Today', '11:28 am'],
    ['Grocery, but ginger',  'Text',        'Yesterday', '8:04 pm'],
    ['Bridge conversation',  'Voice · 3:41','Nov 14',   '3:10 pm'],
    ['On patience',          'Text',        'Nov 12',   '9:22 am'],
    ['How coffee smells',    'Voice · 22s', 'Nov 10',   '7:40 am'],
  ];
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans }}>
      <EditorialTitle size="serif3">Tables</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 20, marginTop: 4 }}>
        For density. Row height 44. First column bolded. Zebra is implied by hairlines, not fill.
      </div>
      <div style={{ background: C.color.card, borderRadius: C.radius.md, overflow: 'hidden', border: '1px solid ' + C.color.hairline }}>
        {/* Header */}
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 1fr', padding: '0 20px', height: 40, alignItems: 'center', background: C.color.sunk, ...typeStyle(C.type.caption2), color: C.color.ink2, fontWeight: 700, textTransform: 'uppercase', letterSpacing: 0.6 }}>
          <div>Title</div><div>Kind</div><div>Day</div><div>Time</div>
        </div>
        {rows.map((r, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 1fr',
            padding: '0 20px', height: 44, alignItems: 'center',
            borderTop: '1px solid ' + C.color.hairline,
            ...typeStyle(C.type.body), color: C.color.ink,
          }}>
            <div style={{ fontWeight: 600 }}>{r[0]}</div>
            <div style={{ color: C.color.ink2 }}>{r[1]}</div>
            <div style={{ color: C.color.ink2 }}>{r[2]}</div>
            <div style={{ color: C.color.ink2, fontVariantNumeric: 'tabular-nums' }}>{r[3]}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ───────── Command palette ─────────
function ComplexCommand() {
  const results = [
    { group: 'Jump to', items: [['Today feed','clock','T'],['Search','search','/'],['Ideas','sparkle','I']] },
    { group: 'Actions',  items: [['New voice memory','mic','N'],['New photo','camera','P'],['Quick note','plus','⌘N']] },
    { group: 'Recent',   items: [['A lane of late light','clock',''],['Grocery, but ginger','clock','']] },
  ];
  return (
    <div style={{ padding: 40, background: '#2a2520', height: '100%', fontFamily: C.type.sans }}>
      <EditorialTitle size="serif3" color="#f3ece1">Command palette</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: 'rgba(243,236,225,0.65)', maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Web-first. ⌘K opens it anywhere. Title is a search field; results are grouped, keyboardable.
      </div>
      <div style={{
        background: '#1a1613', borderRadius: C.radius.lg,
        boxShadow: C.elevation[4], overflow: 'hidden', maxWidth: 620, border: '1px solid rgba(255,245,235,0.1)',
      }}>
        <div style={{ padding: '14px 18px', display: 'flex', alignItems: 'center', gap: 10, borderBottom: '1px solid rgba(255,245,235,0.08)' }}>
          <Icon name="search" size={18} color="rgba(243,236,225,0.5)"/>
          <div style={{ ...typeStyle(C.type.body), color: 'rgba(243,236,225,0.95)', flex: 1 }}>Jump to…</div>
          <Chip dark>Esc</Chip>
        </div>
        <div style={{ padding: 8 }}>
          {results.map((grp, gi) => (
            <div key={gi} style={{ marginBottom: 4 }}>
              <div style={{ ...typeStyle(C.type.caption2), color: 'rgba(243,236,225,0.45)', fontWeight: 700, textTransform: 'uppercase', padding: '8px 12px 4px', letterSpacing: 1 }}>{grp.group}</div>
              {grp.items.map(([name, ic, kb], i) => (
                <div key={i} style={{
                  display: 'flex', alignItems: 'center', gap: 12,
                  padding: '9px 12px', borderRadius: 6,
                  background: gi === 0 && i === 0 ? 'rgba(198,74,28,0.25)' : 'transparent',
                }}>
                  <Icon name={ic} size={18} color="rgba(243,236,225,0.75)"/>
                  <div style={{ flex: 1, ...typeStyle(C.type.body), color: gi === 0 && i === 0 ? '#fff' : 'rgba(243,236,225,0.9)' }}>{name}</div>
                  {kb && <div style={{
                    ...typeStyle(C.type.caption1), fontFamily: C.type.mono,
                    color: 'rgba(243,236,225,0.6)', background: 'rgba(255,245,235,0.08)',
                    padding: '2px 7px', borderRadius: 4,
                  }}>{kb}</div>}
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ───────── Date picker ─────────
function ComplexDate() {
  const days = Array.from({ length: 35 }, (_, i) => {
    const d = i - 2; // start Nov offset
    return d >= 1 && d <= 30 ? d : null;
  });
  const today = 14, selected = 21;
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Date picker</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Calendar grid. Today is a ring; selected is a filled circle. Weekends muted.
      </div>
      <div style={{ background: C.color.card, borderRadius: C.radius.lg, padding: 24, width: 360, border: '1px solid ' + C.color.hairline, boxShadow: C.elevation[1] }}>
        {/* Month header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          <div style={{ ...typeStyle(C.type.title3), color: C.color.ink }}>November 2026</div>
          <div style={{ display: 'flex', gap: 6 }}>
            <Button variant="ghost" size="sm" iconOnly icon="chevronL"/>
            <Button variant="ghost" size="sm" iconOnly icon="chevronR"/>
          </div>
        </div>
        {/* Weekday row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2, marginBottom: 6 }}>
          {['S','M','T','W','T','F','S'].map((d, i) => (
            <div key={i} style={{ textAlign: 'center', ...typeStyle(C.type.caption2), color: (i === 0 || i === 6) ? C.color.ink3 : C.color.ink2, fontWeight: 700, textTransform: 'uppercase' }}>{d}</div>
          ))}
        </div>
        {/* Days */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2 }}>
          {days.map((d, i) => {
            const weekend = (i % 7 === 0) || (i % 7 === 6);
            const isToday = d === today;
            const isSel = d === selected;
            return (
              <div key={i} style={{
                aspectRatio: '1 / 1', display: 'flex', alignItems: 'center', justifyContent: 'center',
                borderRadius: 999,
                background: isSel ? C.color.accent : 'transparent',
                border: isToday && !isSel ? '1.5px solid ' + C.color.accent : 'none',
                color: isSel ? '#fff' : (d === null ? 'transparent' : weekend ? C.color.ink3 : C.color.ink),
                ...typeStyle(C.type.body),
                fontVariantNumeric: 'tabular-nums',
                fontWeight: isSel || isToday ? 600 : 500,
              }}>{d ?? '·'}</div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ComplexList, ComplexTable, ComplexCommand, ComplexDate });

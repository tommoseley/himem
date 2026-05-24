const C = window.Crucible;
// Crucible — Patterns
// Empty · Loading · Error · Confirmation

// ───────── Empty state ─────────
function PatternEmpty() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans }}>
      <EditorialTitle size="serif3">Empty states</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 28, marginTop: 4 }}>
        A quiet moment, not a dead end. Serif headline, short encouragement, a single action.
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
        <Card style={{ padding: 40, minHeight: 320, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
          <div style={{ width: 56, height: 56, borderRadius: 28, background: C.color.accentTint, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 20 }}>
            <Icon name="sparkle" size={24} color={C.color.accent}/>
          </div>
          <div style={{ ...typeStyle(C.type.serif2), color: C.color.ink, marginBottom: 10, maxWidth: 280 }}>Nothing here yet.</div>
          <div style={{ ...typeStyle(C.type.body), color: C.color.ink2, maxWidth: 280, marginBottom: 24 }}>
            Your first memory can be anything — a sentence, a voice note, an image you want to keep.
          </div>
          <Button icon="mic">Record first memory</Button>
        </Card>

        <Card style={{ padding: 40, minHeight: 320, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
          <div style={{ width: 56, height: 56, borderRadius: 28, background: C.color.sunk, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 20 }}>
            <Icon name="search" size={24} color={C.color.ink2}/>
          </div>
          <div style={{ ...typeStyle(C.type.title2), color: C.color.ink, marginBottom: 8 }}>No matches</div>
          <div style={{ ...typeStyle(C.type.body), color: C.color.ink2, maxWidth: 280, marginBottom: 20 }}>
            Nothing matches "bridge conversations this year". Try widening the date.
          </div>
          <Button variant="secondary">Clear filters</Button>
        </Card>
      </div>
    </div>
  );
}

// ───────── Loading ─────────
function PatternLoading() {
  const Shimmer = ({ w, h = 14, rad = 4 }) => (
    <div style={{
      width: w, height: h, borderRadius: rad,
      background: `linear-gradient(90deg, ${C.color.sunk} 25%, ${C.color.hairline} 50%, ${C.color.sunk} 75%)`,
      backgroundSize: '200% 100%',
      animation: 'crucible-shimmer 1200ms linear infinite',
    }}/>
  );
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Loading</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Skeletons for content, spinner for pending actions, progress for known-length tasks.
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: 20 }}>
        <Card>
          <SectionLabel>Skeleton — list item</SectionLabel>
          {[0,1,2].map(i => (
            <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '14px 0', borderBottom: i < 2 ? '1px solid ' + C.color.hairline : 'none' }}>
              <Shimmer w="60%" h={16}/>
              <Shimmer w="30%" h={12}/>
            </div>
          ))}
        </Card>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <Card>
            <SectionLabel>Spinner</SectionLabel>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, paddingTop: 8 }}>
              <div style={{
                width: 20, height: 20, borderRadius: 10,
                border: '2px solid ' + C.color.accent, borderTopColor: 'transparent',
                animation: 'crucible-spin 800ms linear infinite',
              }}/>
              <div style={{ ...typeStyle(C.type.body), color: C.color.ink2 }}>Transcribing…</div>
            </div>
          </Card>
          <Card>
            <SectionLabel>Progress</SectionLabel>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, paddingTop: 8 }}>
              <div style={{ height: 6, background: C.color.sunk, borderRadius: 3, overflow: 'hidden' }}>
                <div style={{ width: '62%', height: '100%', background: C.color.accent, borderRadius: 3 }}/>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', ...typeStyle(C.type.caption1), color: C.color.ink3 }}>
                <span>Uploading</span><span style={{ fontVariantNumeric: 'tabular-nums' }}>62%</span>
              </div>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}

// ───────── Error ─────────
function PatternError() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Errors</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Inline for fields. Banner for page-level. Toast for transient. Never blame the user.
      </div>

      <SectionLabel>Inline — field</SectionLabel>
      <div style={{ marginBottom: 24, maxWidth: 420 }}>
        <Field label="Email" value="jordan@" state="error" helper="That doesn't look finished — we need a full email."/>
      </div>

      <SectionLabel>Banner — page</SectionLabel>
      <div style={{
        display: 'flex', gap: 14, padding: 16,
        background: 'rgba(184,49,30,0.08)', borderRadius: C.radius.md,
        border: '1px solid rgba(184,49,30,0.24)',
        marginBottom: 24,
      }}>
        <Icon name="alert" size={20} color={C.color.danger}/>
        <div style={{ flex: 1 }}>
          <div style={{ ...typeStyle(C.type.headline), color: C.color.ink, marginBottom: 4 }}>Couldn't reach your library</div>
          <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2 }}>
            Your last changes are saved locally. We'll sync when you're back online.
          </div>
        </div>
        <Button size="sm" variant="secondary">Retry</Button>
      </div>

      <SectionLabel>Toast — transient</SectionLabel>
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 10,
        padding: '12px 16px', background: C.color.ink, color: '#fff',
        borderRadius: C.radius.md, boxShadow: C.elevation[3],
        marginBottom: 24,
      }}>
        <Icon name="x" size={16} color="#fff"/>
        <div style={{ ...typeStyle(C.type.subhead), fontWeight: 500 }}>Couldn't save — we'll try again</div>
        <Button size="sm" variant="ghost" style={{ color: C.color.accentOnDark }}>Undo</Button>
      </div>
    </div>
  );
}

// ───────── Confirmation ─────────
function PatternConfirmation() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Confirmation</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Three flavors: destructive (require confirm), reversible (toast with undo), informational (inline success chip).
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
        <Card padding={0}>
          <div style={{ padding: 24 }}>
            <SectionLabel>Destructive — sheet</SectionLabel>
            <Sheet title="Delete this memory?" width="100%" height={260}>
              <div style={{ padding: '0 20px 20px' }}>
                <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, marginBottom: 16 }}>
                  It will move to trash for 30 days, then disappear. This can't be undone after that.
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <Button variant="destructive" fullWidth>Delete</Button>
                  <Button variant="ghost" fullWidth>Keep</Button>
                </div>
              </div>
            </Sheet>
          </div>
        </Card>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <Card>
            <SectionLabel>Reversible — toast</SectionLabel>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 16px', background: C.color.ink, color: '#fff', borderRadius: C.radius.md, marginTop: 8 }}>
              <Icon name="check" size={16} color="#fff"/>
              <div style={{ flex: 1, ...typeStyle(C.type.subhead), fontWeight: 500 }}>Memory moved to Ideas</div>
              <div style={{ ...typeStyle(C.type.subhead), color: C.color.accentOnDark, fontWeight: 600 }}>Undo</div>
            </div>
          </Card>
          <Card>
            <SectionLabel>Informational — inline</SectionLabel>
            <div style={{ display: 'flex', gap: 10, alignItems: 'center', paddingTop: 8 }}>
              <Chip tone="success" icon="check">Saved</Chip>
              <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink3 }}>Just now · synced to cloud</div>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PatternEmpty, PatternLoading, PatternError, PatternConfirmation });

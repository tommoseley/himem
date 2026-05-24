const C = window.Crucible;
// Crucible — Components artboards
// Each component is shown with: variants · states · usage guidelines · do/don't

// ───────── Buttons ─────────
function ComponentButtons() {
  const Row = ({ label, children }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16 }}>
      <div style={{ width: 90, ...typeStyle(C.type.caption2), color: C.color.ink3, fontWeight: 700, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>{children}</div>
    </div>
  );
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Buttons</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Four variants, three sizes. One primary per screen — ember is a rare salt.
      </div>

      <SectionLabel>Variants — medium, default</SectionLabel>
      <Row label="Primary"><Button>Continue</Button><Button icon="plus">New entry</Button><Button iconOnly icon="mic"/></Row>
      <Row label="Secondary"><Button variant="secondary">Cancel</Button><Button variant="secondary" icon="search">Search</Button></Row>
      <Row label="Ghost"><Button variant="ghost">Skip</Button><Button variant="ghost" icon="calendar">Today</Button></Row>
      <Row label="Destructive"><Button variant="destructive">Delete</Button></Row>

      <div style={{ height: 24 }}/>
      <SectionLabel>States — primary</SectionLabel>
      <Row label="Default"><Button>Default</Button></Row>
      <Row label="Hover"><Button state="hover">Hover</Button></Row>
      <Row label="Pressed"><Button state="pressed">Pressed</Button></Row>
      <Row label="Loading"><Button state="loading">Saving…</Button></Row>
      <Row label="Disabled"><Button state="disabled">Disabled</Button></Row>

      <div style={{ height: 24 }}/>
      <SectionLabel>Sizes</SectionLabel>
      <Row label="Small"><Button size="sm">Small</Button><Button size="sm" variant="secondary">Small</Button></Row>
      <Row label="Medium"><Button size="md">Medium</Button><Button size="md" variant="secondary">Medium</Button></Row>
      <Row label="Large"><Button size="lg">Large</Button><Button size="lg" variant="secondary">Large</Button></Row>
    </div>
  );
}

function ComponentButtonsGuidance() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans }}>
      <EditorialTitle size="serif3">Buttons — guidance</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 28, marginTop: 4 }}>
        When to use which variant, and common mistakes.
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
        <GuidanceCard verdict="do" caption="One primary action per screen. Secondary + primary pair horizontally; primary goes right.">
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <Button variant="secondary">Cancel</Button>
            <Button>Save draft</Button>
          </div>
        </GuidanceCard>
        <GuidanceCard verdict="dont" caption="Two primary buttons compete. Pick one — demote the other to secondary or ghost.">
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <Button>Discard</Button>
            <Button>Save draft</Button>
          </div>
        </GuidanceCard>
        <GuidanceCard verdict="do" caption="Destructive actions use the destructive variant — never a primary.">
          <Button variant="destructive" icon="x">Delete memory</Button>
        </GuidanceCard>
        <GuidanceCard verdict="dont" caption="Primary buttons don't carry warnings. The color pulls attention toward the wrong path.">
          <Button>Delete memory</Button>
        </GuidanceCard>
        <GuidanceCard verdict="do" caption="Ghost buttons for tertiary and inline actions. They inherit layout weight from context.">
          <div style={{ display: 'flex', gap: 6 }}>
            <Button variant="ghost" size="sm">Today</Button>
            <Button variant="ghost" size="sm">This week</Button>
            <Button variant="ghost" size="sm">All time</Button>
          </div>
        </GuidanceCard>
        <GuidanceCard verdict="dont" caption="Don't stack secondary buttons in a vertical wall — use a list component instead.">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <Button variant="secondary" fullWidth>Today</Button>
            <Button variant="secondary" fullWidth>This week</Button>
            <Button variant="secondary" fullWidth>All time</Button>
          </div>
        </GuidanceCard>
      </div>
    </div>
  );
}

// ───────── Fields ─────────
function ComponentFields() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Fields</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 28, marginTop: 4 }}>
        Text input with optional icon, label, helper. States mirror focus rings from iOS 17+.
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
        <Field label="Default" placeholder="What did you learn today?"/>
        <Field label="With icon" placeholder="Search memories" icon="search"/>
        <Field label="Filled" value="A line I want to remember."/>
        <Field label="Focused" value="The light came in sideways" state="focus"/>
        <Field label="Error" value="" state="error" helper="A title is required."/>
        <Field label="Helper text" placeholder="Optional" helper="Private unless you share it."/>
        <Field label="Disabled" value="Read only" state="disabled"/>
        <Field label="Large" size="lg" placeholder="Quick capture" icon="mic"/>
      </div>
    </div>
  );
}

// ───────── Chips / badges / toggles / segmented ─────────
function ComponentMicro() {
  const Row = ({ label, children }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 18 }}>
      <div style={{ width: 110, ...typeStyle(C.type.caption2), color: C.color.ink3, fontWeight: 700, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>{children}</div>
    </div>
  );
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Chips, toggles & segments</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Small controls. Chips for status and filter, toggles for single boolean, segments for 2–4 mutually-exclusive options.
      </div>

      <SectionLabel>Chips — tones</SectionLabel>
      <Row label="Neutral"><Chip>Draft</Chip><Chip icon="clock">Saved just now</Chip></Row>
      <Row label="Accent"><Chip tone="accent">New</Chip><Chip tone="accent" icon="sparkle">AI</Chip></Row>
      <Row label="Success"><Chip tone="success" icon="check">Synced</Chip></Row>
      <Row label="Warning"><Chip tone="warn" icon="alert">Pending</Chip></Row>
      <Row label="Danger"><Chip tone="danger">Failed</Chip></Row>

      <div style={{ height: 20 }}/>
      <SectionLabel>Toggle</SectionLabel>
      <Row label="Off → On">
        <Toggle on={false}/><Toggle on={true}/>
      </Row>

      <div style={{ height: 8 }}/>
      <SectionLabel>Segmented</SectionLabel>
      <Row label="Default"><Segmented items={['Today','Week','Month']} active={0}/></Row>
      <Row label="Centered"><Segmented items={['List','Cards','Map']} active={1}/></Row>
    </div>
  );
}

// ───────── Cards & Sheets ─────────
function ComponentCards() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Cards & sheets</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Cards house content, sheets house tasks. Elevation carries both focus and importance.
      </div>

      <SectionLabel>Elevation</SectionLabel>
      <div style={{ display: 'flex', gap: 16, marginBottom: 28 }}>
        {[0, 1, 2, 3].map(l => (
          <Card key={l} elevation={l} style={{ width: 140, height: 100 }}>
            <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink3 }}>Level {l}</div>
            <div style={{ ...typeStyle(C.type.body), color: C.color.ink, marginTop: 8, fontWeight: 600 }}>{l === 0 ? 'Flat' : l === 1 ? 'Default' : l === 2 ? 'Raised' : 'Overlay'}</div>
          </Card>
        ))}
      </div>

      <SectionLabel>Content card</SectionLabel>
      <Card style={{ marginBottom: 20 }}>
        <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <div style={{ width: 4, alignSelf: 'stretch', background: C.color.accent, borderRadius: 2 }}/>
          <div style={{ flex: 1 }}>
            <div style={{ ...typeStyle(C.type.caption2), color: C.color.ink3, fontWeight: 700, textTransform: 'uppercase', marginBottom: 4 }}>Today · 11:28 am</div>
            <div style={{ ...typeStyle(C.type.headline), color: C.color.ink }}>A lane of late light on the kitchen floor.</div>
            <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, marginTop: 6 }}>Voice · 12s · auto-transcribed</div>
          </div>
          <Chip tone="accent" icon="sparkle">Tagged</Chip>
        </div>
      </Card>

      <SectionLabel>Bottom sheet</SectionLabel>
      <div style={{ display: 'flex', gap: 20 }}>
        <Sheet title="Confirm delete" width={320} height={280}>
          <div style={{ padding: '0 20px 20px' }}>
            <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, marginBottom: 20 }}>
              This entry will be moved to the trash. You have 30 days to restore it.
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <Button variant="destructive" fullWidth>Move to trash</Button>
              <Button variant="ghost" fullWidth>Cancel</Button>
            </div>
          </div>
        </Sheet>
      </div>
    </div>
  );
}

// ───────── Navigation ─────────
function ComponentNav() {
  return (
    <div style={{ padding: 40, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif3">Navigation</EditorialTitle>
      <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink2, maxWidth: 440, marginBottom: 24, marginTop: 4 }}>
        Large titles on mobile. Sidebar on tablet. Command bar on web.
      </div>

      <SectionLabel>iOS nav bar — large title</SectionLabel>
      <div style={{ background: C.color.paper, padding: '16px 0', marginBottom: 24 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0 16px', marginBottom: 6 }}>
          <Icon name="chevronL" size={20} color={C.color.accent}/>
          <Icon name="sparkle" size={20} color={C.color.accent}/>
        </div>
        <div style={{ padding: '0 16px', ...typeStyle(C.type.title1), color: C.color.ink }}>Memories</div>
      </div>

      <SectionLabel>iOS tab bar — trimmed to 4</SectionLabel>
      <div style={{
        display: 'flex', justifyContent: 'space-around', padding: '10px 20px',
        background: C.color.card, borderRadius: C.radius.lg, border: '1px solid ' + C.color.hairline,
        marginBottom: 24, maxWidth: 390,
      }}>
        {[['Today','clock',true],['Search','search'],['Ideas','sparkle'],['Me','calendar']].map(([n, ic, active]) => (
          <div key={n} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
            <Icon name={ic} size={22} color={active ? C.color.accent : C.color.ink3}/>
            <div style={{ ...typeStyle(C.type.caption2), color: active ? C.color.accent : C.color.ink3, fontWeight: 600, textTransform: 'none', letterSpacing: 0 }}>{n}</div>
          </div>
        ))}
      </div>

      <SectionLabel>Sidebar — iPadOS / Web</SectionLabel>
      <div style={{ display: 'flex', gap: 16 }}>
        <div style={{ width: 240, background: C.color.card, borderRadius: C.radius.md, padding: 16, border: '1px solid ' + C.color.hairline }}>
          <div style={{ ...typeStyle(C.type.caption2), color: C.color.ink3, fontWeight: 700, textTransform: 'uppercase', marginBottom: 10, padding: '0 8px' }}>Library</div>
          {[['Today','clock',true],['All memories','calendar'],['Ideas','sparkle'],['Favorites','bolt']].map(([n, ic, active]) => (
            <div key={n} style={{
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '8px 10px', borderRadius: 6,
              background: active ? C.color.accentTint : 'transparent',
              color: active ? C.color.accentPressed : C.color.ink,
              ...typeStyle(C.type.body), fontWeight: active ? 600 : 500, marginBottom: 2,
            }}>
              <Icon name={ic} size={18}/>
              <div>{n}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ComponentButtons, ComponentButtonsGuidance, ComponentFields, ComponentMicro, ComponentCards, ComponentNav });

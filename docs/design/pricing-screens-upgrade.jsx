// pricing-screens-upgrade.jsx
// 3 · The upgrade moment — an offer, never a wall.
//   C1 · After a glance (once-ever) — fires right after the user keeps their
//        first draft. They've just felt the value → offer to deepen it.
//        Framed as capability ("reach"), never as "you're missing out", and
//        never implying Plus is less private.
//   C3 · Settings (always present) — the "never a wall" baseline. Even users
//        who said "Not now" to C1 can find Plus here.
// C2 (the "you've organized 12 by hand" counter) was rejected — surveillant,
// reintroduces counting. Not built.

// C1 · After-a-glance nudge --------------------------------------------------
function ScrUpgradeC1() {
  return (
    <PhoneScreen>
      <MemHeader />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 13, paddingTop: 6 }}>
        <div style={{ margin: '0 14px' }}><OrganizeChip variant="done" /></div>
        <OrganizedBody />

        {/* the offer — AI-blue, because it's about the organize/connect capability */}
        <div style={{
          margin: '4px 14px 0', background: PX.aiTint, border: '1px solid ' + PX.ai,
          borderRadius: 14, padding: '14px 15px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 7 }}>
            <span style={{
              width: 24, height: 24, borderRadius: 7, background: PX.ai, color: '#fff',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
            }}><Spark size={14} color="#fff" /></span>
            <span style={{ fontSize: 14, fontWeight: 600, color: PX.ink }}>Want this to just happen?</span>
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.5, marginBottom: 12 }}>
            Plus organizes every memory the moment you capture it — and reaches across your library to connect what belongs together.
          </div>
          <div style={{ display: 'flex', gap: 9 }}>
            <Btn kind="accent" size="md" full={false} style={{ flex: 1 }}>See Plus</Btn>
            <Btn kind="ghost" size="md" full={false} style={{ flex: '0 0 auto' }}>Not now</Btn>
          </div>
        </div>
        <div style={{ fontSize: 10.5, color: PX.ink3, textAlign: 'center' }}>Shown once. Never again inline.</div>
        <div style={{ flex: 1 }} />
      </div>
    </PhoneScreen>
  );
}

// C3 · Settings entry (always present) --------------------------------------
function ScrUpgradeC3() {
  return (
    <PhoneScreen>
      <NavBar title="Settings" back="" large />
      <div style={{ flex: 1, overflow: 'hidden', paddingTop: 4 }}>
        {/* Plus card */}
        <div style={{
          margin: '0 14px 18px', background: PX.card, border: '1px solid ' + PX.accent,
          borderRadius: 16, padding: '15px 16px',
        }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 4 }}>
            <SerifH size={20} style={{ color: PX.accent }}>HiMem Plus</SerifH>
            <span style={{ fontSize: 12.5, color: PX.ink3 }}>from $6.99/mo</span>
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.5, marginBottom: 12 }}>
            Automatic organizing, memories that connect themselves, and unlimited projects.
          </div>
          <Btn kind="accent" size="md">See plans</Btn>
        </div>

        <ListGroup header="AI &amp; Organizing">
          <ListRow icon={<Spark size={14} />} title="Organizing" value="Manual" />
          <ListRow icon={<Proj size={14} />} title="Projects" value="1 of 3" />
        </ListGroup>
        <div style={{ height: 16 }} />
        <ListGroup header="Your memories">
          <ListRow icon={<Mem size={14} />} title="Memory Box" />
          <ListRow title="Captured Clips" value="0" />
          <ListRow title="Recently Deleted" />
        </ListGroup>
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrUpgradeC1, ScrUpgradeC3,
});

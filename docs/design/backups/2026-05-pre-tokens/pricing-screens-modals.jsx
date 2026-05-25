// pricing-screens-modals.jsx
// Modal / event screens: upgrade prompt (2 variants), soft 75% toast,
// hard 100% fair-use (2 variants), project cap, AI pack purchase sheet,
// founders detail, founders cap-hit.

// ─────────────────────────────────────────────────────────────
// Lightweight "behind" mocks used inside sheets/modals
// ─────────────────────────────────────────────────────────────
function BehindToday() {
  return (
    <div style={{ width: 340, height: 735, background: PX.paper, padding: '48px 0 0', fontFamily: PX.sans }}>
      <div style={{ padding: '14px 20px 10px' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 }}>Thursday, May 15</div>
        <div style={{ fontFamily: PX.serif, fontSize: 32, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, marginTop: 6 }}>Today</div>
      </div>
      <div style={{ padding: '4px 16px' }}>
        {[
          { topic: '#2F9E6B', t: '7:42 pm', body: 'The pear tree finally fruited. Three pears, the size of fists.' },
          { topic: '#E2763A', t: '12:15 pm', body: 'Tomato seedlings outgrowing the windowsill — ready to move out.' },
          { topic: '#C08A1F', t: '9:02 am', body: 'Idea: the watch should auto-stop on wrist-off. Never lose a recording.' },
        ].map((e, i) => (
          <div key={i} style={{
            background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
            padding: '12px 14px', marginBottom: 8,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: e.topic }}/>
              <span style={{ fontSize: 11, color: PX.ink3, letterSpacing: 0.2 }}>{e.t}</span>
            </div>
            <div style={{ fontFamily: PX.serif, fontSize: 14, lineHeight: 1.4, color: PX.ink }}>{e.body}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function BehindProjects() {
  return (
    <div style={{ width: 340, height: 735, background: PX.paper, padding: '48px 0 0', fontFamily: PX.sans }}>
      <div style={{ padding: '14px 20px 10px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, letterSpacing: -0.4, color: PX.ink }}>Projects</div>
      </div>
      <div style={{ padding: '4px 14px' }}>
        <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, padding: '14px 16px' }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: PX.ink }}>The garden, year three</div>
          <div style={{ fontSize: 12, color: PX.ink3, marginTop: 3 }}>184 memories · since March 2024</div>
        </div>
      </div>
    </div>
  );
}

function BehindMemoryWithAI() {
  return (
    <div style={{ width: 340, height: 735, background: PX.paper, padding: '48px 0 0', fontFamily: PX.sans }}>
      <div style={{ padding: '8px 18px 0' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>Today · 4:18 pm</div>
        <div style={{ fontFamily: PX.serif, fontSize: 22, lineHeight: 1.2, color: PX.ink, marginBottom: 16 }}>
          The library smelled of old wood today. Marigolds on the front desk.
        </div>
        <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 10, opacity: 0.6 }}>
          <div style={{ width: 32, height: 32, borderRadius: 8, background: PX.accent, color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <Spark size={18}/>
          </div>
          <div>
            <div style={{ fontSize: 15, fontWeight: 600, color: PX.ink }}>Organize with AI</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A. Upgrade prompt — V1 "Honest two-path" (matches spec copy)
// Fires once when trigger met (3 starter used + ≥5 memories).
// ─────────────────────────────────────────────────────────────
function ScrUpgradePromptA() {
  return (
    <PhoneScreen statusDark={false}>
      <Sheet behind={<BehindToday/>} height="80%">
        <div style={{ padding: '14px 22px 28px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{
            width: 36, height: 36, borderRadius: 10, background: PX.accent, color: '#fff',
            display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 18,
          }}>
            <Spark size={20}/>
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 26, lineHeight: 1.15, letterSpacing: -0.3, color: PX.ink, marginBottom: 10 }}>
            You've built a HiMem habit.
          </div>
          <div style={{ fontSize: 14.5, color: PX.ink2, lineHeight: 1.5, marginBottom: 22 }}>
            You're out of starter AI assists. Keep going?
          </div>

          {/* Option A: Pack */}
          <button style={{
            background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
            padding: '14px 16px', textAlign: 'left', marginBottom: 10, cursor: 'default',
          }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 4 }}>
              <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Add 20 AI assists</span>
              <span style={{ flex: 1 }}/>
              <span style={{ fontFamily: PX.serif, fontSize: 18, fontWeight: 500, color: PX.ink }}>$4.99</span>
            </div>
            <div style={{ fontSize: 12.5, color: PX.ink3 }}>One-time. Never expires.</div>
          </button>

          {/* Option B: Plus */}
          <button style={{
            background: PX.ink, color: '#FFFCF6', border: 'none', borderRadius: 14,
            padding: '14px 16px', textAlign: 'left', marginBottom: 14, cursor: 'default',
          }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 4 }}>
              <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.2 }}>Subscribe to HiMem Plus</span>
              <span style={{ flex: 1 }}/>
              <span style={{ fontFamily: PX.serif, fontSize: 18, fontWeight: 500 }}>$4.99/mo</span>
            </div>
            <div style={{ fontSize: 12.5, opacity: 0.65 }}>50 assists / month · unlimited projects · auto-organize.</div>
          </button>

          <div style={{ flex: 1 }}/>

          <button style={{
            background: 'transparent', border: 'none', color: PX.ink2,
            fontSize: 15, fontWeight: 500, padding: '12px 0', cursor: 'default',
          }}>Not now</button>
          <div style={{ fontSize: 11, color: PX.ink3, textAlign: 'center', marginTop: 4, lineHeight: 1.5 }}>
            Free keeps working forever. You can buy assists later from Settings.
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// B. Upgrade prompt — V2 "What continues / what pauses"
// Same two paid paths, but no per-assist math (math belongs in
// Settings and pack purchase, not at an emotional moment). Frames
// the decision around scope: what HiMem still does for free vs
// what AI was helping with.
// ─────────────────────────────────────────────────────────────
function ScrUpgradePromptB() {
  return (
    <PhoneScreen>
      <Sheet behind={<BehindToday/>} height="86%">
        <div style={{ padding: '14px 22px 26px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ fontFamily: PX.serif, fontSize: 22, lineHeight: 1.2, letterSpacing: -0.3, color: PX.ink, marginBottom: 4 }}>
            You've used your starter AI.
          </div>
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginBottom: 18 }}>
            HiMem keeps working without it. Here's what changes.
          </div>

          {/* Continues / pauses */}
          <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden', marginBottom: 16 }}>
            <div style={{ padding: '12px 14px', borderBottom: '1px solid ' + PX.divider }}>
              <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.confirmed, marginBottom: 8 }}>Continues, free</div>
              {[
                'Capture from watch and phone',
                'Saved to Memory Box, forever',
                'Manual organization, tags, search',
              ].map(s => (
                <div key={s} style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '3px 0', fontSize: 13, color: PX.ink, letterSpacing: -0.1 }}>
                  <Check size={13} color={PX.confirmed}/>{s}
                </div>
              ))}
            </div>
            <div style={{ padding: '12px 14px' }}>
              <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.warn, marginBottom: 8 }}>Pauses without AI</div>
              {[
                'Auto-titles and grouping',
                'Related-entry suggestions',
                'Topic and place inferences',
              ].map(s => (
                <div key={s} style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '3px 0', fontSize: 13, color: PX.ink2, letterSpacing: -0.1 }}>
                  <span style={{ width: 13, height: 1.5, background: PX.ink4, borderRadius: 1 }}/>{s}
                </div>
              ))}
            </div>
          </div>

          <div style={{ flex: 1 }}/>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <Btn kind="primary">Subscribe to Plus · $4.99/mo</Btn>
            <Btn kind="secondary">Continue with 20-pack · $4.99</Btn>
            <Btn kind="ghost" size="md">Not now</Btn>
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// Supporter · Settings entry (post-trust)
// Appears only after ≥1 month + ≥10 memories. Settings-only, never
// in onboarding or upgrade. The entry is intentionally quiet —
// no badge, no pulse, no upsell language.
// ─────────────────────────────────────────────────────────────
function ScrSupporterSettings({ t }) {
  const eligible = !!t.tenured;
  return (
    <PhoneScreen>
      <NavBar back="" title="Settings" large/>
      <div style={{ padding: '4px 0 28px', overflow: 'auto', flex: 1 }}>

        <ListGroup>
          <ListRow icon={<Mem size={14}/>} title="Your AI" detail="Allowance, packs, plan" multiline/>
          <ListRow icon={<Proj size={14}/>} title="Projects" value="1"/>
          <ListRow icon={<Spark size={14}/>} title="HiMem Plus" detail="Upgrade or manage" multiline/>
        </ListGroup>

        <ListGroup header="Capture" style={{ marginTop: 20 }}>
          <ListRow icon={<Mem size={14}/>} title="Captured Clips" value="0 new"/>
          <ListRow icon={<Proj size={14}/>} title="Watch companion" value="On"/>
        </ListGroup>

        {/* Supporter row — tenured only */}
        {eligible && (
          <ListGroup
            header="Behind HiMem"
            style={{ marginTop: 20 }}
            footer="Voluntary. No feature unlocks. We surface this only after you've stuck around."
          >
            <ListRow
              icon={<svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M7 12.5S1.5 9 1.5 5.3a3 3 0 015.5-1.6 3 3 0 015.5 1.6C12.5 9 7 12.5 7 12.5z"/></svg>}
              title="Support HiMem"
              detail="Help us keep building, no strings."
              multiline
            />
          </ListGroup>
        )}

        <ListGroup header="About" style={{ marginTop: 20 }}>
          <ListRow icon={<Mem size={14}/>} title="Privacy"/>
          <ListRow icon={<Mem size={14}/>} title="Help &amp; feedback"/>
          <ListRow icon={<Mem size={14}/>} title="Version" value="1.0.0" chevron={false}/>
        </ListGroup>

        {!eligible && (
          <div style={{ fontSize: 11, color: PX.ink3, padding: '20px 22px 0', lineHeight: 1.55, fontStyle: 'italic' }}>
            Supporter row hidden until ≥1 month of use + ≥10 memories saved. Never surfaces in onboarding or upgrade.
          </div>
        )}
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// Supporter · detail
// No feature unlocks. Just an honest "this helps us keep going."
// $2.99/mo or $29.99/yr (two months free). Single price, editorial copy.
// ─────────────────────────────────────────────────────────────
function ScrSupporterDetail() {
  return (
    <PhoneScreen>
      <NavBar back="Settings" title="Support HiMem"/>
      <div style={{ padding: '8px 22px 28px', overflow: 'auto', flex: 1 }}>

        <div style={{ padding: '18px 0 6px' }}>
          <div style={{ width: 38, height: 38, borderRadius: 11, background: PX.accentTint, color: PX.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 18 }}>
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M10 17.5S2.5 12.5 2.5 7.5A4 4 0 0110 5a4 4 0 017.5 2.5C17.5 12.5 10 17.5 10 17.5z"/></svg>
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 26, lineHeight: 1.15, letterSpacing: -0.4, color: PX.ink, marginBottom: 12 }}>
            Help us keep building, on your terms.
          </div>
          <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.55, marginBottom: 8 }}>
            HiMem is small, independent, and has no ads. If it's earning its place on your phone, you can chip in.
          </div>
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.55 }}>
            <strong style={{ color: PX.ink, fontWeight: 600 }}>This unlocks nothing.</strong> Free stays free. Plus stays Plus. Supporters just help cover the bill.
          </div>
        </div>

        <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{
            background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
            padding: '14px 16px',
          }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
              <span style={{ fontSize: 14, fontWeight: 600, color: PX.ink }}>Monthly</span>
              <span style={{ flex: 1 }}/>
              <span style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 500, color: PX.ink }}>$2.99</span>
              <span style={{ fontSize: 12, color: PX.ink3 }}>/month</span>
            </div>
          </div>
          <div style={{
            background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
            padding: '14px 16px',
          }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
              <span style={{ fontSize: 14, fontWeight: 600, color: PX.ink }}>Yearly</span>
              <span style={{ flex: 1 }}/>
              <span style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 500, color: PX.ink }}>$29.99</span>
              <span style={{ fontSize: 12, color: PX.ink3 }}>/year</span>
            </div>
            <div style={{ fontSize: 12, color: PX.ink3, marginTop: 6 }}>The two-months-free option.</div>
          </div>
        </div>

        <div style={{ marginTop: 20, padding: '14px 16px', background: PX.sunk, borderRadius: 12 }}>
          <div style={{ fontSize: 11.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
            What you get
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.55 }}>
            Our thanks. A small heart in Settings. The knowledge that an indie app you like keeps shipping. That's it.
          </div>
        </div>

        <div style={{ marginTop: 22 }}>
          <Btn kind="primary">Become a supporter · $2.99/mo</Btn>
        </div>
        <div style={{ fontSize: 11, color: PX.ink3, textAlign: 'center', marginTop: 10, lineHeight: 1.55 }}>
          Cancel any time. Nothing about HiMem changes if you do.
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// Soft 75% — toast on Today
// ─────────────────────────────────────────────────────────────
function ScrSoft75() {
  return (
    <PhoneScreen>
      <div style={{ padding: '14px 20px 6px' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 }}>Thursday, May 15</div>
        <div style={{ fontFamily: PX.serif, fontSize: 32, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, marginTop: 6, marginBottom: 12 }}>Today</div>
      </div>

      <Toast>
        <div style={{ fontWeight: 700, marginBottom: 2 }}>38 of 50 assists used this month</div>
        <div style={{ fontSize: 12, fontWeight: 400, opacity: 0.85 }}>Resets Jun 1. Add more any time.</div>
      </Toast>

      <div style={{ padding: '12px 14px 0', overflow: 'hidden' }}>
        {[
          { topic: '#2F9E6B', t: '7:42 pm', body: 'The pear tree finally fruited. Three pears, the size of fists, hidden behind the leaves.' },
          { topic: '#E2763A', t: '12:15 pm', body: 'Tomato seedlings outgrowing the windowsill — ready to move out.' },
          { topic: '#C08A1F', t: '9:02 am', body: 'Idea: the watch should auto-stop on wrist-off. Never lose a recording.' },
          { topic: '#4A5C6E', t: 'Yesterday', body: 'The library smelled of old wood today. Marigolds on the front desk.' },
        ].map((e, i) => (
          <div key={i} style={{
            background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
            padding: '12px 14px', marginBottom: 8,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: e.topic }}/>
              <span style={{ fontSize: 11, color: PX.ink3, letterSpacing: 0.2 }}>{e.t}</span>
            </div>
            <div style={{ fontFamily: PX.serif, fontSize: 14, lineHeight: 1.4, color: PX.ink }}>{e.body}</div>
          </div>
        ))}
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// C. Hard 100% — V1 "Modal block" (spec literal)
// Triggered at point of consumption when monthly + packs both empty.
// ─────────────────────────────────────────────────────────────
function ScrHard100A() {
  return (
    <PhoneScreen>
      <Sheet behind={<BehindMemoryWithAI/>} height="68%">
        <div style={{ padding: '14px 22px 26px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{
            width: 32, height: 32, borderRadius: 9, background: PX.warnTint, color: '#7A4A0E',
            display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14,
          }}>
            <Spark size={18}/>
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 22, lineHeight: 1.2, letterSpacing: -0.3, color: PX.ink, marginBottom: 10 }}>
            You've used this month's AI.
          </div>
          <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.5, marginBottom: 16 }}>
            Your 50 included assists reset on <strong style={{ color: PX.ink }}>Jun 1</strong>. Add more if you'd like HiMem to keep helping right now.
          </div>

          <div style={{ display: 'flex', gap: 10, marginBottom: 14 }}>
            <PackTileLite assists={20} price="$4.99" per="$0.25 each"/>
            <PackTileLite assists={100} price="$19.99" per="$0.20 each" tag="Better"/>
          </div>

          <div style={{ fontSize: 11.5, color: PX.ink3, lineHeight: 1.5, padding: '0 2px' }}>
            Pack assists never expire and stack on top of your monthly allowance.
          </div>

          <div style={{ flex: 1 }}/>

          <Btn kind="ghost" size="md">Wait until Jun 1</Btn>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// D. Hard 100% — V2 "Inline · quiet"
// The Organize card shifts to its exhausted state. No scrim, no
// modal. The user gets the message at the place they tried to act.
// ─────────────────────────────────────────────────────────────
function ScrHard100B() {
  return <ScrOrganizeExhausted/>;
}

function PackTileLite({ assists, price, per, tag }) {
  return (
    <div style={{
      flex: 1, background: PX.paper, border: '1px solid ' + PX.hairline, borderRadius: 12,
      padding: '10px 12px', position: 'relative',
    }}>
      {tag && (
        <span style={{
          position: 'absolute', top: -7, right: 8,
          background: PX.accent, color: '#fff', fontSize: 9.5, fontWeight: 700,
          padding: '2px 6px', borderRadius: 5, letterSpacing: 0.3, textTransform: 'uppercase',
        }}>{tag}</span>
      )}
      <div style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 500, color: PX.ink, lineHeight: 1, marginBottom: 1 }}>{assists}</div>
      <div style={{ fontSize: 11, color: PX.ink3, marginBottom: 6 }}>assists</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: PX.ink }}>{price}</div>
      <div style={{ fontSize: 10.5, color: PX.ink3, fontFamily: PX.mono }}>{per}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Project cap — Free user trying to create 2nd project
// ─────────────────────────────────────────────────────────────
function ScrProjectCap() {
  return (
    <PhoneScreen>
      <Sheet behind={<BehindProjects/>} height="54%">
        <div style={{ padding: '14px 22px 26px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{
            width: 32, height: 32, borderRadius: 9, background: PX.accentTint, color: PX.accent,
            display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14,
          }}>
            <Proj size={18}/>
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 22, lineHeight: 1.2, letterSpacing: -0.3, color: PX.ink, marginBottom: 10 }}>
            Free includes one project.
          </div>
          <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.5, marginBottom: 6 }}>
            Plus opens up as many as you want — keep work, family, and the garden in their own spaces.
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.5 }}>
            You can also tag memories inside your existing project — that's free.
          </div>

          <div style={{ flex: 1 }}/>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <Btn kind="primary">Upgrade to Plus · $4.99/mo</Btn>
            <Btn kind="ghost" size="md">Maybe later</Btn>
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// AI Pack purchase sheet — standalone, from Settings → "Add AI assists"
// ─────────────────────────────────────────────────────────────
function ScrPackPurchase() {
  return (
    <PhoneScreen>
      <Sheet behind={<div style={{ width: 340, height: 735, background: PX.paper }}/>} height="72%">
        <div style={{ padding: '14px 18px 24px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 14 }}>
            <span style={{ flex: 1 }}/>
            <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink }}>Add AI assists</span>
            <span style={{ flex: 1 }}/>
            <span style={{ position: 'absolute', right: 22, top: 16, fontSize: 14, color: PX.accent, fontWeight: 500 }}>Done</span>
          </div>

          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginBottom: 18 }}>
            Pack assists never expire and stack on top of your monthly allowance.
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <PackPickRow assists={20} price="$4.99" per="$0.25 / assist"/>
            <PackPickRow assists={100} price="$19.99" per="$0.20 / assist · 20% off" featured/>
          </div>

          <div style={{ marginTop: 18, padding: '12px 14px', borderRadius: 12, background: PX.sunk }}>
            <div style={{ fontSize: 11.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
              A note on rates
            </div>
            <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.5 }}>
              Plus is <strong style={{ color: PX.ink }}>$0.10 / assist</strong> at the same monthly cost as a 20-pack. If you find yourself buying packs often, Plus saves money.
            </div>
          </div>

          <div style={{ flex: 1 }}/>

          <Btn kind="primary">Buy 100 assists · $19.99</Btn>
          <div style={{ fontSize: 11, color: PX.ink3, textAlign: 'center', marginTop: 10, lineHeight: 1.5 }}>
            One-time purchase via App Store. Restore Purchases in Settings.
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

function PackPickRow({ assists, price, per, featured }) {
  return (
    <div style={{
      background: featured ? PX.accentTint : PX.card,
      border: '1px solid ' + (featured ? PX.accentTint2 : PX.hairline),
      borderRadius: 14, padding: '14px 16px',
      display: 'flex', alignItems: 'center', gap: 14,
    }}>
      <div style={{
        width: 44, height: 44, borderRadius: 11, background: featured ? PX.accent : PX.accentTint,
        color: featured ? '#fff' : PX.accent, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Spark size={20}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
          <span style={{ fontFamily: PX.serif, fontSize: 20, fontWeight: 500, color: PX.ink, letterSpacing: -0.3 }}>{assists}</span>
          <span style={{ fontSize: 13, color: PX.ink2 }}>assists</span>
        </div>
        <div style={{ fontSize: 11.5, color: PX.ink3, fontFamily: PX.mono, marginTop: 2 }}>{per}</div>
      </div>
      <div style={{ fontFamily: PX.serif, fontSize: 20, fontWeight: 500, color: PX.ink, letterSpacing: -0.3 }}>{price}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Founders Lifetime — detail screen
// ─────────────────────────────────────────────────────────────
function ScrFoundersDetail({ t }) {
  const closed = t.foundersRemaining <= 0;
  const lowStock = t.foundersRemaining > 0 && t.foundersRemaining <= 25;
  return (
    <PhoneScreen>
      <NavBar back="Plans" title="Founders"/>
      <div style={{ padding: '12px 18px 28px', overflow: 'auto', flex: 1 }}>
        <div style={{
          background: PX.ink, color: '#FFFCF6', borderRadius: 18, padding: '22px 20px',
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', opacity: 0.65, marginBottom: 10 }}>
            HiMem Founders
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 32, lineHeight: 1.05, letterSpacing: -0.6, marginBottom: 14 }}>
            Pay once.<br/>Helped early.
          </div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 18 }}>
            <span style={{ fontFamily: PX.serif, fontSize: 38, fontWeight: 500, letterSpacing: -0.6 }}>$99</span>
            <span style={{ fontSize: 13, opacity: 0.65 }}>one-time</span>
          </div>

          {closed ? (
            <div style={{ fontSize: 13, opacity: 0.7, lineHeight: 1.45 }}>
              All 250 Founders seats are claimed. Thank you.
            </div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: lowStock ? '#FFCE9A' : '#FFCE9A' }}/>
              <span style={{ fontFamily: PX.mono, fontSize: 12, opacity: 0.85, letterSpacing: 0.3 }}>
                {t.foundersRemaining} of 250 remaining
              </span>
            </div>
          )}
        </div>

        <div style={{ marginTop: 20 }}>
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, marginBottom: 10 }}>
            What you get
          </div>
          {[
            { t: 'HiMem Plus, for life', d: 'Auto-organize, unlimited projects, 50 assists/mo. No renewal.' },
            { t: '100 bonus assists at purchase', d: 'Into your pack balance. Never expires.' },
            { t: 'TestFlight access', d: 'Builds before they ship. See what\u2019s coming.' },
            { t: 'Early feature flags', d: 'Toggle new things on before everyone else.' },
          ].map((b, i, arr) => (
            <div key={i} style={{ display: 'flex', gap: 12, padding: '10px 4px', borderBottom: i < arr.length - 1 ? '1px solid ' + PX.divider : 'none' }}>
              <div style={{ width: 18, height: 18, borderRadius: 9, background: PX.confirmedTint, color: PX.confirmed, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: 1 }}>
                <Check size={11}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>{b.t}</div>
                <div style={{ fontSize: 12, color: PX.ink3, marginTop: 2, lineHeight: 1.4 }}>{b.d}</div>
              </div>
            </div>
          ))}
        </div>

        <div style={{ fontSize: 11.5, color: PX.ink3, padding: '18px 4px 22px', lineHeight: 1.55 }}>
          Studio (multi-memory synthesis) ships post-MVP and isn&rsquo;t included.
        </div>

        {closed ? (
          <Btn kind="secondary">See Plus plans instead</Btn>
        ) : (
          <Btn kind="primary">Become a Founder · $99</Btn>
        )}
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrUpgradePromptA, ScrUpgradePromptB, ScrSoft75, ScrHard100A, ScrHard100B,
  ScrProjectCap, ScrPackPurchase, ScrFoundersDetail,
  ScrSupporterSettings, ScrSupporterDetail,
  BehindToday, BehindProjects, BehindMemoryWithAI, PackTileLite, PackPickRow,
});

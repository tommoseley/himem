// pricing-screens-settings.jsx
// Stable-state screens: onboarding starter, inline counter, Settings · Your AI,
// Settings · Upgrade hub. Each takes a `t` (tweaks) prop.

// Helpers --------------------------------------------------------------------

function monthlyRemaining(t) {
  if (t.tier === 'free') return 0;
  return Math.max(0, 50 - t.monthlyUsed);
}
function isPlus(t) { return t.tier === 'plus_monthly' || t.tier === 'plus_yearly' || t.tier === 'founders'; }
function tierLabel(t) {
  return { free: 'Free', plus_monthly: 'Plus · Monthly', plus_yearly: 'Plus · Yearly', founders: 'Founders Lifetime' }[t.tier];
}

// ─────────────────────────────────────────────────────────────
// 1. Onboarding · starter assists — "what is AI organize"
// One-time card the first time the user encounters an "Organize with AI" button.
// ─────────────────────────────────────────────────────────────
function ScrOnboardingStarter() {
  return (
    <PhoneScreen>
      <div style={{ padding: '40px 22px 0', display: 'flex', flexDirection: 'column', height: '100%' }}>
        <div style={{
          width: 56, height: 56, borderRadius: 16, background: PX.accent, color: '#fff',
          display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 24,
        }}>
          <Spark size={26}/>
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 28, lineHeight: 1.15, letterSpacing: -0.4, color: PX.ink, marginBottom: 14 }}>
          AI can help organize your memories.
        </div>
        <div style={{ fontSize: 15, lineHeight: 1.5, color: PX.ink2, marginBottom: 22 }}>
          It suggests titles, groups related entries, and finds patterns you've written about. You stay in control — every suggestion is yours to accept or skip.
        </div>

        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
          padding: '14px 16px', marginBottom: 10,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
            <span style={{ fontSize: 22, fontWeight: 600, fontFamily: PX.serif, color: PX.ink }}>3</span>
            <span style={{ fontSize: 14, color: PX.ink2 }}>starter AI assists, on the house</span>
          </div>
          <div style={{ fontSize: 12.5, lineHeight: 1.5, color: PX.ink3 }}>
            Try it on a few memories. After that, you can add more or subscribe to Plus for 50 every month.
          </div>
        </div>

        <div style={{ fontSize: 11, color: PX.ink3, lineHeight: 1.5, padding: '4px 4px 0' }}>
          Your memories stay yours — AI is the helper, never the keeper. You can use HiMem without it for as long as you like.
        </div>

        <div style={{ flex: 1 }} />

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, paddingBottom: 28 }}>
          <Btn kind="primary">Try it on a memory</Btn>
          <Btn kind="ghost" size="md">Not now</Btn>
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 2. Organize with AI — one button, whole-memory pass.
// Idle  → bottom card with the action + what 1 assist gets you.
// Done  → memory is now organized: title (serif), summary, topics,
//         next steps, related. Re-organize affordance at the bottom.
// Out   → same card, muted. Quiet "Resets Jun 1 · See options →".
// Rules: accepting individual outputs = free. Manual edits = free.
//        Re-organize after new clips = 1 assist. Failures = 0.
// ─────────────────────────────────────────────────────────────

function OrganizeCard({ state }) {
  if (state === 'exhausted') {
    return (
      <div style={{
        background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
        padding: '14px 14px', display: 'flex', alignItems: 'center', gap: 12,
        margin: '18px 0 6px',
      }}>
        <div style={{
          width: 36, height: 36, borderRadius: 9, background: PX.warnTint, color: '#7A4A0E',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          <Spark size={18}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>Organize with AI</div>
          <div style={{ fontSize: 12, color: PX.ink3, marginTop: 2 }}>Used this month's AI · resets Jun 1</div>
        </div>
        <span style={{ fontSize: 12.5, color: PX.accent, fontWeight: 500, letterSpacing: -0.1 }}>
          See options →
        </span>
      </div>
    );
  }
  if (state === 'reorganize') {
    return (
      <div style={{
        background: 'rgba(198,74,28,0.05)', border: '1px dashed rgba(198,74,28,0.3)', borderRadius: 14,
        padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 12,
        margin: '20px 0 6px',
      }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>3 new clips since last organize</div>
          <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 2 }}>Re-organize folds them in · 1 assist</div>
        </div>
        <span style={{
          fontSize: 12, fontWeight: 600, color: '#fff', background: PX.accent,
          padding: '7px 12px', borderRadius: 8, letterSpacing: -0.1,
        }}>Re-organize</span>
      </div>
    );
  }
  // idle
  return (
    <button style={{
      width: '100%', background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '14px 14px', display: 'flex', alignItems: 'flex-start', gap: 12,
      cursor: 'default', textAlign: 'left', margin: '18px 0 6px',
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 9, background: PX.accent, color: '#fff',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>
        <Spark size={18}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Organize with AI</span>
          <span style={{ flex: 1 }}/>
          <span style={{
            fontSize: 10.5, fontWeight: 700, color: PX.accent, background: PX.accentTint,
            padding: '3px 7px', borderRadius: 6, letterSpacing: 0.4,
          }}>1 ASSIST</span>
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 4, lineHeight: 1.45 }}>
          Suggests a title, summary, topics, next steps, and related memories. Accept what you like.
        </div>
      </div>
    </button>
  );
}

function MemoryBlock({ organized }) {
  const tags = organized ? ['Garden', 'Backyard', 'Pear tree', 'Year three'] : ['Garden', 'Backyard'];
  return (
    <React.Fragment>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>
        Yesterday · 7:42 pm
      </div>

      {organized && (
        <div style={{
          fontFamily: PX.serif, fontSize: 26, lineHeight: 1.15, letterSpacing: -0.4,
          color: PX.ink, marginBottom: 6,
        }}>Pears, year three</div>
      )}

      <div style={{
        fontFamily: PX.serif, fontSize: organized ? 16 : 22, lineHeight: organized ? 1.42 : 1.22, letterSpacing: -0.2,
        color: organized ? PX.ink2 : PX.ink, marginBottom: 12,
      }}>
        The pear tree finally fruited. Three pears, the size of fists, hidden behind the leaves near the back fence.
      </div>

      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 14 }}>
        {tags.map(t => (
          <span key={t} style={{
            fontSize: 12, fontWeight: 500, color: PX.ink2,
            padding: '4px 10px', borderRadius: 10, background: 'rgba(26,22,18,0.05)',
          }}>{t}</span>
        ))}
      </div>

      {/* Audio peek */}
      <div style={{
        background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 12,
        padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10,
      }}>
        <div style={{ width: 28, height: 28, borderRadius: 14, background: PX.accentTint, color: PX.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="10" height="11" viewBox="0 0 10 11" fill="currentColor"><path d="M1 1v9l8-4.5z"/></svg>
        </div>
        <div style={{ flex: 1, height: 14, display: 'flex', gap: 1.5, alignItems: 'center' }}>
          {Array.from({ length: 28 }).map((_, i) => (
            <span key={i} style={{ width: 2, height: 3 + (Math.sin(i*0.7)+1)*5, borderRadius: 1, background: i < 8 ? PX.accent : PX.ink4 }}/>
          ))}
        </div>
        <span style={{ fontFamily: PX.mono, fontSize: 11, color: PX.ink3 }}>0:42</span>
      </div>
    </React.Fragment>
  );
}

function OrgSection({ label, children, byAi }) {
  return (
    <div style={{ marginTop: 18 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <span style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3 }}>{label}</span>
        {byAi && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10, color: PX.accent, opacity: 0.8 }}>
            <Spark size={9}/>AI
          </span>
        )}
      </div>
      <div style={{ fontSize: 13.5, color: PX.ink, lineHeight: 1.5, letterSpacing: -0.1 }}>
        {children}
      </div>
    </div>
  );
}

function ScrOrganizeIdle() {
  return (
    <PhoneScreen>
      <NavBar back="Today" title="Memory" trailing={
        <span style={{ color: PX.accent, fontSize: 15, fontWeight: 500 }}>Edit</span>
      }/>
      <div style={{ padding: '8px 18px 24px', overflow: 'auto', flex: 1 }}>
        <MemoryBlock organized={false}/>
        <OrganizeCard state="idle"/>
        <div style={{ fontSize: 11, color: PX.ink3, padding: '8px 4px 0', lineHeight: 1.5 }}>
          Or keep it as-is. HiMem works fine without organizing.
        </div>
      </div>
    </PhoneScreen>
  );
}

function ScrOrganizeDone() {
  return (
    <PhoneScreen>
      <NavBar back="Today" title="Memory" trailing={
        <span style={{ color: PX.accent, fontSize: 15, fontWeight: 500 }}>Edit</span>
      }/>
      <div style={{ padding: '8px 18px 24px', overflow: 'auto', flex: 1 }}>
        <MemoryBlock organized={true}/>

        <OrgSection label="Summary" byAi>
          A late-season win in the back corner. Three pears found hidden behind the leaves — the tree's third year.
        </OrgSection>

        <OrgSection label="Next steps" byAi>
          <ul style={{ margin: 0, paddingLeft: 18, lineHeight: 1.55 }}>
            <li>Check ripeness in a few days.</li>
            <li>Photograph the spot before frost.</li>
          </ul>
        </OrgSection>

        <OrgSection label="Related memories" byAi>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 2 }}>
            {[
              { d: 'Apr 12, 2025', body: 'Pruned the pear tree this morning. Two heavy branches off the southwest side.' },
              { d: 'Sep 8, 2024', body: 'No pears again. Year two. Maybe it just needs more time.' },
            ].map(r => (
              <div key={r.d} style={{
                background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 10,
                padding: '8px 12px',
              }}>
                <div style={{ fontSize: 10.5, color: PX.ink3, marginBottom: 2, letterSpacing: 0.2 }}>{r.d}</div>
                <div style={{ fontFamily: PX.serif, fontSize: 13, color: PX.ink, lineHeight: 1.4 }}>{r.body}</div>
              </div>
            ))}
          </div>
        </OrgSection>

        <OrganizeCard state="reorganize"/>
      </div>
    </PhoneScreen>
  );
}

function ScrOrganizeExhausted() {
  return (
    <PhoneScreen>
      <NavBar back="Today" title="Memory" trailing={
        <span style={{ color: PX.accent, fontSize: 15, fontWeight: 500 }}>Edit</span>
      }/>
      <div style={{ padding: '8px 18px 24px', overflow: 'auto', flex: 1 }}>
        <MemoryBlock organized={false}/>
        <OrganizeCard state="exhausted"/>
        <div style={{ fontSize: 11, color: PX.ink3, padding: '8px 4px 0', lineHeight: 1.5 }}>
          HiMem keeps working without AI. Capture and storage don't pause.
        </div>
      </div>
    </PhoneScreen>
  );
}
// ─────────────────────────────────────────────────────────────
// 3. Settings · Your AI — the daily-life counter surface.
// Shows tier, monthly allowance + remaining, pack balance, reset date.
// ─────────────────────────────────────────────────────────────
function ScrSettingsYourAI({ t }) {
  const remaining = monthlyRemaining(t);
  const monthlyTotal = isPlus(t) ? 50 : 0;
  const used = isPlus(t) ? t.monthlyUsed : 0;
  const pct = monthlyTotal ? Math.min(100, (used / monthlyTotal) * 100) : 0;
  const isFree = t.tier === 'free';
  const starterLeft = Math.max(0, 3 - (t.starterUsed || 0));
  const freeTotal = starterLeft + t.packBalance;

  return (
    <PhoneScreen bg={PX.paper}>
      <NavBar back="Settings" title="Your AI" />
      <div style={{ padding: '4px 0 28px', overflow: 'auto', flex: 1 }}>

        {/* Hero — current balance */}
        <div style={{ padding: '14px 18px 22px' }}>
          {isFree ? (
            <React.Fragment>
              <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 }}>Free · Starter + Packs</div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 8 }}>
                <span style={{ fontFamily: PX.serif, fontSize: 48, fontWeight: 400, color: PX.ink, lineHeight: 1, letterSpacing: -1 }}>{freeTotal}</span>
                <span style={{ fontSize: 14, color: PX.ink2 }}>{freeTotal === 1 ? 'assist remaining' : 'assists remaining'}</span>
              </div>
              <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 6, lineHeight: 1.45 }}>
                {starterLeft > 0
                  ? `${starterLeft} starter · ${t.packBalance} from packs · packs never expire`
                  : `${t.packBalance} from packs · never expire`}
              </div>
            </React.Fragment>
          ) : (
            <React.Fragment>
              <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 }}>This month</div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, marginTop: 8 }}>
                <span style={{ fontFamily: PX.serif, fontSize: 48, fontWeight: 400, color: PX.ink, lineHeight: 1, letterSpacing: -1 }}>{remaining}</span>
                <span style={{ fontSize: 18, color: PX.ink3, fontFamily: PX.serif }}>/ {monthlyTotal}</span>
                <span style={{ fontSize: 14, color: PX.ink2, marginLeft: 6 }}>included</span>
              </div>
              {/* progress bar */}
              <div style={{ marginTop: 14, height: 6, background: PX.sunk, borderRadius: 3, overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${pct}%`, background: pct >= 100 ? '#B8311E' : pct >= 75 ? PX.warn : PX.accent }} />
              </div>
              <div style={{ fontSize: 12, color: PX.ink3, marginTop: 8, display: 'flex', justifyContent: 'space-between' }}>
                <span>{used} used</span>
                <span>Resets Jun 1</span>
              </div>
            </React.Fragment>
          )}
        </div>

        {!isFree && t.packBalance > 0 && (
          <ListGroup header="Pack balance">
            <ListRow
              icon={<Plus size={14}/>}
              title={`${t.packBalance} pack assists`}
              detail="Used after your monthly allowance. Never expire."
              chevron={false}
              multiline
            />
          </ListGroup>
        )}

        <ListGroup header="Add more" style={{ marginTop: 20 }}>
          <ListRow icon={<Plus/>} title="20 assists" value="$4.99" />
          <ListRow icon={<Plus/>} title="100 assists" value="$19.99" />
        </ListGroup>

        <ListGroup header="Plan" style={{ marginTop: 20 }} footer="Cancel anytime in Settings. AI features pause; your memories stay.">
          <ListRow
            icon={isFree ? <Mem size={14}/> : <Spark size={14}/>}
            title={tierLabel(t)}
            detail={isFree ? 'Save, organize, capture — yours forever.' :
              t.tier === 'founders' ? 'Plus features for life · ' + t.packBalance + ' pack assists' :
              t.tier === 'plus_yearly' ? '$39.99/year · renews Mar 14, 2027' :
              '$4.99/month · renews Jun 12'}
            multiline
            value={isFree ? 'Upgrade' : 'Manage'}
            accent={isFree}
            chevron={!isFree}
          />
        </ListGroup>

        <div style={{ fontSize: 11, color: PX.ink3, padding: '20px 22px 0', lineHeight: 1.55 }}>
          AI is an organizational helper, not the product. HiMem works without it.
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 4. Settings · Upgrade hub — Plus monthly/yearly + Founders + Packs
// ─────────────────────────────────────────────────────────────
function ScrUpgradeHub({ t }) {
  const foundersOpen = t.foundersRemaining > 0;
  return (
    <PhoneScreen>
      <NavBar back="Settings" title="HiMem Plus" />
      <div style={{ padding: '0 14px 28px', overflow: 'auto', flex: 1 }}>

        {/* Header */}
        <div style={{ padding: '14px 6px 18px' }}>
          <div style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, lineHeight: 1.12, letterSpacing: -0.4, color: PX.ink, marginBottom: 8 }}>
            Plus adds AI<br/>and unlimited projects.
          </div>
          <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.5 }}>
            Storage and capture stay free, forever. Plus lets HiMem help you organize, and removes the one-project limit.
          </div>
        </div>

        {/* Plus monthly + yearly cards */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <PlanCard
            title="Plus · Monthly"
            price="$4.99"
            unit="/month"
            features={['50 AI assists / month', 'Unlimited projects', 'Auto-organize']}
          />
          <PlanCard
            title="Plus · Yearly"
            price="$39.99"
            unit="/year"
            sub="Two months free · $3.33/mo"
            features={['50 AI assists / month', 'Unlimited projects', 'Auto-organize']}
            featured
          />
        </div>

        {/* Founders tile — secondary slot, only while cap holds */}
        {foundersOpen && (
          <div style={{ marginTop: 18 }}>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, padding: '0 8px 8px' }}>
              Or, one-time
            </div>
            <div style={{
              background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
              padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12,
            }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                  <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Founders Lifetime</span>
                  <span style={{ fontFamily: PX.mono, fontSize: 11, color: PX.warn }}>{t.foundersRemaining} of 250 left</span>
                </div>
                <div style={{ fontSize: 13, color: PX.ink2, marginTop: 4, lineHeight: 1.4 }}>
                  $99 once · Plus for life · TestFlight + 100 bonus assists
                </div>
              </div>
              <svg width="7" height="12" viewBox="0 0 7 12" fill="none">
                <path d="M1 1l5 5-5 5" stroke={PX.ink4} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </div>
          </div>
        )}

        {/* AI packs */}
        <div style={{ marginTop: 22 }}>
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, padding: '0 8px 8px' }}>
            Or top up without a subscription
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <PackTile assists={20} price="$4.99" per="$0.25 each"/>
            <PackTile assists={100} price="$19.99" per="$0.20 each" tag="Better value"/>
          </div>
        </div>

        <div style={{ fontSize: 11, color: PX.ink3, padding: '22px 8px 0', lineHeight: 1.55 }}>
          Your memories are always yours. Free works forever. Cancel any time — capture and storage keep going.
        </div>
      </div>
    </PhoneScreen>
  );
}

function PlanCard({ title, price, unit, sub, features, featured }) {
  return (
    <div style={{
      background: featured ? PX.ink : PX.card,
      color: featured ? '#FFFCF6' : PX.ink,
      border: featured ? 'none' : '1px solid ' + PX.hairline,
      borderRadius: 16, padding: '16px 18px',
      display: 'flex', flexDirection: 'column', gap: 12,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: -0.2 }}>{title}</span>
        <span style={{ flex: 1 }} />
        <span style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 500, letterSpacing: -0.4 }}>{price}</span>
        <span style={{ fontSize: 13, opacity: 0.65 }}>{unit}</span>
      </div>
      {sub && <div style={{ fontSize: 12, opacity: 0.6, marginTop: -6 }}>{sub}</div>}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {features.map(f => (
          <div key={f} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, opacity: featured ? 0.9 : 0.85 }}>
            <Check size={12} color={featured ? '#FFCE9A' : PX.confirmed}/>
            <span>{f}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function PackTile({ assists, price, per, tag }) {
  return (
    <div style={{
      flex: 1, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '12px 14px', position: 'relative',
    }}>
      {tag && (
        <span style={{
          position: 'absolute', top: -8, right: 10,
          background: PX.accent, color: '#fff', fontSize: 10, fontWeight: 700,
          padding: '2px 6px', borderRadius: 6, letterSpacing: 0.3, textTransform: 'uppercase',
        }}>{tag}</span>
      )}
      <div style={{ fontFamily: PX.serif, fontSize: 26, fontWeight: 500, letterSpacing: -0.4, color: PX.ink }}>{assists}</div>
      <div style={{ fontSize: 12, color: PX.ink3, marginBottom: 8 }}>assists</div>
      <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>{price}</div>
      <div style={{ fontSize: 11, color: PX.ink3 }}>{per}</div>
    </div>
  );
}

Object.assign(window, {
  ScrOnboardingStarter,
  ScrOrganizeIdle, ScrOrganizeDone, ScrOrganizeExhausted,
  ScrSettingsYourAI, ScrUpgradeHub,
  OrganizeCard, MemoryBlock, OrgSection,
  PlanCard, PackTile, monthlyRemaining, isPlus, tierLabel,
});

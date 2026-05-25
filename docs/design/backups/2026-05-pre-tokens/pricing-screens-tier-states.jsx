// pricing-screens-tier-states.jsx
// Post-purchase + tier-identity surfaces.
// Philosophy: Plus = clean receipt + Manage. Supporter = quiet thanks.
// Founder = ceremonial moment + permanent identity.

// ─────────────────────────────────────────────────────────────
// SETTINGS HUB — tier-aware
// Replaces ScrUpgradeHub's "upgrade" voice when the user has a plan.
// ─────────────────────────────────────────────────────────────
function ScrPlanHub({ t }) {
  const tier = t.tier;
  const isFounders = tier === 'founders';
  const isPlus = tier === 'plus_monthly' || tier === 'plus_yearly';
  const isSupporter = !!t.supporter && !isPlus && !isFounders;
  const foundersOpen = t.foundersRemaining > 0;

  return (
    <PhoneScreen>
      <NavBar back="Settings" title={isFounders ? 'Founders' : isPlus ? 'Your plan' : 'HiMem Plus'} />
      <div style={{ padding: '0 14px 28px', overflow: 'auto', flex: 1 }}>

        {/* TIER-SPECIFIC HERO */}
        {isFounders && <FoundersHero/>}
        {isPlus && <PlusHero t={t}/>}
        {isSupporter && <SupporterCard cadence={t.supporter}/>}
        {!isFounders && !isPlus && !isSupporter && (
          <div style={{ padding: '14px 6px 18px' }}>
            <div style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, lineHeight: 1.12, letterSpacing: -0.4, color: PX.ink, marginBottom: 8 }}>
              Plus adds AI<br/>and unlimited projects.
            </div>
            <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.5 }}>
              Storage and capture stay free, forever. Plus lets HiMem help organize, and removes the one-project limit.
            </div>
          </div>
        )}

        {/* PLAN CARDS — only for non-subscribers (Free + Supporter) */}
        {!isFounders && !isPlus && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <PlanCard title="Plus · Monthly" price="$4.99" unit="/month"
              features={['50 AI assists / month', 'Unlimited projects', 'Auto-organize']}/>
            <PlanCard title="Plus · Yearly" price="$39.99" unit="/year"
              sub="Two months free · $3.33/mo"
              features={['50 AI assists / month', 'Unlimited projects', 'Auto-organize']} featured/>
          </div>
        )}

        {/* FOUNDERS TILE — hidden if already a founder */}
        {!isFounders && foundersOpen && (
          <div style={{ marginTop: 18 }}>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, padding: '0 8px 8px' }}>
              {isPlus ? 'Want more? One-time deal.' : 'Or, one-time'}
            </div>
            <div style={{
              background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
              padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12,
            }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap' }}>
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

        {/* AI PACKS — always available */}
        <div style={{ marginTop: 22 }}>
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, padding: '0 8px 8px' }}>
            {(isFounders || isPlus) ? 'Top up assists' : 'Or top up without a subscription'}
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <PackTile assists={20} price="$4.99" per="$0.25 each"/>
            <PackTile assists={100} price="$19.99" per="$0.20 each" tag="Better value"/>
          </div>
        </div>

        {/* MANAGE — only for paid subscriptions */}
        {(isPlus || (isSupporter)) && (
          <div style={{ marginTop: 22 }}>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, padding: '0 8px 8px' }}>
              Manage
            </div>
            <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden' }}>
              <ListRow icon={<Spark size={13}/>} title="Pause AI for this memory"
                detail="Hides organize stars. AI never runs without your tap."
                multiline chevron={false}
                value={
                  <span style={{
                    width: 32, height: 20, borderRadius: 10, background: PX.sunk, position: 'relative', display: 'inline-block',
                  }}>
                    <span style={{ position: 'absolute', left: 2, top: 2, width: 16, height: 16, borderRadius: 8, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.2)' }}/>
                  </span>
                }
              />
              <ListRow icon={<Mem size={13}/>}
                title="Manage in App Store"
                detail={isPlus ? (tier === 'plus_yearly' ? '$39.99/year · renews Mar 14, 2027' : '$4.99/month · renews Jun 12') :
                  (t.supporter === 'yearly' ? '$29.99/year · renews May 16, 2027' : '$2.99/month · renews Jun 16')}
                multiline isLast/>
            </div>
          </div>
        )}

        <div style={{ fontSize: 11, color: PX.ink3, padding: '22px 8px 0', lineHeight: 1.55 }}>
          {isFounders
            ? 'Founder · since May 2026.'
            : 'Your memories are always yours. Free works forever. Cancel any time — capture and storage keep going.'}
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// FoundersHero — permanent identity card
// ─────────────────────────────────────────────────────────────
function FoundersHero() {
  return (
    <div style={{
      margin: '14px 0 18px',
      background: PX.ink, color: '#FFFCF6', borderRadius: 18, padding: '22px 20px',
      position: 'relative', overflow: 'hidden',
    }}>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', opacity: 0.6, marginBottom: 12 }}>
        Founder
      </div>
      <div style={{ fontFamily: PX.serif, fontSize: 30, lineHeight: 1.05, letterSpacing: -0.5, marginBottom: 14 }}>
        Plus, forever.
      </div>
      <div style={{ fontSize: 13, opacity: 0.7, lineHeight: 1.5, marginBottom: 18 }}>
        One of the first 250. Thank you for showing up early.
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
        {[
          { t: '50 AI assists / month', d: 'Plus monthly allowance, included' },
          { t: '100 bonus assists at purchase', d: 'Into your pack balance, never expire' },
          { t: 'TestFlight access', d: 'Builds before they ship' },
          { t: 'Early feature flags', d: 'New things, before everyone else' },
        ].map((b, i) => (
          <div key={i} style={{ display: 'flex', gap: 9, alignItems: 'center', padding: '2px 0', fontSize: 12.5, opacity: 0.92 }}>
            <Check size={11} color="#FFCE9A"/>
            <span style={{ flex: 1 }}>{b.t}</span>
            <span style={{ opacity: 0.5, fontSize: 11 }}>{b.d}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// PlusHero — clean status, no upsell
// ─────────────────────────────────────────────────────────────
function PlusHero({ t }) {
  const cadence = t.tier === 'plus_yearly' ? 'Yearly' : 'Monthly';
  const renewal = t.tier === 'plus_yearly' ? 'Mar 14, 2027' : 'Jun 12';
  return (
    <div style={{ padding: '14px 6px 18px' }}>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 }}>
        Your plan
      </div>
      <div style={{ fontFamily: PX.serif, fontSize: 32, fontWeight: 400, lineHeight: 1.1, letterSpacing: -0.5, color: PX.ink, marginTop: 6 }}>
        HiMem Plus · {cadence}
      </div>
      <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginTop: 8 }}>
        Renews {renewal}. AI organization and unlimited projects, included.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SupporterCard — soft thanks, never on top
// ─────────────────────────────────────────────────────────────
function SupporterCard({ cadence = 'monthly' }) {
  return (
    <div style={{
      margin: '14px 0 18px',
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12,
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 10, background: PX.accentTint, color: PX.accent,
        display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>
        <Heart size={18}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>
          You support HiMem
        </div>
        <div style={{ fontSize: 12, color: PX.ink3, marginTop: 2 }}>
          {cadence === 'yearly' ? '$29.99/year · renews May 16, 2027' : '$2.99/month · renews Jun 16'}
        </div>
      </div>
      <span style={{ fontSize: 13, color: PX.accent, fontWeight: 500 }}>Manage</span>
    </div>
  );
}

// Small Heart glyph (no emoji)
function Heart({ size = 16, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color || 'currentColor'} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M8 14S2.2 10.4 2.2 6.2A3.5 3.5 0 018 4.5a3.5 3.5 0 015.8 1.7C13.8 10.4 8 14 8 14z"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// TIER MARK — small icon next to the product name.
// Simple, no UGC, no extra storage. Just a glyph keyed off tier.
//   • Founder  → filled ochre diamond (rare, marked)
//   • Plus     → outlined ochre ring with a small dot (subscriber)
//   • Supporter → outlined heart in ochre (patron)
//   • Free     → nothing
// Renders inline-flex so it sits comfortably next to a wordmark.
// ─────────────────────────────────────────────────────────────
function TierMark({ tier, size = 14 }) {
  if (!tier || tier === 'free') return null;
  if (tier === 'founders') {
    // Filled ochre diamond
    const s = size;
    return (
      <svg width={s} height={s} viewBox="0 0 16 16" aria-label="Founder">
        <path d="M8 1l5 7-5 7-5-7 5-7z" fill={PX.accent}/>
      </svg>
    );
  }
  if (tier === 'plus_monthly' || tier === 'plus_yearly' || tier === 'plus') {
    // Outlined ring with center dot
    const s = size;
    return (
      <svg width={s} height={s} viewBox="0 0 16 16" aria-label="Plus">
        <circle cx="8" cy="8" r="6.2" fill="none" stroke={PX.accent} strokeWidth="1.6"/>
        <circle cx="8" cy="8" r="2.3" fill={PX.accent}/>
      </svg>
    );
  }
  if (tier === 'supporter') {
    // Outlined heart
    const s = size;
    return (
      <svg width={s} height={s} viewBox="0 0 16 16" aria-label="Supporter">
        <path d="M8 13.5S2.5 10.2 2.5 6.5A3 3 0 018 4.8a3 3 0 015.5 1.7C13.5 10.2 8 13.5 8 13.5z"
              fill="none" stroke={PX.accent} strokeWidth="1.4" strokeLinejoin="round"/>
      </svg>
    );
  }
  return null;
}

// ─────────────────────────────────────────────────────────────
// LAUNCH SCREEN — tier-aware. One line, that's it.
// Founder gets a small mark + 'Thanks, founder' line for 30 days post-purchase.
// Plus / Supporter / Free: clean wordmark, nothing extra.
// ─────────────────────────────────────────────────────────────
function ScrLaunchTier({ tier = 'founders' }) {
  const showFounderLine = tier === 'founders';
  return (
    <PhoneScreen>
      <div style={{ padding: '160px 28px 0', display: 'flex', flexDirection: 'column', height: '100%' }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
          <div style={{
            fontFamily: PX.serif, fontSize: 56, fontWeight: 400, letterSpacing: -1.5,
            lineHeight: 1, color: PX.ink,
          }}>
            Hi<em style={{ fontStyle: 'italic' }}>Mem</em>
          </div>
          {tier !== 'free' && (
            <span style={{ marginTop: 8 }}><TierMark tier={tier} size={16}/></span>
          )}
        </div>
        {showFounderLine && (
          <div style={{
            marginTop: 16, fontSize: 13, color: PX.ink2, lineHeight: 1.5,
            fontFamily: PX.serif, fontStyle: 'italic', letterSpacing: -0.1,
          }}>
            Thanks for being a founder.
          </div>
        )}

        <div style={{ flex: 1 }}/>

        <div style={{ fontSize: 11, color: PX.ink3, lineHeight: 1.55, paddingBottom: 36 }}>
          {tier === 'founders' && 'Founder line shows for 30 days after purchase, then retires.'}
          {(tier === 'plus_monthly' || tier === 'plus' || tier === 'plus_yearly') && 'Plus: small mark only. No copy.'}
          {tier === 'supporter' && 'Supporter: small mark only. No copy.'}
          {tier === 'free' && 'Free: no mark.'}
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// MARKS COMPARISON — single artboard showing the 4 states
// side-by-side, so the design system pattern is legible.
// ─────────────────────────────────────────────────────────────
function ScrMarksSpecimen() {
  const rows = [
    { tier: 'founders', label: 'Founder' },
    { tier: 'plus_monthly', label: 'Plus' },
    { tier: 'supporter', label: 'Supporter' },
    { tier: 'free', label: 'Free' },
  ];
  return (
    <PhoneScreen>
      <NavBar back="" title="Tier marks" large/>
      <div style={{ padding: '8px 18px 28px', overflow: 'auto', flex: 1 }}>
        <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.55, marginBottom: 18 }}>
          A single small ochre glyph keyed off tier. Sits to the right of the wordmark on launch and in the Settings header. No names, no UGC.
        </div>
        <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden' }}>
          {rows.map((r, i) => (
            <div key={r.tier} style={{
              display: 'flex', alignItems: 'center', padding: '16px 16px',
              borderBottom: i < rows.length - 1 ? '1px solid ' + PX.divider : 'none',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1 }}>
                <span style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 400, color: PX.ink, letterSpacing: -0.4 }}>
                  Hi<em style={{ fontStyle: 'italic' }}>Mem</em>
                </span>
                <TierMark tier={r.tier} size={13}/>
              </div>
              <span style={{ fontSize: 12.5, color: PX.ink3, letterSpacing: -0.05 }}>{r.label}</span>
            </div>
          ))}
        </div>
        <div style={{ fontSize: 11, color: PX.ink3, padding: '14px 4px 0', lineHeight: 1.55 }}>
          Founder gets one extra line on launch — <em>"Thanks for being a founder"</em> — for 30 days, then it retires to Settings. The mark itself never goes away.
        </div>
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrPlanHub, ScrLaunchTier, ScrMarksSpecimen,
  FoundersHero, PlusHero, SupporterCard, Heart, TierMark,
});

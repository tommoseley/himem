// pricing-screens-reorganize.jsx
//
// Memory Detail · the full Reorganize / Stale surface shown vertically
// so all the panels are visible at once. The point here is to evaluate
// the STATE-COMMUNICATION parts of the experience (cost pill, badge
// pill, stale context strip, action affordance) — the editorial parts
// (clip body, mentions chips) are placeholders.
//
// Three states modeled side-by-side:
//   A. Stale + assists available    → Refresh CTA, 1 ASSIST cost pill
//   B. Stale + free user exhausted  → STARTER USED badge, See options
//   C. Stale + Plus user exhausted  → MONTHLY USED badge, Resets Jun 1
//
// Companion to §2 (decision tree), §14 (free journey), §15 (Plus pack).

// ─────────────────────────────────────────────────────────────
// TALL CANVAS — no status bar, no notch. The artboard's bezel
// provides the "phone-ish" container; this is the scroll content.
// ─────────────────────────────────────────────────────────────
function TallMemoryCanvas({ children }) {
  return (
    <div style={{
      width: '100%', height: '100%', background: PX.paper,
      position: 'relative', fontFamily: PX.sans, color: PX.ink,
      overflow: 'hidden', display: 'flex', flexDirection: 'column',
    }}>
      {children}
    </div>
  );
}

// Slim status-ish strip at top — just for visual weight + the live
// time / battery details that orient the artboard as "phone."
function TallStatusStrip() {
  return (
    <div style={{
      height: 30, flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 22px',
      fontSize: 13, fontWeight: 600, color: PX.ink,
    }}>
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>2:16</span>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
        {/* signal */}
        <span style={{ display: 'inline-flex', alignItems: 'flex-end', gap: 1.5 }}>
          {[3, 5, 7, 9].map(h => (
            <span key={h} style={{ width: 2.5, height: h, background: PX.ink, borderRadius: 0.5 }}/>
          ))}
        </span>
        {/* wifi */}
        <svg width="12" height="9" viewBox="0 0 12 9" fill="none" stroke={PX.ink} strokeWidth="1.2" strokeLinecap="round">
          <path d="M1 3a8 8 0 0110 0"/>
          <path d="M2.6 5a5.4 5.4 0 016.8 0"/>
          <circle cx="6" cy="7.5" r="0.9" fill={PX.ink} stroke="none"/>
        </svg>
        {/* battery */}
        <span style={{
          display: 'inline-flex', alignItems: 'center',
          border: '1px solid ' + PX.ink, borderRadius: 2.5,
          width: 22, height: 10, padding: 1.5, gap: 2,
          position: 'relative',
        }}>
          <span style={{ width: '70%', height: '100%', background: PX.ink, borderRadius: 0.5 }}/>
          <span style={{
            position: 'absolute', right: -2.5, top: 3, width: 1.5, height: 4,
            background: PX.ink, borderRadius: 1,
          }}/>
        </span>
      </span>
    </div>
  );
}

// Metadata row above clips — date + time + place. Pulled from the
// screenshot; this is the live "when/where" header of the memory.
function MemoryMetaRow({ date = 'Wed May 27', time = '1:56 PM', place = '18 Columbus Cir, Bluffton' }) {
  return (
    <div style={{
      padding: '6px 18px 12px',
      fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
      color: PX.ink3,
    }}>
      {date} · {time} · {place}
    </div>
  );
}

// Live mentions section above the Organized card. These are the
// memory's current/canonical mentions — what's actually attached
// to the entry right now. The Organized card's own MENTIONS row
// shows what AI extracted in the last pass; they may differ when stale.
function LiveMentions({ items = ['Abraham Lincoln', 'Integrity over success', 'Stand by what is right'] }) {
  return (
    <div style={{ padding: '0 18px 18px' }}>
      <div style={{
        fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase',
        color: PX.ink3, marginBottom: 8,
      }}>Mentions</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
        {items.map((label, i) => {
          const isPerson = i === 0;
          return (
            <span key={label} style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              padding: '5px 10px', borderRadius: 13,
              fontSize: 12, color: PX.ink2,
              background: PX.wash1, border: '1px solid ' + PX.hairline,
            }}>
              {isPerson ? (
                <svg width="9" height="10" viewBox="0 0 9 10" fill={PX.accent}>
                  <circle cx="4.5" cy="3" r="2"/>
                  <path d="M0.5 9.5c0-2 1.8-3.5 4-3.5s4 1.5 4 3.5"/>
                </svg>
              ) : (
                <span style={{ width: 5, height: 5, borderRadius: 3, background: PX.accent }}/>
              )}
              {label}
            </span>
          );
        })}
      </div>
    </div>
  );
}

// One row of the expanded Organized card — leading check eyebrow
// signals "this field was committed in the last pass."
function OrgStaleRow({ label, isLast, children }) {
  return (
    <div style={{
      padding: '12px 14px',
      borderBottom: isLast ? 'none' : '1px solid ' + PX.divider,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 5,
        fontSize: 10, fontWeight: 700, color: PX.accent,
        letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6,
      }}>
        <Check size={10} color={PX.accent}/>
        <span>{label}</span>
      </div>
      {children}
    </div>
  );
}

// The expanded Organized · stale card. Shows what AI committed last
// pass + an amber footer band with the "X new clips since organized"
// context (the missing "why stale" signal). Action is intentionally
// NOT in this card — it lives in a separate ReorganizeCard below so
// "review what's there" and "spend an assist to refresh" stay distinct.
function OrganizedStaleCard({ newClips = 2 }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      overflow: 'hidden',
    }}>
      {/* Header band — chip expanded form */}
      <div style={{
        padding: '11px 14px', background: PX.accentTint,
        display: 'flex', alignItems: 'center', gap: 8, color: PX.accent,
      }}>
        <Spark size={12}/>
        <span style={{ fontSize: 12.5, fontWeight: 600, letterSpacing: -0.05 }}>
          Organized · stale
        </span>
        <span style={{ flex: 1 }}/>
        <svg width="10" height="6" viewBox="0 0 10 6" fill="none">
          <path d="M1 5l4-4 4 4" stroke={PX.accent} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" opacity="0.7"/>
        </svg>
      </div>

      <OrgStaleRow label="Title">
        <div style={{ fontFamily: PX.serif, fontSize: 17, lineHeight: 1.22, color: PX.ink, letterSpacing: -0.2 }}>
          On integrity and moral courage
        </div>
      </OrgStaleRow>

      <OrgStaleRow label="Summary">
        <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.48 }}>
          You reflected on personal integrity and ethical decision-making — standing firm on what is right, while remaining flexible when circumstances change. Identified as foundational thinking about values and accountability.
        </div>
      </OrgStaleRow>

      <OrgStaleRow label="Topics">
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            fontSize: 12, color: PX.ink2, padding: '3px 9px', borderRadius: 10, background: PX.wash1,
          }}>
            <span style={{ width: 5, height: 5, borderRadius: 3, background: PX.accent }}/>
            How We Work
          </span>
        </div>
      </OrgStaleRow>

      <OrgStaleRow label="Mentions" isLast>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {['Abraham Lincoln', 'Integrity over success', 'Stand by what is right'].map((m, i) => (
            <span key={m} style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              fontSize: 12, color: PX.ink2, padding: '3px 9px', borderRadius: 10, background: PX.wash1,
            }}>
              {i === 0 ? (
                <svg width="8" height="9" viewBox="0 0 9 10" fill={PX.accent}>
                  <circle cx="4.5" cy="3" r="2"/>
                  <path d="M0.5 9.5c0-2 1.8-3.5 4-3.5s4 1.5 4 3.5"/>
                </svg>
              ) : (
                <span style={{ width: 5, height: 5, borderRadius: 3, background: PX.accent }}/>
              )}
              {m}
            </span>
          ))}
        </div>
      </OrgStaleRow>

      {/* The "why stale" strip — names the new evidence. Amber band,
          but no action — action lives in ReorganizeCard below. */}
      <div style={{
        padding: '10px 14px',
        background: PX.warnTint, color: PX.warnInk,
        borderTop: '1px solid ' + PX.divider,
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <Spark size={11}/>
        <span style={{ fontSize: 11.5, fontWeight: 600, letterSpacing: -0.05 }}>
          {newClips} new clips since this was organized
        </span>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// REORGANIZE CARD — the action affordance, mirror of OrganizeCard
// but for the stale state. Always sits BELOW the OrganizedStaleCard.
// Three configs via (exhausted, variant):
//   (false, _)        → 1 ASSIST cost pill,    "Refresh suggestions"
//   (true, 'free')    → STARTER USED badge,    "See options →"
//   (true, 'plus')    → MONTHLY USED badge,    "Resets Jun 1"
// ─────────────────────────────────────────────────────────────
function ReorganizeCard({ exhausted = false, variant = 'plus', resetDate = 'Jun 1' }) {
  const exhaustedBody = variant === 'free'
    ? <>Your <strong style={{ color: PX.ink2, fontWeight: 600 }}>3 free starter assists</strong> are spent. Add a pack or get 50&thinsp;/&thinsp;month with Plus. <span style={{ color: PX.accent }}>See options →</span></>
    : <>This month&rsquo;s 50 assists are used. Resets <strong style={{ color: PX.ink2, fontWeight: 600 }}>{resetDate}</strong>. <span style={{ color: PX.accent }}>Get more →</span></>;
  const liveBody = <>Spends 1 assist to fold the new clips in and refresh title, summary, topics, and mentions.</>;
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '12px 14px', display: 'flex', alignItems: 'flex-start', gap: 12,
      opacity: exhausted ? 0.85 : 1,
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 9,
        background: exhausted ? PX.sunk : PX.accent,
        color: exhausted ? PX.ink3 : PX.accentInk,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        marginTop: 1,
      }}>
        <Spark size={18}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 3,
        }}>
          <span style={{
            fontSize: 14, fontWeight: 600,
            color: exhausted ? PX.ink2 : PX.ink, letterSpacing: -0.15,
          }}>Reorganize with AI</span>
          <span style={{ flex: 1 }}/>
          {exhausted ? (
            <span style={{
              fontSize: 9.5, fontWeight: 700, color: PX.warnInk, background: PX.warnTint,
              padding: '4px 7px', borderRadius: 7, letterSpacing: 0.4, textTransform: 'uppercase',
              whiteSpace: 'nowrap',
            }}>{variant === 'free' ? 'Starter used' : 'Monthly used'}</span>
          ) : (
            <span style={{
              fontSize: 10, fontWeight: 700, color: PX.accent, background: PX.accentTint,
              padding: '4px 7px', borderRadius: 7, letterSpacing: 0.4, textTransform: 'uppercase',
              whiteSpace: 'nowrap',
            }}>1 Assist</span>
          )}
        </div>
        <div style={{ fontSize: 12, color: PX.ink3, lineHeight: 1.45, letterSpacing: -0.05 }}>
          {exhausted ? exhaustedBody : liveBody}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CLIP — single clip card (the Lincoln quote, from the live screenshot)
// Stripped down; the editorial here isn't the point.
// ─────────────────────────────────────────────────────────────
function StaleClipCard() {
  return (
    <div style={{
      margin: '0 18px 18px',
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '14px 16px',
    }}>
      <div style={{
        fontFamily: PX.serif, fontSize: 14.5, lineHeight: 1.42, color: PX.ink, letterSpacing: -0.05,
      }}>
        I am not bound to win, but I am bound to be true. I am not bound to succeed, but I am bound to live up to what light I have. I must stand by anybody that stands right, stand with him while he is right, and part with him when he goes wrong. — Abraham Lincoln.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// NAV — slim version of MemoryNav for the tall layout. Same action
// icons as the screenshot (trash, folder+, share, edit).
// ─────────────────────────────────────────────────────────────
function StaleNav() {
  return (
    <div style={{
      padding: '6px 14px 10px', display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0,
    }}>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 4,
        height: 32, padding: '0 12px 0 8px', borderRadius: 16,
        background: PX.card, border: '1px solid ' + PX.hairline,
        color: PX.accent, fontSize: 14, fontWeight: 500, letterSpacing: -0.1,
      }}>
        <svg width="9" height="14" viewBox="0 0 9 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M7 1L1 7l6 6"/>
        </svg>
        <span>Today</span>
      </span>
      <span style={{ flex: 1 }}/>
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 0,
        height: 32, padding: '0 4px', borderRadius: 16,
        background: PX.card, border: '1px solid ' + PX.hairline,
      }}>
        {[
          <svg key="trash" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={PX.ink3} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 3.5h9M5 3.5V2.5a1 1 0 011-1h2a1 1 0 011 1v1M3.5 3.5l.5 8a1 1 0 001 1h4a1 1 0 001-1l.5-8M6 6v4M8 6v4"/></svg>,
          <svg key="folder" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={PX.ink3} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M1.5 3.5a1 1 0 011-1h3l1 1.5h4a1 1 0 011 1V11a1 1 0 01-1 1h-8a1 1 0 01-1-1V3.5z"/><path d="M11.5 5.5v3M10 7h3"/></svg>,
          <svg key="share" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={PX.ink3} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M7 9V1M4.5 3.5L7 1l2.5 2.5M2.5 9.5V12a1 1 0 001 1h7a1 1 0 001-1V9.5"/></svg>,
          <svg key="edit" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke={PX.ink3} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M9 2.5l2.5 2.5L4 12.5H1.5V10L9 2.5z"/></svg>,
        ].map((g, i) => (
          <span key={i} style={{ width: 30, height: 28, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{g}</span>
        ))}
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// COMPOSITE — three tall Memory Detail states
// ─────────────────────────────────────────────────────────────
function ScrMemoryStaleTall({ exhausted = false, variant = 'plus' }) {
  const stateLabel = !exhausted
    ? 'A · Assists available'
    : variant === 'free' ? 'B · Free · starter used' : 'C · Plus · monthly used';
  return (
    <TallMemoryCanvas>
      <TallStatusStrip/>
      <StaleNav/>
      <MemoryMetaRow/>
      <StaleClipCard/>
      <LiveMentions/>
      <div style={{ padding: '0 18px 14px' }}>
        <OrganizedStaleCard newClips={2}/>
      </div>
      <div style={{ padding: '0 18px 14px' }}>
        <ReorganizeCard exhausted={exhausted} variant={variant}/>
      </div>

      {/* State label strip — sits at the bottom of each artboard so we
          can read what state we're looking at when comparing side-by-side. */}
      <div style={{ flex: 1 }}/>
      <div style={{
        margin: '4px 18px 18px', padding: '8px 12px', borderRadius: 8,
        background: PX.sunk, color: PX.ink3,
        fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
        fontFamily: PX.mono,
      }}>
        State {stateLabel}
      </div>
    </TallMemoryCanvas>
  );
}

function ScrMemoryStaleAvailable()  { return <ScrMemoryStaleTall exhausted={false}/>; }
function ScrMemoryStaleFreeOut()    { return <ScrMemoryStaleTall exhausted={true} variant="free"/>; }
function ScrMemoryStalePlusOut()    { return <ScrMemoryStaleTall exhausted={true} variant="plus"/>; }

Object.assign(window, {
  ScrMemoryStaleTall,
  ScrMemoryStaleAvailable, ScrMemoryStaleFreeOut, ScrMemoryStalePlusOut,
  OrganizedStaleCard, ReorganizeCard, OrgStaleRow,
  TallMemoryCanvas, TallStatusStrip, StaleNav, MemoryMetaRow, LiveMentions, StaleClipCard,
});

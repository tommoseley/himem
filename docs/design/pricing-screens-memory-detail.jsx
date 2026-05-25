// pricing-screens-memory-detail.jsx
// The Memory Detail screen + the unified "Organize with AI" / "AI Suggestions"
// pattern. Resolves the production state-collision between the cream Organize
// card and the yellow "App is Inferring" card.
//
// Pattern: ambient inference is a quiet italic caption (free, no card).
// One assist = one whole-memory polish pass that promotes the caption into
// editable structured fields. Accept / edit / skip is free. Refresh after the
// memory changes is a new assist.

// ─────────────────────────────────────────────────────────────
// CHROME — Memory Detail nav bar + FAB + mentions disclosure
// ─────────────────────────────────────────────────────────────
function MemoryNav({ date = 'Monday, May 11', titleBelow, aiTag = false }) {
  return (
    <div style={{ padding: '4px 14px 6px', display: 'flex', flexDirection: 'column', gap: 6, flexShrink: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {/* Date pill (acts as back to Today) */}
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 4,
          height: 32, padding: '0 12px 0 8px', borderRadius: 16,
          background: PX.card, border: '1px solid ' + PX.hairline,
          color: PX.accent, fontSize: 14, fontWeight: 500, letterSpacing: -0.1,
        }}>
          <svg width="9" height="14" viewBox="0 0 9 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M7 1L1 7l6 6"/>
          </svg>
          <span>{date}</span>
        </span>
        <span style={{ flex: 1 }}/>
        {/* Action icons */}
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
      {titleBelow && (
        <div style={{ padding: '4px 4px 0', display: 'flex', alignItems: 'flex-start', gap: 8 }}>
          <div style={{
            fontFamily: PX.serif, fontSize: 22, lineHeight: 1.18, letterSpacing: -0.3,
            color: PX.ink, flex: 1, fontWeight: 400,
          }}>{titleBelow}</div>
          {aiTag && (
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 4,
              background: PX.accentTint, color: PX.accent, fontSize: 9.5, fontWeight: 700,
              padding: '3px 6px 3px 5px', borderRadius: 5, letterSpacing: 0.4, textTransform: 'uppercase',
              marginTop: 6, flexShrink: 0,
            }}>
              <Spark size={9}/> AI
            </span>
          )}
        </div>
      )}
    </div>
  );
}

function MemoryMentions({ count = 5 }) {
  return (
    <div style={{
      padding: '14px 18px 0', display: 'flex', alignItems: 'center', gap: 8,
      fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase',
      color: PX.ink3, borderTop: '1px solid ' + PX.divider,
    }}>
      <span>Mentions</span>
      <svg width="9" height="6" viewBox="0 0 9 6" fill="none" stroke={PX.ink4} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M1 1l3.5 3.5L8 1"/>
      </svg>
      <span style={{ flex: 1 }}/>
      <span style={{ color: PX.ink3, fontFamily: PX.mono, letterSpacing: 0.3 }}>{count}</span>
    </div>
  );
}

function MemoryFAB() {
  return (
    <div style={{
      position: 'absolute', right: 18, bottom: 38, zIndex: 5,
      width: 50, height: 50, borderRadius: 25, background: PX.accent,
      color: PX.accentInk, display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: PX.shadowFabAccent,
    }}>
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
        <path d="M10 4v12M4 10h12"/>
      </svg>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CLIPS — text and image clips inside a memory
// ─────────────────────────────────────────────────────────────
function ClipText({ time, body }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '12px 14px', marginBottom: 10,
    }}>
      <div style={{ fontSize: 11, color: PX.ink3, marginBottom: 6, letterSpacing: 0.2 }}>{time}</div>
      <div style={{
        fontFamily: PX.serif, fontSize: 14.5, lineHeight: 1.4, color: PX.ink,
        letterSpacing: -0.1,
      }}>{body}</div>
    </div>
  );
}

// Placeholder video-thumbnail imagery (not Crucible UI — these are
// decorative pixels mimicking a captured-video frame). Colors are
// intentionally literal because they represent image content, not chrome.
function ClipImage({ time }) {
  return (
    <div style={{
      width: 140, height: 110, borderRadius: 12, marginBottom: 10,
      background: 'linear-gradient(135deg, #5a4e3a 0%, #2a261c 100%)',
      position: 'relative', overflow: 'hidden',
    }}>
      {/* tablet glyph */}
      <div style={{
        position: 'absolute', left: 18, top: 24, right: 18, bottom: 30,
        background: 'rgba(245,239,230,0.12)', borderRadius: 6,
        border: '1px solid rgba(245,239,230,0.18)',
      }}>
        <div style={{ position: 'absolute', left: 6, top: 6, right: 6, height: 8, display: 'flex', gap: 3 }}>
          {Array.from({ length: 6 }).map((_, i) => (
            <span key={i} style={{ width: 6, height: 6, borderRadius: 1, background: 'rgba(245,239,230,0.30)' }}/>
          ))}
        </div>
        <div style={{ position: 'absolute', left: 6, bottom: 4, fontSize: 5, color: 'rgba(245,239,230,0.4)' }}>● ● ● ●</div>
      </div>
      <div style={{
        position: 'absolute', left: 8, top: 6,
        width: 18, height: 18, borderRadius: 9,
        background: 'rgba(0,0,0,0.45)', color: PX.accentInk,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 11, lineHeight: 1,
      }}>×</div>
      <div style={{
        position: 'absolute', left: 8, bottom: 6, fontSize: 11, color: PX.accentInk,
        fontWeight: 500, letterSpacing: 0.2,
      }}>{time}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// AI ZONE — the four states that replace the production collision
// ─────────────────────────────────────────────────────────────

// State A · IDLE · ambient hint above + Organize card below
function AmbientHint({ children }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 8,
      padding: '4px 4px 14px',
    }}>
      <span style={{ color: PX.ink4, marginTop: 4, flexShrink: 0 }}><Spark size={11}/></span>
      <div style={{
        fontFamily: PX.serif, fontSize: 13, fontStyle: 'italic',
        color: PX.ink3, lineHeight: 1.5, letterSpacing: -0.05,
      }}>{children}</div>
    </div>
  );
}

function OrganizeCard({ exhausted, resetDate = 'Jun 1' }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 12,
      opacity: exhausted ? 0.78 : 1,
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 9,
        background: exhausted ? PX.sunk : PX.accent,
        color: exhausted ? PX.ink3 : PX.accentInk,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>
        <Spark size={18}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: exhausted ? PX.ink2 : PX.ink, letterSpacing: -0.15 }}>
          Organize with AI
        </div>
        <div style={{ fontSize: 12, color: PX.ink3, marginTop: 2, lineHeight: 1.45, letterSpacing: -0.05 }}>
          {exhausted
            ? <>This month's AI is used. Resets <strong style={{ color: PX.ink2, fontWeight: 600 }}>{resetDate}</strong>. <span style={{ color: PX.accent }}>See options</span></>
            : <>Suggests a title, summary, topics, next steps, and related memories.</>}
        </div>
      </div>
      {!exhausted && (
        <span style={{
          flexShrink: 0, fontSize: 10, fontWeight: 700, color: PX.accent, background: PX.accentTint,
          padding: '4px 7px', borderRadius: 7, letterSpacing: 0.4, textTransform: 'uppercase',
        }}>1 Assist</span>
      )}
    </div>
  );
}

// State B · POST-PASS · REVIEW · unified AI Suggestions card.
// The card's header IS the OrganizedChip in its expanded form — same
// icon, same ochre tint, same text — stretched to a full-width band
// with the chevron flipped to indicate "expanded, tap to collapse."
// One element, two states.
function AISuggestionsCard() {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      overflow: 'hidden',
    }}>
      {/* Header band = the chip, expanded. Same visual language. */}
      <div style={{
        padding: '11px 14px',
        background: PX.accentTint,
        display: 'flex', alignItems: 'center', gap: 8,
        color: PX.accent,
      }}>
        <Spark size={12}/>
        <span style={{ fontSize: 12.5, fontWeight: 600, letterSpacing: -0.05 }}>
          Organized · review
        </span>
        <span style={{ flex: 1 }}/>
        {/* Chevron UP — expanded; tap to collapse back to the chip. */}
        <svg width="10" height="6" viewBox="0 0 10 6" fill="none">
          <path d="M1 5l4-4 4 4" stroke={PX.accent} strokeWidth="1.6"
                strokeLinecap="round" strokeLinejoin="round" opacity="0.7"/>
        </svg>
      </div>

      {/* Title suggestion */}
      <SuggestRow label="Title">
        <div style={{ fontFamily: PX.serif, fontSize: 16, lineHeight: 1.25, color: PX.ink, letterSpacing: -0.2 }}>
          A product concept for content creators
        </div>
      </SuggestRow>

      {/* Summary */}
      <SuggestRow label="Summary">
        <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.5 }}>
          Capture thoughts, images, and videos across watch, phone, and iPad. AI helps classify creative fragments into structured content.
        </div>
      </SuggestRow>

      {/* Topics */}
      <SuggestRow label="Topics">
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {['Product idea', 'Content tools', 'Multi-device'].map(t => (
            <span key={t} style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              fontSize: 12, fontWeight: 500, color: PX.ink2,
              padding: '3px 9px 3px 7px', borderRadius: 10, background: PX.wash1,
            }}>
              <Check size={10} color={PX.accent}/>{t}
            </span>
          ))}
        </div>
      </SuggestRow>

      {/* Next steps */}
      <SuggestRow label="Next steps" isLast>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
          {[
            'Sketch a 30-second capture flow for watch',
            'Test voice → structured fragment pipeline',
          ].map(t => (
            <div key={t} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 12.5, color: PX.ink2, lineHeight: 1.4 }}>
              <span style={{ width: 4, height: 4, borderRadius: 2, background: PX.ink4, marginTop: 7, flexShrink: 0 }}/>
              <span style={{ flex: 1 }}>{t}</span>
            </div>
          ))}
        </div>
      </SuggestRow>

      {/* Footer */}
      <div style={{
        padding: '10px 12px',
        background: PX.paper,
        display: 'flex', gap: 8, alignItems: 'center',
      }}>
        <button style={{
          flex: 1, background: PX.ink, color: PX.accentInk, border: 'none', borderRadius: 9,
          padding: '8px 12px', fontSize: 13, fontWeight: 600, letterSpacing: -0.1, cursor: 'default',
        }}>Accept all</button>
        <button style={{
          background: 'transparent', border: '1px solid ' + PX.hairline, borderRadius: 9,
          padding: '8px 12px', fontSize: 13, fontWeight: 500, color: PX.ink2, letterSpacing: -0.1, cursor: 'default',
        }}>Edit</button>
      </div>
    </div>
  );
}

function SuggestRow({ label, children, isLast }) {
  return (
    <div style={{
      padding: '11px 14px',
      borderBottom: isLast ? 'none' : '1px solid ' + PX.divider,
    }}>
      <div style={{
        fontSize: 10, fontWeight: 700, color: PX.ink3,
        letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6,
      }}>{label}</div>
      {children}
    </div>
  );
}

// State C · POST-PASS · APPLIED · collapsed chip.
// The chip and the AISuggestionsCard header are the same element — see
// AISuggestionsCard for the expanded form. Chevron points down here to
// indicate "tap to expand inline."
function OrganizedChip() {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 7,
      padding: '7px 12px 7px 10px', borderRadius: 999,
      background: PX.accentTint, color: PX.accent,
      fontSize: 12, fontWeight: 600, letterSpacing: -0.05,
    }}>
      <Spark size={11}/>
      <span>Organized · review</span>
      <svg width="10" height="6" viewBox="0 0 10 6" fill="none" style={{ marginLeft: 1 }}>
        {/* Chevron DOWN — collapsed; tap to expand inline. */}
        <path d="M1 1l4 4 4-4" stroke={PX.accent} strokeWidth="1.6"
              strokeLinecap="round" strokeLinejoin="round" opacity="0.7"/>
      </svg>
    </div>
  );
}

// State D · STALE · applied chip + refresh callout
function StaleFooter({ exhausted = false, resetDate = 'Jun 1' }) {
  return (
    <div style={{
      background: PX.warnTint, borderRadius: 10,
      padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10,
      fontSize: 12, color: PX.warnInk, letterSpacing: -0.05, marginTop: 10,
    }}>
      <span style={{ color: PX.warnInk, flexShrink: 0, marginTop: 1 }}><Spark size={12}/></span>
      <div style={{ flex: 1, lineHeight: 1.4 }}>
        <div style={{ fontWeight: 700 }}>AI suggestions may be out of date</div>
        <div style={{ marginTop: 2, opacity: 0.85, fontWeight: 400 }}>
          2 new clips were added since this memory was organized.
        </div>
      </div>
      <span style={{
        flexShrink: 0, fontSize: 11, fontWeight: 600, color: exhausted ? PX.ink3 : PX.warnInk,
        letterSpacing: -0.05, opacity: exhausted ? 0.7 : 1, alignSelf: 'center',
      }}>
        {exhausted ? `Resets ${resetDate}` : 'Refresh · 1 assist'}
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// COMPOSITE SCREENS · five Memory Detail states
// ─────────────────────────────────────────────────────────────
const SAMPLE_CLIPS = (
  <React.Fragment>
    <ClipText time="11:28 AM" body={
      <>The nice part about the application is that you can be just about <em>anywhere</em> and have a thought and record it. And get it under your system. If you shower with your watch, you can have ideas in the shower. Which I've done.</>
    }/>
    <ClipImage time="3:42 PM"/>
  </React.Fragment>
);

// A · Idle · ambient hint + Organize card
function ScrMemoryIdle() {
  return (
    <PhoneScreen>
      <MemoryNav/>
      <div style={{ padding: '8px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {SAMPLE_CLIPS}
        <AmbientHint>
          About this: a product concept for content creators that captures thoughts and media across watch, phone, and iPad.
        </AmbientHint>
        <OrganizeCard/>
        <div style={{ flex: 1 }}/>
        <MemoryMentions/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// B · Post-pass · Review · the unified AI Suggestions card
function ScrMemoryReview() {
  return (
    <PhoneScreen>
      <MemoryNav/>
      <div style={{ padding: '8px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {SAMPLE_CLIPS}
        <AISuggestionsCard/>
        <div style={{ flex: 1 }}/>
        <MemoryMentions/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// C · Post-pass · Applied · AI title at top, collapsed chip below clips
function ScrMemoryApplied() {
  return (
    <PhoneScreen>
      <MemoryNav titleBelow="A product concept for content creators"/>
      <div style={{ padding: '4px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {SAMPLE_CLIPS}
        <div style={{ padding: '0 0 6px' }}>
          <OrganizedChip/>
        </div>
        <div style={{ flex: 1 }}/>
        <MemoryMentions/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// D · Stale · applied + refresh callout
function ScrMemoryStale({ exhausted = false }) {
  return (
    <PhoneScreen>
      <MemoryNav titleBelow="A product concept for content creators"/>
      <div style={{ padding: '4px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {SAMPLE_CLIPS}
        <ClipText time="4:18 PM" body="Also: keep the audio always — even after we polish, the raw clips are the source of truth."/>
        <div style={{ padding: '2px 0 0' }}>
          <OrganizedChip/>
        </div>
        <StaleFooter exhausted={exhausted}/>
        <div style={{ flex: 1 }}/>
        <MemoryMentions/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// E · Exhausted · Organize card muted with "See options"
function ScrMemoryExhausted() {
  return (
    <PhoneScreen>
      <MemoryNav/>
      <div style={{ padding: '8px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {SAMPLE_CLIPS}
        <AmbientHint>
          About this: a product concept for content creators that captures thoughts and media across watch, phone, and iPad.
        </AmbientHint>
        <OrganizeCard exhausted/>
        <div style={{ flex: 1 }}/>
        <MemoryMentions/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// DECISION TREE · exhaustive state table
// Wider than a phone — renders inside a regular DCArtboard.
// ─────────────────────────────────────────────────────────────
function ScrDecisionTree() {
  const Row = ({ inputs, title, hint, accent, sub, isLast }) => (
    <div style={{
      display: 'grid',
      gridTemplateColumns: '1.1fr 0.4fr 1.4fr',
      gap: 16, padding: '14px 18px',
      borderBottom: isLast ? 'none' : '1px solid ' + PX.divider,
      alignItems: 'flex-start',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {inputs.map((row, i) => (
          <div key={i} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5,
            color: row.dim ? PX.ink3 : PX.ink, fontFamily: PX.mono, letterSpacing: 0.1,
          }}>
            <span style={{
              width: 6, height: 6, borderRadius: 3,
              background: row.dim ? PX.ink4 : (row.color || PX.accent),
              flexShrink: 0,
            }}/>
            <span>{row.k}</span>
            <span style={{ color: PX.ink3 }}>=</span>
            <span style={{ color: row.dim ? PX.ink3 : PX.ink2, fontWeight: 500 }}>{row.v}</span>
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', height: '100%' }}>
        <svg width="32" height="10" viewBox="0 0 32 10" fill="none">
          <path d="M0 5h30M25 1l5 4-5 4" stroke={PX.ink4} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </div>
      <div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 3 }}>
          <span style={{
            width: 8, height: 8, borderRadius: 4, background: accent || PX.accent, flexShrink: 0,
          }}/>
          <span style={{ fontSize: 13.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>{title}</span>
        </div>
        <div style={{ fontSize: 12, color: PX.ink2, lineHeight: 1.5, paddingLeft: 16 }}>{hint}</div>
        {sub && <div style={{ fontSize: 11, color: PX.ink3, lineHeight: 1.5, paddingLeft: 16, marginTop: 2, fontStyle: 'italic', fontFamily: PX.serif }}>{sub}</div>}
      </div>
    </div>
  );

  return (
    <div style={{
      width: '100%', height: '100%', background: PX.paper,
      fontFamily: PX.sans, color: PX.ink, padding: 28,
      display: 'flex', flexDirection: 'column',
      overflow: 'hidden',
    }}>
      <div style={{ marginBottom: 8 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
          Memory Detail · AI Zone
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 24, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, lineHeight: 1.15 }}>
          Decision tree.
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.55, marginTop: 6, maxWidth: 640 }}>
          Inputs are stable across tiers. Auto-organize (Plus / Founder) just changes <em>when</em> the memory enters the Organized state — never <em>what</em> gets rendered.
        </div>
      </div>

      <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18, fontSize: 11.5, color: PX.ink2 }}>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 4 }}>Inputs</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, fontFamily: PX.mono, fontSize: 11 }}>
            <div><span style={{ color: PX.accent }}>organized</span> · pass committed?</div>
            <div><span style={{ color: PX.accent }}>reviewed</span> · user touched suggestions?</div>
            <div><span style={{ color: PX.accent }}>stale</span> · clips added since pass?</div>
            <div><span style={{ color: PX.accent }}>assists</span> · monthly + pack + starter &gt; 0?</div>
            <div><span style={{ color: PX.accent }}>ambient</span> · cheap inference available?</div>
          </div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 4 }}>Outputs</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, fontFamily: PX.mono, fontSize: 11 }}>
            <div><span style={{ color: PX.ink2 }}>title</span> · date pill / AI title / custom</div>
            <div><span style={{ color: PX.ink2 }}>hint</span> · italic ambient line or hidden</div>
            <div><span style={{ color: PX.ink2 }}>aiZone</span> · Organize / Suggestions / Chip / Muted</div>
            <div><span style={{ color: PX.ink2 }}>footer</span> · Refresh callout (stale only)</div>
          </div>
        </div>
      </div>

      <div style={{
        marginTop: 18,
        background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden',
      }}>
        <Row
          inputs={[
            { k: 'organized', v: 'false' },
            { k: 'assists', v: '> 0' },
            { k: 'ambient', v: 'true' },
          ]}
          title="State A · Idle"
          accent={PX.accent}
          hint="Italic 'About this:' line + cream Organize · 1 ASSIST card."
          sub="Default for new memories on Free, or Plus with auto-organize off."
        />
        <Row
          inputs={[
            { k: 'organized', v: 'false' },
            { k: 'assists', v: '0', color: PX.danger },
          ]}
          title="State E · Out-of-assists"
          accent={PX.warn}
          hint="Muted Organize card. 'Resets Jun 1 · See options →' replaces the 1-ASSIST pill."
          sub="No modal, no scrim. Tapping 'See options' opens AI Packs."
        />
        <Row
          inputs={[
            { k: 'organized', v: 'true' },
            { k: 'reviewed', v: 'false' },
          ]}
          title="State B · Post-pass · Review"
          accent={PX.accent}
          hint="Unified AI Suggestions card. Rows: Title · Summary · Topics · Next steps. Apply all / Edit. Replaces idle ambient hint AND the old yellow 'App is Inferring' card."
          sub="On Plus auto-organize, the memory enters this state automatically on save."
        />
        <Row
          inputs={[
            { k: 'organized', v: 'true' },
            { k: 'reviewed', v: 'true' },
            { k: 'stale', v: 'false' },
          ]}
          title="State C · Applied"
          accent={PX.confirmed}
          hint="AI-derived title moves to top (small ✦ AI tag). 'Organized · review' chip lives below clips — tap to reopen suggestions, free."
          sub="Reviewing, editing, or skipping suggestions consumes zero assists."
        />
        <Row
          inputs={[
            { k: 'stale', v: 'true' },
            { k: 'assists', v: '> 0' },
          ]}
          title="State D · Stale"
          accent={PX.warn}
          hint="Applied state + amber footer: '2 new clips · Refresh · 1 assist'. Refresh runs a new whole-memory pass."
          sub="Last pass's title and summary remain valid until refreshed; nothing is silently overwritten."
        />
        <Row
          inputs={[
            { k: 'stale', v: 'true' },
            { k: 'assists', v: '0', color: PX.danger, dim: true },
          ]}
          title="State D · Stale · out-of-assists"
          accent={PX.warn}
          hint="Same applied + amber footer, but 'Resets Jun 1' replaces the Refresh action. No nudge to buy."
          isLast
        />
      </div>

      <div style={{ marginTop: 14, display: 'flex', gap: 18, fontSize: 11, color: PX.ink3, lineHeight: 1.5 }}>
        <div style={{ flex: 1 }}>
          <strong style={{ color: PX.ink, fontWeight: 600 }}>Failure rule.</strong> An aborted or errored pass consumes <em>zero</em> assists. State stays at A. Card temporarily shows "Try again."
        </div>
        <div style={{ flex: 1 }}>
          <strong style={{ color: PX.ink, fontWeight: 600 }}>Accept rule.</strong> Apply / Edit / Skip of any suggestion field is free. Only a fresh whole-memory pass consumes an assist.
        </div>
        <div style={{ flex: 1 }}>
          <strong style={{ color: PX.ink, fontWeight: 600 }}>Ambient rule.</strong> The italic "About this:" line is free and runs in the background. It disappears once a paid pass has been committed.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SUMMARY · the Honest Label
// Lives at the top of the Memory view, between title and clips.
// Plain "Summary" eyebrow — no ✦, no AI tag. By the time it's
// visible here, the synthesis is the memory's, not the AI's.
// Provenance lives in the Organized chip, not on the field.
// Length matches the substance available; never manufactured.
// See AI Organize · spec.md for the full rules.
// ─────────────────────────────────────────────────────────────
function SummarySection({ children, dense = false }) {
  return (
    <div style={{ padding: dense ? '0 4px 10px' : '4px 4px 14px' }}>
      <div style={{
        fontSize: 10, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase',
        color: PX.ink3, marginBottom: 6,
      }}>Summary</div>
      <div style={{
        fontFamily: PX.serif, fontSize: 14.5, lineHeight: 1.48, color: PX.ink,
        letterSpacing: -0.1,
      }}>{children}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// JOURNAL · scan-line row
//
// Organized:      title + summary excerpt (truncated to 2 lines)
// Unorganized:    italic first-clip excerpt with "from first clip"
//                 caption (visually different from a real summary)
// Media-only:     metadata fallback ("3 photos · garden") — no text
//                 to fall back to, so we show what we know
//
// The visible difference between organized and unorganized rows
// is the value proposition for the assist. The user sees the
// contrast and the value becomes visible — not nagged, shown.
// ─────────────────────────────────────────────────────────────
function JournalRow({ title, summary, firstClip, mediaOnly, time, topicDots, isLast = false }) {
  const dot = (color, i) => (
    <span key={i} style={{ width: 6, height: 6, borderRadius: 3, background: color, marginRight: 4, flexShrink: 0 }}/>
  );
  return (
    <div style={{
      padding: '14px 0',
      borderBottom: isLast ? 'none' : '1px solid ' + PX.divider,
    }}>
      <div style={{
        fontSize: 11, color: PX.ink3, marginBottom: 5, letterSpacing: 0.2,
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <span>{time}</span>
        {topicDots && topicDots.length > 0 && (
          <span style={{ display: 'inline-flex', alignItems: 'center', flexShrink: 0 }}>
            {topicDots.map((c, i) => dot(c, i))}
          </span>
        )}
      </div>
      {title ? (
        // Organized
        <React.Fragment>
          <div style={{
            fontFamily: PX.serif, fontSize: 17, lineHeight: 1.22, letterSpacing: -0.25,
            color: PX.ink, marginBottom: 4, fontWeight: 400,
          }}>{title}</div>
          {summary && (
            <div style={{
              fontSize: 13, color: PX.ink2, lineHeight: 1.45, letterSpacing: -0.05,
              display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
            }}>{summary}</div>
          )}
        </React.Fragment>
      ) : mediaOnly ? (
        // Photo / audio only, no text fallback available
        <div style={{
          fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, letterSpacing: -0.05,
          fontStyle: 'italic',
        }}>{mediaOnly}</div>
      ) : (
        // Has text but unorganized — first clip excerpt
        <React.Fragment>
          <div style={{
            fontSize: 9.5, color: PX.ink4, fontStyle: 'italic', marginBottom: 4,
            letterSpacing: 0.4, textTransform: 'uppercase',
          }}>from first clip</div>
          <div style={{
            fontFamily: PX.serif, fontSize: 14.5, fontStyle: 'italic',
            color: PX.ink2, lineHeight: 1.4, letterSpacing: -0.05,
            display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
            overflow: 'hidden',
          }}>{firstClip}</div>
        </React.Fragment>
      )}
    </div>
  );
}

function JournalDateHeader({ children, first = false }) {
  return (
    <div style={{
      paddingTop: first ? 6 : 22,
      paddingBottom: 2,
      fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase',
      color: PX.ink3,
    }}>{children}</div>
  );
}

// ─────────────────────────────────────────────────────────────
// COMPOSITE · Memory view with Summary at top
// Replaces ScrMemoryApplied as the canonical applied state.
// Title becomes plain (no ✦ AI tag) once accepted.
// Summary sits between title and clips.
// ─────────────────────────────────────────────────────────────
function ScrMemoryWithSummary() {
  return (
    <PhoneScreen>
      <MemoryNav titleBelow="A product concept for content creators"/>
      <div style={{ padding: '4px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <SummarySection>
          You're exploring how HiMem could capture creative fragments across watch, phone, and iPad. You noted that audio recordings while showering are a real capture use case — wherever a thought lands, the system should be there.
        </SummarySection>
        <ClipText time="11:28 AM" body={
          <React.Fragment>The nice part about the application is that you can be just about <em>anywhere</em> and have a thought and record it. And get it under your system. If you shower with your watch, you can have ideas in the shower. Which I've done.</React.Fragment>
        }/>
        <ClipImage time="3:42 PM"/>
        <div style={{ padding: '6px 0 0' }}>
          <OrganizedChip/>
        </div>
        <div style={{ flex: 1 }}/>
        <MemoryMentions/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// Thin-summary case — single short clip, summary is one sentence.
// Demonstrates the "fidelity matches substance" rule visually.
function ScrMemoryThinSummary() {
  return (
    <PhoneScreen>
      <MemoryNav titleBelow="Pears"/>
      <div style={{ padding: '4px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <SummarySection>
          You appreciated pears.
        </SummarySection>
        <ClipText time="11:08 AM" body={<em>Mmmm, pears.</em>}/>
        <div style={{ padding: '6px 0 0' }}>
          <OrganizedChip/>
        </div>
        <div style={{ flex: 1 }}/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// Photo-only memory — Organize boundary disclosed; no Summary section
// until the user spends an assist (which will produce a metadata-only
// summary in v1, since vision isn't analyzed).
function ScrMemoryPhotoOnly() {
  return (
    <PhoneScreen>
      <MemoryNav date="Tuesday, May 18"/>
      <div style={{ padding: '4px 14px 12px', flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
          <ClipImage time="8:14 AM"/>
          <ClipImage time="8:14 AM"/>
        </div>
        <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
          <ClipImage time="8:15 AM"/>
        </div>

        {/* Organize card with boundary disclosure */}
        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
          padding: '12px 14px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
            <div style={{
              width: 36, height: 36, borderRadius: 9, background: PX.accent, color: PX.accentInk,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
            }}>
              <Spark size={18}/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>
                Organize with AI
              </div>
              <div style={{ fontSize: 12, color: PX.ink3, marginTop: 2, lineHeight: 1.45 }}>
                Summary describes text and audio. Photos and videos are referenced by count.
              </div>
            </div>
            <span style={{
              flexShrink: 0, fontSize: 10, fontWeight: 700, color: PX.accent, background: PX.accentTint,
              padding: '4px 7px', borderRadius: 7, letterSpacing: 0.4, textTransform: 'uppercase',
            }}>1 Assist</span>
          </div>
        </div>

        <div style={{ flex: 1 }}/>
        <MemoryMentions count={0}/>
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// JOURNAL VIEW · the list. Summary is the scan line.
// Demonstrates organized, unorganized-with-text, and media-only.
// ─────────────────────────────────────────────────────────────
function ScrJournalView() {
  const TG = topicVar('pine'); // garden
  const TI = topicVar('amber');  // ideas
  const TW = topicVar('slate');  // work
  return (
    <PhoneScreen>
      <div style={{ padding: '14px 18px 0' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, letterSpacing: -0.4, color: PX.ink }}>Today</div>
      </div>
      <div style={{ padding: '0 18px', overflow: 'hidden', flex: 1 }}>
        <JournalDateHeader first>Tuesday, May 18</JournalDateHeader>
        <JournalRow
          time="4:18 PM"
          topicDots={[TI, TW]}
          title="A product concept for content creators"
          summary="You're exploring how HiMem could capture creative fragments across watch, phone, and iPad. Audio recordings while showering are a real use case."
        />
        <JournalRow
          time="11:42 AM"
          topicDots={[TG]}
          title="The pear tree finally fruited"
          summary="You found three pears, the size of fists, hidden behind the leaves near the back fence."
        />
        <JournalRow
          time="9:02 AM"
          firstClip="The watch should auto-stop on wrist-off. Never lose a recording mid-thought."
        />
        <JournalRow
          time="8:14 AM"
          mediaOnly="3 photos · garden"
          isLast
        />

        <JournalDateHeader>Yesterday</JournalDateHeader>
        <JournalRow
          time="2:30 PM"
          topicDots={[TW]}
          title="Library afternoon"
          summary="You captured the smell of old wood and marigolds on the front desk."
        />
        <JournalRow
          time="11:08 AM"
          topicDots={[TG]}
          title="Pears"
          summary="You appreciated pears."
          isLast
        />
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// Edge case · day with only unorganized memories — the "incentive"
// reveal. Visibly less scannable than the organized journal above.
function ScrJournalUnorganized() {
  return (
    <PhoneScreen>
      <div style={{ padding: '14px 18px 0' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, letterSpacing: -0.4, color: PX.ink }}>Today</div>
      </div>
      <div style={{ padding: '0 18px', overflow: 'hidden', flex: 1 }}>
        <JournalDateHeader first>Tuesday, May 18</JournalDateHeader>
        <JournalRow
          time="4:18 PM"
          firstClip="The nice part about the application is that you can be just about anywhere and have a thought…"
        />
        <JournalRow
          time="11:42 AM"
          firstClip="Pear tree finally fruited. Three pears."
        />
        <JournalRow
          time="9:02 AM"
          firstClip="The watch should auto-stop on wrist-off. Never lose a recording mid-thought."
        />
        <JournalRow
          time="8:14 AM"
          mediaOnly="3 photos · garden"
        />
        <JournalRow
          time="7:42 AM"
          firstClip="Mmmm, pears."
          isLast
        />
      </div>
      <MemoryFAB/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// SUMMARY SPEC · visual reference for "what summary is and isn't"
// Wider artboard, like ScrDecisionTree. Lives next to the screens
// it governs so designers and engineers can see the rule and the
// concrete examples side-by-side.
// ─────────────────────────────────────────────────────────────
function ScrSummarySpec() {
  const Eg = ({ good = false, bad = false, label, text }) => (
    <div style={{
      background: PX.paper, border: '1px solid ' + PX.hairline, borderRadius: 10,
      padding: '10px 12px', position: 'relative',
    }}>
      <div style={{
        fontSize: 9.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
        color: good ? PX.confirmed : (bad ? PX.danger : PX.ink3),
        marginBottom: 6,
      }}>{label}</div>
      <div style={{
        fontFamily: PX.serif, fontSize: 13, lineHeight: 1.45,
        color: bad ? PX.ink3 : PX.ink,
        textDecoration: bad ? 'line-through' : 'none',
        textDecorationColor: `color-mix(in oklab, ${PX.danger} 50%, transparent)`,
        letterSpacing: -0.05,
      }}>{text}</div>
    </div>
  );

  return (
    <div style={{
      width: '100%', height: '100%', background: PX.paper,
      fontFamily: PX.sans, color: PX.ink, padding: 28,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <div style={{ marginBottom: 14 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
          AI Organize · Summary spec
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 24, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, lineHeight: 1.15 }}>
          The Honest Label.
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.55, marginTop: 6, maxWidth: 640 }}>
          The summary's job is to give a memory a name its author will recognize six months later. It contains nothing the clips don't contain. Length matches substance. Voice is descriptive, not interpretive.
        </div>
      </div>

      <div style={{
        background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
        padding: 16, marginBottom: 14,
      }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, marginBottom: 12 }}>
          Same source clip · "Mmmm, pears."
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Eg good label='Good · honest, thin' text='You appreciated pears.'/>
          <Eg bad label='Bad · invented depth' text='You are exploring questions of seasonality and the simple pleasures of late-spring abundance.'/>
        </div>
      </div>

      <div style={{
        background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
        padding: 16, marginBottom: 14,
      }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, marginBottom: 12 }}>
          Multi-clip · product concept
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Eg good label='Good · grounded' text="You're exploring how HiMem could capture creative fragments across watch, phone, and iPad. Audio recordings while showering are a real use case."/>
          <Eg bad label='Bad · interpretive' text="You seem excited about a new app idea and are processing anxieties about capture friction by recording your thoughts."/>/>
        </div>
      </div>

      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18,
        fontSize: 11.5, color: PX.ink2, lineHeight: 1.55,
      }}>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Allowed</div>
          <div>Paraphrase. Light context from clip metadata (when, where, count). Cross-clip synthesis when literally observable ("Tom returned to this three times").</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Not allowed</div>
          <div>Inference about mental state ("anxious," "excited"). Inference about meaning ("represents," "themes of"). Connective fluff that names patterns the clips don't establish.</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Voice</div>
          <div>Stored with &ldquo;you&rdquo; baked in. On share / export, a simple string replace swaps &ldquo;you&rdquo; for the user&rsquo;s first name. Other people always by name &mdash; no he/she/they/her/his.</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Length</div>
          <div>No minimum. Soft ceiling ~90 words. Hard ceiling: the substance available. Never manufacture words to fill a card.</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Media (v1)</div>
          <div>Text + audio analyzed. Photos and videos referenced by metadata only. v1.5+: optional 3-assist pass adds visual analysis.</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Provenance</div>
          <div>Once accepted, the summary is the memory's — no AI tag on the field. The Organized chip is the only provenance indicator.</div>
        </div>
      </div>

      <div style={{ flex: 1 }}/>
      <div style={{ fontSize: 10.5, color: PX.ink3, lineHeight: 1.5, fontStyle: 'italic', fontFamily: PX.serif, paddingTop: 14, borderTop: '1px solid ' + PX.divider }}>
        Full spec: <code style={{ fontFamily: PX.mono, fontStyle: 'normal' }}>AI Organize · spec.md</code> in project root.
      </div>
    </div>
  );
}


Object.assign(window, {
  MemoryNav, MemoryMentions, MemoryFAB, ClipText, ClipImage,
  AmbientHint, OrganizeCard, AISuggestionsCard, SuggestRow, OrganizedChip, StaleFooter,
  SummarySection, JournalRow, JournalDateHeader,
  ScrMemoryIdle, ScrMemoryReview, ScrMemoryApplied, ScrMemoryStale, ScrMemoryExhausted,
  ScrMemoryWithSummary, ScrMemoryThinSummary, ScrMemoryPhotoOnly,
  ScrJournalView, ScrJournalUnorganized,
  ScrDecisionTree, ScrSummarySpec, ScrAudienceRendering,
});

// ─────────────────────────────────────────────────────────────
// AUDIENCE-AWARE RENDERING · stored / owner / external, side-by-side
// Same source clips, three renderings of the same summary.
// Demonstrates: the voice changes by audience, not by setting.
// See AI Organize · spec.md §3 for the substitution rules.
// ─────────────────────────────────────────────────────────────
function ScrAudienceRendering() {
  const Card = ({ kind, label, sub, body, tone }) => {
    const palette = {
      stored:   { bg: PX.sunk,       fg: PX.ink,  eb: PX.ink3,  border: PX.hairline },
      owner:    { bg: PX.card,       fg: PX.ink,  eb: PX.accent, border: PX.accentTint2 },
      external: { bg: PX.card,       fg: PX.ink,  eb: PX.ink2,  border: PX.hairline },
    }[kind];
    return (
      <div style={{
        background: palette.bg, border: '1px solid ' + palette.border, borderRadius: 12,
        padding: '14px 16px', flex: 1, minWidth: 0,
      }}>
        <div style={{
          fontSize: 9.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
          color: palette.eb, marginBottom: 4,
        }}>{label}</div>
        {sub && (
          <div style={{ fontSize: 10.5, color: PX.ink3, marginBottom: 8, fontFamily: PX.mono, letterSpacing: 0 }}>
            {sub}
          </div>
        )}
        <div style={{
          fontFamily: kind === 'stored' ? PX.mono : PX.serif,
          fontSize: kind === 'stored' ? 12 : 13.5,
          lineHeight: 1.45, color: palette.fg, letterSpacing: -0.05,
        }}>{body}</div>
      </div>
    );
  };

  const Triplet = ({ source, stored, owner, external }) => (
    <div style={{ marginBottom: 16 }}>
      <div style={{
        fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase',
        color: PX.ink3, marginBottom: 8,
      }}>{source}</div>
      <div style={{ display: 'flex', gap: 10, alignItems: 'stretch' }}>
        <Card kind="stored"   label="Stored"   sub="canonical, with <user> token" body={stored}/>
        <div style={{ display: 'flex', alignItems: 'center', color: PX.ink4, paddingTop: 22 }}>
          <svg width="14" height="12" viewBox="0 0 14 12" fill="none">
            <path d="M0 6h11M8 1l5 5-5 5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </div>
        <Card kind="owner"    label="Owner sees"     sub="in-app, memory + journal" body={owner}/>
        <Card kind="external" label="Anyone else"    sub="shared, exported, family"  body={external}/>
      </div>
    </div>
  );

  return (
    <div style={{
      width: '100%', height: '100%', background: PX.paper,
      fontFamily: PX.sans, color: PX.ink, padding: 28,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <div style={{ marginBottom: 14 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
          AI Organize · Audience-aware rendering
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 24, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, lineHeight: 1.15 }}>
          The summary you wrote is the summary they read.
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.55, marginTop: 6, maxWidth: 720 }}>
          Voice changes by audience, not by setting. Stored with a <code style={{ fontFamily: PX.mono, fontSize: 11.5 }}>&lt;user&gt;</code> token; rendered as <em>you</em> for the owner in-app and as the owner's first name everywhere else.
        </div>
      </div>

      <Triplet
        source='"Mmmm, pears." · single short clip'
        stored="<user> appreciated pears."
        owner="You appreciated pears."
        external="Tom appreciated pears."
      />

      <Triplet
        source="Multi-clip · product concept"
        stored="<user> is exploring how HiMem could capture creative fragments across watch, phone, and iPad."
        owner="You're exploring how HiMem could capture creative fragments across watch, phone, and iPad."
        external="Tom is exploring how HiMem could capture creative fragments across watch, phone, and iPad."
      />

      <Triplet
        source="Co-subject memory · multi-person"
        stored="<user> and Sarah talked about the pears."
        owner="You and Sarah talked about the pears."
        external="Tom and Sarah talked about the pears."
      />

      <Triplet
        source="Pure-observation · no subject"
        stored="A sunset over the ridge."
        owner="A sunset over the ridge."
        external="A sunset over the ridge."
      />

      <div style={{ flex: 1 }}/>

      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 14,
        fontSize: 11, color: PX.ink2, lineHeight: 1.5,
        paddingTop: 12, borderTop: '1px solid ' + PX.divider,
      }}>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 4 }}>Where it flips to first name</div>
          Share via email or message · PDF export (share intent) · family-share view (v2+) · memorial / posthumous mode.
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 4 }}>Name requirement</div>
          User must set first name before share or export. If unset, the share action prompts for a name first \u2014 no clinical "the author" fallback.
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 4 }}>Hand-edited summaries</div>
          Stored as literal strings with no <code style={{ fontFamily: PX.mono, fontSize: 10 }}>&lt;user&gt;</code> token. Substitution doesn't apply \u2014 it renders identically for every audience.
        </div>
      </div>
    </div>
  );
}

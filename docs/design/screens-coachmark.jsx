// screens-coachmark.jsx
// Anchored coachmark tour — the SECOND tutorial format (July 5 2026).
//
// Division of labor (locked with the one-pager system):
//   • Full-pager  → explains WHAT A PAGE IS ("This is Captured Clips").
//                   Conceptual, replayable, fires once on first arrival.
//   • Coachmark   → explains WHAT THE CONTROLS DO. Dim the screen, box the
//                   real element in an ochre ring, one-line caption in place.
//                   Best for control-specific features and for orienting an
//                   otherwise-EMPTY first-run screen that has no content to
//                   anchor understanding.
//
// Reconciled with "hand-off, not handhold" (onboarding spec): the first-run
// Today stays the calm empty prompt + FAB arrow — capture is NEVER gated.
// The tour is OFFERED ("Show me around"), never auto-forced, and always lives
// in the ? hub. Perishability wins: a user with a thought hits the FAB and
// ignores the tour; a user who wants orientation taps it.
//
// Crucible dress (not MW Tonight's yellow-on-navy): ochre ring on the target,
// warm-ink scrim, caption card on cream with a Source-Serif lead-in, quiet
// voice. Skip (plain ink) dismisses the WHOLE tour; Next (ochre) advances.

// ── The capture FAB (ochre, bottom-right) ──────────────────────
function CoachFAB() {
  return (
    <div style={{
      position: 'absolute', right: 20, bottom: 26, width: 60, height: 60, borderRadius: 30,
      background: PX.accent, boxShadow: PX.shadowFabAccent,
      display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 2,
    }}>
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={PX.accentInk} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
      </svg>
    </div>
  );
}

// ── Empty first-run home — the hand-off, preserved ─────────────
// Written prompt + arrow to the FAB (capture first). Plus a QUIET
// "Show me around" — the offered, skippable entry to the coachmark tour.
function ScrCoachHomeEmpty() {
  return (
    <PhoneScreen>
      <MemoriesHeader activeFilter="All" />
      <div style={{ flex: 1, position: 'relative', padding: '0 26px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 25, fontWeight: 400, color: PX.ink, letterSpacing: -0.5, lineHeight: 1.2 }}>
          Nothing here yet —<br />which is exactly right.
        </div>
        <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.5, marginTop: 12, maxWidth: 250 }}>
          When a thought comes, catch it. Your memories will gather here on their own.
        </div>
        {/* offered, never forced */}
        <div style={{
          marginTop: 22, display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 40, padding: '0 16px',
          borderRadius: 20, border: '1px solid ' + PX.hairline, background: PX.card,
          fontSize: 13.5, fontWeight: 600, color: PX.ink2, letterSpacing: -0.1,
        }}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={PX.accent} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10" /><path d="M9.5 9a2.5 2.5 0 0 1 4.9.8c0 1.7-2.4 2.2-2.4 2.2M12 17h.01" /></svg>
          Show me around
        </div>

        {/* hand-drawn arrow to the FAB */}
        <div style={{ position: 'absolute', right: 20, bottom: 92, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2 }}>
          <span style={{ fontFamily: PX.serif, fontStyle: 'italic', fontSize: 13, color: PX.ink3 }}>Tap to capture</span>
          <svg width="42" height="30" viewBox="0 0 44 32" fill="none" stroke={PX.ink4} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><path d="M2 4 C 18 4, 30 12, 38 24" /><path d="M31 23l7 2 1-7" /></svg>
        </div>
      </div>
      <CoachFAB />
    </PhoneScreen>
  );
}

// ── The coachmark overlay ──────────────────────────────────────
// `spot` = {top,left,width,height} of the target within the 340×735 screen.
// The dim is a transparent box with a huge box-shadow (the "hole"); an ochre
// ring sits on the target; the caption card flips above/below to stay clear.
function Coachmark({ spot, step, total, title, body, captionBelow = true, radius = 12 }) {
  const capTop = captionBelow ? spot.top + spot.height + 14 : undefined;
  const capBottom = captionBelow ? undefined : (735 - spot.top) + 14;
  return (
    <>
      {/* scrim with cutout */}
      <div style={{
        position: 'absolute', zIndex: 40,
        top: spot.top, left: spot.left, width: spot.width, height: spot.height,
        borderRadius: radius,
        boxShadow: '0 0 0 9999px rgba(26,22,18,0.66)',
      }} />
      {/* ochre ring on the target */}
      <div style={{
        position: 'absolute', zIndex: 41,
        top: spot.top - 4, left: spot.left - 4, width: spot.width + 8, height: spot.height + 8,
        borderRadius: radius + 3, border: '2.5px solid ' + PX.accent,
        boxShadow: '0 0 0 3px rgba(198,74,28,0.25)',
      }} />
      {/* caption card */}
      <div style={{
        position: 'absolute', zIndex: 42, left: 18, right: 18,
        ...(capTop !== undefined ? { top: capTop } : { bottom: capBottom }),
        background: PX.paper, borderRadius: 16, padding: '15px 17px 13px',
        boxShadow: '0 16px 44px rgba(26,22,18,0.32)', border: '1px solid ' + PX.hairline,
      }}>
        <div style={{ fontSize: 15, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
          <span style={{ fontFamily: PX.serif, fontWeight: 600 }}>{title}</span>
          {' '}<span style={{ color: PX.ink2 }}>{body}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', marginTop: 14 }}>
          <span style={{ fontSize: 11, fontWeight: 700, color: PX.ink3, letterSpacing: 1, fontVariantNumeric: 'tabular-nums' }}>
            {step} / {total}
          </span>
          <span style={{ flex: 1 }} />
          <span style={{ minHeight: 40, display: 'inline-flex', alignItems: 'center', fontSize: 14, fontWeight: 600, color: PX.ink3, letterSpacing: -0.1, paddingRight: 16 }}>Skip</span>
          <span style={{
            minHeight: 40, display: 'inline-flex', alignItems: 'center', gap: 6, padding: '0 18px',
            borderRadius: 11, background: PX.accent, color: PX.accentInk, fontSize: 14.5, fontWeight: 600, letterSpacing: -0.1,
          }}>
            {step === total ? 'Done' : 'Next'}
            {step !== total && <svg width="7" height="12" viewBox="0 0 10 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 1l6 6-6 6" /></svg>}
          </span>
        </div>
      </div>
    </>
  );
}

// Home behind the overlay (same empty first-run home, minus the arrow/prompt
// so the spotlight reads clean).
function CoachBase() {
  return (
    <>
      <MemoriesHeader activeFilter="All" />
      <div style={{ flex: 1, position: 'relative' }} />
      <CoachFAB />
    </>
  );
}

// Step 1 · the Memories/Projects segmented control (top center of header)
function ScrCoachStep1() {
  return (
    <PhoneScreen>
      <div style={{ position: 'absolute', inset: 0 }}><CoachBase /></div>
      <Coachmark
        spot={{ top: 52, left: 120, width: 100, height: 30 }}
        step={1} total={3}
        title="Two ways to look."
        body="Everything you’ve kept lives under Memories. Building something over weeks? That’s what Projects are for."
        captionBelow
        radius={9}
      />
    </PhoneScreen>
  );
}

// Step 2 · the capture FAB (the important one)
function ScrCoachStep2() {
  return (
    <PhoneScreen>
      <div style={{ position: 'absolute', inset: 0 }}><CoachBase /></div>
      <Coachmark
        spot={{ top: 649, left: 260, width: 60, height: 60 }}
        step={2} total={3}
        title="A thought that might not survive the walk to your desk?"
        body="Tap to catch it here. Press and hold to start recording hands-free — before it fades."
        captionBelow={false}
        radius={30}
      />
    </PhoneScreen>
  );
}

// Step 3 · search (find it again later)
function ScrCoachStep3() {
  return (
    <PhoneScreen>
      <div style={{ position: 'absolute', inset: 0 }}><CoachBase /></div>
      <Coachmark
        spot={{ top: 54, left: 274, width: 26, height: 26 }}
        step={3} total={3}
        title="Remember talking about Shiprock, months ago?"
        body="Find it in seconds — by a person, a place, a topic, or a phrase you still remember."
        captionBelow
        radius={13}
      />
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrCoachHomeEmpty, ScrCoachStep1, ScrCoachStep2, ScrCoachStep3,
  Coachmark, CoachFAB, CoachBase,
});

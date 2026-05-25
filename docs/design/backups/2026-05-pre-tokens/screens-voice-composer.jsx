// screens-voice-composer.jsx
// Phone voice composer · v1 (May 21 2026).
//
// Implements the "on a roll" affordance on phone, per:
//   • On a roll · spec.md (cross-platform Next contract)
//   • Watch · spec.md §2 (visual language we now mirror on phone)
//   • CLAUDE.md → Watch + capture sections
//
// Locked rules:
//  • Big timer + live waveform as visual hero (matches Watch redesign).
//  • Persistent "Clip N · on a roll" state line under the timer. Never a transient flash.
//  • Stop & save is the primary commit pill (cream-on-ochre).
//    Next is a 56×56 ochre satellite to the right.
//  • Cancel ✕ lives as a top-left corner glyph. No bottom Cancel pill during recording.
//  • Append composer adds an "Adding to · [Memory]" header pill — otherwise identical.
//  • Mic never pauses across Next. Waveform keeps rolling, counter resets to 0:00.

// ─────────────────────────────────────────────────────────────
// Composer header — Cancel ✕ corner glyph, optional "Adding to" pill, Done right
// ─────────────────────────────────────────────────────────────
function ComposerHeader({ appendingTo = null }) {
  return (
    <div style={{
      position: 'absolute', top: 56, left: 0, right: 0,
      padding: '0 18px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      zIndex: 5,
    }}>
      <span style={{
        width: 32, height: 32, borderRadius: 16,
        background: 'rgba(26,22,18,0.06)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        color: PX.ink2,
      }}>
        <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <path d="M2 2l10 10M12 2L2 12"/>
        </svg>
      </span>
      {appendingTo ? (
        <span style={{
          flex: 1, margin: '0 12px',
          height: 28, padding: '0 12px',
          borderRadius: 14, background: PX.card, border: '1px solid ' + PX.hairline,
          display: 'inline-flex', alignItems: 'center', gap: 6,
          fontSize: 12, color: PX.ink2,
          overflow: 'hidden', whiteSpace: 'nowrap',
        }}>
          <span style={{ color: PX.ink3, flexShrink: 0 }}>Adding to ·</span>
          <span style={{ color: PX.ink, fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {appendingTo}
          </span>
        </span>
      ) : (
        <span style={{
          fontSize: 13, fontWeight: 600, color: PX.ink, letterSpacing: -0.1,
          textTransform: 'uppercase', letterSpacing: 1.2,
        }}>Voice</span>
      )}
      <span style={{
        fontSize: 14, fontWeight: 600, color: PX.accent, letterSpacing: -0.1,
      }}>Done</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Live waveform — the visual hero on this surface.
// ─────────────────────────────────────────────────────────────
function Waveform({ bars = 56, tint = PX.accent, tail = 0.25, leadingFalloff = 8, seed = 0 }) {
  // Deterministic-ish heights from sin-wave so each artboard renders consistently
  const heights = Array.from({ length: bars }, (_, i) => {
    const t = (i + seed) * 0.62;
    return 6 + Math.abs(Math.sin(t)) * 26 + (i % 5 === 0 ? 6 : 0) + Math.abs(Math.cos(t * 1.7)) * 8;
  });
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      gap: 3, height: 48, width: '100%', padding: '0 12px',
    }}>
      {heights.map((h, i) => {
        // Last few bars fade to indicate the leading edge
        const fade = i > bars - leadingFalloff
          ? Math.max(0.22, 1 - (i - (bars - leadingFalloff)) / leadingFalloff)
          : 1;
        return (
          <div key={i} style={{
            width: 3, height: Math.max(4, h),
            background: tint,
            opacity: fade < 1 ? fade * tail * 4 : 1,
            borderRadius: 2,
            flexShrink: 0,
          }}/>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Stop & save — big circular ochre commit button.
// ─────────────────────────────────────────────────────────────
function StopButton() {
  return (
    <div style={{
      width: 84, height: 84, borderRadius: 42,
      background: PX.accent,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: '0 6px 22px rgba(166,60,21,0.40), 0 2px 6px rgba(0,0,0,0.10)',
    }}>
      {/* Filled rounded square = "stop" */}
      <div style={{ width: 26, height: 26, background: '#FFFCF6', borderRadius: 5 }}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Next-clip satellite — 56×56, ochre-tinted, forward-chevron-with-trailing-dot.
// `bright=true` shows the post-tap fill + halo state.
// ─────────────────────────────────────────────────────────────
function NextSatellite({ bright = false, disabled = false }) {
  const bg = disabled ? 'rgba(198,74,28,0.10)'
    : bright ? PX.accent
    : PX.accentTint2;
  const fg = disabled ? 'rgba(198,74,28,0.45)'
    : bright ? '#FFFCF6'
    : PX.accent;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
      <div style={{
        width: 56, height: 56, borderRadius: 28,
        background: bg,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: bright ? '0 0 0 3px rgba(198,74,28,0.30)' : 'none',
        transition: 'all 200ms',
      }}>
        <svg width="22" height="14" viewBox="0 0 22 14" fill="none" stroke={fg} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 2l5 5-5 5"/>
          <circle cx="15" cy="7" r="1.8" fill={fg} stroke="none"/>
        </svg>
      </div>
      <span style={{
        fontSize: 11, fontWeight: 600,
        color: disabled ? PX.ink3 : '#E07A4E',
        letterSpacing: 0.3,
      }}>Next</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Composer body — shared layout. Big timer + state line + waveform + Stop|Next.
// ─────────────────────────────────────────────────────────────
function ComposerBody({ timer = '0:23', clipNum = 1, nextBright = false, waveformSeed = 0 }) {
  const onRoll = clipNum >= 2;
  return (
    <div style={{
      position: 'absolute', top: 110, left: 0, right: 0, bottom: 0,
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      padding: '8px 0 30px',
    }}>
      {/* REC indicator */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        color: PX.accent, marginTop: 16,
      }}>
        <span style={{ width: 7, height: 7, borderRadius: 4, background: PX.accent }}/>
        <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase' }}>Rec</span>
      </div>

      {/* Big timer — SF Pro Display weight 300, tabular */}
      <div style={{
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro", system-ui, sans-serif',
        fontSize: 72, fontWeight: 200, letterSpacing: -2.4, lineHeight: 1,
        color: PX.ink, marginTop: 18,
        fontVariantNumeric: 'tabular-nums',
      }}>{timer}</div>

      {/* Persistent state line — only when on a roll */}
      <div style={{
        height: 18, marginTop: 10,
        fontSize: 13, fontWeight: 600,
        color: onRoll ? PX.accent : 'transparent',
        letterSpacing: -0.1,
      }}>
        {onRoll ? `Clip ${clipNum} · on a roll` : ''}
      </div>

      {/* Live waveform hero */}
      <div style={{ width: '100%', marginTop: 32 }}>
        <Waveform seed={waveformSeed}/>
      </div>

      {/* Bottom commit row: Stop centered, Next satellite right */}
      <div style={{
        marginTop: 'auto', width: '100%',
        position: 'relative',
        display: 'flex', justifyContent: 'center', alignItems: 'center',
        paddingBottom: 24,
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
          <StopButton />
          <span style={{ fontSize: 11, fontWeight: 600, color: PX.ink2, letterSpacing: 0.3 }}>Stop &amp; save</span>
        </div>
        {/* Next sits 36pt to the right of the Stop button edge */}
        <div style={{
          position: 'absolute',
          left: 'calc(50% + 42px + 36px)',  // stop radius + spec gap
          top: 14,
        }}>
          <NextSatellite bright={nextBright}/>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 1. Direct voice composer · clip 1 (no roll yet)
// ─────────────────────────────────────────────────────────────
function ScrVCDirectClip1() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <ComposerBody timer="0:23" clipNum={1} waveformSeed={0}/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 2. Direct voice composer · mid-roll (clip 2, "on a roll" line visible)
// ─────────────────────────────────────────────────────────────
function ScrVCDirectMidRoll() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <ComposerBody timer="1:42" clipNum={2} waveformSeed={3}/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 3. Moment of Next tap — bright fill + halo, counter at 0:00, waveform still rolling
// ─────────────────────────────────────────────────────────────
function ScrVCMomentOfTap() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <ComposerBody timer="0:00" clipNum={3} nextBright waveformSeed={7}/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 4. Append composer · clip 1 (with "Adding to" header pill)
// ─────────────────────────────────────────────────────────────
function ScrVCAppendClip1() {
  return (
    <PhoneScreen>
      <ComposerHeader appendingTo="Saturday garden walkthrough"/>
      <ComposerBody timer="0:11" clipNum={1} waveformSeed={11}/>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 5. Append composer · mid-roll (header pill + on-a-roll line both visible)
// ─────────────────────────────────────────────────────────────
function ScrVCAppendMidRoll() {
  return (
    <PhoneScreen>
      <ComposerHeader appendingTo="Saturday garden walkthrough"/>
      <ComposerBody timer="0:47" clipNum={2} waveformSeed={5}/>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrVCDirectClip1,
  ScrVCDirectMidRoll,
  ScrVCMomentOfTap,
  ScrVCAppendClip1,
  ScrVCAppendMidRoll,
  ScrVCCountdownReady,
  ScrVCCountdown3,
  ScrVCCountdown2,
  ScrVCCountdown1,
});

// ─────────────────────────────────────────────────────────────
// Fresh-start countdown · steal Apple Workout's language.
// 3 → 2 → 1 → "Listening" → recording UI.
// Soft haptic per second. Subtle waveform waking up underneath.
// Tap anywhere to cancel. Bypassed on Next-clip (mic never pauses).
// ─────────────────────────────────────────────────────────────
function CountdownRing({ phase = 'sweep', progress = 0, size = 200, stroke = 15 }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const bright = '#E55A22'; // brighter than --accent for countdown readability
  const dim = '#9A3815';
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {phase === 'draw' ? (
        <svg width={size} height={size} style={{ position: 'absolute', inset: 0, transform: 'rotate(90deg)' }}>
          <circle cx={size/2} cy={size/2} r={r}
            fill="none" stroke={bright} strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={c}
            strokeDashoffset={c * (1 - progress)}
          />
        </svg>
      ) : (
        <>
          <svg width={size} height={size} style={{ position: 'absolute', inset: 0 }}>
            <circle cx={size/2} cy={size/2} r={r}
              fill="none" stroke={bright} strokeWidth={stroke}
            />
          </svg>
          <svg width={size} height={size} style={{ position: 'absolute', inset: 0, transform: 'rotate(90deg) scaleX(-1)' }}>
            <circle cx={size/2} cy={size/2} r={r}
              fill="none" stroke={dim} strokeWidth={stroke}
              strokeDasharray={c}
              strokeDashoffset={c * (1 - progress)}
            />
          </svg>
        </>
      )}
    </div>
  );
}

function WakingWaveform() { return null; }

function CountdownBody({ display, phase = 'sweep', progress, isReady = false }) {
  return (
    <div style={{
      position: 'absolute', top: 110, left: 0, right: 0, bottom: 0,
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      padding: '8px 0 30px',
    }}>
      {/* tap-to-cancel hint */}
      <div style={{
        marginTop: 12, fontSize: 11, color: PX.ink3,
        letterSpacing: 0.4, textTransform: 'uppercase', fontWeight: 600,
      }}>
        Tap to cancel
      </div>

      {/* ring + number/word */}
      <div style={{
        position: 'relative', width: 200, height: 200,
        marginTop: 64,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <CountdownRing phase={phase} progress={progress}/>
        <div style={{
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro", system-ui, sans-serif',
          fontSize: isReady ? 44 : 108,
          fontWeight: isReady ? 500 : 200,
          letterSpacing: isReady ? -0.6 : -3.6,
          lineHeight: 1, color: PX.ink,
          fontVariantNumeric: 'tabular-nums',
          position: 'relative',
        }}>{display}</div>
      </div>
    </div>
  );
}

// 6a. "Ready" · bright ring drawing in clockwise from 180°
function ScrVCCountdownReady() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <CountdownBody display="Ready" phase="draw" progress={0.72} isReady/>
    </PhoneScreen>
  );
}

// 6b. "3" · dim sweep starts CCW from 180° (just started)
function ScrVCCountdown3() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <CountdownBody display="3" phase="sweep" progress={0.08}/>
    </PhoneScreen>
  );
}

// 7. "2" · dim sweep at ~38%
function ScrVCCountdown2() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <CountdownBody display="2" phase="sweep" progress={0.38}/>
    </PhoneScreen>
  );
}

// 8. "1" · bright crescent at 12 o'clock
function ScrVCCountdown1() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <CountdownBody display="1" phase="sweep" progress={0.72}/>
    </PhoneScreen>
  );
}

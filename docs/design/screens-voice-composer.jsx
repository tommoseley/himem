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
        background: PX.wash2,
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
      boxShadow: PX.shadowFabAccent,
    }}>
      {/* Filled rounded square = "stop" */}
      <div style={{ width: 26, height: 26, background: PX.accentInk, borderRadius: 5 }}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Next-clip satellite — 56×56, ochre-tinted, forward-chevron-with-trailing-dot.
// `bright=true` shows the post-tap fill + halo state.
// ─────────────────────────────────────────────────────────────
function NextSatellite({ bright = false, disabled = false }) {
  // Disabled state = accent at low alpha against paper. Expressed via
  // color-mix so it adapts to both modes.
  const bg = disabled ? `color-mix(in oklab, ${PX.accent} 10%, ${PX.paper})`
    : bright ? PX.accent
    : PX.accentTint2;
  const fg = disabled ? `color-mix(in oklab, ${PX.accent} 45%, ${PX.paper})`
    : bright ? PX.accentInk
    : PX.accent;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
      <div style={{
        width: 56, height: 56, borderRadius: 28,
        background: bg,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: bright ? `0 0 0 3px color-mix(in oklab, ${PX.accent} 30%, transparent)` : 'none',
        transition: 'all 200ms',
      }}>
        <svg width="22" height="14" viewBox="0 0 22 14" fill="none" stroke={fg} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 2l5 5-5 5"/>
          <circle cx="15" cy="7" r="1.8" fill={fg} stroke="none"/>
        </svg>
      </div>
      <span style={{
        fontSize: 11, fontWeight: 600,
        color: disabled ? PX.ink3 : PX.accent,
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
// ComposerBodyTight — proposed (May 25 2026).
// Same elements as ComposerBody, but:
//   (1) REC + timer + waveform pulled into a single tight cluster in the
//       upper-third of the screen, instead of spread top-to-middle.
//   (2) "Clip N · on a roll" sits between timer and waveform — same place
//       as the watch screen, anchored to the cluster.
//   (3) Live transcript area added below the waveform — Source Serif italic,
//       center-aligned, low opacity. Empty state reads "Listening…".
//       Grows as the user speaks; truncates oldest lines once it fills.
//   (4) The negative space becomes one big breath between transcript bottom
//       and Stop & save, rather than three orphaned bands.
//
// Per-frame `transcript` prop: pass a string for the live-transcribed text
// to render. Pass null/undefined for the empty "Listening…" hint.
// ─────────────────────────────────────────────────────────────
function ComposerBodyTight({ timer = '0:23', clipNum = 1, nextBright = false, waveformSeed = 0, transcript = null }) {
  const onRoll = clipNum >= 2;
  return (
    <div style={{
      position: 'absolute', top: 110, left: 0, right: 0, bottom: 0,
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      padding: '8px 0 30px',
    }}>
      {/* REC indicator — small breath above (was 16, keep) */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        color: PX.accent, marginTop: 14,
      }}>
        <span style={{ width: 6, height: 6, borderRadius: 3, background: PX.accent }}/>
        <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase' }}>Rec</span>
      </div>

      {/* Big timer — pulled up: was marginTop 18, keep, but everything below tightens */}
      <div style={{
        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro", system-ui, sans-serif',
        fontSize: 72, fontWeight: 200, letterSpacing: -2.4, lineHeight: 1,
        color: PX.ink, marginTop: 12,
        fontVariantNumeric: 'tabular-nums',
      }}>{timer}</div>

      {/* Live waveform — pulled up tight to timer (was marginTop 32 from state line,
          now sits 16 below timer with state line BELOW the waveform) */}
      <div style={{ width: '100%', marginTop: 18 }}>
        <Waveform seed={waveformSeed}/>
      </div>

      {/* Persistent state line — moved BELOW the waveform so it labels the
          on-a-roll moment without separating timer from waveform. */}
      <div style={{
        height: 16, marginTop: 6,
        fontSize: 12, fontWeight: 600,
        color: onRoll ? PX.accent : 'transparent',
        letterSpacing: -0.1,
      }}>
        {onRoll ? `Clip ${clipNum} · on a roll` : ''}
      </div>

      {/* Live transcript — Source Serif italic, center-aligned, dimmed.
          Empty state shows "Listening…" in ink4. */}
      <div style={{
        width: '100%', padding: '0 32px',
        marginTop: 22,
        textAlign: 'center',
      }}>
        {transcript ? (
          <p style={{
            fontFamily: PX.serif,
            fontStyle: 'italic',
            fontWeight: 400,
            fontSize: 17,
            lineHeight: 1.55,
            color: PX.ink3,
            margin: 0,
            letterSpacing: -0.1,
            textWrap: 'pretty',
          }}>{transcript}</p>
        ) : (
          <p style={{
            fontFamily: PX.serif,
            fontStyle: 'italic',
            fontWeight: 400,
            fontSize: 15,
            lineHeight: 1.5,
            color: PX.ink4,
            margin: 0,
          }}>Listening&hellip;</p>
        )}
      </div>

      {/* Bottom commit row — same as base composer */}
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
        <div style={{
          position: 'absolute',
          left: 'calc(50% + 42px + 36px)',
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

// ─────────────────────────────────────────────────────────────
// PROPOSED · tight cluster + live transcript. May 25 2026.
//   Direct-voice + append flows, using ComposerBodyTight in place of
//   ComposerBody. Identical chrome, redistributed vertical rhythm,
//   plus a live transcript region populated by the on-device transcription
//   stream.
// ─────────────────────────────────────────────────────────────
function ScrVCTightEmpty() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <ComposerBodyTight timer="0:03" clipNum={1} waveformSeed={6} transcript={null}/>
    </PhoneScreen>
  );
}

function ScrVCTightClip1() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <ComposerBodyTight
        timer="0:14"
        clipNum={1}
        waveformSeed={2}
        transcript="The combine harvester was an amazing invention, but what it really did was disrupt everything\u2026"
      />
    </PhoneScreen>
  );
}

function ScrVCTightMidRoll() {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <ComposerBodyTight
        timer="0:23"
        clipNum={2}
        waveformSeed={3}
        transcript="\u2026and a lot of people lost their jobs, had to change the way they were or find entirely different industries. AI is going to be like that."
      />
    </PhoneScreen>
  );
}

function ScrVCTightAppend() {
  return (
    <PhoneScreen>
      <ComposerHeader appendingTo="Saturday garden walkthrough"/>
      <ComposerBodyTight
        timer="0:31"
        clipNum={1}
        waveformSeed={5}
        transcript="Put the lettuce in this morning \u2014 about three weeks earlier than last year. Soil was already warm, which surprised me."
      />
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrVCDirectClip1,
  ScrVCDirectMidRoll,
  ScrVCMomentOfTap,
  ScrVCAppendClip1,
  ScrVCAppendMidRoll,
  ScrVCTightEmpty,
  ScrVCTightClip1,
  ScrVCTightMidRoll,
  ScrVCTightAppend,
  ScrVCBreath,
  ScrVCFirstRunTutorial,
  BREATH_CAPTIONS,
});

// ─────────────────────────────────────────────────────────────
// First-run capture tutorial (shown ONCE, before the first recording).
// Teaches three things the UI can't say on its own:
//   1. what a recording is (capture a thought, transcribed for you),
//   2. the Next / "on a roll" behavior (the button no label can fully explain),
//   3. that the Apple Watch records too (cross-surface capture).
// Dismissed with "Start recording"; persisted so it never shows again.
// ─────────────────────────────────────────────────────────────
function TutorialPoint({ glyph, title, body, accent }) {
  return (
    <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
      <span style={{
        width: 40, height: 40, borderRadius: 11, flexShrink: 0,
        background: accent ? PX.accentTint2 : PX.aiTint,
        color: accent ? PX.accent : PX.ai,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>{glyph}</span>
      <div style={{ flex: 1, paddingTop: 1 }}>
        <div style={{ fontSize: 15.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>{title}</div>
        <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.5, marginTop: 3, letterSpacing: -0.05 }}>{body}</div>
      </div>
    </div>
  );
}

function ScrVCFirstRunTutorial() {
  const micGlyph = <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>;
  const nextGlyph = <svg width="20" height="14" viewBox="0 0 22 14" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M2 2l5 5-5 5"/><circle cx="15" cy="7" r="1.8" fill="currentColor" stroke="none"/></svg>;
  const watchGlyph = <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>;
  return (
    <PhoneScreen>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', background: PX.paper }}>
        <div style={{ height: 40 }}/>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', color: PX.ink3 }}>
          Capturing a memory
        </div>
        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 28, lineHeight: 1.15, letterSpacing: -0.5, color: PX.ink, margin: '8px 0 0' }}>
          Just start talking.
        </h1>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: PX.ink2, margin: '10px 0 26px', letterSpacing: -0.1 }}>
          HiMem listens, transcribes, and keeps it — no buttons to fumble while a thought is fresh.
        </p>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <TutorialPoint accent glyph={micGlyph} title="Speak, and it's saved"
            body="Tap record and talk. The audio stays on your device; the words become a searchable memory." />
          <TutorialPoint accent glyph={nextGlyph} title="On a roll? Tap Next"
            body="Next saves the current clip and starts a fresh one without stopping — they group into one memory. Great for a list of thoughts." />
          <TutorialPoint glyph={watchGlyph} title="Your Watch records too"
            body="Catch a thought on your Apple Watch and it syncs here automatically. No phone needed in the moment." />
        </div>

        <div style={{ flex: 1, minHeight: 20 }}/>
        <div style={{ paddingBottom: 30 }}>
          <button style={{
            height: 52, width: '100%', borderRadius: 14, border: 'none', cursor: 'pointer',
            background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 9,
          }}>
            {micGlyph && <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={PX.accentInk} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>}
            Start recording
          </button>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 10, lineHeight: 1.4 }}>
            You can always find this again in Settings.
          </div>
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// Fresh-start countdown · revised May 27 2026.
// One second. One ring fills clockwise. Centered caption.
// "Tap to cancel" hint above. Soft haptic at start, slightly stronger at end.
// Caption rotates across recordings — index persisted in localStorage,
// incremented after each start. (Code: bump the index when the user
// commits to the recording, NOT on cancel.)
// Bypassed on Next-clip (mic never pauses).
// ─────────────────────────────────────────────────────────────

const BREATH_CAPTIONS = [
  'Ready when you are.',
  'Start anywhere.',
  'Whenever it comes.',
  'Take your time.',
  'Go ahead.',
  'Say it naturally.',
  "When you're ready.",
  'Hold the thought.',
  'Here when you need it.',
  'Catch the thought.',
  "Don't lose it.",
  "We're ready.",
  'Speak freely.',
];

function BreathRing({ progress = 1, size = 200, stroke = 14 }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {/* faint dim ring underneath — gives the bright fill something to fill against */}
      <svg width={size} height={size} style={{ position: 'absolute', inset: 0 }}>
        <circle cx={size/2} cy={size/2} r={r}
          fill="none" stroke={PX.accentTint2} strokeWidth={stroke}
        />
      </svg>
      {/* bright ring drawing in clockwise from 12 o'clock */}
      <svg width={size} height={size} style={{ position: 'absolute', inset: 0, transform: 'rotate(-90deg)' }}>
        <circle cx={size/2} cy={size/2} r={r}
          fill="none" stroke={PX.accent} strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c * (1 - progress)}
        />
      </svg>
    </div>
  );
}

function BreathBody({ caption, progress = 0.62 }) {
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

      {/* ring + caption inside */}
      <div style={{
        position: 'relative', width: 200, height: 200,
        marginTop: 84,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <BreathRing progress={progress}/>
        <div style={{
          fontFamily: PX.serif,
          fontStyle: 'italic',
          fontWeight: 400,
          fontSize: 22,
          lineHeight: 1.2,
          letterSpacing: -0.2,
          color: PX.ink,
          textAlign: 'center',
          padding: '0 18px',
          position: 'relative',
        }}>{caption}</div>
      </div>

      {/* spacer */}
      <div style={{ flex: 1 }}/>
    </div>
  );
}

// One screen per caption — used in the canvas to show the rotation.
// All show the ring at ~62% progress so the rendered state is identical
// across all sixteen — only the caption varies.
function ScrVCBreath({ index = 0 }) {
  return (
    <PhoneScreen>
      <ComposerHeader />
      <BreathBody caption={BREATH_CAPTIONS[index]}/>
    </PhoneScreen>
  );
}

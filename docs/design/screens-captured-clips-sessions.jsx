// screens-captured-clips-sessions.jsx
// Session-first Captured Clips · v2 (May 19 2026).
//
// Locked rules from `Captured Clips · session-first · spec.md`:
//  • One surface only. No session-detail screen. Cards expand in place.
//  • No multi-select. Inclusion is a per-row ring toggle, always live.
//  • Selection = ring, never check.
//  • The card's "Make a Memory" pill is always present and always means
//    "bundle the currently-included clips." No "Bundle N as memory" copy.
//  • Auto-excluded clips are a muted note, never amber, never a chip.
//  • Operational surface — SF Pro throughout, no Source Serif on the list.
//  • Vocabulary: "Make a Memory" everywhere. "Bundle" is retired.

// ─────────────────────────────────────────────────────────────
// Top chrome — back ‹ on the left, "Done" on the right. No eyebrow.
// ─────────────────────────────────────────────────────────────
function CCHeader({ count = 9, range = 'Today, 12:01 PM–3:36 PM', sessions = 3 }) {
  return (
    <div style={{ padding: '8px 14px 14px' }}>
      <div style={{
        display: 'flex', alignItems: 'center', height: 32,
        justifyContent: 'space-between',
      }}>
        <span style={{
          width: 30, height: 30, borderRadius: 15,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          color: PX.ink2,
        }}>
          <svg width="10" height="16" viewBox="0 0 9 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M7 1L1 7l6 6"/>
          </svg>
        </span>
        <span style={{
          fontSize: 14, fontWeight: 500, color: PX.accent, letterSpacing: -0.1,
        }}>Done</span>
      </div>
      <div style={{
        fontSize: 22, fontWeight: 600, color: PX.ink, letterSpacing: -0.4, marginTop: 14, lineHeight: 1.15,
      }}>
        {count} from your Watch
      </div>
      <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>
        {sessions} session{sessions === 1 ? '' : 's'} · {range}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Selection toggle — a ring. Filled = included, empty = excluded.
// Never a check glyph. (Crucible rule.)
// ─────────────────────────────────────────────────────────────
function IncludeRing({ included = true }) {
  return (
    <span style={{
      width: 20, height: 20, borderRadius: 10, flexShrink: 0,
      border: '1.5px solid ' + (included ? PX.accent : PX.ink4),
      background: included ? PX.accent : 'transparent',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    }}>
      {included && (
        <span style={{ width: 8, height: 8, borderRadius: 4, background: PX.accentInk }} />
      )}
    </span>
  );
}

// ─────────────────────────────────────────────────────────────
// Make-a-Memory pill — full-width within the card.
// The action of the card. Same label every time, regardless of clip count.
// ─────────────────────────────────────────────────────────────
function MakeAMemoryPill({ disabled = false }) {
  return (
    <div style={{
      height: 40, borderRadius: 20,
      background: PX.accent,
      opacity: disabled ? 0.35 : 1,
      color: PX.accentInk,
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      fontSize: 14, fontWeight: 600, letterSpacing: -0.1,
    }}>
      Make a Memory
      <svg width="10" height="14" viewBox="0 0 10 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 1l5 6-5 6"/>
      </svg>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Inline clip row — appears inside an expanded card.
// No screen drill-in. This is the exception view, in place.
// ─────────────────────────────────────────────────────────────
function ClipRow({ offset, duration, transcript, included = true, autoExcluded = false, last = false }) {
  const muted = !included || autoExcluded;
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 12,
      padding: '12px 0', borderBottom: last ? 'none' : '1px solid ' + PX.divider,
    }}>
      <span style={{ marginTop: 3 }}>
        <IncludeRing included={included} />
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6,
          fontSize: 10.5, color: PX.ink3,
          fontVariantNumeric: 'tabular-nums', letterSpacing: -0.05,
        }}>
          <span>{offset}</span>
          <span style={{ color: PX.ink4 }}>·</span>
          <span>{duration}</span>
        </div>
        <div style={{
          fontSize: 13, marginTop: 2, lineHeight: 1.4, letterSpacing: -0.1,
          color: muted ? PX.ink3 : PX.ink2,
          fontStyle: autoExcluded ? 'italic' : 'normal',
          opacity: !included && !autoExcluded ? 0.55 : 1,
        }}>
          {autoExcluded ? 'No speech detected · likely accidental' : `“${transcript}”`}
        </div>
      </div>
      <span style={{
        width: 26, height: 26, flexShrink: 0,
        color: PX.ink3,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="10" height="11" viewBox="0 0 12 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round">
          <polygon points="3,1.5 11,7 3,12.5" />
        </svg>
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Location pin — small glyph preceding a session's place name.
// Watch captures location at record time; absent when no GPS fix.
// ─────────────────────────────────────────────────────────────
function PinGlyph() {
  return (
    <svg width="9" height="11" viewBox="0 0 10 13" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
      <path d="M5 12c2.5-3 4-5.2 4-7a4 4 0 1 0-8 0c0 1.8 1.5 4 4 7z"/>
      <circle cx="5" cy="5" r="1.4"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Session card.
// `expanded` swaps the transcript preview for inline clip rows.
// Action pill is the same in both states.
// ─────────────────────────────────────────────────────────────
function SessionCard({
  time, date = 'Today', place, clips, duration, previewLine, autoExcluded = 0,
  expanded = false, clipsDetail = null, disabled = false,
}) {
  const excludeNote =
    autoExcluded > 0
      ? `${autoExcluded} clip${autoExcluded > 1 ? 's' : ''} auto-excluded · no speech`
      : null;

  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 12,
    }}>
      {/* Meta — time/clips/duration, then date + location beneath */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        <div style={{
          display: 'flex', alignItems: 'baseline', gap: 6,
          fontSize: 12.5, color: PX.ink3, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.1,
        }}>
          <span style={{ fontWeight: 600, color: PX.ink, fontSize: 13.5, letterSpacing: -0.15 }}>{time}</span>
          <span style={{ color: PX.ink4 }}>·</span>
          <span>{clips} clip{clips > 1 ? 's' : ''}</span>
          <span style={{ color: PX.ink4 }}>·</span>
          <span>{duration}</span>
        </div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 5,
          fontSize: 11.5, color: PX.ink3, letterSpacing: -0.05,
        }}>
          {place && (
            <React.Fragment>
              <span style={{ color: PX.ink4, display: 'inline-flex' }}><PinGlyph /></span>
              <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{place}</span>
              <span style={{ color: PX.ink4 }}>·</span>
            </React.Fragment>
          )}
          <span style={{ fontVariantNumeric: 'tabular-nums' }}>{date}</span>
        </div>
      </div>

      {/* Body — preview when collapsed, clip rows when expanded */}
      {!expanded ? (
        <div>
          <div style={{
            fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, letterSpacing: -0.1,
          }}>
            “{previewLine}”
          </div>
          {excludeNote && (
            <div style={{
              fontSize: 11.5, color: PX.ink3, marginTop: 6, letterSpacing: -0.05,
            }}>
              {excludeNote}
            </div>
          )}
        </div>
      ) : (
        <div>
          {clipsDetail.map((c, i) => (
            <ClipRow
              key={i}
              offset={c.offset}
              duration={c.duration}
              transcript={c.transcript}
              included={c.included}
              autoExcluded={c.autoExcluded}
              last={i === clipsDetail.length - 1}
            />
          ))}
        </div>
      )}

      <MakeAMemoryPill disabled={disabled} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 1. Session list — default state, all cards collapsed.
// ─────────────────────────────────────────────────────────────
function ScrCCSessionList() {
  return (
    <PhoneScreen>
      <CCHeader count={9} sessions={3} range="today, 12:01 – 3:36 PM" />
      <div style={{
        flex: 1, overflow: 'hidden',
        padding: '0 14px 14px', display: 'flex', flexDirection: 'column', gap: 10,
      }}>
        <SessionCard
          time="3:36 PM"
          date="Today"
          place="Marsh Walk, Murrells Inlet"
          clips={4}
          duration="0:12"
          previewLine="One, two, three … one, two, three, four, five … one, two, three, four, five? Hey."
          autoExcluded={1}
        />
        <SessionCard
          time="2:40 PM"
          date="Today"
          place="18 Columbus Cir, Bluffton"
          clips={3}
          duration="0:08"
          previewLine="The bit about one point eight billion — I stopped them right there, said first of all that's not even the right number …"
        />
        <SessionCard
          time="12:01 PM"
          date="Today"
          place="Home"
          clips={2}
          duration="0:06"
          previewLine="Garden drip lines need replacing before July … basil starts should be ready Saturday."
        />
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 2. Session list — one card expanded in place.
// Replaces the old "session detail" drill-in screen.
// ─────────────────────────────────────────────────────────────
function ScrCCSessionListExpanded() {
  const clips336 = [
    { offset: '0:00', duration: '0:00', autoExcluded: true,  included: false },
    { offset: '+10s', duration: '0:05', transcript: 'One, two, three.', included: true },
    { offset: '+24s', duration: '0:02', transcript: 'One, two, three, four, five.', included: true },
    { offset: '+34s', duration: '0:03', transcript: 'One, two, three, four, five? Hey.', included: true },
  ];
  return (
    <PhoneScreen>
      <CCHeader count={9} sessions={3} range="today, 12:01 – 3:36 PM" />
      <div style={{
        flex: 1, overflow: 'hidden',
        padding: '0 14px 14px', display: 'flex', flexDirection: 'column', gap: 10,
      }}>
        <SessionCard
          time="3:36 PM"
          date="Today"
          place="Marsh Walk, Murrells Inlet"
          clips={4}
          duration="0:12"
          autoExcluded={1}
          expanded
          clipsDetail={clips336}
        />
        <SessionCard
          time="2:40 PM"
          date="Today"
          place="18 Columbus Cir, Bluffton"
          clips={3}
          duration="0:08"
          previewLine="The bit about one point eight billion — I stopped them right there, said first of all that's not even the right number …"
        />
        <SessionCard
          time="12:01 PM"
          date="Today"
          place="Home"
          clips={2}
          duration="0:06"
          previewLine="Garden drip lines need replacing before July … basil starts should be ready Saturday."
        />
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 3. Make-a-Memory confirm sheet — the seam.
// Voice softens here: Source Serif AI-blue title.
// ─────────────────────────────────────────────────────────────
function ScrCCBundleConfirm() {
  const behind = (
    <PhoneScreen>
      <CCHeader count={9} sessions={3} range="today, 12:01 – 3:36 PM" />
      <div style={{ padding: '0 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <SessionCard
          time="3:36 PM" date="Today" place="Marsh Walk, Murrells Inlet" clips={4} duration="0:12"
          previewLine="One, two, three … one, two, three, four, five … one, two, three, four, five? Hey."
          autoExcluded={1}
        />
      </div>
    </PhoneScreen>
  );
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="68%">
        <div style={{ padding: '14px 22px 20px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 14 }}>
            <span style={{ fontSize: 14.5, color: PX.ink2 }}>Cancel</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink }}>New memory</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 14.5, fontWeight: 600, color: PX.accent }}>Create</span>
          </div>

          <div style={{
            background: PX.card, border: '1px solid ' + PX.hairline,
            borderRadius: 12, padding: '10px 14px',
            display: 'flex', alignItems: 'center', gap: 10, marginBottom: 18,
          }}>
            <div style={{
              width: 28, height: 28, borderRadius: 7, background: PX.accentTint, color: PX.accent,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11v1a7 7 0 0 0 14 0v-1"/></svg>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>3 clips · 3:36 PM · 0:12</div>
              <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 2, display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{ color: PX.ink4, display: 'inline-flex' }}><PinGlyph /></span>
                <span>Marsh Walk, Murrells Inlet · Today · 1 clip excluded</span>
              </div>
            </div>
          </div>

          <div style={{ fontSize: 10.5, fontWeight: 700, color: PX.ink3, letterSpacing: 1.6, textTransform: 'uppercase', marginBottom: 8 }}>
            Title <span style={{ marginLeft: 6, background: PX.aiTint, color: PX.ai, padding: '2px 6px', borderRadius: 4, fontSize: 9.5, letterSpacing: 0.5 }}>AI</span>
          </div>
          <div style={{
            background: PX.card, border: '1px solid ' + PX.aiTint, borderRadius: 10,
            padding: '12px 14px', fontFamily: PX.serif, fontSize: 17, color: PX.ai,
            letterSpacing: -0.1,
          }}>
            Counting and a hello
          </div>
          <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 6 }}>
            Suggested from your transcripts. Tap to rewrite.
          </div>

          <div style={{ fontSize: 10.5, fontWeight: 700, color: PX.ink3, letterSpacing: 1.6, textTransform: 'uppercase', marginTop: 18, marginBottom: 8 }}>
            Topic
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            <span className="cru-topic-chip" style={{ '--topic-color': topicVar('plum') }}>
              <span className="cru-topic-dot" />
              How We Work
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '5px 11px', borderRadius: 13, border: '1px solid ' + PX.hairline, fontSize: 12.5, color: PX.ink2 }}>
              + New
            </span>
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// SYNC / INCOMING
// The operational truth the old surface hid: clips don't teleport
// in. There are two phases — DOWNLOAD (audio watch→phone, known
// duration, determinate) and TRANSCRIBE (phone reads it, unknown,
// indeterminate). The wait the user feels is mostly transcribe;
// naming the phase is what kills the frustration.
// ─────────────────────────────────────────────────────────────

// One-time keyframes for the in-progress motion. Rendered inside
// each sync screen so the canvas artboards are self-contained.
function SyncStyles() {
  return (
    <style>{`
      @keyframes ccPulse  { 0%,100% { opacity: 1 } 50% { opacity: 0.3 } }
      @keyframes ccBar    { 0% { background-position: 0 0 } 100% { background-position: 22px 0 } }
      @keyframes ccShimmer{ 0% { background-position: -160px 0 } 100% { background-position: 220px 0 } }
    `}</style>
  );
}

// Small phase glyphs — status is never color alone (Crucible rule).
function PhaseIcon({ phase }) {
  const c = 'currentColor';
  if (phase === 'waiting') {
    return (
      <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="7" cy="7" r="5.5"/><path d="M7 4v3l2 1.5"/>
      </svg>
    );
  }
  if (phase === 'downloading') {
    return (
      <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        <path d="M7 1.5v8"/><path d="M3.5 6.5L7 10l3.5-3.5"/><path d="M2.5 12.5h9"/>
      </svg>
    );
  }
  if (phase === 'transcribing') {
    return (
      <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke={c} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2.5 4h9M2.5 7h9M2.5 10h5.5"/>
      </svg>
    );
  }
  // paused
  return (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 3.5v7M9 3.5v7"/>
    </svg>
  );
}

// The phase pill that sits where the action pill is on a ready card.
function PhasePill({ phase }) {
  const map = {
    waiting:      { label: 'Waiting',     fg: PX.ink3,    bg: PX.sunk,       pulse: false },
    downloading:  { label: 'Receiving',   fg: PX.accent,  bg: PX.accentTint, pulse: true  },
    transcribing: { label: 'Transcribing',fg: PX.ink2,    bg: PX.sunk,       pulse: true  },
    paused:       { label: 'Paused',      fg: PX.warnInk, bg: PX.warnTint,   pulse: false },
  };
  const s = map[phase] || map.waiting;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      fontSize: 10.5, fontWeight: 700, color: s.fg, background: s.bg,
      padding: '4px 9px', borderRadius: 11, letterSpacing: 0.3, textTransform: 'uppercase',
      animation: s.pulse ? 'ccPulse 1.6s ease-in-out infinite' : 'none',
    }}>
      <PhaseIcon phase={phase} />
      {s.label}
    </span>
  );
}

// Global sync strip — the at-a-glance "system knows, and it's working"
// signal. Scales: summarizes count + which is active. Sits under header.
function SyncStrip({ receiving = 1, total = 2, paused = false }) {
  return (
    <div style={{
      margin: '0 14px 10px', padding: '10px 14px',
      background: PX.card, border: '1px solid ' + (paused ? PX.warnTint : PX.hairline),
      borderRadius: 12, display: 'flex', flexDirection: 'column', gap: 8,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
        <span style={{
          width: 8, height: 8, borderRadius: 4, flexShrink: 0,
          background: paused ? PX.warn : PX.accent,
          animation: paused ? 'none' : 'ccPulse 1.4s ease-in-out infinite',
        }} />
        <span style={{ flex: 1, fontSize: 12.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>
          {paused ? 'Waiting for your Watch' : 'Receiving from your Watch'}
        </span>
        {!paused && (
          <span style={{ fontSize: 11.5, color: PX.ink3, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.05 }}>
            {receiving} of {total}
          </span>
        )}
      </div>
      <div style={{ fontSize: 11, color: PX.ink3, lineHeight: 1.4, letterSpacing: -0.05 }}>
        {paused
          ? 'Your Watch went out of range. Sync picks up where it left off when it’s near.'
          : 'Keep HiMem open to finish faster — it also syncs in the background.'}
      </div>
    </div>
  );
}

// A horizontal shimmer line — skeleton for text that hasn't arrived.
function ShimmerLine({ width = '100%' }) {
  return (
    <div style={{
      height: 9, width, borderRadius: 5, marginBottom: 6,
      background: `linear-gradient(90deg, ${PX.sunk} 0%, rgba(26,22,18,0.10) 50%, ${PX.sunk} 100%)`,
      backgroundSize: '220px 100%',
      animation: 'ccShimmer 1.3s linear infinite',
    }} />
  );
}

// ─────────────────────────────────────────────────────────────
// Incoming session card — a proto-card for a session still arriving.
// Shows what we know (time, place, duration) and its phase where the
// transcript will eventually be. No Make-a-Memory pill until ready.
// ─────────────────────────────────────────────────────────────
function IncomingCard({ time, date = 'Today', place, clips = 1, duration, phase, gotten, paused = false }) {
  const effPhase = paused ? 'paused' : phase;
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
      padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 12,
      opacity: effPhase === 'waiting' ? 0.72 : 1,
    }}>
      {/* Meta — same shape as a ready card, with phase pill trailing */}
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
          <div style={{
            display: 'flex', alignItems: 'baseline', gap: 6,
            fontSize: 12.5, color: PX.ink3, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.1,
          }}>
            <span style={{ fontWeight: 600, color: PX.ink, fontSize: 13.5, letterSpacing: -0.15 }}>{time}</span>
            <span style={{ color: PX.ink4 }}>·</span>
            <span>{clips} clip{clips > 1 ? 's' : ''}</span>
            <span style={{ color: PX.ink4 }}>·</span>
            <span>{duration}</span>
          </div>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 5,
            fontSize: 11.5, color: PX.ink3, letterSpacing: -0.05,
          }}>
            {place && (
              <React.Fragment>
                <span style={{ color: PX.ink4, display: 'inline-flex' }}><PinGlyph /></span>
                <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{place}</span>
                <span style={{ color: PX.ink4 }}>·</span>
              </React.Fragment>
            )}
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>{date}</span>
          </div>
        </div>
        <PhasePill phase={effPhase} />
      </div>

      {/* Phase body — replaces transcript + action while in flight */}
      {effPhase === 'downloading' && (
        <div>
          <div style={{
            height: 6, borderRadius: 3, background: PX.sunk, overflow: 'hidden', marginBottom: 7,
          }}>
            <div style={{
              height: '100%', width: '58%', borderRadius: 3,
              background: `repeating-linear-gradient(115deg, ${PX.accent} 0 11px, ${PX.accentMute || PX.accent} 11px 22px)`,
              backgroundSize: '22px 100%', animation: 'ccBar 0.7s linear infinite',
              opacity: 0.92,
            }} />
          </div>
          <div style={{ fontSize: 11.5, color: PX.ink3, letterSpacing: -0.05, fontVariantNumeric: 'tabular-nums' }}>
            Receiving audio · {gotten} of {duration}
          </div>
        </div>
      )}

      {effPhase === 'transcribing' && (
        <div>
          <ShimmerLine width="96%" />
          <ShimmerLine width="100%" />
          <ShimmerLine width="64%" />
          <div style={{ fontSize: 11.5, color: PX.ink3, letterSpacing: -0.05, marginTop: 2 }}>
            Audio’s here. Reading it now.
          </div>
        </div>
      )}

      {effPhase === 'waiting' && (
        <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, letterSpacing: -0.05 }}>
          In line behind the clip downloading now.
        </div>
      )}

      {effPhase === 'paused' && (
        <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, letterSpacing: -0.05 }}>
          {gotten ? `Got ${gotten} of ${duration} so far. ` : ''}Picks up when your Watch is near.
        </div>
      )}
    </div>
  );
}

// Sync-aware header — count is TOTAL known (ready + incoming); the
// subline splits it. Keeps "from your Watch" honest about everything
// the Watch is sending, not just what finished.
function CCHeaderSync({ total = 4, ready = 2, syncing = 2, range = 'today, 3:37 – 3:50 PM' }) {
  return (
    <div style={{ padding: '8px 14px 14px' }}>
      <div style={{ display: 'flex', alignItems: 'center', height: 32, justifyContent: 'space-between' }}>
        <span style={{
          width: 30, height: 30, borderRadius: 15,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: PX.ink2,
        }}>
          <svg width="10" height="16" viewBox="0 0 9 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M7 1L1 7l6 6"/>
          </svg>
        </span>
        <span style={{ fontSize: 14, fontWeight: 500, color: PX.accent, letterSpacing: -0.1 }}>Done</span>
      </div>
      <div style={{ fontSize: 22, fontWeight: 600, color: PX.ink, letterSpacing: -0.4, marginTop: 14, lineHeight: 1.15 }}>
        {total} from your Watch
      </div>
      <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>
        {ready} ready · {syncing} syncing · {range}
      </div>
    </div>
  );
}

// The two retrieved sessions from the screenshots — reused across the
// sync screens so the in-flight cards have real, ready siblings below.
function ReadyCamSessions() {
  return (
    <React.Fragment>
      <SessionCard
        time="3:43 PM" date="Today" place="Marsh Walk, Murrells Inlet" clips={1} duration="0:14"
        previewLine="back hole. So once I can pre-capture, more than enough. All right, our road trip. Pixel binning in 2026 for 4K video, Sony has lost the plot. This was interesting because I did…"
      />
      <SessionCard
        time="3:37 PM" date="Today" place="Marsh Walk, Murrells Inlet" clips={1} duration="0:37"
        previewLine="than the 87R4, and 7R5. Both the latter were set backwards with their slower scanning sensor, then that in the A7 R3. I think that saying that you're not getting the b…"
      />
    </React.Fragment>
  );
}

// ─────────────────────────────────────────────────────────────
// SYNC SCREEN 1 — actively receiving.
// 3:50 downloading, 3:44 waiting, then the two ready sessions.
// ─────────────────────────────────────────────────────────────
function ScrCCSyncing() {
  return (
    <PhoneScreen>
      <SyncStyles />
      <CCHeaderSync total={4} ready={2} syncing={2} />
      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <SyncStrip receiving={1} total={2} />
        <div style={{ padding: '0 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          <IncomingCard time="3:50 PM" place="Marsh Walk, Murrells Inlet" duration="0:06" gotten="0:04" phase="downloading" />
          <IncomingCard time="3:44 PM" place="Marsh Walk, Murrells Inlet" duration="5:00" phase="waiting" />
          <ReadyCamSessions />
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// SYNC SCREEN 2 — first clip's audio is in, now transcribing;
// the long 5:00 clip is mid-download. Shows the phase handoff.
// ─────────────────────────────────────────────────────────────
function ScrCCTranscribing() {
  return (
    <PhoneScreen>
      <SyncStyles />
      <CCHeaderSync total={4} ready={2} syncing={2} />
      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <SyncStrip receiving={2} total={2} />
        <div style={{ padding: '0 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          <IncomingCard time="3:50 PM" place="Marsh Walk, Murrells Inlet" duration="0:06" phase="transcribing" />
          <IncomingCard time="3:44 PM" place="Marsh Walk, Murrells Inlet" duration="5:00" gotten="1:48" phase="downloading" />
          <ReadyCamSessions />
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// SYNC SCREEN 3 — stalled. Watch went out of range mid-transfer.
// Honest, no blame. Partial progress is preserved.
// ─────────────────────────────────────────────────────────────
function ScrCCStalled() {
  return (
    <PhoneScreen>
      <SyncStyles />
      <CCHeaderSync total={4} ready={2} syncing={2} />
      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <SyncStrip paused />
        <div style={{ padding: '0 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          <IncomingCard time="3:50 PM" place="Marsh Walk, Murrells Inlet" duration="0:06" gotten="0:04" phase="downloading" paused />
          <IncomingCard time="3:44 PM" place="Marsh Walk, Murrells Inlet" duration="5:00" phase="waiting" paused />
          <ReadyCamSessions />
        </div>
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrCCSessionList,
  ScrCCSessionListExpanded,
  ScrCCBundleConfirm,
  ScrCCSyncing,
  ScrCCTranscribing,
  ScrCCStalled,
});

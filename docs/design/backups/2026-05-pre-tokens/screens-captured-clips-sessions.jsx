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
        <span style={{ width: 8, height: 8, borderRadius: 4, background: '#FFFCF6' }} />
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
      background: disabled ? 'rgba(198,74,28,0.35)' : PX.accent,
      color: '#FFFCF6',
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
// Session card.
// `expanded` swaps the transcript preview for inline clip rows.
// Action pill is the same in both states.
// ─────────────────────────────────────────────────────────────
function SessionCard({
  time, clips, duration, previewLine, autoExcluded = 0,
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
      {/* Meta row */}
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
          clips={4}
          duration="0:12"
          previewLine="One, two, three … one, two, three, four, five … one, two, three, four, five? Hey."
          autoExcluded={1}
        />
        <SessionCard
          time="2:40 PM"
          clips={3}
          duration="0:08"
          previewLine="The bit about one point eight billion — I stopped them right there, said first of all that's not even the right number …"
        />
        <SessionCard
          time="12:01 PM"
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
          clips={4}
          duration="0:12"
          autoExcluded={1}
          expanded
          clipsDetail={clips336}
        />
        <SessionCard
          time="2:40 PM"
          clips={3}
          duration="0:08"
          previewLine="The bit about one point eight billion — I stopped them right there, said first of all that's not even the right number …"
        />
        <SessionCard
          time="12:01 PM"
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
          time="3:36 PM" clips={4} duration="0:12"
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
              <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 2 }}>1 clip excluded</div>
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
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '5px 11px', borderRadius: 13, background: 'rgba(198,74,28,0.16)', border: '1px solid rgba(198,74,28,0.28)', fontSize: 12.5, color: '#7A3A14' }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: '#7A6B4F' }} />
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

Object.assign(window, {
  ScrCCSessionList,
  ScrCCSessionListExpanded,
  ScrCCBundleConfirm,
});

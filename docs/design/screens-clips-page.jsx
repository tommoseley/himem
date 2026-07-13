// screens-clips-page.jsx
// The Clips page — first-class evidence surface (Clips · Memories · Projects).
// Retires the standalone "Captured Clips" window. Mocks:
//   ScrClipsDefault      — default view: AI suggestions + not-yet-connected
//                          clips (incl. downloading-from-phone state)
//   ScrClipsAll          — the "All" reveal, placed clips show "Referenced in"
//   ScrClipDetail        — tap a clip → the clip as the PRIMARY object:
//                          transcript · media · date · Referenced in · Projects
// Canonical: HiMem · evidence and context.md, the shaping model, CLAUDE.md · Phone.

// ── Tab bar (Clips · Memories · Projects = Evidence · Context · Intent) ──
// `dot` puts a presence dot (never a number) on a tab — new unseen arrivals.
function TabBar({ active = 'clips', dot = null }) {
  const tabs = [
    ['clips', 'Clips', (c) => <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 8a2 2 0 012-2h9l3 3v7a2 2 0 01-2 2H6a2 2 0 01-2-2z"/><path d="M8 3h8"/></svg>],
    ['memories', 'Memories', (c) => <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M5 4v16l7-3 7 3V4a2 2 0 00-2-2H7a2 2 0 00-2 2z"/></svg>],
    ['projects', 'Projects', (c) => <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6a2 2 0 012-2h4l2 2h6a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/></svg>],
  ];
  return (
    <div style={{
      flexShrink: 0, display: 'flex', borderTop: '1px solid ' + PX.hairline,
      background: PX.card, paddingBottom: 16, paddingTop: 8,
    }}>
      {tabs.map(([id, label, glyph]) => {
        const on = id === active;
        const c = on ? PX.accent : PX.ink4;
        return (
          <div key={id} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
            <span style={{ position: 'relative', display: 'inline-flex' }}>
              {glyph(c)}
              {dot === id && (
                <span style={{
                  position: 'absolute', top: -2, right: -5, width: 9, height: 9, borderRadius: 5,
                  background: PX.accent, border: '1.5px solid ' + PX.card,
                }} />
              )}
            </span>
            <span style={{ fontSize: 10.5, fontWeight: on ? 700 : 500, color: c, letterSpacing: -0.1 }}>{label}</span>
          </div>
        );
      })}
    </div>
  );
}

// ── Clips-page header: title + TWO independent filter axes. STATUS (New ⟷
// All) and TYPE (All / Voice / Photos / Video / Notes) are orthogonal, so
// "new videos only" is expressible. Status is a two-state toggle (ochre, the
// primary lens); type is a neutral chip row (secondary refinement). Never a
// single control mixing the two — that hid Video and made the axes collide. ──
function ClipsHeader({ status = 'new', type = 'all' }) {
  const statuses = [['new', 'New'], ['all', 'All']];
  const types = [['all', 'All'], ['voice', 'Voice'], ['photos', 'Photos'], ['video', 'Video'], ['notes', 'Notes']];
  return (
    <div style={{ flexShrink: 0, padding: '4px 0 8px' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', padding: '2px 18px 10px' }}>
        <span style={{ fontFamily: PX.serif, fontSize: 30, fontWeight: 400, letterSpacing: -0.5, color: PX.ink }}>Clips</span>
        <span style={{ flex: 1 }} />
        <span style={{ color: PX.ink3 }}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/></svg>
        </span>
      </div>
      {/* STATUS axis — a two-state toggle (New ⟷ All), iOS segmented control. */}
      <div style={{ padding: '0 14px', marginBottom: 9 }}>
        <div style={{ display: 'inline-flex', background: PX.wash1, borderRadius: 10, padding: 3, gap: 2 }}>
          {statuses.map(([id, label]) => {
            const on = id === status;
            return (
              <span key={id} style={{
                fontSize: 13.5, fontWeight: on ? 700 : 500, letterSpacing: -0.1,
                color: on ? PX.accentInk : PX.ink2,
                background: on ? PX.accent : 'transparent',
                borderRadius: 8, padding: '6px 20px', minHeight: 32, boxSizing: 'border-box',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              }}>{label}</span>
            );
          })}
        </div>
      </div>
      {/* TYPE axis — filter by media (All = every type). Neutral selection so it
          reads as a secondary refinement, distinct from the ochre status toggle. */}
      <div style={{ display: 'flex', gap: 7, padding: '0 14px', overflow: 'hidden' }}>
        {types.map(([id, label]) => {
          const on = id === type;
          return (
            <span key={id} style={{
              fontSize: 13, fontWeight: on ? 600 : 500, letterSpacing: -0.1,
              color: on ? PX.ink : PX.ink3,
              background: on ? PX.wash2 : 'transparent',
              border: '1px solid ' + (on ? 'transparent' : PX.hairline),
              borderRadius: 9, padding: '5px 11px', minHeight: 30, boxSizing: 'border-box',
              display: 'inline-flex', alignItems: 'center', whiteSpace: 'nowrap',
            }}>{label}</span>
          );
        })}
      </div>
    </div>
  );
}

// ── A loose clip row (unplaced) ──
function LooseClipRow({ mediaIcon, time, place, preview, downloading }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 13,
      padding: '11px 13px', display: 'flex', gap: 11, alignItems: 'flex-start',
      opacity: downloading ? 0.7 : 1,
    }}>
      <span style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0, marginTop: 1,
        background: PX.wash1, color: PX.ink3,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>{mediaIcon}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, fontSize: 11.5, color: PX.ink3, letterSpacing: -0.05, marginBottom: 3 }}>
          <span style={{ fontWeight: 600, color: PX.ink2, fontVariantNumeric: 'tabular-nums' }}>{time}</span>
          {place && <><span style={{ color: PX.ink4 }}>·</span><span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{place}</span></>}
        </div>
        {downloading ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ flex: 1, height: 4, borderRadius: 2, background: PX.wash2, overflow: 'hidden' }}>
              <div style={{ width: '58%', height: '100%', background: PX.ink4, borderRadius: 2 }} />
            </div>
            <span style={{ fontSize: 11, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>Downloading…</span>
          </div>
        ) : (
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.42, letterSpacing: -0.1, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
            “{preview}”
          </div>
        )}
      </div>
      {!downloading && <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ alignSelf: 'center', flexShrink: 0 }}><path d="M1 1l6 6-6 6"/></svg>}
    </div>
  );
}

const MIC = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="2" width="6" height="11" rx="3"/><path d="M5 10a7 7 0 0014 0M12 17v4"/></svg>;
const CAM = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a2 2 0 012-2h2l1.5-2h7L17 5h2a2 2 0 012 2v10a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><circle cx="12" cy="12" r="3.2"/></svg>;
const NOTE = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M5 3h11l3 3v15H5z"/><path d="M8 9h8M8 13h8M8 17h5"/></svg>;

// A photo/video thumbnail tile — a real preview, never a generic glyph.
// `hue` fakes distinct imagery so a burst doesn't read as identical tiles.
function Thumb({ size = 54, hue = 40, video = false, radius = 10 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: radius, flexShrink: 0, position: 'relative', overflow: 'hidden',
      background: `linear-gradient(150deg, oklch(0.72 0.09 ${hue}), oklch(0.55 0.11 ${hue + 30}))`,
    }}>
      {video && (
        <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ width: 20, height: 20, borderRadius: 10, background: 'rgba(255,255,255,0.9)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="9" height="9" viewBox="0 0 12 12" fill="#1A1612"><path d="M3 2l7 4-7 4z"/></svg>
          </span>
        </span>
      )}
    </div>
  );
}

// Burst of same-minute photos/videos collapsed into ONE row: a thumbnail
// strip + count, so a 5-photo burst is one scannable line, not five walls.
function BurstRow({ time, place, count, kind = 'photo', hues }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 13,
      padding: '11px 13px', display: 'flex', flexDirection: 'column', gap: 9,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, fontSize: 11.5, color: PX.ink3, letterSpacing: -0.05 }}>
        <span style={{ fontWeight: 600, color: PX.ink2, fontVariantNumeric: 'tabular-nums' }}>{time}</span>
        <span style={{ color: PX.ink4 }}>·</span>
        <span>{count} {kind === 'video' ? 'clips' : 'photos'}</span>
        {place && <><span style={{ color: PX.ink4 }}>·</span><span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{place}</span></>}
        <span style={{ flex: 1 }} />
        <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        {hues.slice(0, 5).map((h, i) => <Thumb key={i} size={54} hue={h} video={kind === 'video'} />)}
        {count > 5 && (
          <div style={{ width: 54, height: 54, borderRadius: 10, flexShrink: 0, background: PX.wash1, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, fontWeight: 600, color: PX.ink3 }}>+{count - 5}</div>
        )}
      </div>
    </div>
  );
}

// Inline "Add a description" affordance — a photo/video's description is the
// clip's WORDS (the human stand-in for the future visual transcript, exactly
// parallel to a voice clip's transcript), so it's editable at the CLIP level,
// right here on the Clips surface. Ochre = human-written (never AI blue).
const DESC_PENCIL = <svg width="11" height="11" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 17l4-1L17 6l-3-3L4 13l-1 4z"/></svg>;
function AddDescHint() {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12, fontWeight: 600, color: PX.accent, marginTop: 4 }}>
      {DESC_PENCIL} Add a description
    </span>
  );
}

// A single photo/video clip (not a burst) — thumbnail + time. Its description
// (if written) reads as the row's body, the way a voice clip's transcript does;
// if empty, the row invites one. Tap → the media clip detail (full editor).
function MediaClipRow({ time, place, hue, video, desc }) {
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 13, padding: '9px 11px', display: 'flex', gap: 11, alignItems: 'flex-start' }}>
      <Thumb size={46} hue={hue} video={video} radius={9} />
      <div style={{ flex: 1, minWidth: 0 }}>
        {desc
          ? <div style={{ fontSize: 13.5, color: PX.ink, lineHeight: 1.4, letterSpacing: -0.1, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{desc}</div>
          : <div style={{ fontSize: 13.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>{video ? 'Video' : 'Photo'}</div>}
        <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 1, letterSpacing: -0.05 }}>
          {time}{place ? ' · ' + place : ''}
        </div>
        {!desc && <AddDescHint />}
      </div>
      <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, marginTop: 4 }}><path d="M1 1l6 6-6 6"/></svg>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Default view ("New") — the workbench: AI suggestions on top, then
// not-yet-connected clips. Photos/videos are THUMBNAILS, and same-minute
// bursts collapse into one strip so a photo-heavy day isn't a wall of
// identical "Photo" rows (the July 9 dogfood failure).
// ═══════════════════════════════════════════════════════════════
function ScrClipsDefault() {
  return (
    <PhoneScreen>
      <ClipsHeader status="new" type="all" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '2px 14px 10px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {/* AI suggestion (Sort) leads — you triage a GROUP, not 40 loose rows */}
        <div style={{ background: PX.aiTint, border: '1px solid ' + PX.ai, borderRadius: 14, padding: '12px 13px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 9 }}>
            <Spark size={14} color={PX.ai} />
            <span style={{ fontSize: 12.5, fontWeight: 600, color: PX.ai, letterSpacing: -0.05 }}>6 clips seem to belong together</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 11, color: PX.ai, opacity: 0.8, fontFamily: PX.mono }}>May 11 · Tybee</span>
          </div>
          <div style={{ display: 'flex', gap: 6, marginBottom: 11 }}>
            {[20, 45, 70, 95, 130].map((h, i) => <Thumb key={i} size={44} hue={h} radius={8} />)}
            <div style={{ width: 44, height: 44, borderRadius: 8, flexShrink: 0, background: 'rgba(30,92,142,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 600, color: PX.ai }}>+1</div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <span style={{ flex: 1, height: 40, borderRadius: 11, background: PX.ai, color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 14, fontWeight: 600 }}>
              Review
              <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
            </span>
            <span style={{ height: 40, padding: '0 14px', borderRadius: 11, border: '1px solid ' + PX.hairline, color: PX.ink2, display: 'inline-flex', alignItems: 'center', fontSize: 14, fontWeight: 500 }}>Not now</span>
          </div>
        </div>

        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, padding: '2px 4px 0' }}>Sun May 31</div>
        <LooseClipRow mediaIcon={MIC} time="12:21 PM" place="Nancy Hanks Way, Pooler" preview="These journeys are as wild and varied as landscapes — freedom and discovery on the open road." />

        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, padding: '2px 4px 0' }}>Mon May 11</div>
        {/* the burst that used to be 4 identical "Photo" rows — now one strip */}
        <BurstRow time="5:39 PM" place="Tybee Island" count={4} kind="photo" hues={[35, 60, 90, 120]} />
        <MediaClipRow time="5:30 PM" place="Tybee Island" hue={200} video desc="Waves coming in at dusk — the light I want for the opening shot." />
        <MediaClipRow time="5:30 PM" place="Tybee Island" hue={150} />
        <LooseClipRow mediaIcon={MIC} time="2:33 PM" preview="One thing I like is that we can also add links to this — so if I have a link for something…" />
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// All view — placed clips show "Referenced in"
// ═══════════════════════════════════════════════════════════════
function PlacedClipRow({ mediaIcon, time, preview, refs }) {
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 13, padding: '11px 13px', display: 'flex', gap: 11, alignItems: 'flex-start' }}>
      <span style={{ width: 30, height: 30, borderRadius: 8, flexShrink: 0, marginTop: 1, background: PX.wash1, color: PX.ink3, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{mediaIcon}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 11.5, color: PX.ink3, fontWeight: 600, marginBottom: 3, fontVariantNumeric: 'tabular-nums' }}>{time}</div>
        <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.42, letterSpacing: -0.1, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden', marginBottom: 7 }}>“{preview}”</div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, alignItems: 'center' }}>
          <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: PX.ink4 }}>In</span>
          {refs.map(r => (
            <span key={r} style={{ fontSize: 11.5, color: PX.ink2, background: PX.wash1, borderRadius: 8, padding: '2px 8px', letterSpacing: -0.05 }}>{r}</span>
          ))}
        </div>
      </div>
    </div>
  );
}

function ScrClipsAll() {
  return (
    <PhoneScreen>
      <ClipsHeader status="all" type="all" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '2px 14px 10px', display: 'flex', flexDirection: 'column', gap: 9 }}>
        <PlacedClipRow mediaIcon={MIC} time="Jun 30 · 6:12 PM" preview="Ben explained the cheesecake starts at 400°, then finishes at 250°." refs={['CIA Dinner', 'Leadership', 'Cooking']} />
        <PlacedClipRow mediaIcon={CAM} time="Jun 30 · 6:18 PM" preview="Basque burnt top — the whole point is you don't fight the scorch." refs={['CIA Dinner', 'Cooking']} />
        <LooseClipRow mediaIcon={NOTE} time="9:10 AM" preview="And by God, Q-tips. Need to restock before the trip." />
        <PlacedClipRow mediaIcon={MIC} time="May 17 · 4:44 PM" preview="Ordering replacement lemon trees — citrus import rules make them scarce." refs={['Garden']} />
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// Clip as primary object — ONE screen, editing is INLINE (no separate editor
// screen). Tapping a clip from a session or the list opens this; the transcript
// is tap-to-edit in place (a small "Edit" affordance signals it), so the path to
// editing a clip's words is two screens — Session → Clip — never three. View:
// meta · transcript (tap to edit) · Play · Referenced in · a single bottom fate
// stack (Remove from session? · Delete clip). Edit (keyboard up): the transcript
// field + Play + Cancel/Done only — fate actions and Referenced-in sit below and
// are covered by the keyboard. No FAB on an opened clip.
//   · editing   — the inline transcript-edit state (keyboard up).
//   · inSession — clip sits in a session → show "Remove from session".
//   · attached  — referenced in ≥1 memory (else the empty state).
function ClipFateStack({ inSession }) {
  const trash = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={PX.danger} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1 1 0 001 1h8a1 1 0 001-1l1-13"/></svg>;
  const eject = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={PX.ink2} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M10 4H6a2 2 0 00-2 2v12a2 2 0 002 2h4"/><path d="M16 16l4-4-4-4"/><path d="M20 12H10"/></svg>;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 11, marginTop: 28 }}>
      {inSession && (
        <div style={{ minHeight: 50, borderRadius: 14, border: '1px solid ' + PX.hairline, color: PX.ink2, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.2 }}>
          {eject} Remove from session
        </div>
      )}
      <div style={{ minHeight: 50, borderRadius: 14, border: '1px solid ' + PX.danger, color: PX.danger, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.2 }}>
        {trash} Delete clip
      </div>
    </div>
  );
}

function ScrClipDetail({ editing = false, inSession = false, attached = true }) {
  const transcript = "Ben said the Basque cheesecake starts hot — around four hundred — to get that burnt top, then drops to two-fifty to set the center without drying it. He was so easy about it, no performance, just “here's how it works.”";
  return (
    <PhoneScreen>
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 14px 8px' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Clips
        </span>
        <span style={{ flex: 1 }} />
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '0 18px 12px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 12 }}>
          Voice · Jun 30, 6:12 PM · Culinary Institute
        </div>

        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 8 }}>
          <span style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3 }}>Transcript</span>
          <span style={{ flex: 1 }} />
          {!editing && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12.5, fontWeight: 600, color: PX.ink3 }}>
              <svg width="11" height="11" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 17l4-1L17 6l-3-3L4 13l-1 4z"/></svg>
              Edit
            </span>
          )}
        </div>

        {editing ? (
          // EDIT MODE — INLINE on this same screen (not a pushed editor): tap the
          // transcript → it focuses in place. Words only: field + Play +
          // Cancel/Done. No fate actions (showFates=false), no duplicate label
          // (showLabel=false). Path stays Session → Clip (two screens).
          <ClipEditor field="transcript" value={transcript} media="audio" duration="0:42" showLabel={false} showFates={false} />
        ) : (
          <>
            {/* transcript is the working object — tap anywhere in it to edit in place */}
            <div style={{ fontFamily: PX.serif, fontSize: 15.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1, marginBottom: 16 }}>
              {transcript}
            </div>
            {/* original recording — quiet evidence control */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 20 }}>
              <span style={{ width: 30, height: 30, borderRadius: 15, background: PX.accent, color: PX.accentInk, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor"><path d="M5 3.5v9l7-4.5z"/></svg>
              </span>
              <span style={{ fontSize: 13, color: PX.ink3, letterSpacing: -0.05 }}>Original recording · 0:42</span>
            </div>

            <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>Referenced in</div>
            {attached ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
                {[['CIA Dinner', 'One of the best meals we\u2019ve had in years.'], ['Leadership', 'Expertise without ego — comfortable saying \u201cI don\u2019t know.\u201d']].map(([m, note]) => (
                  <div key={m} style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 12, padding: '10px 12px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                      <Mem size={13} color={PX.accent} />
                      <span style={{ fontSize: 13.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>{m}</span>
                      <span style={{ flex: 1 }} />
                      <svg width="6" height="11" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
                    </div>
                    <div style={{ fontSize: 12, color: PX.ink3, lineHeight: 1.4, marginTop: 4, fontStyle: 'italic', fontFamily: PX.serif }}>{note}</div>
                  </div>
                ))}
              </div>
            ) : (
              <div style={{ fontSize: 13.5, color: PX.ink3, letterSpacing: -0.1 }}>Not attached to a memory yet.</div>
            )}

            <ClipFateStack inSession={inSession} />
          </>
        )}
      </div>
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// Media clip (photo/video) as primary object. Parallel to ScrClipDetail,
// but where a voice clip shows Transcript, a photo/video shows DESCRIPTION
// — the clip's words, human-written, editable HERE (evidence-level), the
// same field AI Organize + search read. `described` toggles filled/empty.
// ═══════════════════════════════════════════════════════════════
function ScrMediaClipDetail({ described = false, video = false, editing = false }) {
  return (
    <PhoneScreen>
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 14px 8px' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Clips
        </span>
        <span style={{ flex: 1 }} />
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '0 18px 12px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 10 }}>
          {video ? 'Video' : 'Photo'} · May 11, 5:30 PM · Tybee Island
        </div>
        {/* media hero — the thumbnail IS the evidence, first-class */}
        <MediaThumb kind={video ? 'video' : 'photo'} duration={video ? '0:18' : undefined} height={190} />
        {/* DESCRIPTION — the clip's words. Empty invites; filled reads as body;
            editing routes through the ONE canonical ClipEditor (field="description",
            showFates=false — the fate actions live in the bottom stack, view mode). */}
        {editing
          ? <div style={{ marginTop: 14 }}><ClipEditor field="description" media={video ? 'video' : 'photo'} showFates={false}
              value="Waves coming in at dusk — the low gold light I want for the opening shot. Shot wide so the horizon sits on the lower third." /></div>
          : described
            ? <DescriptionFilled>Waves coming in at dusk — the low gold light I want for the opening shot. Shot wide so the horizon sits on the lower third.</DescriptionFilled>
            : <DescriptionEmpty />}
        {!editing && <>
          {/* Referenced in — same ontology as a voice clip */}
          <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, margin: '18px 0 8px' }}>Referenced in</div>
          <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 12, padding: '10px 12px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
              <Mem size={13} color={PX.accent} />
              <span style={{ fontSize: 13.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>Tybee, opening sequence</span>
              <span style={{ flex: 1 }} />
              <svg width="6" height="11" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
            </div>
          </div>
          <ClipFateStack inSession={false} />
        </>}
      </div>
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// Active Navigation Tap — the Clips status sheet.
// Tapping the already-active Clips tab (when at top) slides this up.
// Answers "what exactly is there?" — sources · processing · available.
// NO census/vanity counts (no "247 referenced"): what needs me, not
// how much I have. Required for v1; discovery of it is the optional part.
// ═══════════════════════════════════════════════════════════════
function StatusLine({ glyph, label, value, tint }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 11, minHeight: 38 }}>
      <span style={{ width: 26, display: 'inline-flex', justifyContent: 'center', color: tint || PX.ink3 }}>{glyph}</span>
      <span style={{ flex: 1, fontSize: 14.5, color: PX.ink, letterSpacing: -0.1 }}>{label}</span>
      <span style={{ fontSize: 14.5, fontWeight: 600, color: PX.ink2, fontVariantNumeric: 'tabular-nums' }}>{value}</span>
    </div>
  );
}

function ScrClipsStatusSheet() {
  const watch = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>;
  const phone = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/></svg>;
  const siri = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v18M8 7v10M16 7v10M4 10v4M20 10v4"/></svg>;
  const dl = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v12M7 11l5 4 5-4M5 21h14"/></svg>;

  return (
    <div style={{ width: 340, height: 735, position: 'relative', background: PX.paper, fontFamily: PX.sans, overflow: 'hidden' }}>
      {/* Clips behind, dimmed */}
      <div style={{ position: 'absolute', inset: 0, opacity: 0.5, pointerEvents: 'none' }}><ScrClipsDefault /></div>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(26,22,18,0.30)' }} />

      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, background: PX.paper,
        borderRadius: '20px 20px 0 0', boxShadow: '0 -10px 40px rgba(0,0,0,0.18)', padding: '10px 20px 20px',
      }}>
        <div style={{ width: 38, height: 5, borderRadius: 3, background: PX.hairline, margin: '2px auto 14px' }} />
        <div style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 400, color: PX.ink, letterSpacing: -0.4, marginBottom: 14 }}>Clips</div>

        <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 2 }}>New arrivals</div>
        {/* Reversed July 12 2026 (was: omit zero rows): the FULL source roster
            shows every time, including sources at 0 — a stable, scannable list is
            more predictable than one that changes shape, and "0 from Siri today"
            is real information. */}
        <StatusLine glyph={watch} label="Apple Watch" value="3" tint={PX.accent} />
        <StatusLine glyph={phone} label="iPhone" value="2" />
        <StatusLine glyph={siri} label="Siri" value="0" />

        <div style={{ height: 1, background: PX.divider, margin: '10px 0' }} />
        <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 2 }}>Processing</div>
        <StatusLine glyph={dl} label="Downloading" value="2" />
        <StatusLine glyph={<Spark size={15} color={PX.ai} />} label="Organizing" value="1" tint={PX.ai} />

        <div style={{ height: 1, background: PX.divider, margin: '10px 0' }} />
        {/* "Not yet connected" — plain English, not internal jargon ("loose /
            available to shape"). It's the count of unshaped clips. */}
        <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 2 }}>Not yet connected</div>
        <StatusLine glyph={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 8a2 2 0 012-2h9l3 3v7a2 2 0 01-2 2H6a2 2 0 01-2-2z"/></svg>} label="Clips" value="18" />

        {/* quick filter shortcuts — mirror the header filter vocabulary exactly */}
        <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
          <span style={{ flex: 1, minHeight: 40, borderRadius: 11, background: PX.accent, color: PX.accentInk, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, fontWeight: 600 }}>Review new</span>
          <span style={{ minHeight: 40, padding: '0 14px', borderRadius: 11, border: '1px solid ' + PX.hairline, color: PX.ink2, display: 'inline-flex', alignItems: 'center', fontSize: 14, fontWeight: 500 }}>Voice</span>
          <span style={{ minHeight: 40, padding: '0 14px', borderRadius: 11, border: '1px solid ' + PX.hairline, color: PX.ink2, display: 'inline-flex', alignItems: 'center', fontSize: 14, fontWeight: 500 }}>Photos</span>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Mixed session card — idle-gap sessioning is MEDIA-AGNOSTIC.
// A photo captured within the idle window of the surrounding voice
// clips folds INTO the session as a third clip (a thumbnail row),
// NOT a separate top-level "Photo" row above it. The card's
// composition reads as per-media glyphs + counts — 2 voice · 1
// photo — the shared ClipComposition line (identical to the memory
// card, register-styled), never a flat "3 clips". Start a Memory
// yields ONE memory holding all
// three. Fixes the July 11 dogfood bug: a photo at 10:34 floated
// above the voice-only "2 clips" session it belonged to by time.
//   • Every clip in the session carries the ochre inclusion ring.
//   • A voice clip shows offset · duration · transcript · Retry.
//   • A photo/video clip shows offset + a real thumbnail — no
//     fake transcript, no Retry (there's nothing to transcribe).
//   • Rows sort by capture timestamp: voice(0:00) → photo(+128s)
//     → voice(+180s), one continuous sitting.
// ═══════════════════════════════════════════════════════════════
// ── Per-media glyph + count, the composition summary shared by the session
// card and the memory card. Ochre mic (audio/brand), quiet ink for the rest.
// A media type at 0 is omitted — never a "photo 0". ──
function SessionCounts({ media = {} }) {
  const items = [];
  if (media.audio) items.push([MIC, PX.accent, media.audio]);
  if (media.photo) items.push([CAM, PX.ink3, media.photo]);
  if (media.note) items.push([NOTE, PX.ink3, media.note]);
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 12 }}>
      {items.map(([g, c, n], i) => (
        <span key={i} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 13.5, color: PX.ink2, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
          <span style={{ color: c, display: 'inline-flex' }}>{g}</span>{n}
        </span>
      ))}
    </span>
  );
}

// ── Collapsed session card — the CALM default in the New list. A BUNDLE OF
// EVIDENCE, not a decision: composition header (time · per-media counts ·
// duration) + a preview of the FIRST clip's words (capture order, never a
// concatenation) + a quiet "tap to review". NO Create/Delete here — those
// live inside the opened session (fate actions at the bottom of the opened
// item). A list of N sessions must not be N pairs of shouting buttons. ──
function SessionCard({ time, day, media, dur, preview }) {
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 18, padding: '15px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 2 }}>
        <span style={{ fontSize: 15, fontWeight: 700, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>{time}</span>
        <span style={{ color: PX.ink4 }}>·</span>
        <SessionCounts media={media} />
        <span style={{ color: PX.ink4 }}>·</span>
        <span style={{ fontSize: 13.5, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>{dur}</span>
      </div>
      <div style={{ fontSize: 12.5, color: PX.ink3, marginBottom: 12 }}>{day}</div>
      <div style={{ fontSize: 15, color: PX.ink2, lineHeight: 1.45, letterSpacing: -0.1, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
        “{preview}”
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 12, fontSize: 12.5, fontWeight: 600, color: PX.ink3 }}>
        Tap to review
        <svg width="6" height="11" viewBox="0 0 8 14" fill="none" stroke={PX.ink3} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Clips · New — the CALM session list. Sessions read as bundles of
// evidence ("here's what arrived"), not decisions requiring a button.
// Preview = the FIRST clip's words (fixes the dogfood bug where the
// collapsed preview concatenated clips out of order). Tap opens the
// session (ScrMixedSession), where Create/Delete live.
// ═══════════════════════════════════════════════════════════════
function ScrClipsSessions() {
  return (
    <PhoneScreen>
      <ClipsHeader status="new" type="all" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '2px 16px 10px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div>
          <div style={{ fontFamily: PX.serif, fontSize: 27, fontWeight: 400, letterSpacing: -0.5, color: PX.ink, lineHeight: 1.1 }}>4 new clips</div>
          <div style={{ fontSize: 13.5, color: PX.ink3, letterSpacing: -0.1, marginTop: 5 }}>2 sessions · yesterday, 10:32 AM–5:29 PM</div>
        </div>
        <SessionCard time="5:29 PM" day="Yesterday" media={{ audio: 1 }} dur="0:05" preview="And here is another voice clip coming from my watch." />
        <SessionCard time="10:32 AM" day="Yesterday" media={{ audio: 2, photo: 1 }} dur="0:06" preview="This is a test voice clip" />
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ── Confirmation toast — the feedback that was missing. After Create, the
// sheet dismisses and this lands briefly: a check + "Memory created" + a "View"
// action that opens the new memory. Auto-dismisses; not a blocking dialog. ──
function CreatedToast({ label = 'Memory created' }) {
  return (
    <div style={{ position: 'absolute', left: 16, right: 16, bottom: 92, display: 'flex', alignItems: 'center', gap: 11, background: PX.ink, color: PX.accentInk, borderRadius: 14, padding: '13px 15px', boxShadow: '0 10px 34px rgba(0,0,0,0.24)' }}>
      <span style={{ width: 22, height: 22, borderRadius: 11, background: PX.confirmed, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M3 8.5l3.5 3.5L13 4"/></svg>
      </span>
      <span style={{ flex: 1, fontSize: 14.5, fontWeight: 600, letterSpacing: -0.1 }}>{label}</span>
      <span style={{ fontSize: 14.5, fontWeight: 700, color: PX.accentBright, letterSpacing: -0.1 }}>View</span>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// Clips · New — AFTER creating a memory from the 10:32 session (1 of 2
// clips included, 1 excluded). The four post-create truths, made visible:
//   • the session is consumed → we're back on the Clips LIST (not the
//     stale session screen);
//   • the included clip is connected → it LEFT New (gone from here);
//   • the excluded clip RETURNED to the bench as a loose New clip;
//   • a "Memory created · View" toast confirms it worked.
// New count dropped 3 → 2 (by the ONE included clip, not the whole session).
// ═══════════════════════════════════════════════════════════════
function ScrClipsAfterCreate() {
  return (
    <PhoneScreen>
      <ClipsHeader status="new" type="all" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '2px 16px 10px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div>
          <div style={{ fontFamily: PX.serif, fontSize: 27, fontWeight: 400, letterSpacing: -0.5, color: PX.ink, lineHeight: 1.1 }}>2 new clips</div>
          <div style={{ fontSize: 13.5, color: PX.ink3, letterSpacing: -0.1, marginTop: 5 }}>yesterday</div>
        </div>
        <SessionCard time="5:29 PM" day="Yesterday" media={{ audio: 1 }} dur="0:05" preview="And here is another voice clip coming from my watch." />
        {/* the excluded clip, returned to the bench as a loose New clip */}
        <SessionCard time="10:32 AM" day="Yesterday" media={{ audio: 1 }} dur="0:03" preview="This is a test voice clip y'all" />
      </div>
      <CreatedToast />
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// Clips · New · EMPTY — source-agnostic copy. Clips now arrive from
// the phone + button, the Watch, and Siri, so the empty state must NOT
// say "from your Watch" / "Audio you record on your Apple Watch lands
// here" (CC's build). Source is per-clip metadata, never the headline.
// ═══════════════════════════════════════════════════════════════
function ScrClipsEmpty() {
  return (
    <PhoneScreen>
      <ClipsHeader status="new" type="all" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '2px 18px 10px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 27, fontWeight: 400, letterSpacing: -0.5, color: PX.ink, lineHeight: 1.1 }}>Nothing new</div>
        <div style={{ fontSize: 14, color: PX.ink3, letterSpacing: -0.1, marginTop: 8, lineHeight: 1.5, maxWidth: 300 }}>
          Clips you capture — with the + button, on your Watch, or with Siri — land here.
        </div>
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// Session clip rows — the operational register of the canonical ClipAtom.
// These wrap ClipAtom (register="operational", inclusion ring) and add only the
// session-body chrome: a divider between stacked rows. No duplicate ring/retry/
// play primitives — those live once in screens-clip-model.jsx.
function SessionVoiceRow({ offset, dur, text, divider, failed = false, included = true }) {
  return (
    <div style={{ borderTop: divider ? '1px solid ' + PX.hairline : 'none', paddingTop: divider ? 14 : 0 }}>
      <ClipAtom media="audio" register="operational" ring included={included} meta={offset} duration={dur} transcript={text} failed={failed} />
    </div>
  );
}

// A photo/video clip inside the session — the same atom, media register. The
// empty-description invite is rendered by ClipAtom itself (operational media),
// so nothing here duplicates it.
function SessionMediaRow({ offset, hue, label = 'Photo', video, divider, desc, included = true }) {
  return (
    <div style={{ borderTop: divider ? '1px solid ' + PX.hairline : 'none', paddingTop: divider ? 14 : 0 }}>
      <ClipAtom media={video ? 'video' : 'photo'} register="operational" ring included={included} meta={offset} hue={hue} description={desc} />
    </div>
  );
}

// The OPENED session — pushed from the calm list (tap a SessionCard). This is
// where the actions live: the composition sits at the top, the clip body in the
// middle, and Start a Memory (ochre primary) + Delete session (red,
// bottom-most) at the end — the "fate actions at the bottom of the opened item"
// rule. The list card carries NONE of this; it's a bundle of evidence, not a
// decision.
function ScrMixedSession() {
  return (
    <PhoneScreen>
      {/* back to the calm list, not the page title */}
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 14px 8px' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Clips
        </span>
        <span style={{ flex: 1 }} />
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '0 18px 10px', display: 'flex', flexDirection: 'column' }}>
        {/* composition header — the bundle, at the top of the opened item */}
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 2 }}>
          <span style={{ fontSize: 17, fontWeight: 700, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>10:32 AM</span>
          <span style={{ color: PX.ink4 }}>·</span>
          <SessionCounts media={{ audio: 2, photo: 1 }} />
          <span style={{ color: PX.ink4 }}>·</span>
          <span style={{ fontSize: 13.5, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>0:06</span>
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginBottom: 20 }}>Yesterday · one sitting</div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <SessionVoiceRow offset="0:00" dur="0:03" text="This is a test voice clip" />
          <SessionMediaRow offset="+128s" hue={35} label="Photo" divider />
          <SessionVoiceRow offset="+180s" dur="0:02" text="Here, picture of my new camera." divider />
        </div>

        {/* Start a Memory — the ochre PRIMARY, at the action position. No
            sparkle (the user acts; not an AI action). */}
        <div style={{ minHeight: 52, borderRadius: 14, background: PX.accent, color: PX.accentInk, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, marginTop: 24 }}>
          Start a Memory
          <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.accentInk} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
        </div>
        {/* Delete session — red, bottom-most (fate action) */}
        <div style={{ minHeight: 52, borderRadius: 14, border: '1px solid ' + PX.danger, color: PX.danger, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, marginTop: 11 }}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={PX.danger} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1 1 0 001 1h8a1 1 0 001-1l1-13"/></svg>
          Delete session
        </div>
        <div style={{ fontSize: 12, color: PX.ink3, textAlign: 'center', marginTop: 10 }}>Moves to Recently Deleted · kept for 30 days.</div>
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// Session with one clip EXCLUDED — the inclusion ring OFF.
// The excluded clip's ring is a hollow ink hairline (a choice), its
// transcript de-emphasised one step but fully legible — deliberately
// UNLIKE the failed-clip style (dimmed + Retry). It stays IN the card;
// it just won't join the memory when you Start a Memory.
// ═══════════════════════════════════════════════════════════════
function ScrSessionExcluded() {
  return (
    <PhoneScreen>
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 14px 8px' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Clips
        </span>
        <span style={{ flex: 1 }} />
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '0 18px 10px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 2 }}>
          <span style={{ fontSize: 17, fontWeight: 700, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>10:32 AM</span>
          <span style={{ color: PX.ink4 }}>·</span>
          <SessionCounts media={{ audio: 2, photo: 1 }} />
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginBottom: 18 }}>Yesterday · tap a ring to include or leave out</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <SessionVoiceRow offset="0:00" dur="0:03" text="This is a test voice clip" />
          <SessionMediaRow offset="+128s" hue={35} divider />
          <SessionVoiceRow offset="+180s" dur="0:02" text="Ignore this one — I bumped record by accident." divider included={false} />
        </div>
        <div style={{ minHeight: 52, borderRadius: 14, background: PX.accent, color: PX.accentInk, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, marginTop: 24 }}>
          Start a Memory · 2 clips
          <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.accentInk} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
        </div>
        <div style={{ fontSize: 12, color: PX.ink3, textAlign: 'center', marginTop: 10 }}>The left-out clip stays on your bench.</div>
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// Single-clip session — the SAME atom with ring={false} (excluding the
// sole clip = deleting the session, so inclusion is meaningless) and it
// KEEPS its Play/evidence control. No bespoke bare-transcript card.
// Triage collapses to Start a Memory + Delete session.
// ═══════════════════════════════════════════════════════════════
function ScrSingleClipSession() {
  return (
    <PhoneScreen>
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 14px 8px' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Clips
        </span>
        <span style={{ flex: 1 }} />
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '0 18px 10px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 2 }}>
          <span style={{ fontSize: 17, fontWeight: 700, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>5:29 PM</span>
          <span style={{ color: PX.ink4 }}>·</span>
          <SessionCounts media={{ audio: 1 }} />
          <span style={{ color: PX.ink4 }}>·</span>
          <span style={{ fontSize: 13.5, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>0:11</span>
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginBottom: 18 }}>Yesterday</div>
        {/* the atom, ring OFF, Play kept */}
        <ClipAtom media="audio" register="operational" meta="0:00" duration="0:11" transcript="Remind me to email the framer about the Naples print before Friday." />
        <div style={{ minHeight: 52, borderRadius: 14, background: PX.accent, color: PX.accentInk, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, marginTop: 24 }}>
          Start a Memory
          <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.accentInk} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
        </div>
        <div style={{ minHeight: 52, borderRadius: 14, border: '1px solid ' + PX.danger, color: PX.danger, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, fontSize: 16, fontWeight: 600, letterSpacing: -0.2, marginTop: 11 }}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={PX.danger} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1 1 0 001 1h8a1 1 0 001-1l1-13"/></svg>
          Delete session
        </div>
      </div>
      <TabBar active="clips" />
    </PhoneScreen>
  );
}

// ═══════════════════════════════════════════════════════════════
// A session clip OPENED — this is now just ScrClipDetail with
// inSession (Remove from session in the bottom fate stack) and its
// editing mode (words-only editor). No bespoke editor-with-fate-row
// screen exists anymore; see ScrClipDetail.
// ═══════════════════════════════════════════════════════════════

Object.assign(window, {
  TabBar, ClipsHeader, LooseClipRow, PlacedClipRow, Thumb, BurstRow, MediaClipRow,
  AddDescHint, SessionMediaRow, ScrMediaClipDetail, ClipFateStack,
  StatusLine, ScrClipsStatusSheet, SessionCounts, SessionCard, ScrClipsSessions,
  CreatedToast, ScrClipsAfterCreate, ScrClipsEmpty,
  ScrClipsDefault, ScrClipsAll, ScrClipDetail, ScrMixedSession,
  ScrSessionExcluded, ScrSingleClipSession,
});

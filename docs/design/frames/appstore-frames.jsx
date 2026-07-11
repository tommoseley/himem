// HiMem · App Store marketing frames
// Rebuilt June 11 2026 — drawn from the CURRENT Crucible design language
// instead of stale shipping screenshots. Every phone is hand-composed from
// today's vocabulary so the store never advertises an outdated build:
//   · button colour code (ochre = you act, blue = invoke AI, +trailing ✦)
//   · unified editing model (no pen; transcript-first clip; Original-recording)
//   · AI-blue "Draft organized" review-state chip
//   · "Find the thread ✦" as the named Plus AI action
//   · data-custody closer (memories live in the user's own iCloud)
//
//   Frame 1 — Watch capture (drawn, ochre)            "Catch the thought"
//   Frame 2 — Memory detail · organize draft           "A draft in your words"
//   Frame 3 — Today / Memories landing                 "Today, quietly"
//   Frame 4 — Captured Clips · sessions                "Sort it out"
//   Frame 5 — Project · Find the thread                "Find the thread"
//   Frame 6 — Data custody (typographic closer)        "Yours. In your iCloud."
//
// Brand: HiMem. American spelling everywhere.

// Fixed light palette (marketing frames are not theme-aware).
const C = {
  paper: '#EFECE5', card: '#FBF9F4', ink: '#1A1612', ink2: '#46413A', ink3: '#857E72',
  hair: '#E0DBD0', wash: '#EDE8DE', sunk: '#E6E1D7',
  accent: '#C64A1C', accentInk: '#F7F1E8', accentTint: '#F4E2D7',
  ai: '#1E5C8E', aiTint: '#E2ECF4', aiEdge: '#BFD4E6',
  serif: '"Source Serif 4", Georgia, serif',
  sans: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
};

// ─────────────────────────────────────────────────────────────────────────────
// Shared: status bar + drawn-phone bezel
// ─────────────────────────────────────────────────────────────────────────────
function StatusBar({ dark }) {
  const c = dark ? '#fff' : C.ink;
  return (
    <div className="status" style={{ color: c }}>
      <span>9:41</span>
      <span className="right">
        {/* signal */}
        <svg width="18" height="12" viewBox="0 0 18 12" fill={c}>
          <rect x="0" y="8" width="3" height="4" rx="1"/>
          <rect x="5" y="5.5" width="3" height="6.5" rx="1"/>
          <rect x="10" y="3" width="3" height="9" rx="1"/>
          <rect x="15" y="0.5" width="3" height="11.5" rx="1"/>
        </svg>
        {/* wifi */}
        <svg width="16" height="12" viewBox="0 0 16 12" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round">
          <path d="M1.5 4.2a9 9 0 0113 0"/>
          <path d="M4 6.8a5.4 5.4 0 018 0"/>
          <circle cx="8" cy="9.6" r="1" fill={c} stroke="none"/>
        </svg>
        {/* battery */}
        <span style={{ display: 'inline-flex', alignItems: 'center' }}>
          <span style={{ width: 23, height: 12, border: '1.4px solid ' + c, borderRadius: 3.5, padding: 1.6, display: 'inline-block', boxSizing: 'border-box', opacity: 0.9 }}>
            <span style={{ display: 'block', width: '72%', height: '100%', background: c, borderRadius: 1.5 }}/>
          </span>
          <span style={{ width: 1.6, height: 4, background: c, borderRadius: 1, marginLeft: 1, opacity: 0.9 }}/>
        </span>
      </span>
    </div>
  );
}

function DrawnPhone({ children, dark = false, style }) {
  return (
    <div className={'phone' + (dark ? ' dark' : '')} style={{ left: '50%', transform: 'translateX(-50%)', ...style }}>
      <div className="notch"/>
      <div className="screen" style={{ background: dark ? '#000' : C.paper, display: 'flex', flexDirection: 'column' }}>
        <StatusBar dark={dark}/>
        <div style={{ flex: 1, minHeight: 0 }}>{children}</div>
      </div>
    </div>
  );
}

// small reusable glyphs
const G = {
  back: <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke={C.accent} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>,
  trash: <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={C.ink3} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>,
  folder: <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={C.ink3} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a1 1 0 011-1h5l2 2h8a1 1 0 011 1v9a1 1 0 01-1 1H4a1 1 0 01-1-1z"/></svg>,
  share: <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={C.ink3} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 15V3M8 7l4-4 4 4M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7"/></svg>,
  spark: (c) => <svg width="15" height="15" viewBox="0 0 24 24" fill={c}><path d="M12 2l1.9 6.1L20 10l-6.1 1.9L12 18l-1.9-6.1L4 10l6.1-1.9z"/></svg>,
  play: <svg width="11" height="11" viewBox="0 0 24 24" fill={C.ink3}><path d="M6 4l14 8-14 8z"/></svg>,
  search: <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke={C.ink2} strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>,
  help: <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke={C.ink2} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M9.2 9a2.8 2.8 0 015.4 1c0 1.8-2.6 2.4-2.6 2.4M12 17h.01"/></svg>,
  gear: <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke={C.ink2} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 01-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 010-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 014 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 010 4h-.1a1.7 1.7 0 00-1.5 1z"/></svg>,
  watchSm: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={C.accentInk} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>,
  sync: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={C.ai} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 0115-6.7L21 8M21 3v5h-5"/><path d="M21 12a9 9 0 01-15 6.7L3 16M3 21v-5h5"/></svg>,
};

function TopicChip({ label, color = C.accent }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, height: 30, padding: '0 13px', borderRadius: 11, background: C.wash, fontSize: 14, color: C.ink, letterSpacing: -0.1 }}>
      <span style={{ width: 7, height: 7, borderRadius: 4, background: color }}/>
      {label}
    </span>
  );
}

// dashed ochre "+ Add" affordance (dashed = add, per the standard)
function AddChip() {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, height: 30, padding: '0 13px', borderRadius: 11, border: '1px dashed ' + C.accent, color: C.accent, fontSize: 14, fontWeight: 600 }}>
      <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10"/></svg>
      Add
    </span>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 1 — Watch capture (drawn, ochre) — already current; unchanged
// ─────────────────────────────────────────────────────────────────────────────
function Frame1() {
  return (
    <div className="frame ochre">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom: 18 }}>Apple Watch</div>
        <div className="headline" style={{ fontSize: 62, color: '#F7F1E8' }}>
          Catch the thought<br/>before it's gone.
        </div>
        <div style={{ marginTop: 22, fontSize: 19, lineHeight: 1.45, color: 'rgba(247,241,232,0.78)', maxWidth: 480 }}>
          Raise your wrist. Speak. HiMem keeps it safe until you're ready to look at it.
        </div>
      </div>

      <div className="watch" style={{ left: '50%', top: 740, transform: 'translateX(-50%)' }}>
        <div className="screen">
          <div style={{ position: 'absolute', top: 14, left: 18, width: 26, height: 26, borderRadius: 13, background: 'rgba(255,255,255,0.10)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="rgba(255,255,255,0.7)" strokeWidth="2" strokeLinecap="round">
              <path d="M2 2l8 8M10 2L2 10"/>
            </svg>
          </div>
          <div style={{ position: 'absolute', top: 18, right: 18, display: 'flex', alignItems: 'center', gap: 4, color: 'var(--accent)', fontSize: 13, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
            <svg width="10" height="12" viewBox="0 0 10 12" fill="currentColor">
              <rect x="3" y="0.5" width="4" height="7" rx="2"/>
              <path d="M1.5 5.5v0.5a3.5 3.5 0 007 0v-.5" stroke="currentColor" strokeWidth="1" fill="none"/>
              <path d="M5 9v2.5" stroke="currentColor" strokeWidth="1"/>
            </svg>
            <span style={{ color: '#fff' }}>3:32</span>
          </div>
          <div style={{ position: 'absolute', top: 50, left: 0, right: 0, textAlign: 'center', fontSize: 13, fontWeight: 700, letterSpacing: 1.8, color: 'var(--accent)' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: 'var(--accent)' }}/>
              REC
            </span>
          </div>
          <div style={{ position: 'absolute', top: 86, left: 0, right: 0, textAlign: 'center', fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif', fontSize: 64, fontWeight: 300, letterSpacing: -2, lineHeight: 1, color: '#F7F1E8', fontVariantNumeric: 'tabular-nums' }}>
            0:24
          </div>
          <div style={{ position: 'absolute', top: 200, left: 28, right: 28, display: 'flex', gap: 4, alignItems: 'center', justifyContent: 'center', height: 40 }}>
            {Array.from({ length: 26 }).map((_, i) => {
              const big = [0, 3, 8, 11, 16, 19, 23, 25].includes(i);
              const tall = big ? 30 + (i % 3) * 4 : 0;
              return big
                ? <div key={i} style={{ width: 5, height: tall, background: 'var(--accent)', borderRadius: 2.5 }}/>
                : <div key={i} style={{ width: 5, height: 5, background: 'var(--accent)', borderRadius: 2.5, opacity: 0.85 }}/>;
            })}
          </div>
          <div style={{ position: 'absolute', bottom: 22, left: 18, right: 18, display: 'flex', gap: 10, alignItems: 'center' }}>
            <div style={{ flex: 1, height: 56, background: '#F1ECE3', color: '#000', borderRadius: 28, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 600 }}>
              Stop & save
            </div>
            <div style={{ width: 56, height: 56, background: 'var(--accent)', borderRadius: 28, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg width="22" height="14" viewBox="0 0 22 14" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                <path d="M2 2l5 5-5 5"/>
                <circle cx="15" cy="7" r="1.6" fill="#fff" stroke="none"/>
              </svg>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 2 — Memory detail · organize draft (current unified-editing language)
// ─────────────────────────────────────────────────────────────────────────────
function Frame2() {
  return (
    <div className="frame">
      <div className="top-text" style={{ top: 70 }}>
        <div className="eyebrow" style={{ marginBottom: 14 }}>Capture first</div>
        <div className="headline" style={{ fontSize: 58 }}>Save it now.<br/>Refine it later.</div>
        <div style={{ marginTop: 22, fontSize: 18, lineHeight: 1.45, color: C.ink2, maxWidth: 470 }}>
          Get the thought down while it's fresh. HiMem keeps a clean copy you can tidy whenever you like — it's always yours to edit.
        </div>
      </div>

      <DrawnPhone style={{ top: 470 }}>
        <div style={{ padding: '6px 20px 0', fontFamily: C.sans, display: 'flex', flexDirection: 'column', height: '100%' }}>
          {/* nav — no pen */}
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 18 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: C.accent, fontSize: 15 }}>{G.back}Today</span>
            <span style={{ flex: 1 }}/>
            <span style={{ display: 'inline-flex', gap: 16 }}>{G.trash}{G.folder}{G.share}</span>
          </div>

          <div style={{ fontFamily: C.serif, fontSize: 26, fontWeight: 600, lineHeight: 1.1, letterSpacing: -0.4, color: C.ink }}>Judi's cooking ideas collection</div>
          <div style={{ fontSize: 13, color: C.ink3, marginTop: 10 }}>May 17 · 9:25 PM</div>

          {/* SUMMARY — blue sparkle eyebrow, ink body */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 18 }}>
            {G.spark(C.ai)}
            <span style={{ fontSize: 11.5, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: C.ai }}>Summary</span>
          </div>
          <div style={{ fontSize: 15.5, lineHeight: 1.45, color: C.ink, marginTop: 9, letterSpacing: -0.1 }}>
            Identified a collection of culinary ideas linked to Judi's recent kitchen inspiration — tomato oil, shrimp hush puppies with remoulade, za'tar vinaigrette, and espresso-sugar creme brulee toppings.
          </div>

          {/* TOPICS */}
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: C.ink3, margin: '18px 0 10px' }}>Topics</div>
          <div style={{ display: 'flex', gap: 8 }}>
            <TopicChip label="Cooking" color="#3E4C66"/>
            <AddChip/>
          </div>

          {/* TRANSCRIPT header with Full/Compact toggle */}
          <div style={{ display: 'flex', alignItems: 'center', margin: '20px 0 12px' }}>
            <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: C.ink3 }}>Transcript · 2 clips · 60 words</span>
            <span style={{ flex: 1 }}/>
            <span style={{ display: 'inline-flex', gap: 2, background: C.sunk, borderRadius: 9, padding: 2 }}>
              <span style={{ width: 34, height: 26, borderRadius: 7, background: C.card, boxShadow: '0 1px 2px rgba(0,0,0,0.08)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={C.ink} strokeWidth="2" strokeLinecap="round"><path d="M4 6h16M4 11h16M4 16h11"/></svg>
              </span>
              <span style={{ width: 34, height: 26, borderRadius: 7, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={C.ink3} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="4.5" cy="6.5" r="1.3" fill={C.ink3} stroke="none"/><path d="M9 6.5h11"/><circle cx="4.5" cy="12" r="1.3" fill={C.ink3} stroke="none"/><path d="M9 12h11"/><circle cx="4.5" cy="17.5" r="1.3" fill={C.ink3} stroke="none"/><path d="M9 17.5h11"/></svg>
              </span>
            </span>
          </div>

          {/* clip 1 */}
          <div style={{ background: C.card, border: '1px solid ' + C.hair, borderRadius: 16, padding: '14px 15px', marginBottom: 11 }}>
            <div style={{ fontSize: 12, color: C.ink3, fontWeight: 600, marginBottom: 8 }}>Sun May 17 · 9:25 PM</div>
            <div style={{ fontSize: 14.5, lineHeight: 1.5, color: C.ink, letterSpacing: -0.05 }}>
              What? Tomato oil. Hush puppies with shrimp in them with remoulade. Lemons, the za'tar vinaigrette. Mix espresso powder with sugar, to top creme brulee, whipped crème fraiche.
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 12, color: C.ink3 }}>
              {G.play}<span style={{ fontSize: 12.5 }}>Original recording</span>
            </div>
          </div>

          {/* clip 2 */}
          <div style={{ background: C.card, border: '1px solid ' + C.hair, borderRadius: 16, padding: '14px 15px' }}>
            <div style={{ fontSize: 12, color: C.ink3, fontWeight: 600, marginBottom: 8 }}>Sun May 17 · 9:28 PM</div>
            <div style={{ fontSize: 14.5, lineHeight: 1.5, color: C.ink, letterSpacing: -0.05 }}>
              This is a collection of cooking ideas that Judi sort of collected today or the past couple days. It's these kind of things that really lead her innovation and drive in the kitchen.
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 12, color: C.ink3 }}>
              {G.play}<span style={{ fontSize: 12.5 }}>Original recording</span>
            </div>
          </div>

          {/* MENTIONS */}
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: C.ink3, margin: '18px 0 10px' }}>Mentions</div>
          <div style={{ display: 'flex', gap: 8 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, height: 30, padding: '0 13px', borderRadius: 11, background: C.wash, fontSize: 14, color: C.ink2 }}>
              <span style={{ width: 7, height: 7, borderRadius: 4, background: C.accent }}/>Tomato oil
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, height: 30, padding: '0 13px', borderRadius: 11, background: C.wash, fontSize: 14, color: C.ink2 }}>
              <span style={{ width: 7, height: 7, borderRadius: 4, background: C.ai }}/>Hush puppies with shrimp
            </span>
          </div>

          <div style={{ flex: 1, minHeight: 22 }}/>
        </div>
      </DrawnPhone>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 3 — Today / Memories landing
// ─────────────────────────────────────────────────────────────────────────────
function MemoryCardMini({ title, time, audio, photo, note, topic, topicColor, topic2, topic2Color, extraTopics, gist, ai }) {
  return (
    <div style={{ background: C.card, border: '1px solid ' + C.hair, borderRadius: 16, padding: '15px 16px', marginBottom: 11 }}>
      <div style={{ fontFamily: C.serif, fontSize: 19, fontWeight: 500, lineHeight: 1.18, letterSpacing: -0.3, color: C.ink }}>{title}</div>
      <div style={{ fontSize: 12.5, color: C.ink3, marginTop: 5 }}>{time}</div>
      {/* media glyphs left · topic chip right — one row */}
      <div style={{ display: 'flex', alignItems: 'center', marginTop: 11 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 13, color: C.ink3 }}>
          {audio != null && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <svg width="15" height="13" viewBox="0 0 18 14" fill="none" stroke={C.accent} strokeWidth="1.8" strokeLinecap="round"><path d="M2 7h0M5 4v6M8 1.5v11M11 4v6M14 6v2M17 7h0"/></svg>
              <span style={{ fontSize: 14, color: C.ink2 }}>{audio}</span>
            </span>
          )}
          {photo != null && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <svg width="15" height="14" viewBox="0 0 20 18" fill="none" stroke={C.ink3} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2 5.5a1.5 1.5 0 011.5-1.5h2L7 2h6l1.5 2h2A1.5 1.5 0 0118 5.5v9A1.5 1.5 0 0116.5 16h-13A1.5 1.5 0 012 14.5z"/><circle cx="10" cy="10" r="3.2"/></svg>
              <span style={{ fontSize: 14, color: C.ink2 }}>{photo}</span>
            </span>
          )}
          {note != null && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <svg width="15" height="13" viewBox="0 0 18 14" fill="none" stroke={C.ink3} strokeWidth="1.8" strokeLinecap="round"><path d="M2 3h14M2 7h14M2 11h9"/></svg>
              <span style={{ fontSize: 14, color: C.ink2 }}>{note}</span>
            </span>
          )}
        </div>
        <span style={{ flex: 1 }}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <TopicChip label={topic} color={topicColor}/>
          {topic2 && <TopicChip label={topic2} color={topic2Color}/>}
          {extraTopics && <span style={{ fontSize: 13, color: C.ink3, fontWeight: 500 }}>+{extraTopics}</span>}
        </div>
      </div>
      {gist && (
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 7, marginTop: 12 }}>
          {ai && <span style={{ marginTop: 1, flexShrink: 0 }}>{G.spark(C.ai)}</span>}
          <span style={{ fontSize: 13.5, lineHeight: 1.45, color: ai ? C.ink2 : C.ink2, fontStyle: ai ? 'normal' : 'italic', fontFamily: ai ? C.sans : C.serif }}>{gist}</span>
        </div>
      )}
    </div>
  );
}
function Frame3() {
  return (
    <div className="frame">
      <div className="top-text" style={{ top: 70 }}>
        <div className="eyebrow" style={{ marginBottom: 14 }}>Your memories</div>
        <div className="headline" style={{ fontSize: 58 }}>Your days,<br/>quietly.</div>
        <div style={{ marginTop: 22, fontSize: 18, lineHeight: 1.45, color: C.ink2, maxWidth: 470 }}>
          Everything you've captured, grouped by the day it happened. No streaks. No nudges. Just your own thinking, returned to you.
        </div>
      </div>

      <DrawnPhone style={{ top: 470 }}>
        <div style={{ padding: '8px 18px 0', fontFamily: C.sans }}>
          {/* HiMem · Memories|Projects segmented · search/help/gear */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
            <span style={{ fontFamily: C.serif, fontSize: 18, fontWeight: 500, letterSpacing: 0.5, color: C.ink }}>HiMem</span>
            <span style={{ flex: 1 }}/>
            <span style={{ display: 'inline-flex', gap: 13 }}>{G.search}{G.help}{G.gear}</span>
          </div>
          <div style={{ display: 'flex', gap: 4, background: C.sunk, borderRadius: 12, padding: 3, marginBottom: 12 }}>
            <span style={{ flex: 1, textAlign: 'center', padding: '7px 0', borderRadius: 9, background: C.card, color: C.ink, fontSize: 14, fontWeight: 600, boxShadow: '0 1px 2px rgba(0,0,0,0.08)' }}>Memories</span>
            <span style={{ flex: 1, textAlign: 'center', padding: '7px 0', borderRadius: 9, color: C.ink3, fontSize: 14, fontWeight: 600 }}>Projects</span>
          </div>

          {/* Watch inbox banner — pinned at top */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, border: '1px solid ' + C.accent, background: C.card, borderRadius: 13, padding: '11px 13px', marginBottom: 14 }}>
            <span style={{ color: C.accent, flexShrink: 0 }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>
            </span>
            <span style={{ fontSize: 14, fontWeight: 700, color: C.ink }}>2 new from Apple Watch</span>
            <span style={{ fontSize: 13, color: C.ink3 }}>· Tap to review</span>
            <span style={{ flex: 1 }}/>
            <span style={{ color: C.ink3, fontSize: 15 }}>›</span>
          </div>

          {/* topic filter chips */}
          <div style={{ display: 'flex', gap: 7, marginBottom: 18, overflow: 'hidden' }}>
            <span style={{ height: 30, padding: '0 13px', borderRadius: 11, background: C.sunk, color: C.ink, fontSize: 13.5, fontWeight: 600, display: 'inline-flex', alignItems: 'center' }}>All</span>
            <TopicChip label="Content"/>
            <TopicChip label="Cooking" color="#3E4C66"/>
            <TopicChip label="Garden" color="#6B8E3D"/>
          </div>

          {/* date group */}
          <div style={{ fontFamily: C.serif, fontSize: 17, color: C.ink2, marginBottom: 11 }}>Monday, June 8</div>
          <MemoryCardMini
            title="Composting program launch & community education"
            time="6:22 PM"
            audio={14}
            topic="Garden" topicColor="#6B8E3D"
            ai gist="A passionate presentation about Beaufort County's newly launched in-vessel composting program — the first in state government." />

          <div style={{ fontFamily: C.serif, fontSize: 17, color: C.ink2, margin: '6px 0 11px' }}>Wednesday, June 3</div>
          <MemoryCardMini
            title="Travel planning: Georgia, Vermont, and Maine"
            time="9:47 PM"
            audio={3} photo={1}
            topic="Travel" topicColor="#9A4D2E"
            ai gist="You're planning destinations including Helen, Georgia and Stowe, Vermont, with a confirmed trip to Maine in two weeks." />
        </div>
      </DrawnPhone>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 4 — Captured Clips · sessions
// ─────────────────────────────────────────────────────────────────────────────
function Frame4() {
  return (
    <div className="frame">
      <div className="top-text" style={{ top: 70 }}>
        <div className="eyebrow" style={{ marginBottom: 14 }}>Captured Clips</div>
        <div className="headline" style={{ fontSize: 58 }}>Sort it out<br/>when you're ready.</div>
        <div style={{ marginTop: 22, fontSize: 18, lineHeight: 1.45, color: C.ink2, maxWidth: 470 }}>
          Capture now. Organize later. Nothing gets lost in the meantime.
        </div>
      </div>

      <DrawnPhone style={{ top: 470 }}>
        <div style={{ padding: '6px 18px 0', fontFamily: C.sans }}>
          {/* nav — back · title · ochre Done */}
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
            <span style={{ width: 30, height: 30, borderRadius: 15, background: C.card, border: '1px solid ' + C.hair, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{G.back}</span>
            <span style={{ flex: 1, textAlign: 'center', fontSize: 16, fontWeight: 600, color: C.ink, letterSpacing: -0.2 }}>Captured Clips</span>
            <span style={{ fontSize: 15, fontWeight: 600, color: C.accent }}>Done</span>
          </div>

          {/* title block — the warm session-count headline */}
          <div style={{ fontSize: 27, fontWeight: 700, letterSpacing: -0.6, color: C.ink, lineHeight: 1.05 }}>2 from your Watch</div>
          <div style={{ fontSize: 14, color: C.ink3, marginTop: 6, marginBottom: 16 }}>2 sessions · today, 2:09 PM</div>

          {/* session 1 — expanded, one primary action per session */}
          <div style={{ background: C.card, border: '1px solid ' + C.hair, borderRadius: 16, padding: '14px 15px', marginBottom: 12 }}>
            <div style={{ fontSize: 13.5, color: C.ink, fontWeight: 600 }}>
              2:09 PM <span style={{ color: C.ink3, fontWeight: 400 }}>· 1 clip · 0:04</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 11, marginTop: 12 }}>
              <span style={{ width: 22, height: 22, borderRadius: 11, border: '2px solid ' + C.accent, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: 1 }}>
                <span style={{ width: 7, height: 7, borderRadius: 4, background: C.accent }}/>
              </span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 11.5, color: C.ink3, fontVariantNumeric: 'tabular-nums', letterSpacing: 0.3 }}>0:00&nbsp;&nbsp;&nbsp;0:04</div>
                <div style={{ fontSize: 14, color: C.ink, lineHeight: 1.4, marginTop: 3 }}>“Let's take some notes about the garden.”</div>
              </div>
              <span style={{ flexShrink: 0, marginTop: 2 }}>{G.play}</span>
            </div>
            <div style={{ height: 1, background: C.hair, margin: '14px 0' }}/>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <span style={{ fontSize: 13.5, color: C.ink3 }}>Discard</span>
              <span style={{ flex: 1, height: 44, borderRadius: 22, background: C.accent, color: C.accentInk, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7, fontSize: 14.5, fontWeight: 600 }}>
                Where does this belong?
                <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={C.accentInk} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
              </span>
            </div>
          </div>

          {/* session 2 — collapsed */}
          <div style={{ background: C.card, border: '1px solid ' + C.hair, borderRadius: 16, padding: '14px 15px' }}>
            <div style={{ fontSize: 13.5, color: C.ink, fontWeight: 600 }}>
              2:09 PM <span style={{ color: C.ink3, fontWeight: 400 }}>· 1 clip · 0:06</span>
            </div>
            <div style={{ fontSize: 14, color: C.ink, lineHeight: 1.4, margin: '8px 0 14px' }}>“Idea for the porch — string lights along the railing, and move the herb pots into the sun.”</div>
            <span style={{ display: 'flex', height: 44, borderRadius: 22, background: C.accent, color: C.accentInk, alignItems: 'center', justifyContent: 'center', gap: 7, fontSize: 14.5, fontWeight: 600 }}>
              Where does this belong?
              <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={C.accentInk} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
            </span>
          </div>
        </div>
      </DrawnPhone>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 5 — Project · Find the thread (the blue AI signature)
// ─────────────────────────────────────────────────────────────────────────────
function Frame5() {
  return (
    <div className="frame">
      <div className="top-text" style={{ top: 70 }}>
        <div className="eyebrow" style={{ marginBottom: 14 }}>Projects · Plus</div>
        <div className="headline" style={{ fontSize: 58 }}>Find<br/>the thread.</div>
        <div style={{ marginTop: 22, fontSize: 18, lineHeight: 1.45, color: C.ink2, maxWidth: 470 }}>
          HiMem reads across a project and pulls out what connects — plus other memories that may belong.
        </div>
      </div>

      <DrawnPhone style={{ top: 470 }}>
        <div style={{ padding: '6px 18px 0', fontFamily: C.sans }}>
          {/* nav — back · + share trash */}
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 14 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: C.accent, fontSize: 15 }}>{G.back}Projects</span>
            <span style={{ flex: 1 }}/>
            <span style={{ display: 'inline-flex', gap: 16, alignItems: 'center' }}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={C.accent} strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/></svg>
              {G.share}{G.trash}
            </span>
          </div>

          <div style={{ fontFamily: C.serif, fontSize: 30, fontWeight: 500, letterSpacing: -0.5, color: C.ink }}>Building HiMem</div>
          {/* dashed + Add a goal */}
          <div style={{ marginTop: 12 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 32, padding: '0 14px', borderRadius: 11, border: '1px dashed ' + C.ink3, color: C.ink3, fontSize: 14, fontWeight: 500 }}>
              <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10"/></svg>
              Add a goal
            </span>
          </div>

          <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
            <TopicChip label="Content"/>
            <TopicChip label="How We Work" color="#2E6E5B"/>
            <TopicChip label="Technology" color="#9A4D2E"/>
          </div>

          {/* Find the thread card — blue AI button, trailing sparkle */}
          <div style={{ marginTop: 16, background: C.card, border: '1px solid ' + C.hair, borderRadius: 16, padding: '15px 16px' }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12, marginBottom: 13 }}>
              <span style={{ width: 36, height: 36, borderRadius: 10, background: C.aiTint, color: C.ai, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>{G.spark(C.ai)}</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600, color: C.ink, letterSpacing: -0.1 }}>Find the thread</div>
                <div style={{ fontSize: 12.5, color: C.ink3, marginTop: 2, lineHeight: 1.35 }}>A short summary across these 2 memories, and others that may belong.</div>
              </div>
            </div>
            <div style={{ height: 46, borderRadius: 12, background: C.ai, color: C.accentInk, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, width: '100%', fontSize: 14.5, fontWeight: 600, letterSpacing: -0.1 }}>
              Find the thread {G.spark(C.accentInk)}
            </div>
          </div>

          {/* suggested memories row */}
          <div style={{ marginTop: 12, background: C.sunk, borderRadius: 13, padding: '12px 15px', display: 'flex', alignItems: 'center', gap: 9 }}>
            {G.spark(C.ai)}
            <span style={{ fontSize: 14, fontWeight: 600, color: C.ink, letterSpacing: -0.1 }}>7 memories may belong here</span>
            <span style={{ flex: 1 }}/>
            <span style={{ fontSize: 13.5, fontWeight: 600, color: C.ai }}>Review ›</span>
          </div>

          <div style={{ fontSize: 13, color: C.ink3, margin: '18px 2px 11px' }}>2 memories</div>

          <MemoryCardMini
            title="HiMem memory system and reporting needs"
            time="3:37 PM"
            audio={4} extraTopics={1}
            topic="Content" topicColor="#9A4D2E"
            topic2="How We Work" topic2Color="#2E6E5B"
            ai gist="User reflects on HiMem's memory capture system for content creators and its value in preserving ideas." />
          <MemoryCardMini
            title="Inspiration capture app concept"
            time="2:22 PM"
            audio={3}
            topic="Content" topicColor="#9A4D2E"
            topic2="Technology" topic2Color="#9A4D2E"
            gist="“I'm thinking about a new product aimed at content creators — record their thoughts and inspirations…”" />
        </div>
      </DrawnPhone>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 6 — Data custody (typographic closer, dark)
// ─────────────────────────────────────────────────────────────────────────────
function Frame6() {
  return (
    <div className="frame dark" style={{ background: '#000' }}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 64px' }}>
        {/* shield + iCloud mark, ochre */}
        <svg width="76" height="76" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" style={{ marginBottom: 40 }}>
          <path d="M12 2l8 3.5v6c0 5-3.5 8.3-8 10.5-4.5-2.2-8-5.5-8-10.5v-6z"/>
          <path d="M8.5 13.2a2.4 2.4 0 01.3-4.6 3.2 3.2 0 016.1.6 2.1 2.1 0 01-.4 4.1z"/>
        </svg>
        <div className="eyebrow" style={{ color: 'rgba(240,233,220,0.55)', marginBottom: 18 }}>Private by default</div>
        <div className="headline" style={{ fontSize: 58, color: '#F0E9DC' }}>Yours.<br/>In your iCloud.</div>
        <div style={{ marginTop: 26, fontSize: 19, lineHeight: 1.5, color: 'rgba(240,233,220,0.74)', maxWidth: 430 }}>
          Your memories sync through your own iCloud — visible in Files, durable across reinstalls, and never on our servers.
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Frame1, Frame2, Frame3, Frame4, Frame5, Frame6 });

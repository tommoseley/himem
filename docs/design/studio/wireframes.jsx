// Himem Studio — iPad wireframes
// Five lo-fi layout explorations for the "Project workspace" view.
// One concrete project: "The Future of Work" → Reddit essay, LinkedIn article, YouTube reel.

const C = window.Crucible;

// ──────────────────────────────────────────────────────────────
// Wireframe primitives — intentionally lo-fi.
// Boxes, hatching, dotted text lines. No real type, no real images.
// All rendered in Crucible warm-paper palette so the brand still reads.
// ──────────────────────────────────────────────────────────────

const W = {
  paper: C.color.paper,
  card: C.color.card,
  sunk: C.color.sunk,
  line: 'rgba(25,20,15,0.18)',
  lineHeavy: 'rgba(25,20,15,0.32)',
  hairline: 'rgba(25,20,15,0.10)',
  ink: 'rgba(26,22,18,0.78)',
  ink2: 'rgba(26,22,18,0.50)',
  ink3: 'rgba(26,22,18,0.32)',
  fill: 'rgba(25,20,15,0.06)',
  ember: C.color.accent,
  emberTint: C.color.accentTint,
  ai: C.color.ai.base,
  aiTint: C.color.ai.tint,
  audio: C.color.media.audio,
  text: C.color.media.text,
  photo: C.color.media.photo,
  video: C.color.media.video,
};

// Dashed/hatched fill — placeholder for "real content goes here"
function Hatch({ children, style }) {
  return (
    <div style={{
      backgroundImage: `repeating-linear-gradient(135deg, rgba(25,20,15,0.06) 0 1px, transparent 1px 8px)`,
      ...style,
    }}>{children}</div>
  );
}

// A row of fake type lines
function TypeLines({ count = 3, w = ['100%', '92%', '70%'], h = 6, gap = 8, color = W.line, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap, ...style }}>
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} style={{
          height: h, width: (w[i] ?? w[w.length - 1]),
          background: color, borderRadius: h / 2, opacity: 0.55,
        }}/>
      ))}
    </div>
  );
}

// Fake h1
function Hed({ w = '60%', h = 14, style }) {
  return <div style={{ height: h, width: w, background: W.lineHeavy, borderRadius: 2, ...style }}/>;
}

// Lo-fi memory card — appears in bin
function MemCard({ title, mediaTypes = ['text'], style }) {
  return (
    <div style={{
      background: W.card, border: `1px solid ${W.hairline}`, borderRadius: 4,
      padding: 8, display: 'flex', flexDirection: 'column', gap: 6, ...style,
    }}>
      <div style={{ display: 'flex', gap: 4 }}>
        {mediaTypes.map((t, i) => (
          <div key={i} style={{ width: 6, height: 6, borderRadius: 3, background: W[t] }}/>
        ))}
      </div>
      <Hed w="80%" h={6}/>
      <TypeLines count={2} h={4} gap={4} w={['100%', '60%']}/>
    </div>
  );
}

// Pencil annotation curl in margin (lo-fi — a wavy underline)
function PencilSquiggle({ w = 80, color = W.ink2, style }) {
  return (
    <svg width={w} height={10} viewBox={`0 0 ${w} 10`} style={style}>
      <path d={`M 2 6 Q ${w/4} 1 ${w/2} 6 T ${w-2} 6`} fill="none" stroke={color} strokeWidth={1.2} strokeLinecap="round"/>
    </svg>
  );
}

// Tab pill (used in studio chrome)
function Tab({ children, active, onClick, style }) {
  return (
    <div onClick={onClick} style={{
      padding: '5px 10px', borderRadius: 6,
      background: active ? W.card : 'transparent',
      boxShadow: active ? '0 1px 2px rgba(0,0,0,0.06)' : 'none',
      fontSize: 11, fontWeight: active ? 600 : 500,
      color: active ? C.color.ink : W.ink2,
      cursor: 'pointer', whiteSpace: 'nowrap',
      ...style,
    }}>{children}</div>
  );
}

// iPad chrome — status bar + outer rounded frame.
// Internal because each artboard renders its own iPad device.
function IPadFrame({ children, width = 1366, height = 1024 }) {
  return (
    <div style={{
      width, height, background: W.paper, position: 'relative',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif',
      overflow: 'hidden', display: 'flex', flexDirection: 'column',
    }}>
      {/* status bar */}
      <div style={{
        height: 24, padding: '0 24px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        fontSize: 11, fontWeight: 600, color: C.color.ink, letterSpacing: -0.2,
        flexShrink: 0,
      }}>
        <span>9:41</span>
        <span style={{ color: W.ink2, fontWeight: 500, fontSize: 10 }}>Tue · Apr 28</span>
        <span style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <span style={{ width: 14, height: 8, border: `1px solid ${W.ink}`, borderRadius: 1, position: 'relative' }}>
            <span style={{ position: 'absolute', inset: 1, right: 4, background: W.ink }}/>
          </span>
        </span>
      </div>
      <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
        {children}
      </div>
    </div>
  );
}

// Studio top chrome — same across all layouts so the variation is in the body.
function StudioTopChrome({ projectTitle = 'The Future of Work', mode = 'project', aiPresence = 'palette' }) {
  return (
    <div style={{
      height: 48, padding: '0 18px',
      display: 'flex', alignItems: 'center', gap: 12,
      borderBottom: `1px solid ${W.hairline}`, background: W.paper, flexShrink: 0,
    }}>
      {/* HI MEM mark */}
      <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 2, color: W.ink2 }}>HI MEM</div>
      <div style={{ width: 1, height: 18, background: W.hairline }}/>
      {/* Memories | Projects segmented */}
      <div style={{
        display: 'flex', gap: 2, padding: 2, borderRadius: 8,
        background: W.fill,
      }}>
        <Tab active={mode === 'memories'}>Memories</Tab>
        <Tab active={mode === 'project'}>Projects</Tab>
      </div>
      {/* breadcrumb to project */}
      <div style={{ fontSize: 11, color: W.ink2, display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ color: W.ink2 }}>Projects</span>
        <span>›</span>
        <span style={{ color: C.color.ink, fontWeight: 600 }}>{projectTitle}</span>
      </div>
      <div style={{ flex: 1 }}/>
      {/* command palette hint */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        padding: '4px 8px', border: `1px solid ${W.hairline}`, borderRadius: 6,
        fontSize: 10, color: W.ink2, background: W.card,
      }}>
        <span>⌘K</span><span style={{ color: W.ink3 }}>·</span><span>Tools</span>
      </div>
      {/* user/avatar */}
      <div style={{ width: 24, height: 24, borderRadius: 12, background: W.fill, border: `1px solid ${W.hairline}` }}/>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────
// Reusable studio panes
// ──────────────────────────────────────────────────────────────

// LEFT PANE — Memory bin / library
function PaneBin({ width = 240, compact = false }) {
  const memories = [
    { t: 'AI rewrites office norms', m: ['text'] },
    { t: 'Voice note · airport rant', m: ['audio'] },
    { t: 'Whiteboard photo · hybrid', m: ['photo', 'text'] },
    { t: 'Substack: 4-day week', m: ['text'] },
    { t: 'Zoom replaced by ambient', m: ['audio', 'text'] },
    { t: 'Clip · agent demo', m: ['video'] },
    { t: 'Quote · "agency over hours"', m: ['text'] },
    { t: 'Photo · standing desks 2026', m: ['photo'] },
  ];
  return (
    <div style={{
      width, background: W.paper, borderRight: `1px solid ${W.hairline}`,
      display: 'flex', flexDirection: 'column', flexShrink: 0,
    }}>
      {/* search */}
      <div style={{ padding: 10, borderBottom: `1px solid ${W.hairline}` }}>
        <div style={{
          height: 26, padding: '0 8px', borderRadius: 6,
          background: W.fill, display: 'flex', alignItems: 'center', gap: 6,
          fontSize: 11, color: W.ink3,
        }}>
          <span>⌕</span><span>Search bin · 47 memories</span>
        </div>
      </div>
      {/* topic filter */}
      <div style={{ padding: '8px 10px', display: 'flex', gap: 4, flexWrap: 'wrap' }}>
        <div style={{ padding: '2px 6px', fontSize: 9, fontWeight: 600, borderRadius: 999, background: C.color.topicPalette[10].bg, color: C.color.topicPalette[10].fg }}>● Future of Work</div>
        <div style={{ padding: '2px 6px', fontSize: 9, color: W.ink2 }}>+ Topic</div>
      </div>
      {/* sticky AI suggestion strip */}
      <div style={{
        margin: '4px 10px 8px', padding: 8, borderRadius: 6,
        background: W.aiTint, border: `1px solid ${W.ai}22`,
        display: 'flex', flexDirection: 'column', gap: 4,
      }}>
        <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: 0.5, color: W.ai, textTransform: 'uppercase' }}>AI · Suggested</div>
        <div style={{ fontSize: 10, color: W.ink, lineHeight: 1.3 }}>3 memories from "Cooking" reference labor patterns — pull?</div>
      </div>
      {/* list */}
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 10px 10px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 9, fontWeight: 600, color: W.ink2, padding: '4px 0', letterSpacing: 0.4, textTransform: 'uppercase' }}>In this project · 12</div>
        {memories.slice(0, compact ? 4 : 8).map((m, i) => (
          <MemCard key={i} title={m.t} mediaTypes={m.m}/>
        ))}
      </div>
    </div>
  );
}

// CENTER PANE — Document
function PaneDocument({ flex = 1, aiPresence = 'silent', showOutputTabs = true, narrow = false }) {
  return (
    <div style={{
      flex, background: W.paper, display: 'flex', flexDirection: 'column', minWidth: 0,
    }}>
      {/* output tabs */}
      {showOutputTabs && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 2, padding: '8px 18px 0',
          borderBottom: `1px solid ${W.hairline}`,
        }}>
          <Tab active>Reddit · long</Tab>
          <Tab>LinkedIn · short</Tab>
          <Tab>Reel · 90s</Tab>
          <div style={{ flex: 1 }}/>
          <div style={{ fontSize: 10, color: W.ink2, padding: '0 6px' }}>Draft 3 · 1,840 words</div>
        </div>
      )}
      {/* document body */}
      <div style={{
        flex: 1, overflow: 'hidden',
        padding: narrow ? '32px 60px' : '32px 80px',
        background: W.card, position: 'relative',
        display: 'flex', flexDirection: 'column', gap: 18,
      }}>
        {/* title */}
        <div>
          <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: 1.6, color: W.ai, textTransform: 'uppercase', marginBottom: 6 }}>Reddit · r/futurology</div>
          <div style={{
            fontFamily: 'Source Serif 4, Georgia, serif',
            fontSize: 22, fontWeight: 600, color: C.color.ink, letterSpacing: -0.3,
            lineHeight: 1.15,
          }}>
            The future of work isn't remote vs. office. It's about who decides.
          </div>
          <div style={{ marginTop: 8, fontSize: 10, color: W.ink2, display: 'flex', gap: 10 }}>
            <span>Edited 2m ago</span>
            <span>·</span>
            <span>9 source memories pulled</span>
          </div>
        </div>
        {/* paragraphs (lo-fi text lines, with one inline AI annotation) */}
        <TypeLines count={4} w={['100%', '98%', '94%', '88%']} h={5} gap={7}/>
        <TypeLines count={5} w={['100%', '100%', '92%', '96%', '70%']} h={5} gap={7}/>

        {/* an inline pulled memory — looks like a blockquote referencing the bin */}
        <div style={{
          padding: '10px 14px', borderLeft: `2px solid ${W.ember}`, background: W.emberTint,
          display: 'flex', flexDirection: 'column', gap: 6,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 9, fontWeight: 600, color: W.ember, textTransform: 'uppercase', letterSpacing: 0.4 }}>
            <div style={{ width: 5, height: 5, borderRadius: 3, background: W.audio }}/>
            <span>Memory · airport rant · 0:42</span>
          </div>
          <TypeLines count={2} w={['100%', '70%']} h={4} gap={5} color={W.ember}/>
        </div>

        <TypeLines count={6} w={['100%', '94%', '100%', '88%', '96%', '60%']} h={5} gap={7}/>

        {/* AI presence variants */}
        {aiPresence === 'copilot' && (
          <div style={{
            position: 'absolute', right: 18, top: 80,
            width: 180, padding: 10, borderRadius: 6,
            background: W.aiTint, border: `1px solid ${W.ai}33`,
            display: 'flex', flexDirection: 'column', gap: 6,
          }}>
            <div style={{ fontSize: 9, fontWeight: 700, color: W.ai, letterSpacing: 0.4, textTransform: 'uppercase' }}>AI · Margin note</div>
            <div style={{ fontSize: 10, color: W.ink, lineHeight: 1.4 }}>This paragraph repeats the thesis from §1. Cut or strengthen?</div>
            <div style={{ display: 'flex', gap: 4, marginTop: 2 }}>
              <div style={{ padding: '2px 6px', fontSize: 9, fontWeight: 600, borderRadius: 4, background: W.ai, color: '#fff' }}>Trim</div>
              <div style={{ padding: '2px 6px', fontSize: 9, fontWeight: 500, borderRadius: 4, background: 'transparent', color: W.ink2, border: `1px solid ${W.hairline}` }}>Dismiss</div>
            </div>
          </div>
        )}

        {/* pencil annotation (Apple Pencil) */}
        <div style={{ position: 'absolute', right: 30, top: 220, transform: 'rotate(-4deg)', fontFamily: '"Bradley Hand", "Marker Felt", cursive', fontSize: 11, color: 'rgba(30,92,142,0.78)' }}>
          tighten ↑
          <PencilSquiggle w={50} color="rgba(30,92,142,0.5)" style={{ marginTop: 1 }}/>
        </div>
      </div>
    </div>
  );
}

// RIGHT PANE — Inspector & tools
function PaneInspector({ width = 280, aiPresence = 'palette' }) {
  return (
    <div style={{
      width, background: W.paper, borderLeft: `1px solid ${W.hairline}`,
      display: 'flex', flexDirection: 'column', flexShrink: 0,
    }}>
      {/* tabs: Outline · Tools · Notes · Assets */}
      <div style={{
        display: 'flex', padding: 8, gap: 2, borderBottom: `1px solid ${W.hairline}`,
        background: W.fill,
      }}>
        <Tab active>Tools</Tab>
        <Tab>Outline</Tab>
        <Tab>Notes</Tab>
        <Tab>Assets</Tab>
      </div>
      {/* tools list */}
      <div style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 8, overflow: 'hidden', flex: 1 }}>
        <div style={{ fontSize: 9, fontWeight: 700, color: W.ink2, letterSpacing: 0.6, textTransform: 'uppercase' }}>Edit</div>
        <ToolRow label="Trim & tighten" hint="Cut by N%" />
        <ToolRow label="Tone rewrite" hint="Conversational ▾" />
        <ToolRow label="Pull-quote extractor" />
        <ToolRow label="Headline brainstormer" />

        <div style={{ fontSize: 9, fontWeight: 700, color: W.ink2, letterSpacing: 0.6, textTransform: 'uppercase', marginTop: 6 }}>Source</div>
        <ToolRow label="Find related memories" />
        <ToolRow label="Continuity check" />

        <div style={{ fontSize: 9, fontWeight: 700, color: W.ink2, letterSpacing: 0.6, textTransform: 'uppercase', marginTop: 6 }}>Output</div>
        <ToolRow label="Adapt for LinkedIn" hint="from Reddit" />
        <ToolRow label="Adapt for Reel script" hint="from Reddit" />
        <ToolRow label="Export PDF / .md" />
      </div>
      {aiPresence === 'chat' && (
        <div style={{ borderTop: `1px solid ${W.hairline}`, padding: 10, background: W.aiTint, height: 180, display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ fontSize: 9, fontWeight: 700, color: W.ai, letterSpacing: 0.5, textTransform: 'uppercase' }}>AI · Project chat</div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
            <div style={{ alignSelf: 'flex-start', maxWidth: '88%', padding: 6, borderRadius: 6, background: W.card, fontSize: 10, color: W.ink }}>Want me to start the LinkedIn version from §1–4?</div>
            <div style={{ alignSelf: 'flex-end', maxWidth: '88%', padding: 6, borderRadius: 6, background: W.ai, color: '#fff', fontSize: 10 }}>yes — keep it under 600 words</div>
          </div>
          <div style={{ height: 22, borderRadius: 4, background: W.card, border: `1px solid ${W.hairline}`, display: 'flex', alignItems: 'center', padding: '0 6px', fontSize: 10, color: W.ink3 }}>Ask the project…</div>
        </div>
      )}
    </div>
  );
}

function ToolRow({ label, hint }) {
  return (
    <div style={{
      padding: '6px 8px', border: `1px solid ${W.hairline}`, borderRadius: 6,
      background: W.card, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    }}>
      <span style={{ fontSize: 10, color: C.color.ink, fontWeight: 500 }}>{label}</span>
      {hint && <span style={{ fontSize: 9, color: W.ink2 }}>{hint}</span>}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────
// LAYOUT 1 — Three-pane classic
// Bin · Document · Inspector. The producer's IDE.
// ──────────────────────────────────────────────────────────────
function StudioThreePane({ aiPresence = 'silent' }) {
  return (
    <IPadFrame>
      <StudioTopChrome aiPresence={aiPresence}/>
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        <PaneBin/>
        <PaneDocument aiPresence={aiPresence}/>
        <PaneInspector aiPresence={aiPresence}/>
      </div>
    </IPadFrame>
  );
}

// ──────────────────────────────────────────────────────────────
// LAYOUT 2 — Two-pane with collapsible drawers
// Document is the hero. Bin and Inspector live behind edge handles.
// ──────────────────────────────────────────────────────────────
function StudioTwoPane({ aiPresence = 'silent' }) {
  return (
    <IPadFrame>
      <StudioTopChrome aiPresence={aiPresence}/>
      <div style={{ flex: 1, display: 'flex', minHeight: 0, position: 'relative' }}>
        {/* Bin drawer (collapsed handle on left) */}
        <div style={{
          width: 44, background: W.paper, borderRight: `1px solid ${W.hairline}`,
          display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '12px 0', gap: 14, flexShrink: 0,
        }}>
          <div style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', fontSize: 10, fontWeight: 600, color: W.ink2, letterSpacing: 1, textTransform: 'uppercase' }}>Bin · 47</div>
          <div style={{ width: 22, height: 22, borderRadius: 4, background: W.fill, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: W.ink2 }}>›</div>
          <div style={{ flex: 1 }}/>
          {/* media filter dots */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {['audio', 'text', 'photo', 'video'].map(t => (
              <div key={t} style={{ width: 8, height: 8, borderRadius: 4, background: W[t] }}/>
            ))}
          </div>
        </div>
        {/* Document */}
        <PaneDocument aiPresence={aiPresence}/>
        {/* Inspector drawer (collapsed handle on right) */}
        <div style={{
          width: 44, background: W.paper, borderLeft: `1px solid ${W.hairline}`,
          display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '12px 0', gap: 14, flexShrink: 0,
        }}>
          <div style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', fontSize: 10, fontWeight: 600, color: W.ink2, letterSpacing: 1, textTransform: 'uppercase' }}>Tools</div>
          <div style={{ width: 22, height: 22, borderRadius: 4, background: W.fill, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: W.ink2 }}>‹</div>
          <div style={{ flex: 1 }}/>
          <div style={{ width: 22, height: 22, borderRadius: 4, background: W.ai, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, fontWeight: 700 }}>✦</div>
        </div>
        {/* Floating bin preview slid out partway */}
        <div style={{
          position: 'absolute', left: 44, top: 12, bottom: 12, width: 200,
          background: W.card, borderRadius: 8,
          boxShadow: '0 8px 24px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.06)',
          padding: 10, display: 'flex', flexDirection: 'column', gap: 6,
        }}>
          <div style={{ fontSize: 9, fontWeight: 700, color: W.ink2, letterSpacing: 0.5, textTransform: 'uppercase' }}>Bin · drag onto doc</div>
          <MemCard mediaTypes={['audio']}/>
          <MemCard mediaTypes={['text']}/>
          <MemCard mediaTypes={['photo', 'text']}/>
        </div>
      </div>
    </IPadFrame>
  );
}

// ──────────────────────────────────────────────────────────────
// LAYOUT 3 — Tab-bar workspace
// The studio is one app at a time: Outline / Write / Assets / Export.
// ──────────────────────────────────────────────────────────────
function StudioTabBar({ aiPresence = 'silent' }) {
  return (
    <IPadFrame>
      <StudioTopChrome aiPresence={aiPresence}/>
      {/* big workspace tabs */}
      <div style={{
        height: 52, padding: '0 24px',
        display: 'flex', alignItems: 'center', gap: 4,
        borderBottom: `1px solid ${W.hairline}`, background: W.paper, flexShrink: 0,
      }}>
        {[
          { l: 'Bin', n: '47' },
          { l: 'Outline', n: '8' },
          { l: 'Write', n: '', active: true },
          { l: 'Assets', n: '12' },
          { l: 'Export', n: '3' },
        ].map((t) => (
          <div key={t.l} style={{
            padding: '8px 16px', display: 'flex', alignItems: 'center', gap: 6,
            borderRadius: 8,
            background: t.active ? W.card : 'transparent',
            boxShadow: t.active ? '0 1px 2px rgba(0,0,0,0.06)' : 'none',
            border: t.active ? `1px solid ${W.hairline}` : '1px solid transparent',
            fontSize: 13, fontWeight: t.active ? 600 : 500,
            color: t.active ? C.color.ink : W.ink2,
          }}>
            <span>{t.l}</span>
            {t.n && <span style={{ fontSize: 10, color: W.ink3, padding: '1px 5px', borderRadius: 4, background: W.fill }}>{t.n}</span>}
          </div>
        ))}
        <div style={{ flex: 1 }}/>
        <div style={{ fontSize: 11, color: W.ink2 }}>● Saved · 2m</div>
      </div>
      {/* Content for "Write" tab */}
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        <PaneDocument aiPresence={aiPresence} showOutputTabs={true} narrow={false}/>
        {/* Slim contextual panel */}
        <div style={{
          width: 240, background: W.paper, borderLeft: `1px solid ${W.hairline}`,
          padding: 14, display: 'flex', flexDirection: 'column', gap: 10, flexShrink: 0,
        }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: W.ink2, letterSpacing: 0.5, textTransform: 'uppercase' }}>This output</div>
          <div style={{ padding: 10, background: W.card, borderRadius: 6, border: `1px solid ${W.hairline}`, display: 'flex', flexDirection: 'column', gap: 4 }}>
            <div style={{ fontSize: 11, fontWeight: 600, color: C.color.ink }}>Reddit · r/futurology</div>
            <div style={{ fontSize: 10, color: W.ink2 }}>Long · 1,840 / ~2,500 target</div>
          </div>
          <ToolRow label="Trim 20%"/>
          <ToolRow label="Tone: tighter"/>
          <ToolRow label="Title brainstorm"/>
          <div style={{ flex: 1 }}/>
          <div style={{ fontSize: 10, color: W.ink2, padding: 8, background: W.fill, borderRadius: 6 }}>
            Switch to <b>Outline</b> to restructure, or <b>Assets</b> to swap photos.
          </div>
        </div>
      </div>
    </IPadFrame>
  );
}

// ──────────────────────────────────────────────────────────────
// LAYOUT 4 — Canvas / corkboard
// Free-arrange cards. The document is one card. Outputs are siblings.
// ──────────────────────────────────────────────────────────────
function StudioCanvas({ aiPresence = 'silent' }) {
  // small layout helpers
  const cardShadow = '0 1px 2px rgba(0,0,0,0.05), 0 4px 12px rgba(0,0,0,0.06)';
  return (
    <IPadFrame>
      <StudioTopChrome aiPresence={aiPresence}/>
      <div style={{
        flex: 1, position: 'relative', minHeight: 0,
        background: W.sunk,
        backgroundImage: `radial-gradient(${W.line} 1px, transparent 1px)`,
        backgroundSize: '20px 20px',
        overflow: 'hidden',
      }}>
        {/* Source memories cluster (top-left) */}
        <div style={{ position: 'absolute', top: 24, left: 32, width: 240, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: W.ink2, letterSpacing: 0.5, textTransform: 'uppercase' }}>Source memories</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {Array.from({ length: 8 }).map((_, i) => (
              <MemCard key={i} mediaTypes={[['audio','text','photo','video','text','photo','audio','text'][i]]}/>
            ))}
          </div>
        </div>

        {/* Outline card (middle-left, connected to memories) */}
        <div style={{
          position: 'absolute', top: 70, left: 320, width: 220,
          background: W.card, borderRadius: 6, padding: 12, boxShadow: cardShadow,
          display: 'flex', flexDirection: 'column', gap: 8,
        }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: W.ink2, letterSpacing: 0.5, textTransform: 'uppercase' }}>Outline</div>
          {['1 · Hook: not where, who decides', '2 · Three trends', '3 · Counter: agency vs hours', '4 · What workplaces miss', '5 · Close: a quieter future'].map((s, i) => (
            <div key={i} style={{ fontSize: 10, color: W.ink, padding: '4px 6px', background: W.fill, borderRadius: 4 }}>{s}</div>
          ))}
        </div>

        {/* Main draft card — Reddit */}
        <div style={{
          position: 'absolute', top: 50, left: 580, width: 380, height: 420,
          background: W.card, borderRadius: 6, boxShadow: cardShadow,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ padding: '8px 14px', borderBottom: `1px solid ${W.hairline}`, display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 8, height: 8, borderRadius: 2, background: W.ai }}/>
            <div style={{ fontSize: 11, fontWeight: 600, color: C.color.ink }}>Reddit · long</div>
            <div style={{ flex: 1 }}/>
            <div style={{ fontSize: 9, color: W.ink2 }}>1,840w</div>
          </div>
          <div style={{ padding: 16, flex: 1, display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div style={{ fontFamily: 'Source Serif 4, Georgia, serif', fontSize: 14, fontWeight: 600, color: C.color.ink, lineHeight: 1.2 }}>The future of work isn't remote vs. office. It's about who decides.</div>
            <TypeLines count={3} h={4} gap={5} w={['100%', '94%', '88%']}/>
            <TypeLines count={4} h={4} gap={5} w={['100%', '100%', '90%', '70%']}/>
            <div style={{ padding: 8, borderLeft: `2px solid ${W.ember}`, background: W.emberTint }}>
              <TypeLines count={2} h={4} gap={4} w={['100%', '80%']} color={W.ember}/>
            </div>
            <TypeLines count={3} h={4} gap={5}/>
          </div>
        </div>

        {/* LinkedIn card */}
        <div style={{
          position: 'absolute', top: 500, left: 580, width: 200, height: 240,
          background: W.card, borderRadius: 6, boxShadow: cardShadow,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ padding: '6px 10px', borderBottom: `1px solid ${W.hairline}`, fontSize: 10, fontWeight: 600, color: C.color.ink }}>LinkedIn · short</div>
          <div style={{ padding: 10, flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
            <Hed w="80%" h={8}/>
            <TypeLines count={5} h={3} gap={4}/>
          </div>
        </div>

        {/* Reel card */}
        <div style={{
          position: 'absolute', top: 500, left: 800, width: 180, height: 240,
          background: W.card, borderRadius: 6, boxShadow: cardShadow,
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ padding: '6px 10px', borderBottom: `1px solid ${W.hairline}`, fontSize: 10, fontWeight: 600, color: C.color.ink }}>Reel · 90s</div>
          <Hatch style={{ height: 80, borderBottom: `1px solid ${W.hairline}` }}/>
          <div style={{ padding: 10, flex: 1, display: 'flex', flexDirection: 'column', gap: 4 }}>
            <TypeLines count={4} h={3} gap={4} w={['100%', '90%', '70%', '60%']}/>
          </div>
        </div>

        {/* Notes card (post-it style) */}
        <DCPostIt top={460} left={50} rotate={-3} width={200}>
          Remember: the punchline is who decides, not where you work.
        </DCPostIt>

        {/* Connection lines (dashed) — bin → outline → drafts */}
        <svg style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          <path d="M 280 240 C 300 240, 310 180, 320 180" stroke={W.line} strokeWidth="1" strokeDasharray="3 3" fill="none"/>
          <path d="M 540 220 C 560 220, 560 200, 580 200" stroke={W.line} strokeWidth="1" strokeDasharray="3 3" fill="none"/>
          <path d="M 770 470 C 770 490, 680 490, 680 500" stroke={W.line} strokeWidth="1" strokeDasharray="3 3" fill="none"/>
          <path d="M 770 470 C 800 490, 870 490, 880 500" stroke={W.line} strokeWidth="1" strokeDasharray="3 3" fill="none"/>
        </svg>

        {/* Floating tool palette */}
        <div style={{
          position: 'absolute', right: 20, top: 24, width: 56,
          background: W.card, borderRadius: 8, boxShadow: cardShadow,
          padding: 8, display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'center',
        }}>
          {['✦', '✂', '✎', '↻', '⊕'].map((g, i) => (
            <div key={i} style={{
              width: 36, height: 36, borderRadius: 6,
              background: i === 0 ? W.ai : 'transparent',
              color: i === 0 ? '#fff' : W.ink2,
              display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14,
            }}>{g}</div>
          ))}
        </div>

        {/* AI command palette overlay */}
        {aiPresence === 'palette' && (
          <div style={{
            position: 'absolute', left: '50%', top: 80, transform: 'translateX(-50%)',
            width: 360, background: W.card, borderRadius: 10, boxShadow: '0 12px 32px rgba(0,0,0,0.18)',
            padding: 12, display: 'flex', flexDirection: 'column', gap: 6,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 6, background: W.fill, borderRadius: 6 }}>
              <span style={{ color: W.ai, fontWeight: 700 }}>✦</span>
              <span style={{ fontSize: 12, color: C.color.ink }}>tighten the conclusion</span>
              <span style={{ fontSize: 9, color: W.ink3, marginLeft: 'auto' }}>⏎</span>
            </div>
            <div style={{ fontSize: 10, color: W.ink2, padding: '4px 6px' }}>Trim · Tone · Headline · Find quote · Adapt</div>
          </div>
        )}
      </div>
    </IPadFrame>
  );
}

// ──────────────────────────────────────────────────────────────
// LAYOUT 5 — Doc-first with rail
// Manuscript dominates. Thin tool rail on the side. Drawers on demand.
// ──────────────────────────────────────────────────────────────
function StudioDocFirst({ aiPresence = 'copilot' }) {
  return (
    <IPadFrame>
      <StudioTopChrome aiPresence={aiPresence}/>
      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* thin tool rail (left) */}
        <div style={{
          width: 56, background: W.paper, borderRight: `1px solid ${W.hairline}`,
          padding: '14px 0', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, flexShrink: 0,
        }}>
          {[
            { g: '◫', l: 'Bin' },
            { g: '☰', l: 'Outline' },
            { g: '✎', l: 'Write', active: true },
            { g: '◐', l: 'Assets' },
            { g: '↗', l: 'Export' },
          ].map((t, i) => (
            <div key={i} style={{
              width: 40, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2,
              padding: '6px 0', borderRadius: 6,
              background: t.active ? W.fill : 'transparent',
              color: t.active ? C.color.ink : W.ink2,
            }}>
              <span style={{ fontSize: 14 }}>{t.g}</span>
              <span style={{ fontSize: 8, fontWeight: 600 }}>{t.l}</span>
            </div>
          ))}
          <div style={{ flex: 1 }}/>
          {/* AI ✦ button */}
          <div style={{
            width: 40, height: 40, borderRadius: 8, background: W.ai, color: '#fff',
            display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16,
          }}>✦</div>
        </div>

        {/* full-bleed manuscript */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          {/* output switcher pinned to top */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6, padding: '10px 24px',
            borderBottom: `1px solid ${W.hairline}`, background: W.paper,
          }}>
            <Tab active>Reddit · long</Tab>
            <Tab>LinkedIn · short</Tab>
            <Tab>Reel · 90s</Tab>
            <div style={{ flex: 1 }}/>
            <div style={{ fontSize: 10, color: W.ink2 }}>1,840 / 2,500 words</div>
            <div style={{ width: 80, height: 4, background: W.fill, borderRadius: 2, overflow: 'hidden' }}>
              <div style={{ width: '74%', height: '100%', background: W.ember }}/>
            </div>
          </div>

          {/* manuscript */}
          <div style={{
            flex: 1, overflow: 'hidden', background: W.card,
            padding: '40px 14% 40px 14%',
            display: 'flex', flexDirection: 'column', gap: 22,
            position: 'relative',
          }}>
            <div>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.6, color: W.ai, textTransform: 'uppercase', marginBottom: 10 }}>r/futurology · draft 3</div>
              <div style={{
                fontFamily: 'Source Serif 4, Georgia, serif',
                fontSize: 30, fontWeight: 600, color: C.color.ink, letterSpacing: -0.4,
                lineHeight: 1.1, maxWidth: 580,
              }}>
                The future of work isn't remote vs. office.<br/>It's about who decides.
              </div>
            </div>
            <TypeLines count={4} w={['100%', '98%', '94%', '88%']} h={6} gap={9}/>
            <div style={{
              padding: '14px 18px', borderLeft: `2px solid ${W.ember}`, background: W.emberTint,
              display: 'flex', flexDirection: 'column', gap: 6,
            }}>
              <div style={{ fontSize: 10, fontWeight: 600, color: W.ember, textTransform: 'uppercase', letterSpacing: 0.4, display: 'flex', gap: 6, alignItems: 'center' }}>
                <div style={{ width: 6, height: 6, borderRadius: 3, background: W.audio }}/>
                <span>From memory · airport rant · 0:42</span>
              </div>
              <TypeLines count={2} w={['100%', '80%']} h={5} gap={6} color={W.ember}/>
            </div>
            <TypeLines count={6} w={['100%', '94%', '100%', '88%', '96%', '60%']} h={6} gap={9}/>

            {aiPresence === 'copilot' && (
              <>
                {/* margin annotation 1 */}
                <div style={{
                  position: 'absolute', right: 40, top: 220, width: 160,
                  padding: 10, borderRadius: 6, background: W.aiTint, border: `1px solid ${W.ai}33`,
                }}>
                  <div style={{ fontSize: 9, fontWeight: 700, color: W.ai, textTransform: 'uppercase', letterSpacing: 0.4, marginBottom: 4 }}>Margin · ✦</div>
                  <div style={{ fontSize: 10, color: W.ink, lineHeight: 1.4 }}>Stronger if you cite the Substack memory here.</div>
                </div>
                {/* margin annotation 2 (pencil) */}
                <div style={{
                  position: 'absolute', right: 40, top: 380, transform: 'rotate(-2deg)',
                  fontFamily: '"Bradley Hand", "Marker Felt", cursive', fontSize: 13, color: 'rgba(30,92,142,0.78)',
                }}>
                  cut this ¶ ↓
                  <PencilSquiggle w={60} color="rgba(30,92,142,0.5)" style={{ marginTop: 2 }}/>
                </div>
              </>
            )}
          </div>
        </div>
      </div>
    </IPadFrame>
  );
}

window.StudioThreePane = StudioThreePane;
window.StudioTwoPane = StudioTwoPane;
window.StudioTabBar = StudioTabBar;
window.StudioCanvas = StudioCanvas;
window.StudioDocFirst = StudioDocFirst;

// screens-projects-spec.jsx
// Annotated dev specs for the Suggested memories review row.
// Pure visual reference — no behavior.
//
// SPEC was a duplicate of PX (with one bug: paper was #FFFCF6, should have
// been canvas card-color). Now an alias of PX with the file-local "rule"
// annotation color kept as a literal — that's dev-tool chrome, not a
// design token.

const SPEC = {
  ...PX,
  paper: PX.card,        // this file shows specs on a white page, not cream
  rule:  '#9FB7CC',      // annotation tick color — dev-tool chrome, not Crucible
};

// ─── Small annotation primitives ──────────────────────────────
function Note({ children, style }) {
  return (
    <div style={{
      fontFamily: SPEC.mono, fontSize: 10.5, color: SPEC.ai, lineHeight: 1.4,
      letterSpacing: 0, ...style,
    }}>{children}</div>
  );
}

function Caption({ children, style }) {
  return (
    <div style={{
      fontFamily: SPEC.sans, fontSize: 10.5, color: SPEC.ink3,
      letterSpacing: 1.4, textTransform: 'uppercase', fontWeight: 700, ...style,
    }}>{children}</div>
  );
}

function Tick({ x, y, w = 60, side = 'right' }) {
  // Horizontal measurement tick
  return (
    <svg width={w + 14} height="10" viewBox={`0 0 ${w + 14} 10`} style={{ position: 'absolute', left: x, top: y, color: SPEC.rule }}>
      <line x1="2" y1="5" x2={w + 12} y2="5" stroke="currentColor" strokeWidth="1"/>
      <line x1="2" y1="1" x2="2" y2="9" stroke="currentColor" strokeWidth="1"/>
      <line x1={w + 12} y1="1" x2={w + 12} y2="9" stroke="currentColor" strokeWidth="1"/>
    </svg>
  );
}

// ─── The annotated row ────────────────────────────────────────
function SuggestionRowSpec() {
  return (
    <div style={{
      width: 720, height: 520, background: SPEC.paper,
      fontFamily: SPEC.sans, color: SPEC.ink, position: 'relative',
      padding: '28px 32px',
    }}>
      <div style={{ fontFamily: SPEC.serif, fontSize: 22, fontWeight: 400, letterSpacing: -0.3, lineHeight: 1.15 }}>
        Suggestion row
      </div>
      <div style={{ fontSize: 12, color: SPEC.ink3, marginTop: 4, lineHeight: 1.5, maxWidth: 480 }}>
        One row per proposed memory in the review sheet. Three parts: selection ring, body, confidence band.
      </div>

      {/* The row itself, at native scale */}
      <div style={{
        marginTop: 26, position: 'relative',
        background: SPEC.card, border: '1px solid ' + SPEC.hairline, borderRadius: 14,
        padding: '14px 16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
          {/* Ring */}
          <span style={{
            width: 22, height: 22, borderRadius: 11, flexShrink: 0, marginTop: 1,
            border: '1.5px solid ' + SPEC.ai, background: SPEC.ai,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke={SPEC.accentInk} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 8.5l3.2 3.2L13 5"/>
            </svg>
          </span>

          {/* Body */}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14.5, fontWeight: 600, color: SPEC.ink, letterSpacing: -0.1 }}>
              Notes on Studio as creator workspace
            </div>
            <div style={{ fontSize: 11, color: SPEC.ink3, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>
              May 12 · 10:14 AM
            </div>
            <div style={{ fontSize: 12.5, color: SPEC.ink2, lineHeight: 1.45, fontStyle: 'italic', fontFamily: SPEC.serif, marginTop: 8 }}>
              Mentions Studio and project synthesis — the same thread you're pulling on here.
            </div>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 10, fontSize: 11, color: SPEC.ink3, fontWeight: 700, letterSpacing: 1.4 }}>
              <span style={{ width: 6, height: 6, borderRadius: 3, background: SPEC.confirmed }} />
              LIKELY MATCH
            </div>
          </div>
        </div>

        {/* Callouts */}
        <Note style={{ position: 'absolute', right: -250, top: 6, width: 240 }}>
          <strong>Ring · selection</strong><br/>
          22×22, border 1.5px<br/>
          unselected: stroke ink4<br/>
          selected: fill AI #1E5C8E + check #fff<br/>
          <em>Crucible: selection = ring, completion = check inside ring</em>
        </Note>
        <Note style={{ position: 'absolute', right: -250, top: 122, width: 240 }}>
          <strong>Title</strong><br/>
          SF Pro 14.5/1.2 · weight 600 · tracking -0.1<br/>
          <br/>
          <strong>Date</strong><br/>
          SF Pro 11 · ink3 · tabular nums
        </Note>
        <Note style={{ position: 'absolute', right: -250, top: 210, width: 240 }}>
          <strong>Why-it-may-belong</strong><br/>
          Source Serif 4 12.5/1.45 · italic<br/>
          ink2 · one sentence · no period after\u2026<br/>
          AI returns at most this long.
        </Note>
        <Note style={{ position: 'absolute', right: -250, top: 286, width: 240 }}>
          <strong>Confidence band</strong><br/>
          6×6 dot + 11px uppercase, tracking 1.4<br/>
          <span style={{ color: SPEC.confirmed }}>● LIKELY</span> = confirmed green #3FA877<br/>
          <span style={{ color: SPEC.warn }}>● MAYBE</span> = warn amber #B87322<br/>
          Two bands only. No "Strong" / "Weak."
        </Note>
      </div>

      <div style={{ position: 'absolute', left: 32, bottom: 22, right: 32, fontSize: 11, color: SPEC.ink3, lineHeight: 1.5 }}>
        Row sits in a sheet with 20px side padding. Rows stack with a 1px ink-divider between them (not a card per row).
        Selecting a row tints nothing in the row itself — the only feedback is the ring filling.
      </div>
    </div>
  );
}

// ─── The four states stacked ──────────────────────────────────
function SuggestionRowStates() {
  const Row = ({ selected, confidence, title, date, why, dim }) => {
    const tones = {
      likely: { dot: SPEC.confirmed, label: 'LIKELY MATCH' },
      maybe:  { dot: SPEC.warn,      label: 'MAYBE'        },
    };
    const t = tones[confidence];
    return (
      <div style={{
        display: 'flex', alignItems: 'flex-start', gap: 12,
        padding: '14px 0', borderBottom: '1px solid ' + SPEC.hairline,
        opacity: dim ? 0.55 : 1,
      }}>
        <span style={{
          width: 22, height: 22, borderRadius: 11, flexShrink: 0, marginTop: 1,
          border: '1.5px solid ' + (selected ? SPEC.ai : SPEC.ink4),
          background: selected ? SPEC.ai : 'transparent',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        }}>
          {selected && (
            <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke={SPEC.accentInk} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 8.5l3.2 3.2L13 5"/>
            </svg>
          )}
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14.5, fontWeight: 600, color: SPEC.ink, letterSpacing: -0.1 }}>{title}</div>
          <div style={{ fontSize: 11, color: SPEC.ink3, marginTop: 3, fontVariantNumeric: 'tabular-nums' }}>{date}</div>
          <div style={{ fontSize: 12.5, color: SPEC.ink2, lineHeight: 1.45, fontStyle: 'italic', fontFamily: SPEC.serif, marginTop: 7 }}>
            {why}
          </div>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 9, fontSize: 11, color: SPEC.ink3, fontWeight: 700, letterSpacing: 1.4 }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: t.dot }} />
            {t.label}
          </div>
        </div>
      </div>
    );
  };

  return (
    <div style={{ width: 720, height: 520, background: SPEC.paper, fontFamily: SPEC.sans, padding: '28px 32px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ fontFamily: SPEC.serif, fontSize: 22, fontWeight: 400, letterSpacing: -0.3 }}>Row states</div>
      <div style={{ fontSize: 12, color: SPEC.ink3, marginTop: 4, lineHeight: 1.5 }}>
        Selection toggles per row. Confidence is server-side; not user-editable. Dim state is for skipped suggestions
        coming back in a later run (they shouldn't, but if they do we soften them).
      </div>

      <div style={{ marginTop: 22, flex: 1, display: 'flex', flexDirection: 'column' }}>
        <Caption style={{ marginBottom: 4 }}>Selected · Likely</Caption>
        <Row
          selected confidence="likely"
          title="Watch capture session feedback"
          date="May 8 · 4:48 PM"
          why="Tagged Technology; mentions watch recording, the central capture surface for this project."
        />

        <Caption style={{ marginTop: 14, marginBottom: 4 }}>Unselected · Maybe</Caption>
        <Row
          confidence="maybe"
          title="AI displacement, historical job patterns"
          date="Apr 22 · 8:31 AM"
          why="Overlaps with broader future-of-work topics, but not directly with the product thread."
        />

        <Caption style={{ marginTop: 14, marginBottom: 4 }}>Selected · Maybe</Caption>
        <Row
          selected confidence="maybe"
          title="Studio in three sketches"
          date="May 4 · 9:11 PM"
          why="Three Studio doodles; same product but unclear which thread."
        />
      </div>
    </div>
  );
}

Object.assign(window, { SuggestionRowSpec, SuggestionRowStates });

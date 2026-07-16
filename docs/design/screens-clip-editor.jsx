// ═══════════════════════════════════════════════════════════════
// screens-clip-editor.jsx — the UNIFIED CLIP EDITOR MODAL
//
// One editor, invoked when a clip is tapped from ANY surface (Clips bench,
// session, memory detail, search, cluster editor). Structure:
//   1 · THE CLIP (the atom) — media + timing + transcript/description.
//       Edited ONCE; the change is true in every memory that references it.
//       This is the layer that must never wipe.
//   2 · MEMORY SECTIONS (one per edge) — the clip is evidence in N memories;
//       each section is ONE edge, carrying that memory's own annotation
//       ("why this matters here") + "Remove from this memory" (de-associate).
//       Duplicated per memory. A loose clip (0 edges) shows none.
//   3 · DELETE THIS CLIP — destroys the atom, removes it from ALL memories,
//       with a live-count warning (July 13 Trash-by-object lock).
// ═══════════════════════════════════════════════════════════════
const P = window.PX;

// ── shared bits ───────────────────────────────────────────────
const _CHEV = <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={P.ai} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>;
const _EJECT = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M10 4H6a2 2 0 00-2 2v12a2 2 0 002 2h4"/><path d="M16 16l4-4-4-4"/><path d="M20 12H10"/></svg>;
const _TRASH = <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>;
// AI sparkle — trailing marker on blue AI buttons only (never on ochre user buttons)
const _SPARK = <svg width="13" height="13" viewBox="0 0 16 16" fill={P.ai}><path d="M8 0l1.4 5.2L14.6 6 9.4 7.4 8 12.6 6.6 7.4 1.4 6l5.2-1.4z"/></svg>;
const _PLUS = <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke={P.accent} strokeWidth="2.2" strokeLinecap="round"><path d="M8 2v12M2 8h12"/></svg>;

function EditorTopBar({ onDone }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 16px', height: 52, borderBottom: '1px solid ' + P.divider, flexShrink: 0 }}>
      <span style={{ fontSize: 15.5, color: P.ink2, letterSpacing: -0.1 }}>Cancel</span>
      <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: P.ink3 }}>Clip</span>
      <span style={{ fontSize: 15.5, fontWeight: 600, color: P.accent, letterSpacing: -0.1 }}>Done</span>
    </div>
  );
}

// grabber + sheet chrome around any editor content
function ModalSheet({ children, h }) {
  return (
    <div style={{ width: 360, minHeight: h, background: P.paper, borderTopLeftRadius: 20, borderTopRightRadius: 20, overflow: 'hidden', display: 'flex', flexDirection: 'column', boxShadow: P.shadowModal, position: 'relative' }}>
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8, flexShrink: 0 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: P.wash2 }} />
      </div>
      {children}
    </div>
  );
}

// ── Zone 1 · THE CLIP (atom) ──────────────────────────────────
function ClipHero({ media, hue = 35, duration = '0:42', timing, editing }) {
  if (media === 'photo' || media === 'video') {
    return (
      <div style={{ display: 'flex', gap: 13, alignItems: 'center' }}>
        <div style={{ width: 68, height: 68, borderRadius: 13, background: `linear-gradient(135deg, hsl(${hue} 45% 62%), hsl(${hue + 18} 50% 48%))`, flexShrink: 0 }} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12, color: P.ink3, letterSpacing: -0.05, marginBottom: 4 }}>{timing}</div>
          <div style={{ fontSize: 13, color: P.ai, fontWeight: 600 }}>Tap to view full size</div>
        </div>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
      <span style={{ width: 44, height: 44, borderRadius: 22, background: P.accentTint, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <svg width="15" height="15" viewBox="0 0 12 12" fill={P.accent}><path d="M2 1.5l8 4.5-8 4.5z"/></svg>
      </span>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 12, color: P.ink3, letterSpacing: -0.05, marginBottom: 3 }}>{timing}</div>
        <div style={{ fontSize: 13, color: P.ink2 }}>Original recording · {duration}</div>
      </div>
    </div>
  );
}

// blue AI action — re-run transcription on the atom. Bordered pill (tertiary),
// verb-that-names-the-AI + trailing sparkle. Never ghosted; stays legible blue.
function RetranscribeAction() {
  return (
    <div style={{ marginTop: 12 }}>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 38, padding: '0 15px', borderRadius: 11, border: '1px solid ' + P.ai, color: P.ai, fontSize: 14, fontWeight: 600, letterSpacing: -0.05 }}>
        Transcribe again with AI {_SPARK}
      </span>
    </div>
  );
}

function TextBlock({ label, text, editing, note, canRetranscribe }) {
  return (
    <div style={{ marginTop: 16 }}>
      <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: P.ink3, marginBottom: 8 }}>{label}</div>
      {editing ? (
        <div>
          <div style={{ border: '1px solid ' + P.accent, background: P.paper, borderRadius: 12, padding: '11px 13px', boxShadow: '0 0 0 3px ' + P.accentTint, fontSize: 15, lineHeight: 1.55, color: P.ink, letterSpacing: -0.1 }}>
            {text}<span style={{ display: 'inline-block', width: 2, height: 18, background: P.accent, verticalAlign: 'text-bottom', marginLeft: 1 }} />
          </div>
          {note && <div style={{ fontSize: 12, color: P.ai, marginTop: 8, display: 'flex', gap: 6, alignItems: 'flex-start', lineHeight: 1.45 }}><span style={{ marginTop: 1 }}>✦</span><span>{note}</span></div>}
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 14, marginTop: 12 }}>
            <span style={{ fontSize: 14.5, fontWeight: 600, color: P.ink2 }}>Cancel</span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 38, padding: '0 15px', borderRadius: 11, background: P.accent, color: P.accentInk, fontSize: 14.5, fontWeight: 600 }}>
              <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke={P.accentInk} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M3 8.5l3.5 3.5L13 4"/></svg> Done
            </span>
          </div>
        </div>
      ) : (
        <div>
          <div style={{ fontSize: 15, lineHeight: 1.55, color: P.ink, letterSpacing: -0.1 }}>{text}</div>
          {canRetranscribe && <RetranscribeAction />}
        </div>
      )}
    </div>
  );
}

// user action — associate this clip with another memory. Dashed = add/provisional;
// ochre = the user acts. Shown even at 0 edges (a loose clip can be added).
function AddToMemory() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, minHeight: 46, borderRadius: 13, border: '1px dashed ' + P.accent, color: P.accent, fontSize: 14.5, fontWeight: 600, letterSpacing: -0.05, marginTop: 2 }}>
      {_PLUS} Add to a memory
    </div>
  );
}

// ── Zone 2 · a MEMORY edge-row (collapsible; single-open accordion) ──
// Collapsed: title + date + one-line annotation preview. Expanded: full
// annotation (editable) + Remove-from-this-memory. Clip stays the hero above;
// edges collapse so a clip in many memories never buries Delete. Same accordion
// model as Memory Detail (openCompactRowId) — one open at a time.
function MemoryEdge({ title, date, annotation, annotationEmpty, open }) {
  return (
    <div style={{ background: P.card, border: '1px solid ' + (open ? P.hairline2 || P.hairline : P.hairline), borderRadius: 14, padding: '11px 14px', marginBottom: 10 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, minHeight: 44 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: P.serif, fontSize: 16, fontWeight: 500, color: P.ink, letterSpacing: -0.2, lineHeight: 1.2 }}>{title}</div>
          <div style={{ fontSize: 12, color: P.ink3, marginTop: 2 }}>{date}</div>
          {!open && !annotationEmpty && (
            <div style={{ fontSize: 13, lineHeight: 1.4, color: P.ink3, letterSpacing: -0.05, fontStyle: 'italic', fontFamily: P.serif, marginTop: 5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{annotation}</div>
          )}
          {!open && annotationEmpty && (
            <div style={{ fontSize: 13, color: P.ai, fontWeight: 600, marginTop: 5 }}>Add a note</div>
          )}
        </div>
        <span style={{ flexShrink: 0, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>{_CHEV}</span>
      </div>
      {open && (
        <>
          <div style={{ marginTop: 11, paddingTop: 11, borderTop: '1px solid ' + P.divider }}>
            <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.1, textTransform: 'uppercase', color: P.ink4, marginBottom: 6 }}>Why this matters here</div>
            {annotationEmpty
              ? <div style={{ fontSize: 14, color: P.ai, fontWeight: 600 }}>Add a note</div>
              : <div style={{ fontSize: 14, lineHeight: 1.5, color: P.ink2, letterSpacing: -0.05, fontStyle: 'italic', fontFamily: P.serif }}>{annotation}</div>}
          </div>
          <div style={{ marginTop: 11, paddingTop: 10, borderTop: '1px solid ' + P.divider, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 34, fontSize: 13.5, fontWeight: 600, color: P.ink2, letterSpacing: -0.05 }}>{_EJECT} Remove from this memory</span>
            <span style={{ fontSize: 13, fontWeight: 600, color: P.ai }}>Open ›</span>
          </div>
        </>
      )}
    </div>
  );
}

// ── Zone 3 · DELETE THIS CLIP (atom-level destruction) ────────
function DeleteFooter({ count }) {
  const warn = count === 0
    ? "This clip isn't in any memory yet."
    : `This clip is evidence in ${count} ${count === 1 ? 'memory' : 'memories'}. Deleting it removes it from ${count === 1 ? 'that memory' : 'all of them'}.`;
  return (
    <div style={{ padding: '14px 16px 18px', borderTop: '1px solid ' + P.divider, flexShrink: 0, background: P.paper }}>
      <div style={{ fontSize: 12, color: P.ink3, lineHeight: 1.45, marginBottom: 10, textAlign: 'center' }}>{warn}</div>
      <div style={{ minHeight: 50, borderRadius: 13, border: '1px solid ' + P.danger, color: P.danger, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1 }}>
        {_TRASH} Delete this Clip
      </div>
    </div>
  );
}

// ── full editor body (scrolling middle) ───────────────────────
function EditorBody({ media, hue, duration, timing, transcript, editing, edges }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '16px 16px 8px' }}>
        <ClipHero media={media} hue={hue} duration={duration} timing={timing} />
        <TextBlock
          label={media === 'photo' || media === 'video' ? 'Description' : 'Transcript'}
          text={transcript}
          editing={editing}
          canRetranscribe={!editing && media !== 'photo'}
          note={editing ? 'This is the clip itself — your edit shows in every memory that uses it.' : null}
        />
        {edges && edges.length > 0 && (
          <div style={{ marginTop: 20, paddingTop: 4 }}>
            <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: P.ink3, marginBottom: 10 }}>Evidence in {edges.length} {edges.length === 1 ? 'memory' : 'memories'}</div>
            {edges.map((e, i) => <MemoryEdge key={i} {...e} />)}
            <AddToMemory />
          </div>
        )}
        {(!edges || edges.length === 0) && (
          <div style={{ marginTop: 20, paddingTop: 4 }}>
            <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: P.ink3, marginBottom: 10 }}>Not in any memory yet</div>
            <AddToMemory />
          </div>
        )}
      </div>
    </div>
  );
}

// scrim wrapper so it reads as a modal over content
function ModalStage({ children, w = 420, h = 820 }) {
  return (
    <div style={{ width: w, minHeight: h, background: P.paper, position: 'relative', overflow: 'hidden', display: 'flex', alignItems: 'flex-end', justifyContent: 'center', paddingTop: 28, boxSizing: 'border-box' }}>
      {/* dimmed underlying surface */}
      <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(180deg, ${P.wash1}, ${P.paper})` }} />
      <div style={{ position: 'absolute', inset: 0, background: P.scrim }} />
      <div style={{ position: 'relative' }}>{children}</div>
    </div>
  );
}

Object.assign(window, { EditorTopBar, ModalSheet, ClipHero, TextBlock, RetranscribeAction, AddToMemory, MemoryEdge, DeleteFooter, EditorBody, ModalStage });

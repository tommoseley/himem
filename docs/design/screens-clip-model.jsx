// screens-clip-model.jsx
// ─────────────────────────────────────────────────────────────
// The unified Clip → Collection → Memory model  (Plan B · July 11 2026)
//
// The ontology, made load-bearing in code:
//   • A CLIP is the atom. It has ONE structure everywhere:
//         timing header → content → evidence control.
//     Only its *register* (skin) changes — operational (Clips / session:
//     SF Pro, dense, inclusion ring) vs reflective (Memory: roomier, no ring).
//     The same clip is recognisably the same object on both surfaces.
//   • A CLIP COLLECTION is a composition header (timespan + media counts)
//     plus a body of clip atoms.
//   • A SESSION is a collection with NO derived layer — a proto-memory.
//   • A MEMORY is a collection WITH a derived layer (AI title, summary,
//     topics, mentions). The memory CARD is the collapsed form (derived
//     layer + composition, body hidden); the memory DETAIL is the expanded
//     form (derived layer + composition + the clip-atom body).
//
// So: Memory = ClipCollection + derived data.  Session = ClipCollection.
// That is the whole model. See "Clip model · spec.md".
//
// Loads after crucible-primitives.jsx, screens-projects.jsx,
// screens-memories.jsx (for MediaRow / topic helpers), screens-clips-page.jsx
// (for Thumb).
// ─────────────────────────────────────────────────────────────

// The media-type glyph that LEADS every clip's timing header, in EVERY
// register — so a voice clip, note, photo, and video are instantly
// distinguishable before you read a word (fixes: a note and a voice clip
// were near-identical; only the thumbnail flagged a photo). Same glyph
// vocabulary + coloring as the composition line's MediaRow: audio is ochre
// (brand/audio), the rest quiet ink3. Informational — never interactive.
function ClipTypeGlyph({ media = 'audio', size = 14 }) {
  const c = media === 'audio' ? PX.accent : PX.ink3;
  const p = { width: size, height: size, viewBox: '0 0 16 16', fill: 'none', stroke: c, strokeWidth: 1.5, strokeLinecap: 'round', strokeLinejoin: 'round', style: { flexShrink: 0 } };
  if (media === 'photo') return <svg {...p}><rect x="1.5" y="3.5" width="13" height="10" rx="2" /><circle cx="8" cy="8.5" r="2.4" /><path d="M5 3.5l1-1.5h4l1 1.5" /></svg>;
  if (media === 'video') return <svg {...p}><rect x="1.5" y="4" width="9" height="8" rx="1.6" /><path d="M10.5 7l4-2.2v6.4L10.5 9" /></svg>;
  if (media === 'note') return <svg {...p}><path d="M3 3.5h10M3 6.5h10M3 9.5h7" /></svg>;
  return <svg {...p}><rect x="6" y="1.5" width="4" height="7.5" rx="2" /><path d="M3.5 7a4.5 4.5 0 009 0M8 11.5v3" /></svg>;
}

// The ONE inclusion ring (operational triage only). Two states, both a CHOICE:
//   on  → filled ochre = "this clip joins the memory when you Start a Memory"
//   off → hollow ink hairline = excluded from the bundle (NOT a failure). Kept
//         visually distinct from the failed-clip style (which dims the text AND
//         pairs a Retry link); an excluded clip's text stays legible, no Retry.
function ClipRing({ on = true }) {
  return <span style={{
    width: 22, height: 22, borderRadius: 11,
    border: on ? '6px solid ' + PX.accent : '2px solid ' + PX.ink4,
    background: PX.card, boxSizing: 'border-box', flexShrink: 0, marginTop: 2,
  }} />;
}

// ── The evidence control — media presence, media-aware, one control. ──
// audio / video → a Play affordance ("Original recording"); the register only
// sets how much it says. photo → the thumbnail IS the evidence (handled in the
// atom's content slot), so nothing here. note → nothing (the text is the clip).
function ClipEvidence({ media = 'audio', duration, register = 'reflective' }) {
  if (media === 'note' || media === 'photo') return null;
  const op = register === 'operational';
  const label = media === 'video' ? 'Video' : 'Original recording';
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, color: PX.ink3 }}>
      <span style={{
        width: op ? 22 : 24, height: op ? 22 : 24, borderRadius: 12,
        border: '1px solid ' + PX.hairline, flexShrink: 0,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="9" height="9" viewBox="0 0 12 12" fill={PX.ink3}><path d="M2 1.5l8 4.5-8 4.5z" /></svg>
      </span>
      <span style={{ fontSize: 12, letterSpacing: -0.05 }}>
        {op ? (duration || '0:00') : label + (duration ? ' · ' + duration : '')}
      </span>
    </div>
  );
}

// Retry-transcription link — operational only (a failed voice transcript is an
// exception you handle on the workbench, never on the reflective surface).
function ClipRetry() {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 13, fontWeight: 600, color: PX.ai }}>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={PX.ai} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 9a7 7 0 0111-5l3 2M21 15a7 7 0 01-11 5l-3-2" /><path d="M17 3v3h-3M7 21v-3h3" /></svg>
      Retry transcription
    </span>
  );
}

// ═════════════════════════════════════════════════════════════
// THE CLIP ATOM. One structure, two registers.
//   timing header  →  content (transcript OR thumbnail)  →  evidence
//   • register: 'operational' (Clips / session) | 'reflective' (Memory)
//   • ring:    inclusion ring, operational triage only
//   • failed:  show Retry (operational voice only)
// ═════════════════════════════════════════════════════════════
function ClipAtom({
  media = 'audio', meta, transcript, description,
  duration, hue = 40, register = 'reflective',
  ring = false, included = true, failed = false,
}) {
  const op = register === 'operational';
  const isMedia = media === 'photo' || media === 'video';
  // Excluded = ring present but off. A choice: de-emphasise the words a step
  // (ink2, still fully legible) — never to the dimmed/failed level.
  const excluded = ring && !included;
  const bodyInk = excluded ? PX.ink2 : PX.ink;

  const metaEl = (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 7,
      fontSize: op ? 12.5 : 12, color: PX.ink3, fontVariantNumeric: 'tabular-nums',
      letterSpacing: -0.05, fontWeight: 500,
    }}>
      <ClipTypeGlyph media={media} size={op ? 13 : 14} />
      <span>{meta}</span>
    </div>
  );

  const contentEl = isMedia ? (
    <div style={{ display: 'flex', gap: 12, alignItems: description ? 'flex-start' : 'center' }}>
      <ClipThumb size={op ? 50 : 60} hue={hue} video={media === 'video'} radius={11} />
      {description
        ? <div style={{ flex: 1, fontSize: op ? 14 : 15, lineHeight: 1.45, color: bodyInk, letterSpacing: -0.1 }}>{description}</div>
        : <div style={{ flex: 1 }}>
            <div style={{ fontSize: op ? 14.5 : 15.5, fontWeight: 600, color: bodyInk, letterSpacing: -0.1 }}>{media === 'video' ? 'Video' : 'Photo'}</div>
            {op && typeof window !== 'undefined' && window.AddDescHint ? <window.AddDescHint /> : null}
          </div>}
    </div>
  ) : (
    <div style={{ fontSize: op ? 15 : 15, lineHeight: 1.5, color: bodyInk, letterSpacing: -0.1 }}>
      {op ? '\u201C' + transcript + '\u201D' : transcript}
    </div>
  );

  const evidenceRow = (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, minHeight: 22 }}>
      <ClipEvidence media={media} duration={duration} register={register} />
      {failed && op && media !== 'photo' && <ClipRetry />}
    </div>
  );
  const showEvidence = media === 'audio' || media === 'video';

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
      {ring && <ClipRing on={included} />}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 9 }}>
        {metaEl}
        {contentEl}
        {showEvidence && evidenceRow}
      </div>
    </div>
  );
}

// ── The composition line — timespan + media counts. The SAME primitive that
// heads a session card, sits on a memory card, and heads a memory's transcript.
// (MediaRow is the media-count component shared with the memory card.) ──
function ClipComposition({ timespan, media, words, register = 'reflective' }) {
  const op = register === 'operational';
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
      {timespan && (
        <span style={{ fontSize: op ? 13.5 : 12.5, fontWeight: 600, color: PX.ink2, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.1 }}>
          {timespan}
        </span>
      )}
      <MediaRow media={media} />
      {words != null && (
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink4 }}>
          {words} words
        </span>
      )}
    </div>
  );
}

// ── The collection skeleton. Optional `derived` node (title/summary/topics)
// rendered ABOVE the composition turns a bare session into a memory. `body`
// is the clip-atom list; omit it for the collapsed (card) form. ──
function ClipCollection({ derived, timespan, media, words, register = 'reflective', body, actions }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      {derived}
      <ClipComposition timespan={timespan} media={media} words={words} register={register} />
      {body && (
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {body}
        </div>
      )}
      {actions}
    </div>
  );
}

// Divider used between stacked atoms in a collection body.
function ClipDivider() {
  return <div style={{ height: 1, background: PX.hairline, margin: '14px 0' }} />;
}

// Internal thumbnail fallback — keeps this file self-contained so it can load
// on pages that don't load screens-clips-page.jsx. Uses the richer window.Thumb
// when present (Clips page), else this minimal gradient tile.
function ClipThumb({ size = 50, hue = 40, video = false, radius = 11 }) {
  if (typeof window !== 'undefined' && window.Thumb) {
    return <window.Thumb size={size} hue={hue} video={video} radius={radius} />;
  }
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

// ═════════════════════════════════════════════════════════════
// THE CLIP EDITOR. One editor, two fields (locked July 11 2026).
//   field='transcript' → edits a voice/note clip's words.
//   field='description' → edits a photo/video clip's words.
// Both are the clip's WORDS — the same act on the same slot — so they are the
// same component. It owns: the edit field (mirrors the read view, auto-grows),
// the quiet Play/evidence control kept visible while editing (audio/video),
// the fate-action row (Delete clip · optional Move to…), and the Cancel/Done
// commit row. Replaces MDClipV2's editing branch, MDClipCompactRow's editing
// branch, and the standalone description edit path.
//   · showMove — include "Move to memory…" (full memory card yes; compact row no).
//   · scope   — 'session' | 'memory' shows the neutral Remove fate action
//               ("Remove from session" ejects to the loose bench; "Remove from
//               memory" cuts membership, the clip survives). Omit on the global
//               clip detail / a loose bench clip — nothing to remove it FROM.
//   · onCancel / onDone — commit handlers (mock: no-ops).
// ═════════════════════════════════════════════════════════════
const _TRASH = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>;
const _MOVE = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 17v-3a4 4 0 014-4h11"/><path d="M16 5l5 5-5 5"/></svg>;
// Eject-to-bench glyph for Remove — an arrow leaving a container. Reads as
// "take this out of the grouping," NOT destruction (that's _TRASH).
const _EJECT = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M10 4H6a2 2 0 00-2 2v12a2 2 0 002 2h4"/><path d="M16 16l4-4-4-4"/><path d="M20 12H10"/></svg>;
const _CHECK = <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M3 8.5l3.5 3.5L13 4"/></svg>;

function ClipEditor({ field = 'transcript', value = '', media = 'audio', duration = '0:42', showMove = false, scope, showFates = true, showLabel = true, onCancel, onDone }) {
  const isDesc = field === 'description';
  const label = isDesc ? 'Description' : 'Transcript';
  const showPlay = media === 'audio' || media === 'video';
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {showLabel && <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3 }}>{label}</div>}
      {/* the edit field — mirrors the read view, auto-grows, inline caret */}
      <div style={{
        border: '1px solid ' + PX.accent, background: PX.paper, borderRadius: 12,
        padding: '10px 12px', boxShadow: '0 0 0 3px ' + PX.accentTint,
        fontSize: 14.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1,
      }}>
        {value}
        <span style={{ display: 'inline-block', width: 2, height: 17, background: PX.accent, verticalAlign: 'text-bottom', marginLeft: 1 }} />
      </div>
      {/* play control stays visible while editing an audio/video clip */}
      {showPlay && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: PX.ink3 }}>
          <span style={{ width: 24, height: 24, borderRadius: 12, border: '1px solid ' + PX.hairline, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <svg width="9" height="9" viewBox="0 0 12 12" fill={PX.ink3}><path d="M2 1.5l8 4.5-8 4.5z"/></svg>
          </span>
          <span style={{ fontSize: 12, letterSpacing: -0.05 }}>{media === 'video' ? 'Video' : 'Original recording'} · {duration}</span>
        </div>
      )}
      {/* fate-action row — stacked, escalating consequence top→bottom:
          Remove (neutral) → optional Move → Delete (red). Suppressed with
          showFates={false} on any surface that already owns the fate actions in
          VIEW mode (e.g. the Clips clip detail, whose opened-item bottom stack
          carries Remove/Delete) — so editing words never duplicates them. */}
      {showFates && (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, paddingTop: 2 }}>
        {scope && (
          <span style={{ minHeight: 40, display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: 14.5, fontWeight: 600, color: PX.ink2, letterSpacing: -0.1 }}>
            {_EJECT} {scope === 'memory' ? 'Remove from memory' : 'Remove from session'}
          </span>
        )}
        {showMove && (
          <span style={{ minHeight: 40, display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: 14.5, fontWeight: 600, color: PX.ink2, letterSpacing: -0.1 }}>
            {_MOVE} Move to memory…
          </span>
        )}
        <span style={{ minHeight: 40, display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: 14.5, fontWeight: 600, color: PX.danger, letterSpacing: -0.1 }}>
          {_TRASH} Delete clip
        </span>
      </div>
      )}
      {/* commit row — Cancel / Done */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'center', gap: 14 }}>
        <span onClick={onCancel} style={{ minHeight: 40, display: 'inline-flex', alignItems: 'center', fontSize: 14.5, fontWeight: 600, color: PX.ink2, letterSpacing: -0.1, cursor: 'pointer' }}>Cancel</span>
        <span onClick={onDone} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 40, padding: '0 16px', borderRadius: 11, background: PX.accent, color: PX.accentInk, fontSize: 14.5, fontWeight: 600, cursor: 'pointer' }}>
          {_CHECK} Done
        </span>
      </div>
    </div>
  );
}

Object.assign(window, {
  ClipRing, ClipTypeGlyph, ClipEvidence, ClipRetry, ClipAtom, ClipComposition, ClipCollection, ClipDivider, ClipEditor,
});

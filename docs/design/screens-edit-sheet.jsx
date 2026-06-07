// screens-edit-sheet.jsx
// ONE canonical "edit the derived text on a media item" sheet, applied to both
// the photo/video DESCRIPTION and the voice/video TRANSCRIPT. Before this, the
// two editors were drawn as unrelated screens (full-screen vs sheet, plain vs
// pill nav, ringed field vs bare text). They do the same job and must read as
// siblings.
//
// Shared chrome (identical in both):
//   · Sheet presentation — cream, rounded top, dimmed memory behind
//   · Top bar — Cancel (plain, left) · type title (center) · Done (ochre, right)
//   · Metadata line — date · time · (duration/location)
//   · Field eyebrow + editable field with the SAME focus treatment (ochre ring)
//   · Footer slot — one line, same position/size (caption OR action)
//
// Legitimately media-specific (the only differences that remain):
//   · Hero block — photo thumbnail  vs  audio player (scrubber + play)
//   · Field label — DESCRIPTION / TRANSCRIPT
//   · Footer — "Part of this memory · searchable"  vs  "Retry transcription"

// ── the shared template ──────────────────────────────────────
function EditSheet({ title, hero, meta, fieldLabel, value, caret, footer }) {
  return (
    <div style={{ width: 340, height: 735, background: '#807A6E', position: 'relative', overflow: 'hidden', fontFamily: PX.sans }}>
      {/* dimmed memory peeking behind the sheet */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(26,22,18,0.34)' }} />

      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, top: 24,
        background: PX.paper, borderTopLeftRadius: 20, borderTopRightRadius: 20,
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        {/* grabber */}
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: PX.ink4, opacity: 0.5 }} />
        </div>

        {/* top bar — Cancel · title · Done */}
        <div style={{ display: 'flex', alignItems: 'center', padding: '10px 18px 12px', flexShrink: 0 }}>
          <span style={{ fontSize: 15, color: PX.ink2, minWidth: 56 }}>Cancel</span>
          <span style={{ flex: 1, textAlign: 'center', fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>{title}</span>
          <span style={{ fontSize: 15, fontWeight: 700, color: PX.accent, minWidth: 56, textAlign: 'right' }}>Done</span>
        </div>

        <div style={{ flex: 1, overflow: 'hidden', padding: '0 18px', display: 'flex', flexDirection: 'column' }}>
          {/* hero (media-specific) */}
          {hero}

          {/* metadata line */}
          <div style={{ fontSize: 12, color: PX.ink3, fontWeight: 500, margin: '14px 0 12px', fontVariantNumeric: 'tabular-nums' }}>{meta}</div>

          {/* field eyebrow */}
          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>{fieldLabel}</div>

          {/* editable field — identical focus treatment for both */}
          <div style={{
            flex: 1, minHeight: 0,
            border: '2px solid ' + PX.accent, borderRadius: 12, background: PX.card,
            padding: '12px 13px', fontSize: 15, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1,
          }}>
            {value}
            {caret && <span style={{ display: 'inline-block', width: 2, height: 18, background: '#2A6FDB', marginLeft: 1, verticalAlign: 'text-bottom' }} />}
          </div>

          {/* footer slot (media-specific, same position) */}
          <div style={{ padding: '12px 0 14px', flexShrink: 0 }}>{footer}</div>
        </div>

        {/* keyboard */}
        <MiniKeyboard />
      </div>
    </div>
  );
}

// ── photo / video description ────────────────────────────────
function ScrEditDescription() {
  return (
    <EditSheet
      title="Photo"
      meta="Jun 7, 2026 · 1:28 PM · West Garden"
      fieldLabel="Description"
      value={<>I’m giving myself a thumbs up. Good with staying in the south, not the north — but family wins.</>}
      caret
      hero={(
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 4 }}>
          <div style={{ width: 116, height: 150, borderRadius: 12, background: PX.sunk, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
            <PhotoGlyph size={30} color={PX.ink4} />
          </div>
        </div>
      )}
      footer={<span style={{ fontSize: 11.5, color: PX.ink3 }}>Part of this memory · searchable</span>}
    />
  );
}

// ── voice / video transcript ─────────────────────────────────
function ScrEditTranscript() {
  return (
    <EditSheet
      title="Voice clip"
      meta="Jun 7, 2026 · 1:25 PM · 0:06"
      fieldLabel="Transcript"
      value={<>So it looks like we’re flying up to Maine in two weeks to see my son.</>}
      caret
      hero={(
        <div style={{ paddingTop: 6 }}>
          {/* scrubber */}
          <div style={{ height: 3, borderRadius: 2, background: PX.hairline, marginBottom: 12 }}>
            <div style={{ width: '0%', height: '100%', background: PX.accent, borderRadius: 2 }} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <span style={{ fontSize: 12, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>0:00</span>
            <span style={{ width: 52, height: 52, borderRadius: 26, background: PX.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg width="17" height="19" viewBox="0 0 16 18" fill="#fff"><path d="M0 0l16 9L0 18z" /></svg>
            </span>
            <span style={{ fontSize: 12, color: PX.ink3, fontVariantNumeric: 'tabular-nums' }}>0:06</span>
          </div>
        </div>
      )}
      footer={(
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 12.5, fontWeight: 600, color: PX.accent }}>
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M13.5 8a5.5 5.5 0 11-1.6-3.9M13.5 2v3.2h-3.2" /></svg>
          Retry transcription
        </span>
      )}
    />
  );
}

// ── annotated note ───────────────────────────────────────────
function EditSheetSpecCard() {
  const row = { padding: '13px 18px', borderBottom: '1px solid ' + PX.hairline };
  const eyebrow = { fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.accent, marginBottom: 5 };
  const body = { fontSize: 13.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 };
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, overflow: 'hidden', fontFamily: PX.sans }}>
      <div style={{ padding: '16px 18px 12px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 21, color: PX.ink, letterSpacing: -0.3 }}>One edit sheet, two media</div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 3 }}>Description and transcript are the same job — edit the words on a media item.</div>
      </div>
      <div style={row}><div style={eyebrow}>Shared chrome</div><div style={body}>Sheet presentation, grabber, <strong>Cancel · title · Done</strong> bar, metadata line, ochre-ring field, and a one-line footer — identical in both.</div></div>
      <div style={row}><div style={eyebrow}>Same field, always</div><div style={body}>The transcript now sits in the same focused field the description uses. No more bare-text vs boxed-text split.</div></div>
      <div style={{ ...row, borderBottom: 'none' }}><div style={eyebrow}>Only the content differs</div><div style={body}>Hero is a photo thumb or an audio player; footer is a searchable caption or <em>Retry transcription</em>. Those are content, not chrome.</div></div>
    </div>
  );
}

Object.assign(window, {
  EditSheet, ScrEditDescription, ScrEditTranscript, EditSheetSpecCard,
});

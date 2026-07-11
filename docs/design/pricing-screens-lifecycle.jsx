// pricing-screens-lifecycle.jsx
// 2 · Memory-Detail · the organize lifecycle (Capture → Draft → Accept).
// Built on the shared Memory-Detail chrome so the states read as one screen
// changing, not four different screens.
//
//   Stage 1 · Unorganized   — Free: ochre "Organize" button (manual, on-device)
//                             Plus: auto-runs, so users rarely see this
//   Stage 2 · Draft (B2)     — quiet AI-blue dashed chip + "Tap to review & keep"
//   Stage 2s · Review sheet  — carries B1's copy: "A draft from your device —
//                             make sure it sounds like you"
//   Stage 3 · Organized      — plain solid chip, no nag
//   Stage 3st · Stale        — amber "new clips · Refresh" (unchanged prior spec)
//
// The chip tracks REVIEW STATE, not tier — an unreviewed Plus auto-organize
// also shows "Draft organized".

// Shared Memory-Detail chrome ------------------------------------------------
function MemHeader() {
  return (
    <div style={{ flexShrink: 0, padding: '4px 14px 8px' }}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7" /></svg>
          Today
        </span>
        <span style={{ flex: 1 }} />
        <span style={{ display: 'inline-flex', gap: 14, color: PX.ink3 }}>
          <svg width="17" height="17" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 4h11M6 4V2.7a1 1 0 011-1h2a1 1 0 011 1V4M4 4l.5 9a1 1 0 001 1h5a1 1 0 001-1L12 4" /></svg>
          <svg width="17" height="17" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M8 11V2M5 5l3-3 3 3M3 11v2.5a1 1 0 001 1h8a1 1 0 001-1V11" /></svg>
          <span style={{ fontSize: 17, fontWeight: 700, letterSpacing: 1 }}>⚙</span>
        </span>
      </div>
      <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginTop: 8 }}>
        Wed May 27 · 1:56 PM · Bluffton
      </div>
    </div>
  );
}

function ClipRow() {
  return (
    <div style={{
      margin: '0 14px', background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 13, padding: '11px 13px', display: 'flex', gap: 10, alignItems: 'flex-start',
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 4, background: PX.accent, marginTop: 5, flexShrink: 0 }} />
      <div style={{ fontFamily: PX.serif, fontSize: 13.5, lineHeight: 1.4, color: PX.ink }}>
        I am not bound to win, but I am bound to be true. I must stand by anybody that stands right — Abraham Lincoln.
      </div>
    </div>
  );
}

// Organized title + summary block (shared by draft & done states) -----------
function OrganizedBody({ draft }) {
  return (
    <div style={{ margin: '0 14px' }}>
      <SerifH size={21} style={{ marginBottom: 6 }}>On integrity and moral courage</SerifH>
      <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.5 }}>
        You return to a standard you hold yourself to — staying true to what is right over what merely succeeds, and standing with people only while they stand right.
      </div>
      <div style={{ display: 'flex', gap: 7, marginTop: 10, flexWrap: 'wrap' }}>
        {['How We Work', 'Integrity'].map(t => (
          <span key={t} style={{
            display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 38, boxSizing: 'border-box',
            fontSize: 13.5, color: PX.ink, background: PX.wash1,
            border: '1px solid transparent', borderRadius: 11, padding: '0 14px',
          }}>
            <span style={{ width: 7, height: 7, borderRadius: 4, background: PX.accent, flexShrink: 0 }} />{t}
          </span>
        ))}
      </div>
    </div>
  );
}

// Stage 1 · Unorganized (Free) ----------------------------------------------
function ScrLifeUnorganized() {
  return (
    <PhoneScreen>
      <MemHeader />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 14, paddingTop: 6 }}>
        <ClipRow />
        <div style={{ margin: '0 14px', padding: '14px 15px', background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, marginBottom: 3 }}>Organize this memory</div>
          <div style={{ fontSize: 12, color: PX.ink3, lineHeight: 1.45, marginBottom: 12 }}>
            Suggests a title, summary, and topics — drafted right on your device.
          </div>
          <Btn kind="accent" size="md" leading={<Spark size={15} />}>Organize</Btn>
          <div style={{ fontSize: 11, color: PX.ink3, textAlign: 'center', marginTop: 8 }}>
            On-device · private · free
          </div>
        </div>
        <div style={{ flex: 1 }} />
      </div>
    </PhoneScreen>
  );
}

// Stage 2 · Draft organized (B2) --------------------------------------------
// Affordance vocabulary (June 2026): status is NEVER a button. The
// "Draft organized · unreviewed" state is a quiet label (no pill, no dashed
// costume) — it informs. The review ACTION is one full-width AI-blue button,
// 48px+, impossible to miss or mis-tap. Three weak fragments → one clear pair.
function ScrLifeDraft() {
  return (
    <PhoneScreen>
      <MemHeader />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 13, paddingTop: 6 }}>
        {/* status — a quiet label, not a button */}
        <div style={{ margin: '0 14px', display: 'flex', alignItems: 'center', gap: 7 }}>
          <Spark size={14} color={PX.ai} />
          <span style={{ fontSize: 13, fontWeight: 600, color: PX.ai, letterSpacing: -0.05 }}>Draft organized</span>
          <span style={{ width: 3, height: 3, borderRadius: 2, background: PX.ink4, flexShrink: 0 }} />
          <span style={{ fontSize: 13, color: PX.ink3 }}>unreviewed</span>
        </div>
        <OrganizedBody draft />
        {/* review — one real button, the primary action */}
        <button style={{
          margin: '0 14px', height: 50, width: 'calc(100% - 28px)', boxSizing: 'border-box',
          background: PX.aiTint, border: '1.5px solid ' + PX.ai, borderRadius: 14, cursor: 'pointer',
          color: PX.ai, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          <Spark size={16} color={PX.ai} />
          Review this draft
          <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={PX.ai} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginLeft: 2 }}><path d="M1 1l6 6-6 6" /></svg>
        </button>
        <div style={{ borderTop: '1px solid ' + PX.divider, margin: '2px 14px 0', paddingTop: 13 }}>
          <ClipRow />
        </div>
        <div style={{ flex: 1 }} />
      </div>
    </PhoneScreen>
  );
}

// Stage 2s · Review sheet (B1 copy lives here) ------------------------------
function ScrLifeReviewSheet() {
  const behind = (
    <PhoneScreen>
      <MemHeader />
      <div style={{ paddingTop: 6, display: 'flex', flexDirection: 'column', gap: 13 }}>
        <div style={{ margin: '0 14px' }}><OrganizeChip variant="draft" /></div>
        <OrganizedBody draft />
      </div>
    </PhoneScreen>
  );
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="74%">
        <div style={{ padding: '14px 20px 20px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <OrganizeChip variant="draft" />
          </div>
          <SerifH size={22} style={{ marginTop: 12 }}>A draft from your device.</SerifH>
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginTop: 8 }}>
            Make sure it sounds like you. Keep it as is, or edit anything that’s a little off.
          </div>

          {/* the drafted fields, reviewable */}
          <div style={{ marginTop: 16, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden' }}>
            {[['Title', 'On integrity and moral courage'], ['Summary', 'You return to a standard you hold yourself to — staying true to what is right over what merely succeeds.']].map(([k, v], i) => (
              <div key={k} style={{ padding: '11px 14px', borderTop: i ? '1px solid ' + PX.divider : 'none' }}>
                <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ai, marginBottom: 4 }}>{k}</div>
                <div style={{ fontSize: 13.5, color: PX.ink, lineHeight: 1.4, fontFamily: i ? PX.sans : PX.serif }}>{v}</div>
              </div>
            ))}
          </div>

          <div style={{ flex: 1 }} />
          <Btn kind="accent">Looks good</Btn>
          <div style={{ height: 8 }} />
          <Btn kind="secondary" size="md">Edit</Btn>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// Stage 3 · Organized (reviewed) --------------------------------------------
function ScrLifeOrganized() {
  return (
    <PhoneScreen>
      <MemHeader />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 13, paddingTop: 6 }}>
        <div style={{ margin: '0 14px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <OrganizeChip variant="done" />
          <span style={{ flex: 1 }} />
          {/* reorganize entry — quiet, AI-blue, never metered */}
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12.5, color: PX.ai, fontWeight: 600 }}>
            <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v3H9M2 11V8h3" /><path d="M11.5 8a4.5 4.5 0 01-8 2.5M2.5 6a4.5 4.5 0 018-2.5" /></svg>
            Reorganize
          </span>
        </div>
        <OrganizedBody />
        <div style={{ borderTop: '1px solid ' + PX.divider, margin: '2px 14px 0', paddingTop: 13 }}>
          <ClipRow />
        </div>
        <div style={{ flex: 1 }} />
      </div>
    </PhoneScreen>
  );
}

// Stage 3r · Reorganize review sheet ----------------------------------------
// Reorganize re-enters the SAME draft→review→organized lifecycle. The new
// draft REPLACES the old one (never branches). Review is always shown.
//
// Scope (locked June 6): reorganize rethinks ONLY Title and Summary — never
// Topics or Mentions. Both new values require EXPLICIT approval, whether or
// not the user had edited them: nothing changes without consent. Each field
// defaults to the current value (ring + check); the new wording is the opt-in.
function ReorgField({ label, current, suggestion, serif, first }) {
  return (
    <div style={{ padding: '12px 14px', borderTop: first ? 'none' : '1px solid ' + PX.divider }}>
      <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink2, marginBottom: 8 }}>{label}</div>
      {/* Current — selected by default (ring + check) */}
      <div style={{ background: PX.card, border: '2px solid ' + PX.accent, borderRadius: 10, padding: '9px 11px', marginBottom: 7 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
          <Check size={11} color={PX.accent} />
          <span style={{ fontSize: 10.5, fontWeight: 700, color: PX.accent, letterSpacing: 0.2 }}>Current · kept</span>
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink, lineHeight: 1.4, fontFamily: serif ? PX.serif : PX.sans }}>{current}</div>
      </div>
      {/* New suggestion — opt-in, must be approved to apply */}
      <div style={{ background: PX.card, border: '1px solid ' + PX.aiEdge, borderRadius: 10, padding: '9px 11px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
          <span style={{ width: 11, height: 11, borderRadius: 6, border: '1.5px solid ' + PX.ai, flexShrink: 0 }} />
          <span style={{ fontSize: 10.5, fontWeight: 700, color: PX.ai, letterSpacing: 0.2 }}>New suggestion · tap to use</span>
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.4, fontFamily: serif ? PX.serif : PX.sans }}>{suggestion}</div>
      </div>
    </div>
  );
}

function ScrLifeReorganizeSheet() {
  const behind = (
    <PhoneScreen>
      <MemHeader />
      <div style={{ paddingTop: 6, display: 'flex', flexDirection: 'column', gap: 13 }}>
        <div style={{ margin: '0 14px' }}><OrganizeChip variant="draft" /></div>
        <OrganizedBody draft />
      </div>
    </PhoneScreen>
  );
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="80%">
        <div style={{ padding: '14px 20px 20px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <OrganizeChip variant="draft" />
          </div>
          <SerifH size={22} style={{ marginTop: 12 }}>A fresh take.</SerifH>
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginTop: 8 }}>
            Reorganize rethinks the title and summary. Keep what you have, or adopt the new wording — your call on each.
          </div>

          <div style={{ marginTop: 16, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden' }}>
            <ReorgField
              first
              serif
              label="Title"
              current="On integrity and moral courage"
              suggestion="Integrity, and standing by what’s right"
            />
            <ReorgField
              label="Summary"
              current="A reminder to myself: do the right thing even when it costs me. Stand with people only while they stand right."
              suggestion="You return to a standard you hold yourself to — staying true to what is right over what merely succeeds."
            />
          </div>

          <div style={{ flex: 1, minHeight: 12 }} />
          <Btn kind="accent">Keep this version</Btn>
          <div style={{ height: 8 }} />
          <Btn kind="secondary" size="md">Reorganize again</Btn>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// Stage 3st · Organized + stale ---------------------------------------------
function ScrLifeStale() {
  return (
    <PhoneScreen>
      <MemHeader />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 13, paddingTop: 6 }}>
        <div style={{ margin: '0 14px' }}><OrganizeChip variant="done" /></div>
        <OrganizedBody />
        <Toast kind="warn">2 new clips since this was organized — <strong style={{ fontWeight: 700 }}>Refresh</strong></Toast>
        <div style={{ flex: 1 }} />
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrLifeUnorganized, ScrLifeDraft, ScrLifeReviewSheet, ScrLifeOrganized,
  ScrLifeReorganizeSheet, ScrLifeStale,
  ReorgField,
  MemHeader, ClipRow, OrganizedBody,
});

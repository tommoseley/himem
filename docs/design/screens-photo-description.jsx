// screens-photo-description.jsx
// Photo / video DESCRIPTION — manual, human-written, per item.
//
// Locked decisions (June 2026, defaults):
//   · The description is part of the memory's WORDS. AI Organize and search
//     read it the same way they read a voice transcript — so a photo-only
//     memory becomes organizable and findable NOW, before visual AI ships.
//     It is the human stand-in for the future visual transcript.
//   · Per item (each photo / video gets its own), not per group.
//   · Entry: inline preview under the tile + tap the media to open a viewer
//     where you read/edit it.
//   · Empty state is PROMPTING (not faint) — right now it's the only way to
//     make a photo searchable, so the invitation earns visibility.
//   · Optional — never blocks. Label is "Description".
//
// Color discipline: the description is HUMAN-written, so its affordances use
// ochre (PX.accent, the user-action color) — never AI blue. Blue stays
// reserved for the future AI visual-analysis pass.

// ── shared bits ──────────────────────────────────────────────
function mediaMeta({ day, date, time, location }) {
  return `${day} ${date} · ${time}${location ? ' · ' + location : ''}`;
}

function PhotoGlyph({ size = 30, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="8.5" cy="10" r="1.6" />
      <path d="M21 16l-5-5L7 19" />
    </svg>
  );
}

function VideoGlyph({ size = 30, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="6" width="13" height="12" rx="2" />
      <path d="M16 10l5-3v10l-5-3z" />
    </svg>
  );
}

// Flat placeholder thumbnail — no gradient (Crucible rule). A real photo /
// video frame replaces this in production; the tile IS the thumbnail.
function MediaThumb({ kind = 'photo', duration, height = 168, onTapLabel = true }) {
  return (
    <div style={{
      position: 'relative', width: '100%', height,
      background: PX.sunk, borderRadius: 12,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      overflow: 'hidden',
    }}>
      {kind === 'video'
        ? <VideoGlyph size={34} color={PX.ink4} />
        : <PhotoGlyph size={34} color={PX.ink4} />}

      {/* type / duration chip */}
      <span style={{
        position: 'absolute', left: 9, bottom: 9,
        display: 'inline-flex', alignItems: 'center', gap: 5,
        fontSize: 10.5, fontWeight: 600, letterSpacing: 0.3,
        color: '#fff', background: 'rgba(26,22,18,0.62)',
        padding: '3px 8px', borderRadius: 8, textTransform: 'uppercase',
      }}>
        {kind === 'video' && (
          <svg width="8" height="9" viewBox="0 0 8 9" fill="#fff"><path d="M0 0l8 4.5L0 9z" /></svg>
        )}
        {kind === 'video' ? (duration || '0:24') : 'Photo'}
      </span>

      {/* play badge for video */}
      {kind === 'video' && (
        <span style={{
          position: 'absolute', width: 46, height: 46, borderRadius: 23,
          background: 'rgba(26,22,18,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="16" height="18" viewBox="0 0 16 18" fill="#fff"><path d="M0 0l16 9L0 18z" /></svg>
        </span>
      )}
    </div>
  );
}

// ── description sub-states ────────────────────────────────────

// Empty → prompting invitation (ochre, human action)
function DescriptionEmpty() {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 10,
      padding: '11px 12px', marginTop: 10,
      background: PX.accentTint, borderRadius: 10,
    }}>
      <span style={{
        width: 26, height: 26, borderRadius: 7, background: PX.accent, color: PX.accentInk,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>
        <svg width="13" height="13" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 17l4-1L17 6l-3-3L4 13l-1 4z" /></svg>
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: PX.accent, letterSpacing: -0.1 }}>
          Add a description
        </div>
        <div style={{ fontSize: 11.5, color: PX.ink3, lineHeight: 1.4, marginTop: 1 }}>
          A few words make this searchable and help HiMem organize the memory.
        </div>
      </div>
    </div>
  );
}

// Filled → the description IS the card's body text (parallels a transcript)
function DescriptionFilled({ children }) {
  return (
    <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 7 }}>
      <div style={{
        fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
        color: PX.ink3,
      }}>Description</div>
      <div style={{ fontSize: 14.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
        {children}
      </div>
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        fontSize: 12, fontWeight: 600, color: PX.accent, marginTop: 1,
      }}>
        <svg width="11" height="11" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 17l4-1L17 6l-3-3L4 13l-1 4z" /></svg>
        Edit
      </div>
    </div>
  );
}

// ── the media card (parallels MDClip) ────────────────────────
function MDMediaCard({ kind = 'photo', day, date, time, location, duration, description }) {
  return (
    <div style={{
      background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 16, padding: '14px 14px 16px',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div style={{ fontSize: 12, color: PX.ink3, fontVariantNumeric: 'tabular-nums', letterSpacing: -0.05, fontWeight: 500 }}>
        {mediaMeta({ day, date, time, location })}
      </div>
      <MediaThumb kind={kind} duration={duration} />
      {description ? <DescriptionFilled>{description}</DescriptionFilled> : <DescriptionEmpty />}
    </div>
  );
}

// ── memory detail with media inline ──────────────────────────
function ScrMemoryWithMedia() {
  return (
    <div style={{
      width: 340, minHeight: 1240, background: PX.paper, position: 'relative',
      fontFamily: PX.sans, color: PX.ink, overflow: 'hidden',
    }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
        <span style={{ fontSize: 11 }}>●●●</span>
      </div>

      <div style={{ padding: '6px 18px 10px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: PX.accent, fontSize: 15 }}>
          <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7" /></svg>
          Today
        </span>
      </div>

      <div style={{ padding: '0 18px 80px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 27, lineHeight: 1.1, letterSpacing: -0.5, color: PX.ink }}>
          The new raised bed
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink3 }}>May 27 · 4:13 PM · West Garden</div>

        {/* photo WITH a description — shows the filled state in context */}
        <MDMediaCard
          kind="photo"
          day="Tue" date="May 27" time="4:13 PM" location="West Garden"
          description="The cedar bed after the soil went in — front-left corner where the posts didn't line up. Need a second bag of compost before planting."
        />

        {/* a voice clip, to show media sits naturally beside transcripts */}
        <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, padding: '14px 16px 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ fontSize: 12, color: PX.ink3, fontWeight: 500 }}>Tue May 27 · 4:15 PM · West Garden</div>
          <div style={{ fontSize: 15, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
            Going to put the tomatoes along the back so they don't shade everything else out.
          </div>
        </div>

        {/* video WITHOUT a description — prompting empty state in context */}
        <MDMediaCard
          kind="video" duration="0:18"
          day="Tue" date="May 27" time="4:16 PM" location="West Garden"
        />
      </div>
    </div>
  );
}

// ── fullscreen viewer (read + edit) ──────────────────────────
function MiniKeyboard() {
  const rows = ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'];
  const key = (w) => ({
    height: 30, minWidth: w, flex: w ? 'none' : 1,
    background: '#FCFAF6', borderRadius: 5, boxShadow: '0 1px 0 rgba(26,22,18,0.25)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontSize: 13, color: PX.ink, fontWeight: 500,
  });
  return (
    <div style={{ background: '#CBC6BC', padding: '7px 4px 10px', display: 'flex', flexDirection: 'column', gap: 7 }}>
      {rows.map((r, i) => (
        <div key={i} style={{ display: 'flex', gap: 5, justifyContent: 'center', padding: i === 1 ? '0 16px' : 0 }}>
          {i === 2 && <div style={{ ...key(34), background: '#A9A398' }} />}
          {r.split('').map(c => <div key={c} style={key()}>{c}</div>)}
          {i === 2 && <div style={{ ...key(34), background: '#A9A398' }} />}
        </div>
      ))}
      <div style={{ display: 'flex', gap: 5, justifyContent: 'center' }}>
        <div style={{ ...key(40), background: '#A9A398', fontSize: 11 }}>123</div>
        <div style={key()}>space</div>
        <div style={{ ...key(64), background: PX.accent, color: '#fff', fontSize: 12, fontWeight: 600 }}>return</div>
      </div>
    </div>
  );
}

function ScrPhotoViewer({ kind = 'photo', editing = false }) {
  return (
    <div style={{
      width: 340, height: 735, background: '#1A1612', position: 'relative',
      fontFamily: PX.sans, color: '#fff', overflow: 'hidden',
      display: 'flex', flexDirection: 'column',
    }}>
      {/* top bar — in edit mode it becomes the canonical Cancel / Done pair.
         Done lives here (not above the keyboard) because iOS's own Proofread/
         Rewrite QuickType strip occupies the row over the keyboard and would
         fight any Save control placed there. The top bar is always free. */}
      <div style={{ display: 'flex', alignItems: 'center', padding: '16px 18px 10px', flexShrink: 0 }}>
        {editing ? (
          <span style={{ fontSize: 15, color: 'rgba(255,255,255,0.7)', fontWeight: 400 }}>Cancel</span>
        ) : (
          <span style={{
            width: 30, height: 30, borderRadius: 15, background: 'rgba(255,255,255,0.14)',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 16,
          }}>×</span>
        )}
        <span style={{ flex: 1, textAlign: 'center', fontSize: 12.5, color: 'rgba(255,255,255,0.7)' }}>
          May 27 · 4:13 PM
        </span>
        {editing ? (
          <span style={{ fontSize: 15, fontWeight: 700, color: PX.accent }}>Done</span>
        ) : (
          <span style={{ width: 30 }} />
        )}
      </div>

      {/* image stage */}
      <div style={{
        flex: editing ? '0 0 150px' : 1, margin: '0 14px',
        background: '#2A2520', borderRadius: 12,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative', transition: 'flex .2s',
      }}>
        {kind === 'video' ? <VideoGlyph size={40} color="rgba(255,255,255,0.32)" /> : <PhotoGlyph size={40} color="rgba(255,255,255,0.32)" />}
        {kind === 'video' && (
          <span style={{ position: 'absolute', width: 50, height: 50, borderRadius: 25, background: 'rgba(255,255,255,0.16)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="17" height="19" viewBox="0 0 16 18" fill="#fff"><path d="M0 0l16 9L0 18z" /></svg>
          </span>
        )}
      </div>

      {/* description panel — cream, slides from bottom */}
      <div style={{
        flexShrink: 0, marginTop: 12,
        background: PX.paper, borderTopLeftRadius: 18, borderTopRightRadius: 18,
        padding: '16px 18px 0', color: PX.ink,
      }}>
        <div style={{
          fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
          color: PX.ink3, marginBottom: 9,
        }}>Description</div>

        {editing ? (
          <div style={{
            border: '2px solid ' + PX.accent, borderRadius: 11, padding: '11px 12px',
            minHeight: 78, fontSize: 14.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1,
          }}>
            The cedar bed after the soil went in — front-left corner where the posts didn’t line up<span style={{
              display: 'inline-block', width: 2, height: 17, background: PX.accent, marginLeft: 1, verticalAlign: 'text-bottom',
            }} />
          </div>
        ) : (
          <div style={{ fontSize: 14.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1, minHeight: 78 }}>
            The cedar bed after the soil went in — front-left corner where the posts didn’t line up. Need a second bag of compost before planting.
          </div>
        )}

        <div style={{
          display: 'flex', alignItems: 'center',
          padding: '12px 0 14px',
        }}>
          <span style={{ fontSize: 11, color: PX.ink3 }}>
            {editing ? 'Part of this memory · searchable' : 'Tap to edit'}
          </span>
        </div>
      </div>

      {editing && <MiniKeyboard />}
    </div>
  );
}

// ── decision callout (documents the locked rules) ────────────
function MediaDescSpecCard() {
  const row = { padding: '13px 18px', borderBottom: '1px solid ' + PX.hairline };
  const eyebrow = { fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.accent, marginBottom: 5 };
  const body = { fontSize: 13.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 };
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, overflow: 'hidden', fontFamily: PX.sans }}>
      <div style={{ padding: '16px 18px 12px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 21, color: PX.ink, letterSpacing: -0.3 }}>How descriptions work</div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 3 }}>Manual now; the human stand-in for the future visual-analysis pass.</div>
      </div>
      <div style={row}>
        <div style={eyebrow}>Part of the memory's words</div>
        <div style={body}>AI Organize and search read the description exactly like a voice transcript. A photo-only memory becomes organizable and findable <em>now</em> — no visual AI required.</div>
      </div>
      <div style={row}>
        <div style={eyebrow}>Per item · optional · prompted</div>
        <div style={body}>Each photo and video gets its own. Never required — but the empty state invites clearly, because today it's the only way to make an image searchable.</div>
      </div>
      <div style={{ ...row, borderBottom: 'none' }}>
        <div style={eyebrow}>Saving · Cancel / Done</div>
        <div style={body}>Editing puts <strong>Cancel</strong> and an ochre <strong>Done</strong> in the top bar — never a Save control above the keyboard, where iOS's Proofread/Rewrite strip sits. Done commits and returns to reading; Cancel discards.</div>
      </div>
      <div style={{ ...row, borderBottom: 'none' }}>
        <div style={eyebrow}>Human, not AI</div>
        <div style={body}>These are the user's words, so every affordance is ochre. AI blue stays reserved for the visual-analysis pass that will later draft these automatically.</div>
      </div>
    </div>
  );
}

Object.assign(window, {
  MDMediaCard, MediaThumb, DescriptionEmpty, DescriptionFilled,
  ScrMemoryWithMedia, ScrPhotoViewer, MiniKeyboard, MediaDescSpecCard,
  PhotoGlyph, VideoGlyph,
});

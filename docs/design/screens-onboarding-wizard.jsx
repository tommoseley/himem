// screens-onboarding-wizard.jsx
// First-run permission wizard. REPLACES the old 4-screen onboarding.
//
// Why one page per permission: CloudKit's first-run sync warms up on a
// background thread (≈17–20s). Rather than a spinner, we spend that time
// walking the user through permissions one at a time — by the time they
// finish, the backend is ready. The pacing IS the cover.
//
// Order (locked, exactly as requested):
//   1 Sign in with Apple   ASAuthorizationController        (also gets name)
//   2 Microphone           AVAudioSession.requestRecord…    REQUIRED
//   3 Speech               SFSpeechRecognizer.request…      REQUIRED
//   4 Photos               PHPhotoLibrary.request…          optional
//   5 Camera               AVCaptureDevice.requestAccess    optional
//   6 Location             CLLocationManager.requestWhenIn… optional
//   7 Notifications        UNUserNotificationCenter.req…    optional · two channels
//
// Required = Sign in, Microphone, Speech. The rest are skippable and, if
// denied, show a calm "turn this on later in Settings" and continue.
//
// Reflective register: cream paper, Source Serif display, generous
// whitespace, one warm true line per page. SF Pro for everything functional.

const TOTAL_STEPS = 7;

// ─────────────────────────────────────────────────────────────
// Permission glyphs — single warm line icons, ochre on tint.
// ─────────────────────────────────────────────────────────────
const G = {
  apple: (
    <svg width="30" height="34" viewBox="0 0 17 20" fill="currentColor"><path d="M14.7 10.6c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9s-1.9-.9-3.2-.8C4.7 5 3.2 5.9 2.4 7.4c-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.7 2.5 2.9 2.4 1.2 0 1.6-.7 3-.7s1.8.7 3.1.7 2.1-1.2 2.9-2.4c.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.5-1-2.5-3.8zM12 2.8c.6-.8 1.1-1.9.9-3-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.8-1 2.9 1.2 0 2.3-.6 3-1.4z"/></svg>
  ),
  mic: (
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
  ),
  speech: (
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 9v6M8 5v14M12 8v8M16 4v16M20 9v6"/></svg>
  ),
  photos: (
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8.5" cy="8.5" r="1.6"/><path d="M21 15l-5-5L5 21"/></svg>
  ),
  camera: (
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7h3l2-2.5h8L18 7h3a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="4"/></svg>
  ),
  location: (
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/></svg>
  ),
  bell: (
    <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9z"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>
  ),
};

// ─────────────────────────────────────────────────────────────
// Top bar — back chevron, "N of 7" progress rail, optional Skip.
// ─────────────────────────────────────────────────────────────
function WizardTopBar({ step, skippable, showBack = true }) {
  return (
    <div style={{ padding: '6px 18px 0', flexShrink: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', height: 34 }}>
        <span style={{ width: 50, display: 'flex', alignItems: 'center' }}>
          {showBack && (
            <svg width="11" height="18" viewBox="0 0 9 14" fill="none" stroke={PX.ink2} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M7 1L1 7l6 6"/></svg>
          )}
        </span>
        <span style={{ flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: PX.ink3, letterSpacing: 0.2, fontVariantNumeric: 'tabular-nums' }}>
          {step} of {TOTAL_STEPS}
        </span>
        <span style={{ width: 50, textAlign: 'right' }}>
          {skippable && <span style={{ fontSize: 14, fontWeight: 500, color: PX.ink2, letterSpacing: -0.1 }}>Skip</span>}
        </span>
      </div>
      {/* progress rail */}
      <div style={{ display: 'flex', gap: 4, marginTop: 8 }}>
        {Array.from({ length: TOTAL_STEPS }).map((_, i) => (
          <span key={i} style={{
            flex: 1, height: 3, borderRadius: 2,
            background: i < step ? PX.accent : PX.hairline,
          }} />
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// The page template every permission page shares.
//   icon      — glyph from G
//   title     — Source Serif human "why" (the headline)
//   why       — one-line plain-English reason (ink2)
//   example   — concrete HiMem tie-in (shown in a card)
//   cta       — primary button label (names the iOS action)
//   required  — true → "Required" micro-label, no skip
//   denied    — true → swap example for a calm Settings note, CTA → Continue
//   tint      — accent (default) or 'ai' for the AI-blue moment
// ─────────────────────────────────────────────────────────────
function WizardPage({
  step, icon, title, why, example, cta, ctaSub,
  required = false, denied = false, tint = 'accent',
  children, dialog = null, statusTime = '9:41',
}) {
  const skippable = !required && !denied ? step >= 4 : false; // optional pages only
  const glyphFg = tint === 'ai' ? PX.ai : PX.accent;
  const glyphBg = tint === 'ai' ? PX.aiTint : PX.accentTint;

  return (
    <PhoneScreen time={statusTime}>
      <WizardTopBar step={step} skippable={skippable} showBack={step > 1} />

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        {/* icon */}
        <div style={{
          width: 68, height: 68, borderRadius: 19, marginTop: 40,
          background: glyphBg, color: glyphFg,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>{icon}</div>

        {/* title — the human why */}
        <h1 style={{
          fontFamily: PX.serif, fontWeight: 400, fontSize: 27, lineHeight: 1.18,
          letterSpacing: -0.5, color: PX.ink, margin: '22px 0 0', textWrap: 'pretty',
        }}>{title}</h1>

        {/* one-line plain why */}
        <p style={{ fontSize: 14.5, lineHeight: 1.5, color: PX.ink2, margin: '12px 0 0', maxWidth: 260, letterSpacing: -0.1 }}>
          {why}
        </p>

        {required && (
          <div style={{
            marginTop: 16, display: 'inline-flex', alignItems: 'center', gap: 6, alignSelf: 'flex-start',
            fontSize: 10.5, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase',
            color: PX.accent, background: PX.accentTint, padding: '5px 10px', borderRadius: 8,
          }}>
            Required to use HiMem
          </div>
        )}

        {/* custom body (e.g. notification toggles) OR example/denied card */}
        {children ? children : (
          <div style={{
            marginTop: 22,
            background: denied ? PX.sunk : PX.card,
            border: '1px solid ' + (denied ? 'transparent' : PX.hairline),
            borderRadius: 16, padding: '15px 16px',
          }}>
            <div style={{
              fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase',
              color: PX.ink3, marginBottom: 7,
            }}>{denied ? 'No problem' : 'What this is for'}</div>
            <div style={{ fontFamily: PX.serif, fontStyle: 'italic', fontSize: 16, lineHeight: 1.42, color: denied ? PX.ink2 : PX.ink, letterSpacing: -0.1 }}>
              {denied ? 'You can turn this on any time in Settings. Nothing here breaks without it.' : example}
            </div>
          </div>
        )}

        <div style={{ flex: 1 }} />

        {/* dock */}
        <div style={{ paddingBottom: 30, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {ctaSub && (
            <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', lineHeight: 1.45, padding: '0 6px' }}>
              {ctaSub}
            </div>
          )}
          <button style={{
            height: 52, borderRadius: 14, border: 'none', cursor: 'pointer', width: '100%',
            background: tint === 'apple' ? PX.ink : (tint === 'ai' ? PX.ai : PX.accent),
            color: tint === 'apple' ? '#FFFCF6' : (tint === 'ai' ? '#fff' : PX.accentInk),
            fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
          }}>
            {tint === 'apple' && (
              <svg width="16" height="19" viewBox="0 0 17 20" fill="currentColor"><path d="M14.7 10.6c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9s-1.9-.9-3.2-.8C4.7 5 3.2 5.9 2.4 7.4c-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.7 2.5 2.9 2.4 1.2 0 1.6-.7 3-.7s1.8.7 3.1.7 2.1-1.2 2.9-2.4c.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.5-1-2.5-3.8zM12 2.8c.6-.8 1.1-1.9.9-3-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.8-1 2.9 1.2 0 2.3-.6 3-1.4z"/></svg>
            )}
            {cta}
          </button>
        </div>
      </div>

      {dialog}
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// iOS system permission alert — the determinate moment after the CTA.
// Faithful-ish: scrim, rounded card, title + body, stacked buttons.
// ─────────────────────────────────────────────────────────────
function SystemDialog({ title, body, allow = 'Allow', deny = "Don't Allow" }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(20,15,10,0.32)' }}>
      <div style={{
        width: 248, background: 'rgba(248,245,240,0.96)', backdropFilter: 'blur(20px)',
        borderRadius: 14, overflow: 'hidden', boxShadow: '0 20px 50px rgba(0,0,0,0.25)',
        fontFamily: PX.sans,
      }}>
        <div style={{ padding: '18px 18px 16px', textAlign: 'center' }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: '#000', letterSpacing: -0.2, marginBottom: 5 }}>{title}</div>
          <div style={{ fontSize: 12.5, color: '#1a1a1a', lineHeight: 1.4 }}>{body}</div>
        </div>
        <div style={{ borderTop: '0.5px solid rgba(0,0,0,0.18)', display: 'flex', flexDirection: 'column' }}>
          <button style={{ height: 42, border: 'none', background: 'transparent', color: '#0a84ff', fontSize: 15, fontWeight: 400, borderBottom: '0.5px solid rgba(0,0,0,0.18)', cursor: 'pointer' }}>{deny}</button>
          <button style={{ height: 42, border: 'none', background: 'transparent', color: '#0a84ff', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>{allow}</button>
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 1 · Sign in with Apple (also captures the name)
// ═════════════════════════════════════════════════════════════
function ScrW1Apple() {
  return (
    <PhoneScreen>
      <WizardTopBar step={1} skippable={false} showBack={false} />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <div style={{ marginTop: 48 }}>
          <div style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 52, lineHeight: 1, letterSpacing: -1.4, color: PX.ink }}>
            Hi<em style={{ fontStyle: 'italic', color: PX.accent }}>Mem</em>
          </div>
          <p style={{ fontFamily: PX.serif, fontStyle: 'italic', fontSize: 21, lineHeight: 1.36, color: PX.ink2, margin: '20px 0 0', maxWidth: 270, textWrap: 'pretty' }}>
            A quiet place for the thoughts you don’t want to lose.
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 13, marginTop: 26 }}>
            {[
              ['Capture first, organize later.', 'Voice, photo, video, or a note — on your phone or your Watch.'],
              ['AI suggests, you decide.', 'HiMem drafts a title, summary, and topics. Review, edit, or ignore.'],
              ['Your memories stay yours.', 'Synced privately through your own iCloud. Never our servers.'],
            ].map(([h, b]) => (
              <div key={h} style={{ display: 'flex', alignItems: 'flex-start', gap: 11 }}>
                <span style={{ width: 6, height: 6, borderRadius: 3, background: PX.accent, marginTop: 7, flexShrink: 0 }} />
                <div style={{ fontSize: 13.5, lineHeight: 1.45, color: PX.ink2, letterSpacing: -0.1 }}>
                  <strong style={{ color: PX.ink, fontWeight: 600 }}>{h}</strong> {b}
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ paddingBottom: 30, display: 'flex', flexDirection: 'column', gap: 12 }}>
          <button style={{
            height: 52, borderRadius: 14, border: 'none', cursor: 'pointer', width: '100%',
            background: PX.ink, color: '#FFFCF6', fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
          }}>
            <svg width="16" height="19" viewBox="0 0 17 20" fill="currentColor"><path d="M14.7 10.6c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9s-1.9-.9-3.2-.8C4.7 5 3.2 5.9 2.4 7.4c-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.7 2.5 2.9 2.4 1.2 0 1.6-.7 3-.7s1.8.7 3.1.7 2.1-1.2 2.9-2.4c.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.5-1-2.5-3.8zM12 2.8c.6-.8 1.1-1.9.9-3-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.8-1 2.9 1.2 0 2.3-.6 3-1.4z"/></svg>
            Continue with Apple
          </button>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', lineHeight: 1.45, padding: '0 10px' }}>
            One tap with Face ID. No password to set, no email to verify. Your name comes from Apple — we never ask for it twice.
          </div>
          <div style={{ textAlign: 'center' }}>
            <span style={{ fontSize: 13, fontWeight: 600, color: PX.accent, letterSpacing: -0.1 }}>How HiMem works →</span>
          </div>
        </div>
      </div>
    </PhoneScreen>
  );
}

// PAGE 1b · Apple sheet returned the name → confirm + edit.
// Name is pre-filled from Apple's first name; the field is editable so the
// user can change what HiMem calls them. Field-affordance rules (per the
// Edit Project work): filled card surface + real boundary at rest, eyebrow
// label distinct from the value, full-height tap target, ochre focus ring.
function ScrW1Name() {
  return (
    <PhoneScreen>
      <style>{`@keyframes w1caret { 50% { opacity: 0 } }`}</style>
      <WizardTopBar step={1} skippable={false} showBack={false} />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <div style={{ marginTop: 52 }}>
          <div style={{ width: 68, height: 68, borderRadius: 19, background: PX.confirmedTint, color: PX.confirmed, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6L9 17l-5-5"/></svg>
          </div>
          <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 29, lineHeight: 1.16, letterSpacing: -0.5, color: PX.ink, margin: '22px 0 0' }}>
            You’re in. <em style={{ fontStyle: 'italic', color: PX.accent }}>What should we call you?</em>
          </h1>

          {/* Editable name field — pre-filled from Apple */}
          <div style={{ marginTop: 24 }}>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 7 }}>
              Your name
            </div>
            <div style={{
              background: PX.card, border: '1px solid ' + PX.accent,
              boxShadow: '0 0 0 3px ' + PX.accentTint, borderRadius: 12,
              height: 50, padding: '0 14px', display: 'flex', alignItems: 'center',
            }}>
              <span style={{ fontSize: 17, color: PX.ink, letterSpacing: -0.2 }}>Bryan</span>
              <span style={{ display: 'inline-block', width: 2, height: 21, background: PX.accent, marginLeft: 2, borderRadius: 1, animation: 'w1caret 1s step-end infinite' }} />
            </div>
            <div style={{ fontSize: 12, color: PX.ink3, marginTop: 8, lineHeight: 1.45 }}>
              Apple shared this with your sign-in. Change it to anything you like.
            </div>
          </div>
        </div>

        <div style={{ flex: 1 }} />
        <div style={{ paddingBottom: 30 }}>
          <button style={{ height: 52, borderRadius: 14, border: 'none', cursor: 'pointer', width: '100%', background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2 }}>
            Continue
          </button>
        </div>
      </div>
    </PhoneScreen>
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 2 · Microphone (required)
// ═════════════════════════════════════════════════════════════
function ScrW2Mic() {
  return (
    <WizardPage
      step={2} required icon={G.mic}
      title="The fastest way in is to just say it."
      why="HiMem captures by voice — on your phone and your Watch."
      example="“Don’t let me forget the pear tree fruited.” Tap, talk, done."
      cta="Allow microphone"
    />
  );
}

// PAGE 2 · system dialog moment
function ScrW2MicDialog() {
  return (
    <WizardPage
      step={2} required icon={G.mic}
      title="The fastest way in is to just say it."
      why="HiMem captures by voice — on your phone and your Watch."
      example="“Don’t let me forget the pear tree fruited.” Tap, talk, done."
      cta="Allow microphone"
      dialog={<SystemDialog title="“HiMem” Would Like to Access the Microphone" body="So you can capture voice notes and Watch clips." allow="Allow" deny="Don’t Allow" />}
    />
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 3 · Speech (required)
// ═════════════════════════════════════════════════════════════
function ScrW3Speech() {
  return (
    <WizardPage
      step={3} required icon={G.speech}
      title="So you can find a thought by what you said."
      why="Speech turns your voice into words you can search and read back."
      example="Search “pear tree” weeks later and the right memory surfaces."
      cta="Allow speech recognition"
    />
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 4 · Photos (optional)
// ═════════════════════════════════════════════════════════════
function ScrW4Photos() {
  return (
    <WizardPage
      step={4} icon={G.photos}
      title="Let a picture ride along with the thought."
      why="Add photos from your library to any memory."
      example="The recipe you photographed, kept beside the note about it."
      cta="Allow photo access"
    />
  );
}

// PAGE 4 · denied → calm Settings note
function ScrW4PhotosDenied() {
  return (
    <WizardPage
      step={4} denied icon={G.photos}
      title="Let a picture ride along with the thought."
      why="Add photos from your library to any memory."
      cta="Continue"
    />
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 5 · Camera (optional)
// ═════════════════════════════════════════════════════════════
function ScrW5Camera() {
  return (
    <WizardPage
      step={5} icon={G.camera}
      title="Catch the moment, not just the words for it."
      why="Take a photo or video straight into a memory."
      example="Snap the whiteboard before it’s erased — it lands in HiMem."
      cta="Allow camera"
    />
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 6 · Location (optional)
// ═════════════════════════════════════════════════════════════
function ScrW6Location() {
  return (
    <WizardPage
      step={6} icon={G.location}
      title="Let a memory remember where you were."
      why="HiMem tags captures with a place — only while you’re using it."
      example="Months later, a note still says “Marsh Walk, Murrells Inlet.”"
      cta="Allow location while using"
    />
  );
}

// ═════════════════════════════════════════════════════════════
// PAGE 7 · Notifications (optional · two channels)
// Channel A (Captured Clips, passive) ON by default; Channel B
// (Inactivity, opt-in) OFF. Both shown, then the iOS dialog fires.
// ═════════════════════════════════════════════════════════════
function ChannelToggle({ on, title, body }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 12,
      padding: '13px 14px', background: PX.card, border: '1px solid ' + PX.hairline,
      borderRadius: 14,
    }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>{title}</div>
        <div style={{ fontSize: 12, color: PX.ink2, lineHeight: 1.4, marginTop: 2 }}>{body}</div>
      </div>
      <div style={{
        width: 46, height: 28, borderRadius: 999, flexShrink: 0, marginTop: 1,
        background: on ? PX.confirmed : PX.ink4, position: 'relative', transition: 'background .2s',
      }}>
        <span style={{
          position: 'absolute', top: 2, left: on ? 20 : 2, width: 24, height: 24, borderRadius: 999,
          background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)', transition: 'left .2s',
        }} />
      </div>
    </div>
  );
}

function ScrW7Notifications({ dialog = false }) {
  return (
    <PhoneScreen>
      <WizardTopBar step={7} skippable={true} showBack={true} />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <div style={{ width: 68, height: 68, borderRadius: 19, marginTop: 36, background: PX.accentTint, color: PX.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {G.bell}
        </div>
        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 26, lineHeight: 1.18, letterSpacing: -0.5, color: PX.ink, margin: '20px 0 0', textWrap: 'pretty' }}>
          Two kinds of nudge. You choose both.
        </h1>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9, marginTop: 18 }}>
          <ChannelToggle
            on={true}
            title="When clips arrive"
            body="A quiet, silent note when Watch clips are waiting. No buzz."
          />
          <ChannelToggle
            on={false}
            title="If it’s been a while"
            body="An optional reminder after a quiet stretch. Off unless you want it."
          />
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ paddingBottom: 30, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', lineHeight: 1.45, padding: '0 8px' }}>
            iOS will ask once. You can change either of these in Settings later.
          </div>
          <button style={{ height: 52, borderRadius: 14, border: 'none', cursor: 'pointer', width: '100%', background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2 }}>
            Turn on notifications
          </button>
        </div>
      </div>
      {dialog && <SystemDialog title="“HiMem” Would Like to Send You Notifications" body="Notifications may include alerts, sounds, and icon badges." allow="Allow" deny="Don’t Allow" />}
    </PhoneScreen>
  );
}
function ScrW7NotificationsDialog() { return <ScrW7Notifications dialog={true} />; }

// ═════════════════════════════════════════════════════════════
// REQUIRED · can't continue.
// Apple, Microphone, and Speech must be granted to proceed. This is a
// wall — but a warm, helpful one. Recovery differs by case:
//   • apple  → the Apple sheet can be re-shown, so the fix is in-app: Retry.
//   • mic /
//     speech → iOS only asks once; after denial the only path is Settings.
// Warn-amber signals "attention to proceed" (icon + label, never color
// alone); ochre stays the action color. No blame: the app needs this, the
// user didn't do anything wrong.
// ═════════════════════════════════════════════════════════════
const REQUIRED_BLOCK = {
  apple: {
    step: 1, glyph: G.apple, fix: 'retry',
    title: 'Let’s finish signing in.',
    why: 'HiMem keeps your memories private and synced through your Apple account. Without it, there’s nowhere safe to put them.',
    cta: 'Try again with Apple',
    foot: 'Cancelled by mistake? One tap and you’re back.',
  },
  mic: {
    step: 2, glyph: G.mic, fix: 'settings',
    title: 'HiMem can’t hear you yet.',
    why: 'The microphone is how every memory gets captured. There’s no version of HiMem without it.',
    cta: 'Open Settings',
    foot: 'Switch it on, come back, and we’ll pick up right where you left off.',
  },
  speech: {
    step: 3, glyph: G.speech, fix: 'settings',
    title: 'Your words need transcription.',
    why: 'Speech recognition turns what you say into text you can read and search. It’s core to how HiMem works.',
    cta: 'Open Settings',
    foot: 'Switch it on, come back, and we’ll pick up right where you left off.',
  },
};

function ScrRequiredBlock({ perm = 'mic' }) {
  const c = REQUIRED_BLOCK[perm];
  const isRetry = c.fix === 'retry';
  return (
    <PhoneScreen>
      <WizardTopBar step={c.step} skippable={false} showBack={true} />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        {/* amber attention icon — glyph + small alert badge */}
        <div style={{ position: 'relative', width: 68, height: 68, marginTop: 40 }}>
          <div style={{ width: 68, height: 68, borderRadius: 19, background: PX.warnTint, color: PX.warn, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {c.glyph}
          </div>
          <div style={{
            position: 'absolute', right: -5, bottom: -5, width: 26, height: 26, borderRadius: 999,
            background: PX.warn, color: '#fff', border: '2.5px solid ' + PX.paper,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 15, fontWeight: 800, fontFamily: PX.serif, lineHeight: 1,
          }}>!</div>
        </div>

        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 27, lineHeight: 1.18, letterSpacing: -0.5, color: PX.ink, margin: '22px 0 0', textWrap: 'pretty' }}>
          {c.title}
        </h1>
        <p style={{ fontSize: 14.5, lineHeight: 1.5, color: PX.ink2, margin: '12px 0 0', maxWidth: 268, letterSpacing: -0.1 }}>
          {c.why}
        </p>

        <div style={{ marginTop: 16, display: 'inline-flex', alignItems: 'center', gap: 6, alignSelf: 'flex-start', fontSize: 10.5, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', color: PX.warnInk, background: PX.warnTint, padding: '5px 10px', borderRadius: 8 }}>
          Needed to continue
        </div>

        {/* settings-path explainer (only when iOS won't re-ask) */}
        {!isRetry && (
          <div style={{ marginTop: 22, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, padding: '14px 16px' }}>
            <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 9 }}>Two taps in Settings</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[['Settings', 'HiMem'], [perm === 'mic' ? 'Microphone' : 'Speech Recognition', 'On']].map(([a, b], i) => (
                <div key={a} style={{ display: 'flex', alignItems: 'center', gap: 9, fontSize: 13, color: PX.ink2 }}>
                  <span style={{ width: 18, height: 18, borderRadius: 999, background: PX.sunk, color: PX.ink3, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 700, flexShrink: 0 }}>{i + 1}</span>
                  <span>Tap <strong style={{ color: PX.ink, fontWeight: 600 }}>{a}</strong> → turn <strong style={{ color: PX.ink, fontWeight: 600 }}>{b}</strong></span>
                </div>
              ))}
            </div>
          </div>
        )}

        <div style={{ flex: 1 }} />
        <div style={{ paddingBottom: 30, display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', lineHeight: 1.45, padding: '0 6px' }}>{c.foot}</div>
          <button style={{
            height: 52, borderRadius: 14, border: 'none', cursor: 'pointer', width: '100%',
            background: isRetry ? PX.ink : PX.accent, color: isRetry ? '#FFFCF6' : PX.accentInk,
            fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
          }}>
            {isRetry && (
              <svg width="16" height="19" viewBox="0 0 17 20" fill="currentColor"><path d="M14.7 10.6c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9s-1.9-.9-3.2-.8C4.7 5 3.2 5.9 2.4 7.4c-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.7 2.5 2.9 2.4 1.2 0 1.6-.7 3-.7s1.8.7 3.1.7 2.1-1.2 2.9-2.4c.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.5-1-2.5-3.8zM12 2.8c.6-.8 1.1-1.9.9-3-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.8-1 2.9 1.2 0 2.3-.6 3-1.4z"/></svg>
            )}
            {c.cta}
          </button>
        </div>
      </div>
    </PhoneScreen>
  );
}
function ScrBlockApple()  { return <ScrRequiredBlock perm="apple" />; }
function ScrBlockMic()    { return <ScrRequiredBlock perm="mic" />; }
function ScrBlockSpeech() { return <ScrRequiredBlock perm="speech" />; }

// ═════════════════════════════════════════════════════════════
// LAND · the hand-off into Today (backend is warm by now)
// ═════════════════════════════════════════════════════════════
function ScrWLand() {
  return (
    <PhoneScreen>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 30, lineHeight: 1.16, letterSpacing: -0.5, color: PX.ink, marginTop: 58 }}>
          You’re all set, <em style={{ fontStyle: 'italic', color: PX.accent }}>Bryan.</em>
        </h1>
        <p style={{ fontSize: 14.5, lineHeight: 1.55, color: PX.ink2, margin: '12px 0 0', maxWidth: 280 }}>
          HiMem works best when capture is easy. Start with the thought closest to your tongue — or look around first.
        </p>
        <div style={{ marginTop: 26, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, padding: '18px 18px' }}>
          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 9 }}>To get you going</div>
          <div style={{ fontFamily: PX.serif, fontStyle: 'italic', fontSize: 18, lineHeight: 1.38, color: PX.ink }}>
            “What’s something you don’t want to forget today?”
          </div>
        </div>
        <div style={{ flex: 1 }} />
        {/* Action-first footer: capture is the invitation, looking around is the quiet alternative */}
        <div style={{ paddingBottom: 28, display: 'flex', flexDirection: 'column', gap: 12 }}>
          <button style={{
            height: 54, borderRadius: 15, border: 'none', cursor: 'pointer', width: '100%',
            background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            boxShadow: '0 8px 24px rgba(198,74,28,0.28)',
          }}>
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
            Capture your first memory
          </button>
          <button style={{
            height: 50, borderRadius: 15, border: '1px solid ' + PX.hairline, cursor: 'pointer', width: '100%',
            background: 'transparent', color: PX.ink2, fontSize: 15, fontWeight: 500, letterSpacing: -0.1,
          }}>
            Later — let me look around
          </button>
        </div>
      </div>
    </PhoneScreen>
  );
}

// ═════════════════════════════════════════════════════════════
// REINSTALL · restore from iCloud.
// Shown ONLY when a reinstall is detected. The flow is honest and short:
//   Apple auth (prove it's you) → THIS → Today.
// No permission cascade — a returning user already made those choices.
// Anything iOS revoked on uninstall is re-requested in context at first
// capture, not re-walled. The restore is the honest version of "cover the
// CloudKit wait": instead of distracting the user, we show them the true,
// reassuring thing — their memories coming back, counted as they land.
// ═════════════════════════════════════════════════════════════

// Glyph: an iCloud mark with slowly-turning sync arrows — reads as
// "syncing / in progress," deliberately NOT the iOS cloud-with-down-arrow
// "tap to download" control (which read as a broken button). Status, not action.
function RestoreGlyph({ color }) {
  return (
    <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M7 16.5a3.8 3.8 0 0 1-.5-7.6 5.3 5.3 0 0 1 10.2-1.5A3.6 3.6 0 0 1 17.3 16.5" />
      <g style={{ transformOrigin: '12px 13px', animation: 'rgSpin 2.6s linear infinite' }}>
        <path d="M14.6 12.4a2.7 2.7 0 1 0 .3 2.6" />
        <path d="M14.9 10.7v1.9h-1.9" />
      </g>
    </svg>
  );
}

function ScrReinstallRestore() {
  return (
    <PhoneScreen>
      <style>{`
        @keyframes wrBar { 0% { transform: translateX(-100%) } 100% { transform: translateX(320%) } }
        @keyframes rgSpin { to { transform: rotate(360deg) } }
      `}</style>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <div style={{ width: 64, height: 64, borderRadius: 18, background: PX.accentTint, color: PX.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 56 }}>
          <RestoreGlyph color={PX.accent} />
        </div>

        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 30, lineHeight: 1.16, letterSpacing: -0.5, color: PX.ink, margin: '22px 0 0' }}>
          Welcome back, <em style={{ fontStyle: 'italic', color: PX.accent }}>Bryan.</em>
        </h1>
        <p style={{ fontSize: 14.5, lineHeight: 1.55, color: PX.ink2, margin: '12px 0 0', maxWidth: 280 }}>
          Bringing your memories back from iCloud. They’ll keep arriving even after you go in.
        </p>

        {/* Live count — the true, reassuring thing. Hero, not chrome. */}
        <div style={{ marginTop: 34 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 56, lineHeight: 1, letterSpacing: -1.5, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>47</span>
            <span style={{ fontSize: 15, color: PX.ink2, letterSpacing: -0.1 }}>memories back so far</span>
          </div>

          {/* Indeterminate bar — no percent, because CloudKit streams with no
              reliable total. Honest motion, not a fake countdown. */}
          <div style={{ marginTop: 18, height: 4, borderRadius: 2, background: PX.sunk, overflow: 'hidden', position: 'relative' }}>
            <div style={{ position: 'absolute', top: 0, left: 0, height: '100%', width: '32%', borderRadius: 2, background: PX.accent, animation: 'wrBar 1.4s ease-in-out infinite' }} />
          </div>
          <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 9, letterSpacing: -0.05 }}>
            Counting up as they land — on a new device this can take a moment.
          </div>
        </div>

        <div style={{ flex: 1 }} />
        <div style={{ paddingBottom: 28 }}>
          <button style={{
            height: 54, borderRadius: 15, border: 'none', cursor: 'pointer', width: '100%',
            background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
          }}>
            Keep going while it finishes
          </button>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 10, lineHeight: 1.45, padding: '0 8px' }}>
            The rest keep arriving in the background. Nothing waits on this screen.
          </div>
        </div>
      </div>
    </PhoneScreen>
  );
}

// Settled state — restore quieted (no remote-change events for 5s). The
// app auto-advances to Today; this is the half-second of confirmation the
// user sees first. Selection=ring, completion=check: a real green check.
function ScrReinstallRestoreDone() {
  return (
    <PhoneScreen>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <div style={{ width: 64, height: 64, borderRadius: 18, background: PX.confirmedTint, color: PX.confirmed, display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 56 }}>
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6L9 17l-5-5" /></svg>
        </div>

        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 30, lineHeight: 1.16, letterSpacing: -0.5, color: PX.ink, margin: '22px 0 0' }}>
          That’s everything.
        </h1>
        <p style={{ fontSize: 14.5, lineHeight: 1.55, color: PX.ink2, margin: '12px 0 0', maxWidth: 280 }}>
          Your Memory Box is whole again. Picking up right where you left off.
        </p>

        <div style={{ marginTop: 34, display: 'flex', alignItems: 'baseline', gap: 10 }}>
          <span style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 56, lineHeight: 1, letterSpacing: -1.5, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>412</span>
          <span style={{ fontSize: 15, color: PX.ink2, letterSpacing: -0.1 }}>memories restored</span>
        </div>

        <div style={{ flex: 1 }} />
        <div style={{ paddingBottom: 28 }}>
          <button style={{
            height: 54, borderRadius: 15, border: 'none', cursor: 'pointer', width: '100%',
            background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
          }}>
            Go to HiMem
          </button>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 10, lineHeight: 1.45 }}>
            Taking you in…
          </div>
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
function WizardNotes() {
  const card = { background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 18, padding: '22px 24px', display: 'flex', flexDirection: 'column', gap: 14 };
  const h3 = { margin: 0, fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 };
  const p = { margin: 0, fontSize: 13.5, lineHeight: 1.55, color: PX.ink2 };
  const strong = { color: PX.ink, fontWeight: 600 };
  return (
    <div style={{ width: '100%', height: '100%', background: PX.paper, padding: 30, fontFamily: PX.sans, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, alignContent: 'start', overflow: 'hidden' }}>
      <div style={card}>
        <h3 style={h3}>Why the wait is invisible</h3>
        <p style={p}>CloudKit’s first-run sync warms up on a background thread — roughly <strong style={strong}>17–20 seconds</strong>. Instead of a spinner, the permission pages spend that time. <strong style={strong}>The pacing is the cover.</strong> By the time the user finishes notifications, the bin is ready and Land opens instantly.</p>
      </div>
      <div style={card}>
        <h3 style={h3}>Required vs optional</h3>
        <p style={p}><strong style={strong}>Sign in, Microphone, Speech</strong> are required — HiMem doesn’t function without voice capture and transcription. The other four (Photos, Camera, Location, Notifications) are skippable, framed by what they <em>enable</em>, never what they ask for.</p>
      </div>
      <div style={card}>
        <h3 style={{ ...h3, color: PX.warn }}>Required denial is a wall, not a trap</h3>
        <p style={p}>Sign in, Microphone, and Speech must be granted. If denied, the user hits a warm <strong style={strong}>“can’t continue”</strong> page — amber attention, no blame. <strong style={strong}>Apple</strong> is retryable in-app (the sheet re-shows); <strong style={strong}>Mic and Speech</strong> route to Settings, since iOS only asks once. Both pages promise to pick up where they left off.</p>
      </div>
      <div style={card}>
        <h3 style={h3}>Denial is calm, never a wall</h3>
        <p style={p}>iOS shows each system prompt once. If the user declines an <em>optional</em> permission, the page swaps to <strong style={strong}>“you can turn this on later in Settings”</strong> and continues. No nag, no repeat ask, no blame.</p>
      </div>
      <div style={card}>
        <h3 style={{ ...h3, color: PX.accent }}>No paywall in onboarding</h3>
        <p style={p}>There’s no pricing wall here at all. The user gets the full app from day one and meets pricing only when they’ve already gotten value — not at the door. Hard-paywalling first-run is the #1 reason apps die in TestFlight.</p>
      </div>
      <div style={card}>
        <h3 style={h3}>What we cut</h3>
        <p style={p}>No “what is HiMem” promo carousel — the product teaches better. No iCloud opt-in screen — Sign in with Apple implies it. No avatar or display-name form — <strong style={strong}>Apple gives us the name; we use it.</strong></p>
      </div>
      <div style={card}>
        <h3 style={{ ...h3, color: PX.accent }}>Reinstall is a different, shorter path</h3>
        <p style={p}>A returning user already made these choices — re-walling them through seven pages is theater. Reinstall is <strong style={strong}>Apple auth → Restore → Today</strong>. Apple sign-in proves it’s the right person; then we <strong style={strong}>honestly show the memories coming back from iCloud</strong>, counted as they land. Anything iOS revoked on uninstall is re-requested <em>in context at first capture</em>, never as a fresh cascade. The restore <em>is</em> the wait-cover here — not a distraction from the wait, but the reassuring truth of it.</p>
      </div>
      <div style={card}>
        <h3 style={h3}>Two notification channels</h3>
        <p style={p}>Page 7 shows both toggles before the iOS ask: <strong style={strong}>“When clips arrive”</strong> (passive, silent — on) and <strong style={strong}>“If it’s been a while”</strong> (inactivity — off). The user confirms both; the system dialog fires only if at least one is on. Mirrors the locked two-channel model.</p>
      </div>
    </div>
  );
}

function WizardPrinciples() {
  const h4 = { fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', margin: '0 0 8px', color: PX.ink3 };
  const p = { margin: 0, fontSize: 13.5, lineHeight: 1.55, color: PX.ink2 };
  const strong = { color: PX.ink, fontWeight: 600 };
  return (
    <div style={{ width: '100%', height: '100%', background: PX.paper, padding: 34, fontFamily: PX.sans, overflow: 'hidden' }}>
      <div style={{ fontFamily: PX.serif, fontSize: 25, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, marginBottom: 4 }}>Principles</div>
      <div style={{ fontSize: 13, color: PX.ink3, marginBottom: 24 }}>Carried forward from the original onboarding — still true for the wizard.</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '24px 34px' }}>
        <div><h4 style={h4}>Hand-off, not handhold</h4><p style={p}>The last screen is an <strong style={strong}>empty Today</strong> with a written prompt — no tutorial overlay, no fake capture. We get out of the way and let the FAB do the inviting.</p></div>
        <div><h4 style={h4}>Skip is honored</h4><p style={p}>Skipping an optional permission never traps the user — they land in the same Today. Whatever they skipped is requested in context the first time it’s actually needed.</p></div>
        <div><h4 style={h4}>Re-onboarding on a new device</h4><p style={p}>Reinstalling or signing in on a second device skips the permission cascade entirely: <strong style={strong}>Apple auth, then a live iCloud restore</strong>, then Today. Nothing to redo — no topic setup, no re-walled permissions. iOS re-asks for a revoked permission only in context, the first time it’s needed.</p></div>
        <div><h4 style={h4}>Voice &amp; tone</h4><p style={p}>Each page reads like a thoughtful friend, not an app. <strong style={strong}>One italic-serif line for warmth</strong>, SF Pro for everything functional. Specific over clever: “the pear tree fruited,” not “your second brain.”</p></div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// LEARN MORE · “How HiMem works” ladder
// Optional, reachable from the sign-in screen and permanently from Settings.
// The one place we explain the *unusual* parts — the loop, Projects, Studio,
// and the data-custody differentiator. Never a wall: it's a page you choose.
// ═════════════════════════════════════════════════════════════
function LadderStep({ glyph, name, line, last, dim }) {
  return (
    <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
      {/* node + connector */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0 }}>
        <div style={{
          width: 40, height: 40, borderRadius: 11, flexShrink: 0,
          background: dim ? PX.sunk : PX.accentTint, color: dim ? PX.ink3 : PX.accent,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>{glyph}</div>
        {!last && <div style={{ width: 2, flex: 1, minHeight: 8, background: PX.hairline, marginTop: 3 }} />}
      </div>
      {/* text */}
      <div style={{ paddingBottom: last ? 0 : 5, paddingTop: 3 }}>
        <div style={{
          fontSize: 15, fontWeight: 600, color: dim ? PX.ink3 : PX.ink, letterSpacing: -0.2,
          display: 'flex', alignItems: 'baseline', gap: 8,
        }}>
          {name}
          {dim && <span style={{ fontSize: 11, fontWeight: 500, color: PX.ink3, letterSpacing: 0 }}>coming later</span>}
        </div>
        <div style={{ fontSize: 13, lineHeight: 1.45, color: PX.ink2, marginTop: 3, letterSpacing: -0.1, maxWidth: 252 }}>{line}</div>
      </div>
    </div>
  );
}

function ScrWLearnMore() {
  const sparkGlyph = <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/></svg>;
  const memGlyph = <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3h9l5 5v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M14 3v5h5"/></svg>;
  const projGlyph = <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a1 1 0 0 1 1-1h5l2 2h8a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/></svg>;
  const studioGlyph = <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2l2.4 6.5L21 9l-5 4.5L17.5 21 12 17l-5.5 4L8 13.5 3 9l6.6-.5z"/></svg>;
  const capGlyph = <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>;
  return (
    <PhoneScreen>
      {/* top bar — back + close, matches the modal-edit pattern */}
      <div style={{ display: 'flex', alignItems: 'center', padding: '14px 18px 6px', flexShrink: 0 }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: PX.accent, fontSize: 15 }}>
          <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Back
        </span>
        <span style={{ flex: 1 }} />
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'hidden' }}>
        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 28, lineHeight: 1.15, letterSpacing: -0.5, color: PX.ink, margin: '2px 0 0' }}>
          How <em style={{ fontStyle: 'italic', color: PX.accent }}>HiMem</em> works
        </h1>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: PX.ink2, margin: '7px 0 10px', letterSpacing: -0.1 }}>
          Capture first. Organize later. The rest takes care of itself.
        </p>

        <div style={{ display: 'flex', flexDirection: 'column' }}>
          <LadderStep glyph={capGlyph} name="Capture" line="Record a thought, snap a photo, save a video, or jot a note — on your phone or your Watch." />
          <LadderStep glyph={memGlyph} name="Memory" line="Those pieces become a memory: something you can find again, in your words." />
          <LadderStep glyph={sparkGlyph} name="Organize" line="HiMem suggests a title, summary, and topics. You review, edit, or ignore — always your call." />
          <LadderStep glyph={projGlyph} name="Projects" line="A project collects related memories. Over time, HiMem helps surface what belongs together." />
          <LadderStep glyph={studioGlyph} name="Studio" line="Turn a project into something you can share." dim last />
        </div>

        <div style={{ flex: 1 }} />

        {/* data-custody differentiator — the unusual, trust-building truth */}
        <div style={{
          background: PX.sunk, borderRadius: 14, padding: '8px 14px', marginBottom: 10,
          display: 'flex', gap: 11, alignItems: 'flex-start',
        }}>
          <span style={{ color: PX.ink3, flexShrink: 0, marginTop: 1 }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z"/></svg>
          </span>
          <div style={{ fontSize: 12.5, lineHeight: 1.5, color: PX.ink2, letterSpacing: -0.1 }}>
            Your originals — photos, videos, recordings — stay in <strong style={{ color: PX.ink, fontWeight: 600 }}>your own iCloud</strong>. HiMem builds memories from them, but never uploads them to our servers.
          </div>
        </div>

        <div style={{ paddingBottom: 16 }}>
          <button style={{ height: 50, borderRadius: 14, border: 'none', cursor: 'pointer', width: '100%', background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2 }}>
            Got it
          </button>
        </div>
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrW1Apple, ScrW1Name,
  ScrW2Mic, ScrW2MicDialog,
  ScrW3Speech,
  ScrW4Photos, ScrW4PhotosDenied,
  ScrW5Camera,
  ScrW6Location,
  ScrW7Notifications, ScrW7NotificationsDialog,
  ScrRequiredBlock, ScrBlockApple, ScrBlockMic, ScrBlockSpeech,
  ScrWLand, ScrWLearnMore, LadderStep,
  ScrReinstallRestore, ScrReinstallRestoreDone, RestoreGlyph,
  WizardPage, WizardTopBar, SystemDialog, ChannelToggle,
  WizardNotes, WizardPrinciples,
});

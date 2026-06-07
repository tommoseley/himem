// pricing-screens.jsx
// HiMem · Capture · Connect · Create — the new pricing & organize-lifecycle
// surfaces, built against the locked model (Pricing model · Capture-Connect-Create.md)
// and the wireframe direction agreed June 5:
//   1 · Pricing page  → A1 "story" + inline magic-moment card (A3's blue tile)
//   2 · Organize lifecycle → B2 quiet draft-chip; B1 copy lives in the review sheet
//   3 · Upgrade moment → C1 after-a-glance (once-ever) + C3 Settings (always)
//
// Voice + color discipline (Crucible):
//   - Ochre (PX.accent) = primary user action only (Organize, Try Plus, Looks good)
//   - AI blue (PX.ai)   = every organize / inference moment (Draft chip, magic card, C1)
//   - "Draft organized" is a REVIEW-STATE label, not a tier badge. Becomes plain
//     "Organized" only on accept/edit. (AI Organize · spec.md §2b/§9.)
//   - Reach ≠ less private: Plus copy frames the upgrade as capability, never exposure.

// ─────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────
function SerifH({ children, size = 28, style }) {
  return (
    <div style={{
      fontFamily: PX.serif, fontWeight: 400, fontSize: size, lineHeight: 1.12,
      letterSpacing: -0.5, color: PX.ink, ...style,
    }}>{children}</div>
  );
}

// AI-blue draft / organized chip. variant: 'draft' | 'done'
function OrganizeChip({ variant = 'draft' }) {
  const draft = variant === 'draft';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      fontSize: 11.5, fontWeight: 600, letterSpacing: 0.1,
      color: PX.ai, background: PX.aiTint,
      border: (draft ? '1px dashed ' : '1px solid ') + PX.ai,
      padding: '3px 9px', borderRadius: 13,
    }}>
      {draft ? <Spark size={11} /> : <Check size={11} />}
      {draft ? 'Draft organized' : 'Organized'}
    </span>
  );
}

// The magic-moment tile (A3's blue card) — the concrete "show don't tell"
// proof of what Connect feels like. Used in the pricing page and the C1 nudge.
function MagicTile({ compact = false }) {
  return (
    <div style={{
      background: PX.aiTint, border: '1px solid ' + PX.ai,
      borderRadius: 14, padding: compact ? '12px 13px' : '14px 15px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 9 }}>
        <span style={{
          width: 22, height: 22, borderRadius: 6, background: PX.ai, color: '#fff',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}><Spark size={13} color="#fff" /></span>
        <span style={{ fontSize: 12, fontWeight: 700, color: PX.ai, letterSpacing: 0.2 }}>
          8 memories may belong here
        </span>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {[['The pear tree, three years on', 'Garden'], ['What I keep coming back to', 'How We Work'], ['Frost notes — late October', 'Garden']].map(([t, k], i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 8,
            background: PX.card, border: '1px solid ' + PX.aiEdge, borderRadius: 9, padding: '7px 9px',
          }}>
            <span style={{ width: 5, height: 5, borderRadius: 3, background: PX.ai, flexShrink: 0 }} />
            <span style={{ fontSize: 12, color: PX.ink, flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{t}</span>
            <span style={{ fontSize: 10.5, color: PX.ink3 }}>{k}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 1 · PRICING PAGE — A1 story + inline magic-moment tile
// ═════════════════════════════════════════════════════════════
function ScrPricing() {
  return (
    <PhoneScreen>
      {/* close affordance */}
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 16px 2px' }}>
        <span style={{ flex: 1 }} />
        <span style={{
          width: 30, height: 30, borderRadius: 15, background: PX.sunk, color: PX.ink3,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 17,
        }}>×</span>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', padding: '0 20px', display: 'flex', flexDirection: 'column' }}>
        {/* The inversion — leads */}
        <SerifH size={28} style={{ marginTop: 6 }}>
          Your memories stay<br />yours. Even offline.
        </SerifH>
        <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginTop: 10 }}>
          HiMem keeps and organizes everything <strong style={{ color: PX.ink, fontWeight: 600 }}>privately, on your device</strong> — no account needed to hold a thought. Plus helps your memories find each other.
        </div>

        {/* Capture */}
        <div style={{ marginTop: 18 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <SerifH size={19}>Capture</SerifH>
            <span style={{ fontSize: 12, color: PX.ink3, fontWeight: 600 }}>· free, always</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 8 }}>
            {['Capture and keep everything', 'Organize by hand, on your device', 'Three projects · search · fully offline'].map((t, i) => (
              <div key={i} style={{ display: 'flex', gap: 8, fontSize: 13, color: PX.ink2, alignItems: 'baseline' }}>
                <span style={{ color: PX.accent, fontWeight: 700, flexShrink: 0 }}>—</span>{t}
              </div>
            ))}
          </div>
        </div>

        {/* Connect + magic tile */}
        <div style={{ marginTop: 18 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <SerifH size={19} style={{ color: PX.accent }}>Connect</SerifH>
            <span style={{ fontSize: 12, color: PX.ink3, fontWeight: 600 }}>· Plus</span>
          </div>
          <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.5, margin: '7px 0 11px' }}>
            The library starts working for you — surfacing and connecting what belongs together.
          </div>
          <MagicTile />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 5, marginTop: 11 }}>
            {['Surfaces what you’ve already said', 'Connects the memories that belong together', 'Organizes automatically · unlimited projects'].map((t, i) => (
              <div key={i} style={{ display: 'flex', gap: 8, fontSize: 13, color: PX.ink2, alignItems: 'baseline' }}>
                <span style={{ color: PX.ai, fontWeight: 700, flexShrink: 0 }}>＋</span>{t}
              </div>
            ))}
          </div>
        </div>

        {/* Create — coming later, quiet */}
        <div style={{ marginTop: 16, paddingTop: 13, borderTop: '1px solid ' + PX.divider, display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <SerifH size={16} style={{ color: PX.ink3 }}>Create</SerifH>
          <span style={{ fontSize: 12, color: PX.ink3 }}>· turn memories into something — <em>coming later</em></span>
        </div>

        <div style={{ flex: 1, minHeight: 14 }} />

        {/* price + CTA pinned */}
        <div style={{ flexShrink: 0, paddingBottom: 14 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 9 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 5 }}>
              <span style={{ fontFamily: PX.serif, fontWeight: 600, fontSize: 26, color: PX.ink }}>$6.99</span>
              <span style={{ fontSize: 13, color: PX.ink3 }}>/ month</span>
            </div>
            <span style={{ fontSize: 12.5, color: PX.ink3 }}>or $69.99 / year</span>
          </div>
          <Btn kind="accent">Try Plus free for a week</Btn>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 7 }}>
            Keep using Free for as long as you like.
          </div>
        </div>
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  SerifH, OrganizeChip, MagicTile, ScrPricing,
});

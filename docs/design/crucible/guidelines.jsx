const C = window.Crucible;
// Crucible — Writing/voice & Accessibility
// These are reference artboards — large text, examples, rules.

// ───────── Writing / voice ─────────
function WritingVoice() {
  const principles = [
    ['Quiet over loud', 'A small true thing beats a big vague thing.'],
    ['Specific over clever', 'Name the real object. "12 seconds" not "a moment".'],
    ['Warm over neutral', 'We write like a thoughtful friend — not a product.'],
    ['Never blame', 'If something fails, we own it: "we couldn\'t reach…"  — not "you are offline".'],
  ];
  const pairs = [
    ['do', "Saved. We'll sync when you're back online.", "dont", "Offline. Sync failed."],
    ['do', 'Record a first memory', 'dont', 'Get started with your first entry'],
    ['do', 'Nothing here yet.', 'dont', 'No data found.'],
    ['do', 'Keep', 'dont', 'Cancel'],
  ];
  return (
    <div style={{ padding: 48, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif2">Voice</EditorialTitle>
      <div style={{ ...typeStyle(C.type.body), color: C.color.ink2, maxWidth: 560, marginTop: 12, marginBottom: 32 }}>
        How the product speaks. Read a line aloud. If it sounds like a notification from a stranger, rewrite it.
      </div>

      <SectionLabel>Principles</SectionLabel>
      <div style={{ marginBottom: 32 }}>
        {principles.map(([title, body]) => (
          <div key={title} style={{ padding: '14px 0', borderTop: '1px solid ' + C.color.hairline, display: 'flex', gap: 24 }}>
            <div style={{ width: 200, flexShrink: 0, ...typeStyle(C.type.title3), color: C.color.ink }}>{title}</div>
            <div style={{ ...typeStyle(C.type.body), color: C.color.ink2, flex: 1 }}>{body}</div>
          </div>
        ))}
      </div>

      <SectionLabel>Rewrite examples</SectionLabel>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        {pairs.map((p, i) => (
          <React.Fragment key={i}>
            <div style={{ padding: 16, background: C.color.card, borderRadius: C.radius.md, borderLeft: '3px solid ' + C.color.success }}>
              <div style={{ ...typeStyle(C.type.caption2), color: C.color.success, fontWeight: 700, textTransform: 'uppercase', marginBottom: 4 }}>Do</div>
              <div style={{ ...typeStyle(C.type.body), color: C.color.ink }}>{p[1]}</div>
            </div>
            <div style={{ padding: 16, background: C.color.card, borderRadius: C.radius.md, borderLeft: '3px solid ' + C.color.danger }}>
              <div style={{ ...typeStyle(C.type.caption2), color: C.color.danger, fontWeight: 700, textTransform: 'uppercase', marginBottom: 4 }}>Don't</div>
              <div style={{ ...typeStyle(C.type.body), color: C.color.ink3 }}>{p[3]}</div>
            </div>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

// ───────── Accessibility ─────────
function Accessibility() {
  const rules = [
    ['Contrast', '4.5 : 1 body · 3 : 1 headlines ≥ 18pt · 3 : 1 UI glyphs.', 'WCAG 2.2 AA, verified at each palette release.'],
    ['Hit size', 'Minimum 44 × 44 pt. Visual shape may be smaller, hit rect is not.', 'Apply to mic FAB, list chevrons, toggles.'],
    ['Focus ring', '3px ember ring at 45% alpha, offset 2px.', 'Never hide focus. Web + iPadOS keyboard.'],
    ['Motion', 'Respect prefers-reduced-motion. Cross-fade replaces spring.', 'Durations cap at 200ms when reduced.'],
    ['Text', 'All type scales with Dynamic Type. No pixel values leak into UI text.', 'xxxLarge snaps to 130%.'],
    ['Labels', 'Every icon-only control names itself via aria-label or accessibilityLabel.', 'Names use voice: "Record memory", not "Mic".'],
    ['Colorblind', 'Status is never color alone. Pair with icon + label.', 'Success = check + "Synced". Danger = alert + word.'],
    ['Affordance', 'One look, one job: a real button (≥ 44px) is the action; a solid pill + dot is managed content; a quiet label is status. Dashed = add / incomplete only.', 'Status is never dressed as a button; the action is never a bare text link. One primary action per moment, and it is the loudest interactive thing. Origin: the “Draft organized” cluster.'],
    ['Screen reader', 'Group labels follow reading order. Grouped list announces header once.', 'Decorative dividers are aria-hidden.'],
  ];
  return (
    <div style={{ padding: 48, background: C.color.paper, height: '100%', fontFamily: C.type.sans, overflow: 'hidden' }}>
      <EditorialTitle size="serif2">Accessibility</EditorialTitle>
      <div style={{ ...typeStyle(C.type.body), color: C.color.ink2, maxWidth: 560, marginTop: 12, marginBottom: 32 }}>
        Access is a baseline, not a polish pass. These rules ship with the tokens.
      </div>

      <div>
        {rules.map(([n, rule, notes]) => (
          <div key={n} style={{ display: 'grid', gridTemplateColumns: '160px 1fr 1fr', gap: 20, padding: '16px 0', borderTop: '1px solid ' + C.color.hairline }}>
            <div style={{ ...typeStyle(C.type.headline), color: C.color.ink }}>{n}</div>
            <div style={{ ...typeStyle(C.type.body), color: C.color.ink }}>{rule}</div>
            <div style={{ ...typeStyle(C.type.footnote), color: C.color.ink3 }}>{notes}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { WritingVoice, Accessibility });

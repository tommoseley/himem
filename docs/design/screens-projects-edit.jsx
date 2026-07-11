// screens-projects-edit.jsx
// Edit Project screen + the field/topic rules it encodes.
//
// Two problems this screen fixes:
//   1. The Goal field didn't look like a field — its grey placeholder
//      matched the helper text below, so the eye read "Goal" as a section
//      label and the box as inert. Took several taps to discover it was
//      editable.
//   2. Topics appeared editable, but per the locked model
//      (CLAUDE.md § Projects) "a project's topic chips are derived from its
//      members." You don't set them here — they reflect the memories inside.
//
// So: Title + Goal are real, obvious editable fields; Topics is a
// read-only derived block that says where its chips come from.

// ─────────────────────────────────────────────────────────────
// FIELD — the corrected editable field.
// Rules encoded here (Crucible):
//  • The CONTAINER carries the affordance — filled PX.card surface + real
//    boundary, looks like a field at rest before any focus.
//  • Eyebrow LABEL is uppercase/tracked/ink3 — unmistakably a label, never
//    confusable with the sentence-case placeholder inside the field.
//  • Placeholder states INTENT, not the noun ("What are you building
//    toward?"), and is ink3 inside the field — so an empty field still
//    tells you what goes there, and no separate helper line is needed.
//  • Full-height hit target (min 44). Focus → ochre ring + caret,
//    identical across every field. Consistency is the affordance.
// ─────────────────────────────────────────────────────────────
function EditField({ label, value, placeholder, focused = false, multiline = false }) {
  const empty = !value;
  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{
        fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
        color: PX.ink3, marginBottom: 7,
      }}>{label}</div>
      <div style={{
        background: PX.card,
        border: '1px solid ' + (focused ? PX.accent : PX.hairline),
        boxShadow: focused ? '0 0 0 3px ' + PX.accentTint : 'none',
        borderRadius: 12,
        padding: multiline ? '12px 14px' : '0 14px',
        minHeight: multiline ? 76 : 48,
        display: 'flex', alignItems: multiline ? 'flex-start' : 'center',
      }}>
        <span style={{
          fontSize: 16, lineHeight: 1.4, letterSpacing: -0.2,
          color: empty ? PX.ink3 : PX.ink,
          fontFamily: multiline ? PX.serif : PX.sans,
          fontStyle: multiline && !empty ? 'italic' : 'normal',
        }}>
          {empty ? placeholder : value}
        </span>
        {focused && (
          <span style={{
            display: 'inline-block', width: 2, height: 20, background: PX.accent,
            marginLeft: empty ? 1 : 2, borderRadius: 1,
            animation: 'epCaret 1s step-end infinite',
            alignSelf: multiline ? 'flex-start' : 'center',
          }} />
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// DERIVED TOPICS — read-only. The rule, made visible.
// Topics are not set on the project; they're the union of the topics
// of the memories inside it. So this block shows the current derived
// chips, visibly inert (no add control, no ✕), with one honest line
// telling the user where they come from and how to change them.
// ─────────────────────────────────────────────────────────────
function DerivedTopics({ topics }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{
        display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 7,
      }}>
        <span style={{
          fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
          color: PX.ink3,
        }}>Topics</span>
        <span style={{
          fontSize: 10.5, fontWeight: 600, letterSpacing: 0.3, textTransform: 'uppercase',
          color: PX.ink3, background: PX.sunk, padding: '2px 7px', borderRadius: 7,
        }}>From its memories</span>
      </div>
      <div style={{
        background: PX.paper, border: '1px dashed ' + PX.hairline, borderRadius: 12,
        padding: '12px 14px',
      }}>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 9 }}>
          {topics.map(k => <TopicPipChip key={k} k={k} />)}
        </div>
        <div style={{ fontSize: 12, color: PX.ink3, lineHeight: 1.5, letterSpacing: -0.05 }}>
          These come from the memories in this project — add or remove memories to change them. There’s nothing to set here.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// EDIT PROJECT — the screen.
// ─────────────────────────────────────────────────────────────
function ScrEditProject({ goalFocused = true, goalEmpty = true }) {
  return (
    <PhoneScreen>
      <style>{`@keyframes epCaret { 50% { opacity: 0 } }`}</style>

      {/* Sheet-style nav: Cancel / title / Save */}
      <div style={{
        display: 'flex', alignItems: 'center', padding: '14px 18px 12px',
      }}>
        <span style={{ fontSize: 15, color: PX.ink2, letterSpacing: -0.1, width: 56 }}>Cancel</span>
        <span style={{ flex: 1, textAlign: 'center', fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>
          Edit project
        </span>
        <span style={{ fontSize: 15, fontWeight: 600, color: PX.accent, letterSpacing: -0.1, width: 56, textAlign: 'right' }}>Save</span>
      </div>

      <div style={{ padding: '8px 18px 0', flex: 1, overflow: 'hidden' }}>
        <EditField
          label="Name"
          value="Camera reviews 2026"
        />
        <EditField
          label="Goal"
          value={goalEmpty ? '' : 'A buyer’s-guide video before the holidays'}
          placeholder="What are you building toward?"
          focused={goalFocused}
          multiline
        />
        <DerivedTopics topics={['tech', 'content']} />
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// RULES PANEL — the decisions this screen encodes, for the dev/spec.
// ─────────────────────────────────────────────────────────────
function EditRulesPanel() {
  const cell = { padding: '0 0 18px' };
  const eyebrow = { fontSize: 11, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 6 };
  const body = { fontSize: 13.5, color: PX.ink2, lineHeight: 1.55, letterSpacing: -0.05 };
  const code = { fontFamily: PX.mono, fontSize: 12.5, color: PX.ink };
  return (
    <div style={{
      width: '100%', height: '100%', background: PX.paper, padding: 30,
      fontFamily: PX.sans, color: PX.ink, overflow: 'hidden',
    }}>
      <div style={{ fontFamily: PX.serif, fontSize: 25, fontWeight: 400, letterSpacing: -0.4, marginBottom: 4 }}>
        Editing a project
      </div>
      <div style={{ fontSize: 13, color: PX.ink3, marginBottom: 22, lineHeight: 1.5 }}>
        Two rules: how an editable field announces itself, and why topics aren’t one of them.
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0 28px' }}>
        <div style={cell}>
          <div style={eyebrow}>Topics are derived, not edited</div>
          <div style={body}>
            A project’s topics are the union of the topics of the memories inside it. The Edit screen shows them <strong>read-only</strong> (dashed container, no add control, no ✕) with one line: <em>“these come from the memories in this project.”</em> To change them, change the memories. Matches the locked many-to-many model — topic ⟷ project is derived, never set.
          </div>
        </div>
        <div style={cell}>
          <div style={eyebrow}>A field must look like a field at rest</div>
          <div style={body}>
            The container carries the affordance — filled card surface + real boundary — <strong>before</strong> any focus. Never a bare outline that reads as a divider. The old Goal box failed this: a faint outline with grey text read as a label, not an input.
          </div>
        </div>
        <div style={cell}>
          <div style={eyebrow}>Label ≠ placeholder</div>
          <div style={body}>
            Eyebrow label is <code style={code}>UPPERCASE</code> tracked <code style={code}>ink3</code> above the field — unmistakably a label. Placeholder is sentence-case <code style={code}>ink3</code> inside the field, stating intent: <em>“What are you building toward?”</em> Two different jobs, never the same grey doing both.
          </div>
        </div>
        <div style={cell}>
          <div style={eyebrow}>Empty state says intent; no helper line</div>
          <div style={body}>
            Because the placeholder is the question, the old separate caption (<em>“What are you building toward? A video, a post…”</em>) is redundant and removed. One true thing, in the field, instead of a label plus a hint below.
          </div>
        </div>
        <div style={cell}>
          <div style={eyebrow}>Full-height target, 44 min</div>
          <div style={body}>
            Tapping anywhere in the field focuses it — not just the glyphs. The “had to tap a few times” bug was a text-sized target on a centered placeholder.
          </div>
        </div>
        <div style={cell}>
          <div style={eyebrow}>Focus is identical everywhere</div>
          <div style={body}>
            Every field focuses the same way: ochre ring + caret, immediately. Whatever Name does, Goal does. Consistency <em>is</em> the affordance — the user learns one behavior, not one per field.
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  EditField, DerivedTopics, ScrEditProject, EditRulesPanel,
});

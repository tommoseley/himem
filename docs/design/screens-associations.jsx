// screens-associations.jsx
// UNIFIED MANAGED-CHIP MODEL — Topics · Mentions · Projects
//
// The problem: the same act (manage a memory's many-to-many associations)
// had four different mechanisms — topics tap-to-toggle in a sheet, mentions
// inline ✕-pill + inline text, projects no-inline-remove + toolbar folder-plus,
// and (from the project view) a bottom "Remove from X" button.
//
// The model (locked July 17 2026):
//   READ STATE  — filled pills, NAVIGABLE (tap a topic → filter; a project →
//                 open it; a mention → its mentions view). One dashed "Edit"
//                 per section. Read chips are NEVER individually removable inline
//                 (that's the accidental-tap risk, and it collides with tap-to-
//                 navigate).
//   MANAGE STATE — one sheet per type, structurally identical: "ON THIS MEMORY"
//                 (tap a chip → removes, drops back to library) · "Add a new…"
//                 field · "FROM YOUR LIBRARY" (tap → adds). ONE removal idiom
//                 (tap-to-deselect) across all three — so mentions are
//                 library-backed (recurring people are a library).
//   GLYPH RULE   — the leading DOT means "a palette-coloured topic" only.
//                 Topics = ochre dot · Mentions = person glyph · Projects =
//                 folder glyph. (Fixes the off-standard mention dot.)
//   EXCEPTION    — a contextual "Remove from this project" shortcut stays when
//                 viewing a memory THROUGH a specific project. General
//                 management still routes through the sheet.

// ── kinds ───────────────────────────────────────────────────
// glyph: 'topic' (ochre dot) · 'mention' (person) · 'project' (folder)
function KindGlyph({ kind, color }) {
  if (kind === 'topic') return <span style={{ width: 7, height: 7, borderRadius: 4, background: color, flexShrink: 0 }} />;
  if (kind === 'mention') return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
      <circle cx="12" cy="8" r="4" /><path d="M4 21v-1a6 6 0 016-6h4a6 6 0 016 6v1" />
    </svg>
  );
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
      <path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z" />
    </svg>
  );
}

// a chip in any of the section states
// state: 'set' (assigned, read — navigable) · 'pick' (selected in manage,
//        tap to remove) · 'off' (in library, tap to add) · 'new' (AI-coined) ·
//        'del' (library edit mode — tap the red minus to delete the vocabulary
//               entry entirely, everywhere)
function AssocChip({ label, kind = 'topic', state = 'set' }) {
  const off = state === 'off';
  const del = state === 'del';
  const isNew = state === 'new';
  const glyphColor = (off || del) ? PX.ink4 : (kind === 'topic' ? PX.accent : (isNew ? PX.ai : PX.ink2));
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 7,
      minHeight: 40, boxSizing: 'border-box',
      fontSize: 14, fontWeight: 500, letterSpacing: -0.1,
      color: (off || del) ? PX.ink3 : (isNew ? PX.ai : PX.ink),
      background: (off || del) ? 'transparent' : (isNew ? PX.aiTint : PX.wash1),
      border: '1px solid ' + ((off || del) ? PX.hairline : (isNew ? PX.ai : 'transparent')),
      borderStyle: isNew ? 'dashed' : 'solid',
      padding: '0 15px', borderRadius: 12,
    }}>
      {del && (
        <span style={{ width: 17, height: 17, borderRadius: 9, background: PX.danger, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginLeft: -4 }}>
          <svg width="9" height="9" viewBox="0 0 12 12" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round"><path d="M3 6h6" /></svg>
        </span>
      )}
      <KindGlyph kind={kind} color={glyphColor} />
      {label}
      {isNew && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.5, textTransform: 'uppercase', color: PX.ai, marginLeft: 1 }}>New</span>}
      {state === 'pick' && <Check size={13} color={PX.accent} />}
    </span>
  );
}

// dashed "Edit" affordance (read state) — the ONE way into manage
function EditChip({ label = 'Edit' }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      minHeight: 40, boxSizing: 'border-box',
      fontSize: 14, fontWeight: 600, color: PX.accent,
      border: '1px dashed ' + PX.accent, borderRadius: 12, padding: '0 15px', cursor: 'pointer',
    }}>
      <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10" /></svg>
      {label}
    </span>
  );
}

// a read-state section (label + navigable chips + one Edit)
function AssocSection({ label, kind, chips }) {
  return (
    <div>
      <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>{label}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>
        {chips.map(c => <AssocChip key={c} label={c} kind={kind} state="set" />)}
        <EditChip />
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 1 · READ STATE — one memory, three identical managed-chip sections
// ═════════════════════════════════════════════════════════════
function ScrMemoryAssociations() {
  return (
    <div style={{ width: 340, minHeight: 760, background: PX.paper, fontFamily: PX.sans, color: PX.ink, overflow: 'hidden', paddingBottom: 26 }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span><span style={{ fontSize: 11 }}>●●●</span>
      </div>
      <div style={{ padding: '6px 18px 8px', color: PX.accent, fontSize: 15, display: 'flex', alignItems: 'center', gap: 3 }}>
        <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7" /></svg>
        Today
      </div>
      <div style={{ padding: '0 18px', display: 'flex', flexDirection: 'column', gap: 18 }}>
        <div style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 27, lineHeight: 1.12, letterSpacing: -0.5, color: PX.ink }}>
          Together at Kingfisher Wharf
        </div>
        <div style={{ fontSize: 13, color: PX.ink3, marginTop: -8 }}>Fri Jul 17 · 1:02 PM</div>

        {/* three sections — identical shape */}
        <div style={{ borderTop: '1px solid ' + PX.divider, paddingTop: 16 }}>
          <AssocSection label="Topics" kind="topic" chips={['Travel', 'Food']} />
        </div>
        <AssocSection label="Mentions" kind="mention" chips={['Darlene', 'Henry McMaster']} />
        <AssocSection label="Projects" kind="project" chips={['Foodies!', 'Together here']} />

        <div style={{ fontSize: 11.5, color: PX.ink3, lineHeight: 1.5, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 12, padding: '11px 13px', marginTop: 2 }}>
          Every chip taps through to where it lives — a topic filters, a project opens, a mention shows its people. <strong style={{ color: PX.ink2, fontWeight: 600 }}>Edit</strong> is the one way to add or remove.
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 2 · MANAGE SHEET — one structure, three types
// ═════════════════════════════════════════════════════════════
function ManageSheet({ title, kind, addLabel, onMemory, library, note, editing, confirm }) {
  const behind = <div style={{ width: 340, height: 735, background: PX.paper }} />;
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="82%">
        <div style={{ padding: '14px 20px 20px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ display: 'flex', alignItems: 'center' }}>
            <span style={{ fontSize: 15, color: PX.ink2 }}>Cancel</span>
            <span style={{ flex: 1, textAlign: 'center', fontSize: 15, fontWeight: 600, color: PX.ink }}>{title}</span>
            <span style={{ fontSize: 15, fontWeight: 700, color: PX.accent }}>Done</span>
          </div>

          <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, margin: '14px 0 16px' }}>{note}</div>

          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>On this memory</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginBottom: 18 }}>
            {onMemory.map(l => <AssocChip key={l} label={l} kind={kind} state="pick" />)}
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 9, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 11, padding: '0 13px', height: 46, marginBottom: 18 }}>
            <svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke={PX.ink3} strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10" /></svg>
            <span style={{ fontSize: 14.5, color: PX.ink3 }}>{addLabel}</span>
          </div>

          {/* library header carries the Edit / Done toggle for delete-from-library */}
          <div style={{ display: 'flex', alignItems: 'center', marginBottom: 9 }}>
            <span style={{ flex: 1, fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3 }}>From your library</span>
            <span style={{ fontSize: 13, fontWeight: 600, color: editing ? PX.accent : PX.ai }}>{editing ? 'Done' : 'Edit'}</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, overflow: 'auto' }}>
            {library.map(l => <AssocChip key={l} label={l} kind={kind} state={editing ? 'del' : 'off'} />)}
          </div>
          {editing && (
            <div style={{ fontSize: 11.5, color: PX.ink3, lineHeight: 1.45, marginTop: 12, display: 'flex', gap: 7, alignItems: 'flex-start' }}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginTop: 1, flexShrink: 0 }}><circle cx="12" cy="12" r="10" /><path d="M12 16v-4M12 8h.01" /></svg>
              <span>Deleting removes the {kind} from your whole library — and from every memory that uses it. Removing it from just this memory? Tap it above instead.</span>
            </div>
          )}
          <div style={{ flex: 1 }} />
          {confirm && (
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(26,22,18,0.32)', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 22 }}>
              <div style={{ width: 260, background: PX.paper, borderRadius: 18, padding: '20px 20px 16px', boxShadow: '0 20px 50px rgba(0,0,0,0.25)' }}>
                <div style={{ fontFamily: PX.serif, fontSize: 18, color: PX.ink, textAlign: 'center' }}>Delete “{confirm.label}”?</div>
                <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.45, textAlign: 'center', marginTop: 8 }}>
                  Used in <strong style={{ color: PX.ink, fontWeight: 600 }}>{confirm.count} memories</strong>. Deleting removes this {kind} from all of them. The memories themselves are untouched.
                </div>
                <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <div style={{ minHeight: 44, borderRadius: 11, background: PX.danger, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14.5, fontWeight: 600 }}>Delete from library</div>
                  <div style={{ minHeight: 44, borderRadius: 11, border: '1px solid ' + PX.hairline, color: PX.ink2, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14.5, fontWeight: 600 }}>Cancel</div>
                </div>
              </div>
            </div>
          )}
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

function ScrManageTopicsU() {
  return <ManageSheet title="Topics" kind="topic" addLabel="Add a new topic…"
    onMemory={['Travel', 'Food']}
    library={['Work', 'Garden', 'How We Work', 'Health', 'Ideas', 'Money', 'Cooking', 'Restaurant']}
    note="Pick from your library, or add a new topic. Picking the right existing one keeps your topics useful as filters." />;
}
function ScrManageMentionsU() {
  return <ManageSheet title="Mentions" kind="mention" addLabel="Add a new person…"
    onMemory={['Darlene', 'Henry McMaster']}
    library={['Lindsay Graham', 'Judi', 'Ben', 'Mom', 'Dad', 'Alton Brown']}
    note="Pick someone you've mentioned before, or add a new name. Reusing a name keeps people searchable across memories." />;
}
function ScrManageProjectsU() {
  return <ManageSheet title="Projects" kind="project" addLabel="New project…"
    onMemory={['Foodies!', 'Together here']}
    library={['Building HiMem', 'Montana Trip', 'Field Notes', 'Recipes']}
    note="Add this memory to a project, or start a new one. A project connects memories toward something you're building." />;
}

// library Edit mode — delete a vocabulary entry entirely (red minus per chip)
function ScrManageTopicsEditing() {
  return <ManageSheet title="Topics" kind="topic" addLabel="Add a new topic…" editing
    onMemory={['Travel', 'Food']}
    library={['Work', 'Garden', 'How We Work', 'Health', 'Ideas', 'Dhdhdh']}
    note="Pick from your library, or add a new topic. Picking the right existing one keeps your topics useful as filters." />;
}
// the impact confirm — deleting a library entry warns how many memories use it
function ScrDeleteFromLibraryConfirm() {
  return <ManageSheet title="Topics" kind="topic" addLabel="Add a new topic…" editing
    confirm={{ label: 'Garden', count: 4 }}
    onMemory={['Travel', 'Food']}
    library={['Work', 'Garden', 'How We Work', 'Health', 'Ideas', 'Dhdhdh']}
    note="Pick from your library, or add a new topic. Picking the right existing one keeps your topics useful as filters." />;
}

// ═════════════════════════════════════════════════════════════
// 3 · CONTEXTUAL EXCEPTION — memory opened THROUGH a project
// The one place a single de-associate lives outside the sheet:
// "Remove from this project" as a bottom fate button.
// ═════════════════════════════════════════════════════════════
function ScrMemberThroughProject() {
  return (
    <div style={{ width: 340, minHeight: 760, background: PX.paper, fontFamily: PX.sans, color: PX.ink, overflow: 'hidden', paddingBottom: 26 }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span><span style={{ fontSize: 11 }}>●●●</span>
      </div>
      <div style={{ padding: '6px 18px 8px', color: PX.accent, fontSize: 15, display: 'flex', alignItems: 'center', gap: 3 }}>
        <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7" /></svg>
        Foodies!
      </div>
      <div style={{ padding: '0 18px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 26, lineHeight: 1.12, letterSpacing: -0.5 }}>
          Together at Kingfisher Wharf
        </div>
        <div style={{ borderTop: '1px solid ' + PX.divider, paddingTop: 14 }}>
          <AssocSection label="Projects" kind="project" chips={['Foodies!', 'Together here']} />
        </div>
        <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 12, padding: '11px 13px', fontSize: 13, color: PX.ink2, lineHeight: 1.4 }}>
          The full memory (clips, topics, mentions) lives here too — this is the canonical Memory Detail, opened in the project's context.
        </div>
        <div style={{ flex: 1, minHeight: 30 }} />
        {/* the contextual exception — de-associate from THIS project */}
        <div style={{
          minHeight: 50, borderRadius: 13, border: '1px solid ' + PX.accent, color: PX.accent,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          fontSize: 15, fontWeight: 600, letterSpacing: -0.1,
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><polyline points="23 4 23 10 17 10" /><path d="M20.5 15a9 9 0 11-2.1-9.4L23 10" /></svg>
          Remove from Foodies!
        </div>
        <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 8, lineHeight: 1.45 }}>
          Leaves this project only. The memory stays in your library, and in any other project.
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// spec card
// ═════════════════════════════════════════════════════════════
function AssocSpecCard() {
  const row = { padding: '13px 18px', borderBottom: '1px solid ' + PX.hairline };
  const eyebrow = { fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.accent, marginBottom: 5 };
  const body = { fontSize: 13.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 };
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, overflow: 'hidden', fontFamily: PX.sans }}>
      <div style={{ padding: '16px 18px 12px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 21, color: PX.ink, letterSpacing: -0.3 }}>One model for associations</div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 3 }}>Topics, mentions, and projects behave identically.</div>
      </div>
      <div style={row}><div style={eyebrow}>Read = navigate, never remove</div><div style={body}>Filled pills tap through to where they live — a topic filters, a project opens, a mention shows its people. No inline ✕; read chips are never individually removable (kills the accidental-tap, frees the tap for navigation).</div></div>
      <div style={row}><div style={eyebrow}>One dashed Edit per section</div><div style={body}>The single way in to add or remove. Opens the manage sheet for that type.</div></div>
      <div style={row}><div style={eyebrow}>One manage sheet, three types</div><div style={body}><strong style={{ color: PX.ink2, fontWeight: 600 }}>On this memory</strong> (tap a chip to remove) · <strong style={{ color: PX.ink2, fontWeight: 600 }}>Add a new…</strong> · <strong style={{ color: PX.ink2, fontWeight: 600 }}>From your library</strong> (tap to add). One removal idiom everywhere — so mentions are library-backed (recurring people are a library).</div></div>
      <div style={row}><div style={eyebrow}>Glyph rule</div><div style={body}>The leading <strong style={{ color: PX.accent, fontWeight: 600 }}>dot</strong> means a palette-coloured topic — topics only. Mentions use a person glyph, projects a folder glyph. (Retires the off-standard mention dot.)</div></div>
      <div style={row}><div style={eyebrow}>The library feeds the AI</div><div style={body}>Every organize/reorganize pass is handed the existing library (topics <em>and</em> mentions) so it <strong style={{ color: PX.ink2, fontWeight: 600 }}>prefers reusing an entry</strong> over coining a near-duplicate — it coins a new one only when nothing fits, and flags it <strong style={{ color: PX.ai, fontWeight: 600 }}>New</strong>. This is what keeps the library a clean filter (no Garden / Gardening / Yard). <em>(Topics already pass the palette; mentions join it.)</em></div></div>
      <div style={row}><div style={eyebrow}>Deselect vs. delete</div><div style={body}>Tapping a chip in <strong style={{ color: PX.ink2, fontWeight: 600 }}>On this memory</strong> removes it from <em>this</em> memory (stays in the library). To purge the vocabulary entry entirely, the library's <strong style={{ color: PX.ink2, fontWeight: 600 }}>Edit</strong> toggle reveals a red minus per chip — deleting warns how many memories use it (mirrors clip-delete's live count). The memories themselves are never touched.</div></div>
      <div style={{ ...row, borderBottom: 'none' }}><div style={eyebrow}>One exception, named</div><div style={body}>Viewing a memory <em>through</em> a project keeps a contextual <strong style={{ color: PX.accent, fontWeight: 600 }}>Remove from this project</strong> shortcut at the bottom. General management still routes through the sheet. Retires the toolbar folder-plus and the two-add-paths redundancy. <em>(Projects delete via the project's own full-width Delete Project, not the library minus.)</em></div></div>
    </div>
  );
}

Object.assign(window, {
  KindGlyph, AssocChip, EditChip, AssocSection,
  ScrMemoryAssociations, ManageSheet,
  ScrManageTopicsU, ScrManageMentionsU, ScrManageProjectsU,
  ScrManageTopicsEditing, ScrDeleteFromLibraryConfirm,
  ScrMemberThroughProject, AssocSpecCard,
});

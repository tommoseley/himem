// screens-topics.jsx
// TOPIC LIFECYCLE — the surfaces that give topics a clear, visible life.
//
// The problem this solves: when Reorganize was scoped to Title + Summary,
// topics lost their home — suggested by the model but never surfaced for the
// user to see, approve, or correct. And the on-device path invented fresh
// names every pass, fragmenting the palette (Garden / Gardening / Plants / Yard).
//
// Locked model (GPT + CC + design aligned, June 2026):
//   1 · First organize  — AI suggests title, summary, topics, mentions.
//        Topics review section: existing-palette chips pre-selected; any
//        genuinely-new topic is clearly marked NEW. User accepts.
//   2 · Reorganize       — Title + Summary only. Never touches topics/mentions.
//   3 · Memory detail    — a PERSISTENT topic chip row under the summary,
//        tappable to manage. Topic changes are deliberate user actions.
//   4 · Palette rule     — prefer an existing topic when one fits; coin a new
//        one only when the memory clearly doesn't fit. New = flagged.
//
// Color: topics are user-owned organization → ochre dots on wash chips.
// The AI-blue moment is only the "suggested / NEW" flag during review.

// ── a topic chip ─────────────────────────────────────────────
// state: 'set' (assigned, on the memory) · 'new' (AI-coined, flagged) ·
//        'pick' (selectable in manage) · 'off' (selectable, unselected)
function TopicChip({ label, state = 'set', onable }) {
  const isNew = state === 'new';
  const off = state === 'off';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      fontSize: 12.5, fontWeight: 500, letterSpacing: -0.05,
      color: off ? PX.ink3 : (isNew ? PX.ai : PX.ink),
      background: off ? 'transparent' : (isNew ? PX.aiTint : PX.wash1),
      border: '1px solid ' + (off ? PX.hairline : (isNew ? PX.ai : 'transparent')),
      borderStyle: isNew ? 'dashed' : 'solid',
      padding: '5px 11px', borderRadius: 14,
    }}>
      {isNew
        ? <Spark size={11} color={PX.ai} />
        : <span style={{ width: 6, height: 6, borderRadius: 3, background: off ? PX.ink4 : PX.accent, flexShrink: 0 }} />}
      {label}
      {isNew && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.5, textTransform: 'uppercase', color: PX.ai, marginLeft: 1 }}>New</span>}
      {state === 'pick' && <Check size={11} color={PX.accent} />}
    </span>
  );
}

// ═════════════════════════════════════════════════════════════
// 1 · MEMORY DETAIL — the persistent topic chip row (the missing home)
// ═════════════════════════════════════════════════════════════
function TopicRow({ topics, manage }) {
  return (
    <div style={{ margin: '0 14px' }}>
      <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>Topics</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, alignItems: 'center' }}>
        {topics.map(t => <TopicChip key={t} label={t} state="set" />)}
        {manage && (
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            fontSize: 12.5, fontWeight: 600, color: PX.accent,
            border: '1px dashed ' + PX.accent, borderRadius: 14, padding: '5px 11px', cursor: 'pointer',
          }}>
            <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10" /></svg>
            Edit
          </span>
        )}
      </div>
    </div>
  );
}

function ScrMemoryWithTopics() {
  return (
    <div style={{ width: 340, minHeight: 900, background: PX.paper, fontFamily: PX.sans, color: PX.ink, overflow: 'hidden', paddingBottom: 30 }}>
      <div style={{ padding: '14px 22px 4px', display: 'flex', justifyContent: 'space-between', fontSize: 13, fontWeight: 600 }}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span><span style={{ fontSize: 11 }}>●●●</span>
      </div>
      <div style={{ padding: '6px 18px 8px', color: PX.accent, fontSize: 15, display: 'flex', alignItems: 'center', gap: 3 }}>
        <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7" /></svg>
        Wednesday, June 3
      </div>
      <div style={{ padding: '0 18px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 27, lineHeight: 1.12, letterSpacing: -0.5, color: PX.ink }}>
          Travel planning: Georgia, Vermont, and Maine
        </div>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 7 }}>
            <Spark size={13} color={PX.ai} />
            <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ai }}>Summary</span>
          </div>
          <div style={{ fontSize: 14.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 }}>
            Travel-planning entry linked to potential visits in Georgia and Vermont, with a confirmed trip to Maine in two weeks to see family.
          </div>
        </div>
        {/* the persistent topic chip row — directly under the summary */}
        <TopicRow topics={['Travel', 'Family']} manage />
        <div style={{ borderTop: '1px solid ' + PX.divider, paddingTop: 14 }}>
          <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, padding: '11px 13px' }}>
            <div style={{ fontSize: 11.5, color: PX.ink3, marginBottom: 4 }}>Wed Jun 3 · 9:47 PM · Bluffton</div>
            <div style={{ fontSize: 14.5, color: PX.ink, lineHeight: 1.4 }}>Places to visit, Helen, Georgia.</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// 2 · FIRST-ORGANIZE REVIEW — Topics section (existing + flagged new)
// Part of the draft→review→organized sheet. Topics live here, NOT in
// reorganize. Existing-palette chips are pre-selected; a genuinely-new
// topic is marked NEW so the user grows the vocabulary on purpose.
// ═════════════════════════════════════════════════════════════
function ScrOrganizeReviewTopics() {
  const behind = (
    <div style={{ width: 340, height: 735, background: PX.paper }} />
  );
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="86%">
        <div style={{ padding: '14px 20px 20px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <span style={{
            alignSelf: 'flex-start', display: 'inline-flex', alignItems: 'center', gap: 5,
            fontSize: 11.5, fontWeight: 600, color: PX.ai, background: PX.aiTint,
            border: '1px dashed ' + PX.ai, padding: '3px 9px', borderRadius: 13,
          }}><Spark size={11} /> Draft organized</span>

          <div style={{ fontFamily: PX.serif, fontSize: 22, color: PX.ink, letterSpacing: -0.3, marginTop: 12 }}>A draft from your device.</div>
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginTop: 8 }}>
            Review the suggestions and keep what fits. Topics from your library are already picked; anything new is marked.
          </div>

          <div style={{ marginTop: 16, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, overflow: 'hidden' }}>
            {/* title + summary rows (compact — the focus here is Topics) */}
            <div style={{ padding: '11px 14px', borderBottom: '1px solid ' + PX.divider }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ai, marginBottom: 4 }}>Title</div>
              <div style={{ fontSize: 14, color: PX.ink, fontFamily: PX.serif }}>Travel planning: Georgia, Vermont, and Maine</div>
            </div>
            <div style={{ padding: '11px 14px', borderBottom: '1px solid ' + PX.divider }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ai, marginBottom: 4 }}>Summary</div>
              <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.45 }}>A confirmed trip to Maine in two weeks to see family, plus places you’re weighing in Georgia and Vermont.</div>
            </div>
            {/* TOPICS — the heart of this screen */}
            <div style={{ padding: '13px 14px' }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ai, marginBottom: 9 }}>Topics</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginBottom: 10 }}>
                <TopicChip label="Travel" state="set" />
                <TopicChip label="Family" state="set" />
                <TopicChip label="New England" state="new" />
              </div>
              <div style={{ fontSize: 11.5, color: PX.ink3, lineHeight: 1.45, display: 'flex', gap: 7, alignItems: 'flex-start' }}>
                <Spark size={12} color={PX.ai} />
                <span><strong style={{ color: PX.ink2, fontWeight: 600 }}>Travel</strong> and <strong style={{ color: PX.ink2, fontWeight: 600 }}>Family</strong> are from your library. <strong style={{ color: PX.ai, fontWeight: 600 }}>New England</strong> is new — tap to drop it if you’d rather not start a topic.</span>
              </div>
            </div>
          </div>

          <div style={{ flex: 1, minHeight: 10 }} />
          <Btn kind="accent">Keep all</Btn>
          <div style={{ height: 8 }} />
          <Btn kind="secondary" size="md">Adjust</Btn>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ═════════════════════════════════════════════════════════════
// 3 · MANAGE TOPICS — deliberate, independent of reorganize
// Reached by tapping the chip row's Edit. Existing palette to pick from,
// a field to add a new one. This is where topic changes are made — a
// user action, never an AI side effect.
// ═════════════════════════════════════════════════════════════
function ScrManageTopics() {
  const behind = <div style={{ width: 340, height: 735, background: PX.paper }} />;
  const palette = [
    ['Travel', 'pick'], ['Family', 'pick'], ['Work', 'off'], ['Garden', 'off'],
    ['How We Work', 'off'], ['Health', 'off'], ['Ideas', 'off'], ['Money', 'off'],
  ];
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="80%">
        <div style={{ padding: '14px 20px 20px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{ display: 'flex', alignItems: 'center' }}>
            <span style={{ fontSize: 15, color: PX.ink2 }}>Cancel</span>
            <span style={{ flex: 1, textAlign: 'center', fontSize: 15, fontWeight: 600, color: PX.ink }}>Topics</span>
            <span style={{ fontSize: 15, fontWeight: 700, color: PX.accent }}>Done</span>
          </div>

          <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, margin: '14px 0 14px' }}>
            Pick from your library, or add a new topic. Picking the right existing one keeps your topics useful as filters.
          </div>

          {/* current selection */}
          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>On this memory</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginBottom: 18 }}>
            <TopicChip label="Travel" state="pick" />
            <TopicChip label="Family" state="pick" />
          </div>

          {/* add new */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 11, padding: '0 13px', height: 46, marginBottom: 18 }}>
            <svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke={PX.ink3} strokeWidth="2" strokeLinecap="round"><path d="M7 2v10M2 7h10" /></svg>
            <span style={{ fontSize: 14.5, color: PX.ink3 }}>Add a new topic…</span>
          </div>

          {/* existing palette */}
          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 9 }}>From your library</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, overflow: 'auto' }}>
            {palette.map(([l, s]) => <TopicChip key={l} label={l} state={s} />)}
          </div>
          <div style={{ flex: 1 }} />
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ═════════════════════════════════════════════════════════════
// note — the palette-discipline rule, visible on the canvas
// ═════════════════════════════════════════════════════════════
function TopicSpecCard() {
  const row = { padding: '13px 18px', borderBottom: '1px solid ' + PX.hairline };
  const eyebrow = { fontSize: 10, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.accent, marginBottom: 5 };
  const body = { fontSize: 13.5, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1 };
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, overflow: 'hidden', fontFamily: PX.sans }}>
      <div style={{ padding: '16px 18px 12px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 21, color: PX.ink, letterSpacing: -0.3 }}>How topics work</div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 3 }}>A visible home, a review moment, and palette discipline.</div>
      </div>
      <div style={row}><div style={eyebrow}>Prefer the existing palette</div><div style={body}>The model picks an existing topic when one fits, and coins a <strong style={{ color: PX.ai, fontWeight: 600 }}>new</strong> one only when the memory clearly doesn’t. New topics are flagged so the palette grows on purpose — no Garden / Gardening / Yard sprawl. <em>(Fixes the on-device path, which currently ignores the existing list.)</em></div></div>
      <div style={row}><div style={eyebrow}>First organize reviews them</div><div style={body}>Topics are accepted in the draft review sheet, alongside title and summary. Existing chips pre-selected; new ones marked.</div></div>
      <div style={row}><div style={eyebrow}>Reorganize never touches them</div><div style={body}>Reorganize stays Title + Summary only. Topics are managed independently — they’re never churned by a wording refresh.</div></div>
      <div style={{ ...row, borderBottom: 'none' }}><div style={eyebrow}>A persistent home</div><div style={body}>A topic chip row lives under the summary on every memory. Changes are deliberate user taps, never an AI side effect.</div></div>
    </div>
  );
}

Object.assign(window, {
  TopicChip, TopicRow, ScrMemoryWithTopics,
  ScrOrganizeReviewTopics, ScrManageTopics, TopicSpecCard,
});

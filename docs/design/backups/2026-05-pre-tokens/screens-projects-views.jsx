// screens-projects-views.jsx
// The four MVP project screens.

// ─────────────────────────────────────────────────────────────
// 1. Projects tab — populated. De-blued chrome, no FAB.
// ─────────────────────────────────────────────────────────────
function ScrProjectsList() {
  return (
    <PhoneScreen>
      <ProjectsTabHeader activeTopic="Content" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <ProjectCard
          title="Building Himem"
          topics={['content','tech']}
          count={14}
          date="May 13"
        />
        <ProjectCard
          title="AI essay — second draft"
          topics={['content','howWeWork']}
          count={6}
          date="May 9"
        />
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '12px 4px 4px', color: PX.accent,
          fontSize: 15, fontWeight: 500, letterSpacing: -0.2,
        }}>
          <span style={{
            width: 22, height: 22, borderRadius: 11,
            background: PX.accent, color: '#fff',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Plus size={12} color="#fff" />
          </span>
          New project
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 2. Project detail — pre-coalesce. 3+ memories. Coalesce affordance visible.
// ─────────────────────────────────────────────────────────────
function ScrProjectPreCoalesce() {
  return (
    <PhoneScreen>
      <ProjectDetailNav />
      <ProjectTitleBlock
        title="Building Himem"
        topics={['content','tech']}
        count="14 memories · started March 28"
        goal="A capture-and-organize app for content creators."
      />

      {/* Coalesce affordance — AI blue, intentional, not pushy */}
      <div style={{ padding: '16px 14px 10px' }}>
        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline,
          borderRadius: 14, padding: '14px 16px',
          display: 'flex', alignItems: 'center', gap: 12,
        }}>
          <div style={{
            width: 36, height: 36, borderRadius: 10, background: PX.aiTint, color: PX.ai,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <Spark size={18} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>
              Find the thread
            </div>
            <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 2, lineHeight: 1.35 }}>
              A short summary across these memories. 1 assist.
            </div>
          </div>
          <button style={{
            height: 30, padding: '0 14px', borderRadius: 15,
            background: PX.ai, color: '#fff', border: 'none',
            fontSize: 13, fontWeight: 600, letterSpacing: -0.1, cursor: 'default',
          }}>Run</button>
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', padding: '4px 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <ProjectMemoryCard
          title="Inspiration capture app concept"
          time="May 13 · 2:22 PM"
          audio={2} photo={1}
          topics={['content','tech']}
        />
        <ProjectMemoryCard
          title="Watch-first capture, no transcription"
          time="May 11 · 9:04 AM"
          audio={1}
          topics={['tech']}
        />
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 3. Project detail — after a Project Assist run.
//    AI-blue summary card + suggested-memories card.
// ─────────────────────────────────────────────────────────────
function ScrProjectPostCoalesce() {
  return (
    <PhoneScreen>
      <ProjectDetailNav />
      <ProjectTitleBlock
        title="Building Himem"
        topics={['content','tech']}
        count="14 memories · summarized May 18"
      />

      {/* Project summary card — AI blue, Honest Label voice, second-person */}
      <div style={{ padding: '16px 14px 8px' }}>
        <div style={{
          background: PX.card, border: '1px solid ' + PX.aiTint,
          borderRadius: 14, padding: '14px 16px 16px',
          boxShadow: '0 1px 0 ' + PX.aiTint,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
            <span style={{ color: PX.ai, display: 'inline-flex' }}>
              <Spark size={13} />
            </span>
            <span style={{
              fontSize: 10.5, fontWeight: 700, color: PX.ai,
              letterSpacing: 1.6, textTransform: 'uppercase',
            }}>Project summary</span>
            <span style={{ flex: 1 }} />
            <span style={{ fontSize: 11, color: PX.ink3 }}>Organized · today</span>
          </div>
          <div style={{
            fontFamily: PX.serif, fontSize: 16, lineHeight: 1.45, color: PX.ink,
            letterSpacing: -0.1,
          }}>
            You're building a multi-format capture app for content creators — voice and photo on
            the watch, organized on the phone. You've settled on watch-only capture and a tiered
            pricing model with one project free.
          </div>
          <div style={{ display: 'flex', gap: 16, marginTop: 14, fontSize: 13, fontWeight: 500 }}>
            <span style={{ color: PX.ai }}>Edit</span>
            <span style={{ color: PX.ink2 }}>Regenerate</span>
            <span style={{ flex: 1 }} />
            <span style={{ color: PX.ink3, fontSize: 11.5 }}>14 of 14 memories</span>
          </div>
        </div>
      </div>

      {/* Suggested memories card — same AI-blue family, lighter weight */}
      <div style={{ padding: '0 14px 10px' }}>
        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline,
          borderRadius: 14, padding: '13px 16px',
          display: 'flex', alignItems: 'center', gap: 12,
        }}>
          <div style={{
            width: 32, height: 32, borderRadius: 9, background: PX.aiTint, color: PX.ai,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
              <path d="M2 4.5h12M2 8h12M2 11.5h8"/>
              <circle cx="13" cy="11.5" r="2" fill={PX.ai} stroke="none"/>
            </svg>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>
              3 memories may belong here
            </div>
            <div style={{ fontSize: 11.5, color: PX.ink3, marginTop: 2, lineHeight: 1.35 }}>
              From elsewhere in your memories.
            </div>
          </div>
          <span style={{ fontSize: 13, fontWeight: 600, color: PX.ai, letterSpacing: -0.1 }}>
            Review
          </span>
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', padding: '4px 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{
          fontSize: 10.5, fontWeight: 700, color: PX.ink3, letterSpacing: 1.6,
          textTransform: 'uppercase', padding: '2px 4px',
        }}>Memories</div>
        <ProjectMemoryCard
          title="Inspiration capture app concept"
          time="May 13 · 2:22 PM"
          audio={2} photo={1}
          topics={['content','tech']}
        />
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 4. Free user taps Coalesce → Plus upsell sheet over the project
// ─────────────────────────────────────────────────────────────
function ScrCoalesceUpsell() {
  const behind = (
    <PhoneScreen>
      <ProjectDetailNav />
      <ProjectTitleBlock
        title="Building Himem"
        topics={['content','tech']}
        count="14 memories"
        goal="A capture-and-organize app for content creators."
      />
    </PhoneScreen>
  );
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="58%">
        <div style={{ padding: '14px 22px 26px', display: 'flex', flexDirection: 'column', height: '100%' }}>
          <div style={{
            width: 36, height: 36, borderRadius: 10, background: PX.aiTint, color: PX.ai,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16,
          }}>
            <Spark size={20} />
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 24, lineHeight: 1.15, letterSpacing: -0.3, color: PX.ink, marginBottom: 10 }}>
            You've used your starter project summary.
          </div>
          <div style={{ fontSize: 14, color: PX.ink2, lineHeight: 1.5, marginBottom: 8 }}>
            Plus lets HiMem keep finding threads — across this project and any others you start.
            Edit, regenerate, or ignore each one.
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.5 }}>
            Free keeps storing and capturing forever. Your starter project, and its summary, stay yours.
          </div>

          <div style={{ flex: 1 }} />

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <Btn kind="primary">Upgrade to Plus · $4.99/mo</Btn>
            <Btn kind="ghost" size="md">Not now</Btn>
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 5. Suggested-memories review sheet.
// AI proposes, the user decides. No auto-add.
// ─────────────────────────────────────────────────────────────
function SuggestionRow({ title, date, why, confidence = 'likely', selected, sub }) {
  const tones = {
    likely: { dot: PX.confirmed, label: 'Likely' },
    maybe:  { dot: PX.warn,      label: 'Maybe'  },
  };
  const t = tones[confidence];
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 12,
      padding: '14px 4px 14px 4px',
      borderBottom: '1px solid ' + PX.divider,
    }}>
      <span style={{
        width: 22, height: 22, borderRadius: 11, flexShrink: 0, marginTop: 1,
        border: '1.5px solid ' + (selected ? PX.ai : PX.ink4),
        background: selected ? PX.ai : 'transparent',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {selected && <Check size={12} color="#fff" />}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <span style={{ fontSize: 14.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>{title}</span>
        </div>
        <div style={{ fontSize: 11, color: PX.ink3, marginBottom: 6, fontVariantNumeric: 'tabular-nums' }}>{date}</div>
        <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.45, fontStyle: 'italic', fontFamily: PX.serif }}>
          {why}
        </div>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 8, fontSize: 11, color: PX.ink3, fontWeight: 500, letterSpacing: 0.4 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: t.dot }} />
          {t.label.toUpperCase()} MATCH
        </div>
      </div>
    </div>
  );
}

function ScrSuggestionsReview() {
  const behind = (
    <PhoneScreen>
      <ProjectDetailNav />
      <ProjectTitleBlock
        title="Building Himem"
        topics={['content','tech']}
        count="14 memories"
      />
    </PhoneScreen>
  );
  return (
    <PhoneScreen>
      <Sheet behind={behind} height="88%">
        <div style={{ padding: '8px 18px 14px', borderBottom: '1px solid ' + PX.divider, display: 'flex', alignItems: 'center' }}>
          <span style={{ fontSize: 15, fontWeight: 500, color: PX.ink2, letterSpacing: -0.1 }}>Cancel</span>
          <span style={{ flex: 1 }} />
          <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Suggested</span>
          <span style={{ flex: 1 }} />
          <span style={{ fontSize: 15, fontWeight: 600, color: PX.ai }}>Add 2</span>
        </div>

        <div style={{ padding: '14px 20px 6px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <span style={{ color: PX.ai, display: 'inline-flex' }}>
              <Spark size={13} />
            </span>
            <span style={{
              fontSize: 10.5, fontWeight: 700, color: PX.ai,
              letterSpacing: 1.6, textTransform: 'uppercase',
            }}>From your memories</span>
          </div>
          <div style={{ fontFamily: PX.serif, fontSize: 17, lineHeight: 1.35, color: PX.ink, letterSpacing: -0.2 }}>
            These three may belong in <em>Building Himem</em>.
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 8, lineHeight: 1.5 }}>
            HiMem found these by looking at topics, mentions, and dates — not by reading every word.
            Add the ones that fit; skip the rest.
          </div>
        </div>

        <div style={{ padding: '4px 20px 14px', overflow: 'auto', flex: 1 }}>
          <SuggestionRow
            title="Notes on Studio as creator workspace"
            date="May 12 · 10:14 AM"
            why="Mentions Studio, project synthesis, and creator tooling — the same thread you're pulling on here."
            confidence="likely"
            selected
          />
          <SuggestionRow
            title="Watch capture session feedback"
            date="May 8 · 4:48 PM"
            why="Tagged Technology; mentions watch recording, the central capture surface for this project."
            confidence="likely"
            selected
          />
          <SuggestionRow
            title="AI displacement, historical job patterns"
            date="Apr 22 · 8:31 AM"
            why="Overlaps with broader future-of-work topics, but not directly with the product thread."
            confidence="maybe"
          />
        </div>

        <div style={{ padding: '0 20px 18px', borderTop: '1px solid ' + PX.divider, paddingTop: 12 }}>
          <div style={{ fontSize: 11, color: PX.ink3, textAlign: 'center', lineHeight: 1.5 }}>
            Suggestions are proposals. Nothing gets added until you tap <strong style={{ color: PX.ink2 }}>Add 2</strong>.
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrProjectsList, ScrProjectPreCoalesce, ScrProjectPostCoalesce, ScrCoalesceUpsell, ScrSuggestionsReview,
});

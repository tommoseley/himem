// screens-projects-views.jsx
// The MVP project screens. Audited & locked June 10 2026 against:
//   · No-quota model (no "assists" anywhere) — Pricing · Capture-Connect-Create
//   · Button colour code — ochre = you act, blue = invoke AI (+ trailing ✦)
//   · Projects "AI blue, always" — summary, confidence chips, why-lines, sparkle
//   · 44px touch floor
//   · One vocabulary — "Find the thread" (the internal name "Coalesce" is gone)

// ─────────────────────────────────────────────────────────────
// 1. Projects tab — populated. De-blued chrome, no FAB.
// ─────────────────────────────────────────────────────────────
function ScrProjectsList() {
  return (
    <PhoneScreen>
      <ProjectsTabHeader activeTopic="Content" />
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <ProjectCard
          title="Building HiMem"
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
        {/* New project — ochre action, 44px tap row */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          minHeight: 44, padding: '6px 4px', color: PX.accent,
          fontSize: 15, fontWeight: 500, letterSpacing: -0.2, cursor: 'pointer',
        }}>
          <span style={{
            width: 24, height: 24, borderRadius: 12,
            background: PX.accent, color: PX.accentInk,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Plus size={13} color={PX.accentInk} />
          </span>
          New project
        </div>
      </div>
      <TabBar active="projects" />
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 2. Project detail — before a Project Assist run. 3+ memories.
//    "Find the thread" is a Plus AI action: blue, named, trailing ✦, ≥44px.
//    No quota, no "assist" — running it is just running it.
// ─────────────────────────────────────────────────────────────
function ScrProjectDetail() {
  return (
    <PhoneScreen>
      <ProjectDetailNav />
      <ProjectTitleBlock
        title="Building HiMem"
        topics={['content','tech']}
        count="14 memories · started March 28"
        goal="A capture-and-organize app for content creators."
      />

      {/* Find the thread — AI blue, named feature, trailing sparkle */}
      <div style={{ padding: '16px 14px 10px' }}>
        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline,
          borderRadius: 14, padding: '14px 16px',
          display: 'flex', flexDirection: 'column', gap: 12,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
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
                A short summary across these 14 memories, and others that may belong.
              </div>
            </div>
          </div>
          {/* AI button: blue fill, named feature + trailing ✦, full-width, ≥44px */}
          <button style={{
            height: 46, width: '100%', borderRadius: 12,
            background: PX.ai, color: PX.accentInk, border: 'none',
            fontSize: 14.5, fontWeight: 600, letterSpacing: -0.1, cursor: 'default',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          }}>
            Find the thread
            <Spark size={15} color={PX.accentInk} />
          </button>
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', padding: '4px 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {/* Canonical journal MemoryCard — one definition everywhere (screens-memories.jsx) */}
        <MemoryCard
          title="Inspiration capture app concept"
          time="May 13 · 2:22 PM" place="Marsh Walk"
          media={{ audio: 2, photo: 1 }}
          topics={['content','tech']}
          gist={{ kind: 'summary', text: 'A product idea for capturing creative fragments from Watch, phone, and iPad, then using AI to organize them into scripts, essays, and longer-form projects over time.' }}
        />
        <MemoryCard
          title="Watch-first capture, no transcription"
          time="May 11 · 9:04 AM"
          media={{ audio: 1 }}
          topics={['tech']}
          gist={{ kind: 'excerpt', text: 'The watch should just capture — no transcription on-device, no screen to manage. Audio syncs to the phone and becomes a memory there.' }}
        />
        {/* Delete Project — full-width red, at the very bottom below all content
           (deletion lock). No toolbar trash. Dissolves the project; member
           memories survive. No confirm — the scroll here is the deliberation. */}
        <div style={{
          minHeight: 50, borderRadius: 13, border: '1px solid ' + PX.danger, color: PX.danger,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, marginTop: 6,
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>
          Delete Project
        </div>
        <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 8, lineHeight: 1.45 }}>
          Dissolves this project. The memories stay in your library.
        </div>
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 3. Project detail — after a Project Assist run.
//    AI-blue summary card + suggested-memories card.
// ─────────────────────────────────────────────────────────────
function ScrProjectSummarized() {
  return (
    <PhoneScreen>
      <ProjectDetailNav />
      <ProjectTitleBlock
        title="Building HiMem"
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
            {/* review-state label (AI blue, quiet — not a button) */}
            <span style={{ fontSize: 11, color: PX.ai, fontWeight: 600 }}>Draft · give this a glance</span>
          </div>
          <div style={{
            fontFamily: PX.serif, fontSize: 16, lineHeight: 1.45, color: PX.ink,
            letterSpacing: -0.1,
          }}>
            You're building a multi-format capture app for content creators — voice and photo on
            the watch, organized on the phone. You've settled on watch-only capture and a tiered
            pricing model with three projects free.
          </div>
          {/* Unified editing model: the paragraph is tap-to-edit (no "Edit" link).
             The only action is the AI re-run, as a real blue AI button — not a bare text link. */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 14 }}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 44, padding: '0 15px',
              borderRadius: 12, border: '1.5px solid ' + PX.ai, color: PX.ai,
              fontSize: 13, fontWeight: 600, letterSpacing: -0.1,
            }}>
              Find the thread again <Spark size={13} color={PX.ai} />
            </span>
            <span style={{ flex: 1 }} />
            <span style={{ color: PX.ink3, fontSize: 11.5 }}>14 of 14 memories</span>
          </div>
        </div>
      </div>

      {/* Suggested memories card — same AI-blue family, lighter weight */}
      <div style={{ padding: '0 14px 10px' }}>
        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline,
          borderRadius: 14, padding: '13px 16px', minHeight: 44,
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
          {/* Review = blue link into the suggestions sheet, 44px tap */}
          <span style={{ minHeight: 44, display: 'inline-flex', alignItems: 'center', fontSize: 13, fontWeight: 600, color: PX.ai, letterSpacing: -0.1 }}>
            Review
          </span>
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', padding: '4px 14px 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{
          fontSize: 10.5, fontWeight: 700, color: PX.ink3, letterSpacing: 1.6,
          textTransform: 'uppercase', padding: '2px 4px',
        }}>Memories</div>
        <MemoryCard
          title="Inspiration capture app concept"
          time="May 13 · 2:22 PM" place="Marsh Walk"
          media={{ audio: 2, photo: 1 }}
          topics={['content','tech']}
          gist={{ kind: 'summary', text: 'A product idea for capturing creative fragments from Watch, phone, and iPad, then using AI to organize them into scripts, essays, and longer-form projects over time.' }}
        />
      </div>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// 4. Suggested-memories review sheet.
//    AI proposes, the user decides. No auto-add.
//    Confidence is AI blue, ALWAYS — never green/amber (Projects lock).
//    Distinguished by fill (Likely = filled dot) vs outline (Maybe = hollow).
// ─────────────────────────────────────────────────────────────
function SuggestionRow({ title, date, why, confidence = 'likely', selected, sub }) {
  const likely = confidence === 'likely';
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 12,
      padding: '14px 4px 14px 4px',
      borderBottom: '1px solid ' + PX.divider,
    }}>
      <span style={{
        width: 24, height: 24, borderRadius: 12, flexShrink: 0, marginTop: 1,
        border: '1.5px solid ' + (selected ? PX.ai : PX.ink4),
        background: selected ? PX.ai : 'transparent',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {selected && <Check size={12} color={PX.accentInk} />}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <span style={{ fontSize: 14.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>{title}</span>
        </div>
        <div style={{ fontSize: 11, color: PX.ink3, marginBottom: 6, fontVariantNumeric: 'tabular-nums' }}>{date}</div>
        {/* "why" line — AI attribution, AI blue per the Projects lock */}
        <div style={{ fontSize: 12.5, color: PX.ai, lineHeight: 1.45, fontStyle: 'italic', fontFamily: PX.serif }}>
          {why}
        </div>
        {/* confidence chip — AI blue; Likely = filled dot, Maybe = hollow dot */}
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 8, fontSize: 11, color: PX.ai, fontWeight: 600, letterSpacing: 0.4 }}>
          <span style={{
            width: 7, height: 7, borderRadius: 4,
            background: likely ? PX.ai : 'transparent',
            border: '1.5px solid ' + PX.ai, boxSizing: 'border-box',
          }} />
          {likely ? 'LIKELY MATCH' : 'MAYBE MATCH'}
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
        title="Building HiMem"
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
          {/* Add = commit user action → ochre (you act). Muted when 0 selected. */}
          <span style={{ minHeight: 44, display: 'inline-flex', alignItems: 'center', fontSize: 15, fontWeight: 600, color: PX.ink3 }}>Add</span>
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
            These three may belong in <em>Building HiMem</em>.
          </div>
          <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 8, lineHeight: 1.5 }}>
            HiMem found these by looking at topics, mentions, and dates — not by reading every word.
            Add the ones that fit; skip the rest.
          </div>
        </div>

        {/* selection toolbar — count + a Select all/none toggle (ochre = you act).
           Default state: nothing selected, so the toggle offers "Select all";
           once all are selected it flips to "Select none". */}
        <div style={{ display: 'flex', alignItems: 'center', padding: '2px 20px 6px' }}>
          <span style={{ fontSize: 12, color: PX.ink3, letterSpacing: -0.05 }}>3 suggestions · none selected</span>
          <span style={{ flex: 1 }} />
          <span style={{ minHeight: 40, display: 'inline-flex', alignItems: 'center', fontSize: 13, fontWeight: 600, color: PX.accent, letterSpacing: -0.1 }}>Select all</span>
        </div>

        <div style={{ padding: '4px 20px 14px', overflow: 'auto', flex: 1 }}>
          <SuggestionRow
            title="Notes on Studio as creator workspace"
            date="May 12 · 10:14 AM"
            why="Mentions Studio, project synthesis, and creator tooling — the same thread you're pulling on here."
            confidence="likely"
          />
          <SuggestionRow
            title="Watch capture session feedback"
            date="May 8 · 4:48 PM"
            why="Tagged Technology; mentions watch recording, the central capture surface for this project."
            confidence="likely"
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
            Suggestions are proposals. Nothing gets added until you tap <strong style={{ color: PX.ink2 }}>Add</strong>.
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// A local serif heading (pricing-screens' SerifH isn't loaded on this canvas).
function SerifTitle({ children, size = 22, style }) {
  return (
    <div style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: size, lineHeight: 1.14, letterSpacing: -0.4, color: PX.ink, ...style }}>
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 5. Project MEMBER, opened. Tapping a memory card in a project
//    opens the canonical Memory Detail (full clip stream, boxed ✎ → modal,
//    Compact/Full toggle) — NOT this stripped summary card. This mock shows
//    only the project-context additions + bottom fate buttons; the real build
//    reuses Memory Detail wholesale (Projects · MVP spec § Opening a member memory).
//    Bottom fate, per the buttons + July 13 Trash locks:
//      • Remove from [project] (Recycle) — memory LEAVES this project, survives.
//      • Let Go of this Memory (Trash) — dissolves the memory; its CLIPS survive
//        and return to the bench. → Recently Deleted.
// ─────────────────────────────────────────────────────────────
function ScrProjectMemberOpen() {
  return (
    <PhoneScreen>
      {/* nav — back to the project it was opened from */}
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '6px 14px 8px' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, color: PX.accent, fontSize: 15 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          Foodies!
        </span>
        <span style={{ flex: 1 }} />
        <span style={{ display: 'inline-flex', gap: 14, color: PX.ink3 }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M8 11V2M4.5 5.5L8 2l3.5 3.5M3 12v8a1 1 0 001 1h12a1 1 0 001-1v-8"/></svg>
        </span>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', padding: '0 18px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, marginBottom: 8 }}>
          Jul 4 · 9:37 PM · Culinary Institute
        </div>
        <SerifTitle size={24} style={{ marginBottom: 10 }}>Culinary Institute</SerifTitle>

        {/* which projects this memory is in — makes membership legible + editable */}
        <div style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 6, marginBottom: 14 }}>
          <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: PX.ink4 }}>In</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, minHeight: 30, padding: '0 11px', borderRadius: 10, background: PX.wash1, fontSize: 12.5, color: PX.ink }}>
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke={PX.accent} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6a2 2 0 012-2h4l2 2h6a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/></svg>
            Foodies!
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, minHeight: 30, padding: '0 11px', borderRadius: 10, border: '1px dashed ' + PX.accent, fontSize: 12.5, fontWeight: 600, color: PX.accent }}>
            <svg width="10" height="10" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M7 2v10M2 7h10"/></svg>
            Add to project
          </span>
        </div>

        <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ai, marginBottom: 6, display: 'flex', alignItems: 'center', gap: 6 }}>
          <Spark size={12} color={PX.ai} /> Summary
        </div>
        <div style={{ fontSize: 14, lineHeight: 1.5, color: PX.ink, letterSpacing: -0.1, marginBottom: 18 }}>
          You discussed a 400°-then-250° cheesecake with a deliberate wobble, and mentioned working at Bar Oliver in Manhattan. You talked about farm-to-table cooking with Ben, your waiter.
        </div>

        <div style={{ flex: 1 }} />

        {/* the two full-width fate actions — Remove (survives) then Delete (destroys) */}
        <div style={{ paddingBottom: 8 }}>
          <div style={{
            minHeight: 50, borderRadius: 13, border: '1px solid ' + PX.accent, color: PX.accent,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1, marginBottom: 10,
          }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 0115-6.7L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 01-15 6.7L3 16"/><path d="M3 21v-5h5"/></svg>
            Remove from Foodies!
          </div>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginBottom: 18, lineHeight: 1.45 }}>
            Leaves this project. The memory stays in your library.
          </div>
          <div style={{
            minHeight: 50, borderRadius: 13, border: '1px solid ' + PX.danger, color: PX.danger,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            fontSize: 15.5, fontWeight: 600, letterSpacing: -0.1,
          }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>
            Let Go of this Memory
          </div>
          <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 8, lineHeight: 1.45 }}>
            The clips stay — they’ll be available to start other memories.
          </div>
        </div>
      </div>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrProjectsList, ScrProjectDetail, ScrProjectSummarized, ScrSuggestionsReview,
  ScrProjectMemberOpen,
});

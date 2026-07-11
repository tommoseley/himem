// screens-home.jsx
// THE unified home surface — the single answer to "how does the whole
// three-tab experience fit together." Resolves the July-2026 chrome
// inconsistency: Clips had a bottom tab bar; Memories/Projects had a TOP
// segmented control that listed only 2 of the 3 objects. Canonical model:
//
//   • Top bar (identical on every tab): HIMEM wordmark · search · settings.
//   • Context row (per tab): the filters that tab needs.
//   • Bottom tab bar (identical): Clips · Memories · Projects — three peers.
//   • FAB (identical): capture, floating above the tab bar, every tab.
//
// Three peer primary objects ⇒ one bottom tab bar (iOS convention). The old
// top Seg is retired. Reuses the real cards (MemoryCard, TabBar, HiMemMark,
// LooseClipRow, BurstRow, Thumb, TopicChip) so this is the true experience,
// not a diagram.
//
// Loads LAST, after: crucible-primitives, screens-projects, screens-memories,
// screens-clips-page.

// ── Shared top bar — wordmark + search + settings. Identical every tab. ──
function HomeTopBar() {
  return (
    <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', padding: '8px 16px 10px', background: PX.paper }}>
      <HiMemMark />
      <span style={{ flex: 1 }} />
      <span style={{ display: 'inline-flex', gap: 16, color: PX.ink3 }}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="M21 21l-4-4" /></svg>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3" /><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9L17 7M7 17l-2.1 2.1" /></svg>
      </span>
    </div>
  );
}

// ── A horizontal filter/context row. Per-tab content, shared shape. ──
function ContextRow({ segs, active }) {
  return (
    <div style={{ flexShrink: 0, display: 'flex', gap: 7, padding: '0 14px 10px', overflow: 'hidden' }}>
      {segs.map(([id, label]) => {
        const on = id === active;
        return (
          <span key={id} style={{
            fontSize: 13, fontWeight: on ? 600 : 500, letterSpacing: -0.1,
            color: on ? PX.accentInk : PX.ink2, background: on ? PX.accent : PX.wash1,
            borderRadius: 9, padding: '6px 12px', minHeight: 32, boxSizing: 'border-box',
            display: 'inline-flex', alignItems: 'center', whiteSpace: 'nowrap',
          }}>{label}</span>
        );
      })}
    </div>
  );
}

// ── Capture FAB — floats above the tab bar, identical on every tab. ──
function HomeFAB() {
  return (
    <div style={{ position: 'absolute', right: 18, bottom: 84, zIndex: 20 }}>
      <div style={{
        width: 58, height: 58, borderRadius: 29, background: PX.accent, color: PX.accentInk,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: '0 6px 20px rgba(198,74,28,0.4)',
      }}>
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a3 3 0 00-3 3v6a3 3 0 006 0V5a3 3 0 00-3-3z" /><path d="M5 11a7 7 0 0014 0M12 18v3" /></svg>
      </div>
    </div>
  );
}

// ── The chrome wrapper. Every tab is HomeChrome(active, context, body). ──
function HomeChrome({ active, segs, activeSeg, children }) {
  return (
    <PhoneScreen>
      <HomeTopBar />
      {segs && <ContextRow segs={segs} active={activeSeg} />}
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 14px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {children}
      </div>
      <HomeFAB />
      {/* Clips dot shows new unseen arrivals from anywhere but Clips; being ON
          Clips clears it (presence, not a count — never a number). */}
      <TabBar active={active} dot={active === 'clips' ? null : 'clips'} />
    </PhoneScreen>
  );
}

function HDate({ label }) {
  return <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.3, textTransform: 'uppercase', color: PX.ink3, padding: '4px 4px 0' }}>{label}</div>;
}

// ═══════════════════ TAB 1 · CLIPS ═══════════════════
function ScrHomeClips() {
  return (
    <HomeChrome active="clips" segs={[['new', 'New'], ['all', 'All'], ['voice', 'Voice'], ['photos', 'Photos'], ['notes', 'Notes']]} activeSeg="new">
      {/* AI suggestion cluster leads */}
      <div style={{ background: PX.aiTint, border: '1px solid ' + PX.ai, borderRadius: 14, padding: '12px 13px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 9 }}>
          <Spark size={14} color={PX.ai} />
          <span style={{ fontSize: 12.5, fontWeight: 600, color: PX.ai, letterSpacing: -0.05 }}>6 clips seem to belong together</span>
          <span style={{ flex: 1 }} />
          <span style={{ fontSize: 11, color: PX.ai, opacity: 0.8, fontFamily: PX.mono }}>May 11 · Tybee</span>
        </div>
        <div style={{ display: 'flex', gap: 6, marginBottom: 11 }}>
          {[20, 45, 70, 95, 130].map((h, i) => <Thumb key={i} size={44} hue={h} radius={8} />)}
          <div style={{ width: 44, height: 44, borderRadius: 8, flexShrink: 0, background: 'rgba(30,92,142,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 600, color: PX.ai }}>+1</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <span style={{ flex: 1, height: 40, borderRadius: 11, background: PX.ai, color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 14, fontWeight: 600 }}>
            Review
            <svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6" /></svg>
          </span>
          <span style={{ height: 40, padding: '0 14px', borderRadius: 11, border: '1px solid ' + PX.hairline, color: PX.ink2, display: 'inline-flex', alignItems: 'center', fontSize: 14, fontWeight: 500 }}>Not now</span>
        </div>
      </div>
      <HDate label="Sun May 31" />
      <LooseClipRow mediaIcon={<MediaAudio c={PX.accent} />} time="12:21 PM" place="Pooler" preview="These journeys are as wild and varied as landscapes — freedom on the open road." />
      <HDate label="Mon May 11" />
      <BurstRow time="5:39 PM" place="Tybee Island" count={4} kind="photo" hues={[35, 60, 90, 120]} />
      <MediaClipRow time="5:30 PM" place="Tybee Island" hue={200} video />
    </HomeChrome>
  );
}

// ═══════════════════ TAB 2 · MEMORIES ═══════════════════
function ScrHomeMemories() {
  return (
    <HomeChrome active="memories" segs={[['All', 'All'], ['content', 'Content'], ['tech', 'Technology'], ['garden', 'Garden']]} activeSeg="All">
      <HDate label="Today" />
      <MemoryCard
        title="Content creator capture platform concept"
        time="2:22 PM" place="Home"
        media={{ audio: 2, photo: 1 }}
        topics={['content', 'tech']}
        gist={{ kind: 'summary', text: 'A product idea for capturing creative fragments from Watch, phone, and iPad, then using AI to organize them into scripts, essays, and longer-form projects over time.' }}
      />
      <MemoryCard
        title="Culinary Institute"
        time="Jul 4 · 9:37 PM" place="Hyde Park"
        media={{ audio: 5 }}
        topics={['content']}
        gist={{ kind: 'excerpt', text: 'Ben, our waiter — second of three years, all farm-to-table. The brioche had these big flakes of sea salt on top.' }}
      />
    </HomeChrome>
  );
}

// ═══════════════════ TAB 3 · PROJECTS ═══════════════════
function HomeProjectRow({ title, count, date, topics }) {
  return (
    <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14, padding: '14px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 18, fontWeight: 500, color: PX.ink, letterSpacing: -0.2, flex: 1 }}>{title}</div>
        <div style={{ textAlign: 'right', flexShrink: 0 }}>
          <div style={{ fontSize: 17, fontWeight: 600, color: PX.ink, fontVariantNumeric: 'tabular-nums' }}>{count}</div>
          <div style={{ fontSize: 11.5, color: PX.ink3 }}>{date}</div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
        {topics.map(t => <TopicChip key={t} k={t} />)}
      </div>
    </div>
  );
}
function ScrHomeProjects() {
  return (
    <HomeChrome active="projects" segs={[['content', 'Content'], ['cooking', 'Cooking'], ['garden', 'Garden']]} activeSeg="content">
      <div style={{ height: 2 }} />
      <HomeProjectRow title="Building HiMem" count={14} date="May 13" topics={['content', 'tech']} />
      <HomeProjectRow title="AI essay — second draft" count={6} date="May 9" topics={['content', 'howWeWork']} />
      <HomeProjectRow title="Garden year" count={9} date="May 2" topics={['garden']} />
    </HomeChrome>
  );
}

Object.assign(window, {
  HomeTopBar, ContextRow, HomeFAB, HomeChrome,
  ScrHomeClips, ScrHomeMemories, ScrHomeProjects,
});

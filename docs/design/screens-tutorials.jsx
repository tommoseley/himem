// screens-tutorials.jsx
// The replayable one-pager tutorials. Seeded with only the three that earn
// their place (capture, organizing, find-the-thread) plus the full Watch /
// Captured Clips story. Each is a single iOS screen: eyebrow · serif headline
// · intro · 3 points (icon tile + title + body) · ochre dismiss · footnote.
// Delivered in-context at first encounter; replayed from the Tutorials hub.

// ── shared one-pager scaffold ───────────────────────────────────
function TutPoint({ glyph, title, body, tone = 'accent' }) {
  const ai = tone === 'ai';
  return (
    <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
      <span style={{
        width: 40, height: 40, borderRadius: 11, flexShrink: 0,
        background: ai ? PX.aiTint : PX.accentTint2, color: ai ? PX.ai : PX.accent,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>{glyph}</span>
      <div style={{ flex: 1, paddingTop: 1 }}>
        <div style={{ fontSize: 15.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>{title}</div>
        <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.5, marginTop: 3, letterSpacing: -0.05 }}>{body}</div>
      </div>
    </div>
  );
}
function TutorialPage({ eyebrow, title, intro, points, cta, ctaGlyph, secondary, footnote, plus }) {
  return (
    <PhoneScreen>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', background: PX.paper }}>
        {/* dismiss affordance, top-right */}
        <div style={{ display: 'flex', alignItems: 'center', paddingTop: 16 }}>
          <span style={{ flex: 1 }} />
          <span style={{ width: 30, height: 30, borderRadius: 15, background: PX.sunk, color: PX.ink3, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 16 }}>&times;</span>
        </div>
        <div style={{ height: 14 }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
          <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', color: PX.ink3 }}>{eyebrow}</span>
          {plus && (
            <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', color: PX.ai, background: PX.aiTint, border: '1px solid ' + PX.ai, padding: '2px 7px', borderRadius: 8 }}>Plus</span>
          )}
        </div>
        <h1 style={{ fontFamily: PX.serif, fontWeight: 400, fontSize: 28, lineHeight: 1.15, letterSpacing: -0.5, color: PX.ink, margin: '8px 0 0' }}>{title}</h1>
        <p style={{ fontSize: 14, lineHeight: 1.5, color: PX.ink2, margin: '10px 0 26px', letterSpacing: -0.1 }}>{intro}</p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          {points.map((p, i) => <TutPoint key={i} {...p} />)}
        </div>
        <div style={{ flex: 1, minHeight: 20 }} />
        <div style={{ paddingBottom: 30 }}>
          <button style={{
            height: 52, width: '100%', borderRadius: 14, border: 'none', cursor: 'pointer',
            background: PX.accent, color: PX.accentInk, fontSize: 16, fontWeight: 600, letterSpacing: -0.2,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 9,
          }}>
            {ctaGlyph}{cta}
          </button>
          {secondary && (
            <button style={{
              height: 48, width: '100%', borderRadius: 14, border: 'none', cursor: 'pointer', marginTop: 8,
              background: 'transparent', color: PX.ink2, fontSize: 15.5, fontWeight: 600, letterSpacing: -0.2,
            }}>{secondary}</button>
          )}
          {footnote && <div style={{ fontSize: 11.5, color: PX.ink3, textAlign: 'center', marginTop: 10, lineHeight: 1.4 }}>{footnote}</div>}
        </div>
      </div>
    </PhoneScreen>
  );
}

// ── glyphs ──────────────────────────────────────────────────────
const TG = {
  mic: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>,
  micSm: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>,
  next: <svg width="20" height="14" viewBox="0 0 22 14" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M2 2l5 5-5 5"/><circle cx="15" cy="7" r="1.8" fill="currentColor" stroke="none"/></svg>,
  watch: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>,
  watchSm: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>,
  spark: <svg width="19" height="19" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z"/></svg>,
  glance: <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>,
  pencil: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 113 3L12 15l-4 1 1-4z"/></svg>,
  thread: <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 6h16M4 12h10M4 18h7"/></svg>,
  list: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h13M3 12h13M3 18h9"/><circle cx="20" cy="6" r="1.6" fill="currentColor" stroke="none"/></svg>,
  hand: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 11V5a1.5 1.5 0 013 0v5M12 10V4a1.5 1.5 0 013 0v6M15 10V6a1.5 1.5 0 013 0v8a6 6 0 01-6 6h-1a6 6 0 01-5-3l-2.5-4a1.5 1.5 0 012.5-1.6L9 13"/></svg>,
  sync: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 0115-6.7L21 8M21 3v5h-5M21 12a9 9 0 01-15 6.7L3 16M3 21v-5h5"/></svg>,
  bundle: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="5" rx="1.5"/><rect x="5" y="11" width="14" height="4" rx="1.5"/><rect x="7" y="17" width="10" height="3" rx="1.5"/></svg>,
  siri: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M8.5 10v4M12 7.5v9M15.5 10v4"/></svg>,
  siriSm: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M8.5 10v4M12 7.5v9M15.5 10v4"/></svg>,
  bolt: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M13 2L4 14h6l-1 8 9-12h-6z"/></svg>,
};

// ── 1 · Capture · Next · Watch ──────────────────────────────────
function ScrTutCapture() {
  return (
    <TutorialPage
      eyebrow="Capturing a memory"
      title="Just start talking."
      intro="HiMem listens, transcribes, and keeps it — no buttons to fumble while a thought is fresh."
      points={[
        { tone: 'accent', glyph: TG.mic, title: "Speak, and it's saved", body: "Tap record and talk. The audio stays on your device; the words become a searchable memory." },
        { tone: 'accent', glyph: TG.next, title: 'On a roll? Tap Next', body: "Next saves the current clip and starts a fresh one without stopping — they group into one memory. Great for a list of thoughts." },
        { tone: 'ai', glyph: TG.watch, title: 'Your Watch records too', body: "Catch a thought on your Apple Watch and it syncs here automatically. No phone needed in the moment." },
      ]}
      cta="Start recording"
      ctaGlyph={TG.micSm}
      footnote="You can replay this any time from the ? in the toolbar."
    />
  );
}

// ── 2 · Organizing with AI ──────────────────────────────────────
function ScrTutOrganize() {
  return (
    <TutorialPage
      eyebrow="Organizing with AI"
      title="A first draft, in your words."
      intro="When you ask, HiMem drafts the details so a memory is easy to find later — but you stay the editor."
      points={[
        { tone: 'ai', glyph: TG.spark, title: 'AI drafts the details', body: "A title, a short summary, and a topic or two — drafted right on your device. Free organizes when you tap; Plus does it for you." },
        { tone: 'ai', glyph: TG.glance, title: 'Give it a glance', body: "It opens as a draft — keep it as is, or fix anything that doesn't sound like you. Nothing is final until you say so." },
        { tone: 'accent', glyph: TG.pencil, title: 'It stays yours', body: "Edit a title or summary any time. Fixing a detail is an improvement — it never un-organizes the memory." },
      ]}
      cta="Got it"
      footnote="Replay from the ? in the toolbar."
    />
  );
}

// ── 3 · Find the thread (Plus) ──────────────────────────────────
function ScrTutFindThread() {
  return (
    <TutorialPage
      plus
      eyebrow="Projects"
      title="Find the thread."
      intro="A project is a place for related memories. Find the thread reads across them and pulls out what connects."
      points={[
        { tone: 'ai', glyph: TG.thread, title: 'One thread across the project', body: "A short, honest summary of what these memories are really about — in second person, in your voice." },
        { tone: 'ai', glyph: TG.list, title: 'Memories that may belong', body: "It also surfaces memories from elsewhere in your library that look like they fit — “8 may belong here.”" },
        { tone: 'accent', glyph: TG.hand, title: 'You decide', body: "Suggestions are proposals. Nothing is added until you pick it. Run it again whenever the project grows." },
      ]}
      cta="Got it"
      footnote="A Plus feature. Replay from the ? in the toolbar."
    />
  );
}

// ── 4 · Captured Clips · the Watch story ────────────────────────
function ScrTutWatch() {
  return (
    <TutorialPage
      eyebrow="From your Watch"
      title="Catch it on your wrist."
      intro="Your Apple Watch is a capture queue — record a thought anywhere, sort it out on your phone later."
      points={[
        { tone: 'accent', glyph: TG.watch, title: 'Record, hands-free', body: "Raise your wrist and talk. The Watch captures audio only — no screen to manage, nothing to organize in the moment." },
        { tone: 'ai', glyph: TG.sync, title: 'It syncs to your phone', body: "Clips land in Captured Clips on your iPhone and are transcribed there. Your Watch never holds your library — just the latest clips." },
        { tone: 'accent', glyph: TG.bundle, title: 'Shape it into a memory', body: "Review the session and keep it as a new memory, or add it to one you're already building. A roll of clips becomes one memory." },
      ]}
      cta="Got it"
      footnote="Replay from the ? in the toolbar."
    />
  );
}

// ── 5 · Watch discovery (paired, HiMem not yet installed on watch) ──
// The DISCOVERY trigger, distinct from the Watch-story usage tutorial (#4).
// Gated app-side on WCSession: isPaired && !isWatchAppInstalled && !seen.
// Surfaced once on Today (calm surface), after onboarding. No OS prompt.
function ScrTutWatchDiscovery() {
  return (
    <TutorialPage
      eyebrow="Your Apple Watch"
      title="Capture on your wrist."
      intro="You have an Apple Watch — HiMem can record there too, so a thought never has to wait for your phone."
      points={[
        { tone: 'accent', glyph: TG.watch, title: 'Raise and talk', body: "Record a thought hands-free, even when your phone isn't nearby. Audio only — nothing to manage in the moment." },
        { tone: 'ai', glyph: TG.sync, title: 'It shows up here', body: "Clips sync to your iPhone on their own and land in Captured Clips, ready to become memories." },
      ]}
      cta="Add HiMem to your Watch"
      ctaGlyph={TG.watchSm}
      secondary="Later"
      footnote="Shown because your Apple Watch is paired, but HiMem isn't on it yet."
    />
  );
}

// ── 5b · Watch discovery · manual fallback ──
// There is no public API that guarantees installing a watch app, and even
// deep-linking to the Watch app can fail. So #5's "Add HiMem to your Watch"
// CTA is best-effort; when it can't complete, fall through to these written
// steps — which always work because they're just instructions.
function ScrTutWatchManual() {
  const num = (n) => <span style={{ fontSize: 17, fontWeight: 700, fontFamily: PX.sans, color: PX.accent }}>{n}</span>;
  return (
    <TutorialPage
      eyebrow="Add HiMem to your Watch"
      title="A couple of taps in the Watch app."
      intro="We couldn’t open it for you automatically — here’s the manual way. About thirty seconds."
      points={[
        { tone: 'accent', glyph: num(1), title: 'Open the Watch app', body: "On your iPhone, open the app named Watch — it comes with every iPhone." },
        { tone: 'accent', glyph: num(2), title: 'Find “Available Apps”', body: "In the My Watch tab, scroll to the bottom to the Available Apps section." },
        { tone: 'accent', glyph: num(3), title: 'Tap Install next to HiMem', body: "It lands on your wrist in a few moments. Then just raise and talk." },
      ]}
      cta="Open the Watch app"
      ctaGlyph={TG.watchSm}
      secondary="Done"
      footnote="Don’t see Available Apps? Your Watch may still be syncing — try again in a minute."
    />
  );
}

// ── 6 · Capturing with Siri ─────────────────────────────────────
// The phone-side embodiment of the perishability principle: capture with
// zero navigation, before the thought fades. A differentiator the user won't
// stumble onto (the Siri phrases are invisible until we name them), so it
// earns a tutorial on the discoverability criterion. Both phrases ship today
// (open+record, and in-Siri dictation that never opens the app).
function Quote({ children }) {
  return <span style={{ color: PX.ink, fontWeight: 600 }}>{children}</span>;
}
function ScrTutSiri() {
  return (
    <TutorialPage
      eyebrow="Capturing with Siri"
      title="Catch it without a tap."
      intro="Two hands-free ways to save a thought — Siri can open HiMem and start recording, or take it down for you without opening the app at all."
      points={[
        { tone: 'accent', glyph: TG.siri, title: 'Say the word', body: <>&ldquo;<Quote>Hey Siri, record in HiMem</Quote>&rdquo; opens the app and starts recording on its own. Nothing to tap once the thought strikes.</> },
        { tone: 'accent', glyph: TG.mic, title: 'Or just tell Siri', body: <>&ldquo;<Quote>Hey Siri, capture in HiMem</Quote>.&rdquo; Siri asks what you want to remember, takes it down, and saves it &mdash; without ever opening the app. On Plus, it&rsquo;s organized by the time you look.</> },
        { tone: 'accent', glyph: TG.bolt, title: 'Before it fades', body: "From the lock screen, across the room, hands full — the fastest path to a memory that's already slipping away." },
      ]}
      cta="Got it"
      footnote="Say &ldquo;Hey Siri, record in HiMem&rdquo; to try it. Replay from the ? in the toolbar."
    />
  );
}

Object.assign(window, {
  TutorialPage, TutPoint,
  ScrTutCapture, ScrTutOrganize, ScrTutFindThread, ScrTutWatch, ScrTutWatchDiscovery, ScrTutWatchManual,
  ScrTutSiri,
});

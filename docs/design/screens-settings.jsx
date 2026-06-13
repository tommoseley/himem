// screens-settings.jsx
// HiMem · Settings — canonical canvas, mirrors the shipped Settings sheet and
// brings it to Crucible standard. Built June 10 2026 from the live screenshots.
//
// Conformance fixes applied vs. the shipped build (flagged in the canvas):
//   · Toggles are OCHRE when on, not iOS green (green = semantic-only).
//   · "Also save captures to Photos library" REMOVED — contradicts the locked
//     data-custody decision (HiMem writes media to its own iCloud Files
//     container, never the Photos library). See CLAUDE.md · Media storage.
//   · Done in the sheet top bar is ochre (nav-bar action rule).
//
// Structure: common settings at top → Debug section at the bottom (dev-only).

// ── building blocks ─────────────────────────────────────────────
function SHeader({ children }) {
  return (
    <div style={{
      fontSize: 12.5, fontWeight: 600, color: PX.ink3, letterSpacing: -0.1,
      padding: '0 6px 7px', textTransform: 'none',
    }}>{children}</div>
  );
}
function SHelp({ children }) {
  return (
    <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, padding: '8px 6px 0', letterSpacing: -0.05 }}>
      {children}
    </div>
  );
}
function SGroup({ header, help, children, mt = 20 }) {
  return (
    <div style={{ marginTop: mt }}>
      {header && <SHeader>{header}</SHeader>}
      <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, overflow: 'hidden' }}>
        {children}
      </div>
      {help && <SHelp>{help}</SHelp>}
    </div>
  );
}
function SRow({ icon, iconBg, title, value, chevron, badge, last, titleColor, onAccent }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, boxSizing: 'border-box',
      padding: '11px 15px', borderBottom: last ? 'none' : '1px solid ' + PX.divider,
    }}>
      {icon && (
        <span style={{
          width: 28, height: 28, borderRadius: 8, flexShrink: 0,
          background: iconBg || PX.accentTint, color: onAccent || PX.accent,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        }}>{icon}</span>
      )}
      <span style={{ flex: 1, fontSize: 16, color: titleColor || PX.ink, letterSpacing: -0.2, fontWeight: 400 }}>{title}</span>
      {badge != null && (
        <span style={{
          fontSize: 13, fontWeight: 600, color: PX.ink3, background: PX.sunk,
          minWidth: 22, height: 22, padding: '0 8px', borderRadius: 11,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontVariantNumeric: 'tabular-nums',
        }}>{badge}</span>
      )}
      {value != null && <span style={{ fontSize: 16, color: PX.ink3, letterSpacing: -0.2 }}>{value}</span>}
      {chevron && (
        <svg width="8" height="13" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M1 1l6 6-6 6"/></svg>
      )}
    </div>
  );
}
// Ochre toggle (NOT iOS green). on = ochre track.
function SToggle({ on, title, last, icon, iconBg, onAccent }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, boxSizing: 'border-box',
      padding: '11px 15px', borderBottom: last ? 'none' : '1px solid ' + PX.divider,
    }}>
      {icon && (
        <span style={{
          width: 28, height: 28, borderRadius: 8, flexShrink: 0,
          background: iconBg || PX.accentTint, color: onAccent || PX.accent,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        }}>{icon}</span>
      )}
      <span style={{ flex: 1, fontSize: 16, color: PX.ink, letterSpacing: -0.2 }}>{title}</span>
      <span style={{
        width: 50, height: 30, borderRadius: 15, flexShrink: 0, position: 'relative',
        background: on ? PX.accent : '#CFC9BD', transition: 'background .15s',
      }}>
        <span style={{
          position: 'absolute', top: 2.5, left: on ? 22.5 : 2.5, width: 25, height: 25, borderRadius: 13,
          background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.2)', transition: 'left .15s',
        }}/>
      </span>
    </div>
  );
}
function SStepper({ title, value, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, boxSizing: 'border-box',
      padding: '11px 15px', borderBottom: last ? 'none' : '1px solid ' + PX.divider,
    }}>
      <span style={{ flex: 1, fontSize: 16, color: PX.ink, letterSpacing: -0.2 }}>{title}</span>
      <span style={{ fontSize: 15, color: PX.ink3, letterSpacing: -0.1 }}>{value}</span>
      <span style={{ display: 'inline-flex', flexDirection: 'column', color: PX.accent }}>
        <svg width="13" height="9" viewBox="0 0 14 9" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 6l5-4 5 4"/></svg>
        <svg width="13" height="9" viewBox="0 0 14 9" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 3l5 4 5-4"/></svg>
      </span>
    </div>
  );
}

// ── icons ───────────────────────────────────────────────────────
const IcAppearance = <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="9"/><path d="M12 3v18" fill="currentColor"/><path d="M12 3a9 9 0 010 18z" fill="currentColor" stroke="none"/></svg>;
const IcSpark = <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z"/></svg>;
const IcFolder = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a1 1 0 011-1h5l2 2h8a1 1 0 011 1v9a1 1 0 01-1 1H4a1 1 0 01-1-1z"/></svg>;
const IcWatch = <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>;
const IcTrash = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a2 2 0 012-2h2a2 2 0 012 2v2"/></svg>;
const IcPlay = <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M6 4l14 8-14 8z"/></svg>;
const IcReset = <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 109-9 9 9 0 00-7 3.3M3 4v3.5h3.5"/></svg>;

// ── sheet top bar ───────────────────────────────────────────────
function SettingsBar({ title = 'Settings', back }) {
  return (
    <div style={{
      flexShrink: 0, display: 'flex', alignItems: 'center', padding: '14px 16px 12px',
      position: 'sticky', top: 0, zIndex: 3, background: PX.sunk,
    }}>
      {back
        ? <span style={{ width: 34, height: 34, borderRadius: 17, background: PX.card, border: '1px solid ' + PX.hairline, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: PX.ink }}>
            <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
          </span>
        : <span style={{ width: 34 }}/>}
      <span style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, color: PX.ink, letterSpacing: -0.3 }}>{title}</span>
      {back ? <span style={{ width: 34 }}/> : <span style={{ fontSize: 16, fontWeight: 600, color: PX.accent, letterSpacing: -0.2 }}>Done</span>}
    </div>
  );
}

// ── topic rows ──────────────────────────────────────────────────
const SETTINGS_TOPICS = [
  ['Content', 'ember', 4], ['Cooking', 'slate', 2], ['Garden', 'moss', 2],
  ['How We Work', 'tide', 9], ['Technology', 'ember', 10], ['Travel', 'clay', 1],
];
function TopicRow({ label, slug, count, last }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, boxSizing: 'border-box', padding: '11px 15px', borderBottom: last ? 'none' : '1px solid ' + PX.divider }}>
      <span style={{ width: 9, height: 9, borderRadius: 5, background: topicVar(slug), flexShrink: 0 }}/>
      <span style={{ flex: 1, fontSize: 16, color: PX.ink, letterSpacing: -0.2 }}>{label}</span>
      <span style={{ fontSize: 14, color: PX.ink3, letterSpacing: -0.1 }}>{count} {count === 1 ? 'entry' : 'entries'}</span>
      <svg width="8" height="13" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 1l6 6-6 6"/></svg>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// THE SETTINGS MENU — one tall sheet, common at top → Debug at bottom
// ═════════════════════════════════════════════════════════════
function ScrSettingsMenu() {
  return (
    <div style={{ width: 360, minHeight: 2860, background: PX.sunk, fontFamily: PX.sans, color: PX.ink, display: 'flex', flexDirection: 'column' }}>
      <SettingsBar />
      <div style={{ padding: '0 16px 40px' }}>

        <SGroup header="Profile" mt={4}>
          <SRow title="Name" value="Tom" />
        </SGroup>

        <SGroup header="Display">
          <SRow icon={IcAppearance} title="Appearance" value="System" chevron />
          <SRow icon={<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M9.2 9a2.8 2.8 0 015.4 1c0 1.8-2.6 2.4-2.6 2.4M12 17h.01"/></svg>} title="Tutorials" chevron last />
        </SGroup>

        <SGroup header="Topics"
          help={<>Topics are the top-level categories shown in the tab bar. When the AI suggests a new topic, you&rsquo;ll be asked to approve it first.</>}>
          {SETTINGS_TOPICS.map(([l, s, c], i) => <TopicRow key={l} label={l} slug={s} count={c} />)}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: 52, padding: '11px 15px' }}>
            <span style={{ width: 22, height: 22, borderRadius: 11, background: PX.accent, color: PX.accentInk, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M7 2v10M2 7h10"/></svg>
            </span>
            <span style={{ fontSize: 16, fontWeight: 500, color: PX.accent, letterSpacing: -0.2 }}>New Topic</span>
          </div>
        </SGroup>

        <SGroup header="Data Management" help={<>Deleted memories are kept for 30 days before permanent removal.</>}>
          <SRow icon={IcTrash} iconBg={PX.sunk} onAccent={PX.ink3} title="Recently Deleted" badge={24} chevron last />
        </SGroup>

        {/* Plus upgrade entry — ochre (a you-act decision), brand moment */}
        <div style={{ marginTop: 22, background: PX.card, border: '1px solid ' + PX.accent, borderRadius: 16, padding: '15px 16px' }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 4 }}>
            <span style={{ fontFamily: PX.serif, fontSize: 20, fontWeight: 500, color: PX.accent, letterSpacing: -0.3 }}>HiMem Plus</span>
            <span style={{ fontSize: 12.5, color: PX.ink3 }}>from $6.99/mo</span>
          </div>
          <div style={{ fontSize: 13, color: PX.ink2, lineHeight: 1.5, marginBottom: 13 }}>
            Automatic organizing, memories that connect themselves, and unlimited projects.
          </div>
          <div style={{ height: 48, borderRadius: 13, background: PX.accent, color: PX.accentInk, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 600, letterSpacing: -0.2 }}>See plans</div>
        </div>

        <SGroup header="AI &amp; Organizing">
          <SRow icon={IcSpark} title="Organizing" value="Manual" chevron />
          <SRow icon={IcFolder} title="Projects" value="2 of 3" chevron last />
        </SGroup>

        <SGroup help={<>Voice clips from Apple Watch land here. Review them, then create a new memory or add them to an existing one.</>}>
          <SRow icon={IcWatch} title="Captured Clips" value="0 pending" chevron last />
        </SGroup>

        <SGroup header="Voice"
          help={<>Voice recordings are saved on device. You can play them back from entry cards. Tap Done to finish a voice search; the pace setting only controls how long HiMem waits if you stop talking.</>}>
          <SToggle on title="Save voice recordings" />
          <SStepper title="Voice search pace" value="Standard · 10 seconds" last />
        </SGroup>

        <SGroup header="Privacy"
          help={<>Location stays on your device. We never send it to the server. Turn this off and new memories will be saved without location.</>}>
          <SToggle on title="Tag memories with location" last />
        </SGroup>

        <SGroup header="Notifications"
          help={<>Watch clips ping when they land on the iPhone. The daily nudge is an optional reminder if you haven&rsquo;t captured anything by your chosen time.</>}>
          <SRow title="Notifications" value="On" chevron />
          <SToggle on={false} title="Daily nudge" last />
        </SGroup>

        <SGroup header="Handedness"
          help={<>Anchors the Add button to the bottom-left of the screen instead of the bottom-right. The action stack flips with it.</>}>
          <SToggle on={false} title="Left-handed FAB" last />
        </SGroup>

        {/* NOTE: the shipped "Also save captures to Photos library" toggle is
            intentionally OMITTED — it contradicts the locked data-custody
            decision (media lives in HiMem's iCloud Files container, never the
            Photos library). See CLAUDE.md · Media storage. */}

        <SGroup header="Storage">
          <div style={{ padding: '15px 16px' }}>
            <div style={{ fontSize: 16, fontWeight: 600, color: PX.ink, letterSpacing: -0.2, marginBottom: 8 }}>Where your memories live</div>
            <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.55 }}>
              Your transcripts, titles, summaries, topics, and projects sync via iCloud. Original audio, photos, and videos live in your iCloud Drive under a folder called <strong style={{ color: PX.ink, fontWeight: 600 }}>HiMem</strong> — visible in the Files app, exportable anywhere, and durable across reinstalls.
            </div>
            <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.55, marginTop: 12 }}>
              We don&rsquo;t store your memories on our servers.
            </div>
          </div>
        </SGroup>

        {/* ── Debug · dev-only ── */}
        <SGroup header="Debug"
          help={<>Developer-only. Compiled out of Release builds — App Store users never see this section. <strong style={{ color: PX.ink2, fontWeight: 600 }}>Run onboarding test</strong> replays the splash + wizard immediately. <strong style={{ color: PX.ink2, fontWeight: 600 }}>Reset onboarding</strong> clears state for the next cold launch (requires force-quit).</>}>
          <SRow icon={IcPlay} title="Run onboarding test" />
          <SRow icon={IcReset} iconBg={PX.sunk} onAccent={PX.ink3} title="Reset onboarding (next launch)" />
          <div style={{ padding: '11px 15px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <span style={{ flex: 1, fontSize: 16, color: PX.ink, letterSpacing: -0.2 }}>Use lean organize prompt</span>
              <span style={{ width: 50, height: 30, borderRadius: 15, flexShrink: 0, position: 'relative', background: '#CFC9BD' }}>
                <span style={{ position: 'absolute', top: 2.5, left: 2.5, width: 25, height: 25, borderRadius: 13, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.2)' }}/>
              </span>
            </div>
            <div style={{ fontSize: 12.5, color: PX.ink3, lineHeight: 1.45, marginTop: 6 }}>
              Strips Honest-Label rules so on-device organize uses a minimal prompt — diagnostic for safety-rejected memories.
            </div>
          </div>
        </SGroup>

        <SGroup header="Plus override"
          help={<>Forces the isPlus signal so you can exercise the Plus path without an active subscription. Persists across launches. Setting back to Real reads StoreKit&rsquo;s current entitlement state.</>}>
          <div style={{ padding: '12px 14px' }}>
            <div style={{ display: 'flex', background: PX.sunk, borderRadius: 11, padding: 3 }}>
              {['Real', 'Plus', 'Free'].map((s, i) => (
                <span key={s} style={{
                  flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 600, padding: '7px 0', borderRadius: 9,
                  background: i === 0 ? PX.card : 'transparent', color: i === 0 ? PX.ink : PX.ink3,
                  boxShadow: i === 0 ? '0 1px 2px rgba(0,0,0,0.08)' : 'none', letterSpacing: -0.1,
                }}>{s}</span>
              ))}
            </div>
          </div>
          <SRow title="Effective" value="Free" titleColor={PX.ink} last />
        </SGroup>

      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// DETAIL · Appearance
// ═════════════════════════════════════════════════════════════
function ThemeRow({ icon, title, sub, selected, last }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 58, boxSizing: 'border-box', padding: '12px 15px', borderBottom: last ? 'none' : '1px solid ' + PX.divider }}>
      <span style={{ width: 32, height: 32, borderRadius: 8, background: PX.sunk, color: PX.ink2, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>{icon}</span>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 16, color: PX.ink, letterSpacing: -0.2 }}>{title}</div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 1, letterSpacing: -0.05 }}>{sub}</div>
      </div>
      {selected && <svg width="17" height="17" viewBox="0 0 16 16" fill="none" stroke={PX.accent} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M3 8.5l3.5 3.5L13 4"/></svg>}
    </div>
  );
}
function ScrSettingsAppearance() {
  return (
    <div style={{ width: 360, minHeight: 600, background: PX.sunk, fontFamily: PX.sans, color: PX.ink, display: 'flex', flexDirection: 'column' }}>
      <SettingsBar title="Appearance" back />
      <div style={{ padding: '0 16px' }}>
        <SGroup header="Theme" mt={4}
          help={<>The watch is always dark — capture happens in any light.</>}>
          <ThemeRow icon={IcAppearance} title="System" sub="Match iOS · light by day, dark by night" selected />
          <ThemeRow icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="12" r="4.5"/><path d="M12 2v2M12 20v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2 12h2M20 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/></svg>} title="Light" sub="Cream paper, warm ink" />
          <ThemeRow icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M20 14.5A8 8 0 019.5 4 7 7 0 1020 14.5z"/></svg>} title="Dark" sub="Warm near-black, cream type" last />
        </SGroup>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// DETAIL · Edit Topic (sheet over the menu)
// ═════════════════════════════════════════════════════════════
function ScrSettingsEditTopic() {
  const swatches = ['ember','clay','amber','wheat','pine','sage','moss','sea','slate','tide','violet','indigo','plum','rose','sand','terracotta'];
  return (
    <div style={{ width: 360, minHeight: 720, background: PX.sunk, fontFamily: PX.sans, color: PX.ink, position: 'relative', overflow: 'hidden' }}>
      {/* dimmed menu behind */}
      <div style={{ opacity: 0.4, pointerEvents: 'none' }}>
        <SettingsBar title="Settings" />
        <div style={{ padding: '0 16px' }}>
          <SGroup header="Topics" mt={4}>
            {SETTINGS_TOPICS.slice(0,4).map(([l,s,c]) => <TopicRow key={l} label={l} slug={s} count={c} />)}
          </SGroup>
        </div>
      </div>
      {/* sheet */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, top: 150, background: PX.paper, borderTopLeftRadius: 20, borderTopRightRadius: 20, boxShadow: '0 -8px 30px rgba(0,0,0,0.18)', padding: '10px 20px 20px' }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: PX.hairline, margin: '0 auto 14px' }}/>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 22 }}>
          <span style={{ fontSize: 16, color: PX.ink2, letterSpacing: -0.1 }}>Cancel</span>
          <span style={{ flex: 1, textAlign: 'center', fontSize: 16, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Edit Topic</span>
          <span style={{ fontSize: 16, fontWeight: 600, color: PX.accent, letterSpacing: -0.1 }}>Save</span>
        </div>
        {/* name field — tap-to-edit, ochre focus */}
        <div style={{ border: '1.5px solid ' + PX.accent, background: PX.card, borderRadius: 12, padding: '13px 14px', boxShadow: '0 0 0 3px ' + PX.accentTint, textAlign: 'center', marginBottom: 16 }}>
          <span style={{ fontSize: 18, fontWeight: 600, color: PX.ink, letterSpacing: -0.2 }}>Travel</span>
        </div>
        {/* preview chip */}
        <div style={{ textAlign: 'center', marginBottom: 22 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 32, padding: '0 14px', borderRadius: 11, background: PX.wash1 }}>
            <span style={{ width: 7, height: 7, borderRadius: 4, background: topicVar('clay') }}/>
            <span style={{ fontSize: 14, color: PX.ink }}>Travel</span>
          </span>
        </div>
        <div style={{ fontSize: 11, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 12 }}>Color</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, justifyItems: 'center' }}>
          {swatches.map((s, i) => (
            <span key={s} style={{
              width: 44, height: 44, borderRadius: 22, background: topicVar(s),
              boxShadow: i === 1 ? '0 0 0 2.5px ' + PX.paper + ', 0 0 0 4.5px ' + PX.accent : 'none',
            }}/>
          ))}
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// DETAIL · Captured Clips · empty state
// ═════════════════════════════════════════════════════════════
function ScrCapturedClipsEmpty() {
  return (
    <div style={{ width: 360, minHeight: 600, background: PX.paper, fontFamily: PX.sans, color: PX.ink, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '14px 16px 12px' }}>
        <span style={{ width: 34, height: 34, borderRadius: 17, background: PX.card, border: '1px solid ' + PX.hairline, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: PX.ink }}>
          <svg width="9" height="15" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1L1 8l7 7"/></svg>
        </span>
        <span style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, color: PX.ink, letterSpacing: -0.3 }}>Captured Clips</span>
        <span style={{ fontSize: 16, fontWeight: 600, color: PX.accent }}>Done</span>
      </div>
      <div style={{ padding: '14px 22px' }}>
        <div style={{ fontFamily: PX.serif, fontSize: 27, fontWeight: 400, color: PX.ink, letterSpacing: -0.5, lineHeight: 1.15 }}>Nothing new from your Watch</div>
        <div style={{ fontSize: 14, color: PX.ink3, marginTop: 8, lineHeight: 1.5 }}>Audio you record on your Apple Watch lands here.</div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// TUTORIALS HUB — opened from a "?" in the main toolbar. Lists every
// walkthrough; each row replays that tutorial. The home for the voice
// composer's "find this again in Settings" promise.
// ═════════════════════════════════════════════════════════════
function TutorialRow({ glyph, title, sub, accent, last }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, minHeight: 60, boxSizing: 'border-box', padding: '13px 15px', borderBottom: last ? 'none' : '1px solid ' + PX.divider }}>
      <span style={{
        width: 36, height: 36, borderRadius: 10, flexShrink: 0,
        background: accent ? PX.accentTint2 : PX.aiTint, color: accent ? PX.accent : PX.ai,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>{glyph}</span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 16, color: PX.ink, letterSpacing: -0.2 }}>{title}</div>
        <div style={{ fontSize: 12.5, color: PX.ink3, marginTop: 1, letterSpacing: -0.05 }}>{sub}</div>
      </div>
      <svg width="8" height="13" viewBox="0 0 8 14" fill="none" stroke={PX.ink4} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M1 1l6 6-6 6"/></svg>
    </div>
  );
}
function ScrTutorialsHub() {
  const mic = <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>;
  const spark = <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z"/></svg>;
  const folder = <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7a1 1 0 011-1h5l2 2h8a1 1 0 011 1v9a1 1 0 01-1 1H4a1 1 0 01-1-1z"/></svg>;
  const dot = <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="6"/></svg>;
  const watch = <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M8 6l1-3h6l1 3M8 18l1 3h6l1-3"/></svg>;
  const shield = <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z"/></svg>;
  return (
    <div style={{ width: 360, minHeight: 720, background: PX.sunk, fontFamily: PX.sans, color: PX.ink, display: 'flex', flexDirection: 'column' }}>
      <SettingsBar title="Tutorials" back />
      <div style={{ padding: '4px 16px 40px' }}>
        <div style={{ fontSize: 13, color: PX.ink3, lineHeight: 1.5, padding: '4px 6px 14px' }}>
          Short walkthroughs you can replay any time. Opened from the <strong style={{ color: PX.ink2, fontWeight: 600 }}>?</strong> in the toolbar.
        </div>
        <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, overflow: 'hidden' }}>
          <TutorialRow accent glyph={mic} title="Capturing a memory" sub="Recording, Next, and your Watch" />
          <TutorialRow glyph={spark} title="Organizing with AI" sub="Draft, review, and keep" />
          <TutorialRow accent glyph={folder} title="Projects" sub="Group memories and find the thread" />
          <TutorialRow accent glyph={dot} title="Topics" sub="Your top-level categories" />
          <TutorialRow accent glyph={watch} title="Captured Clips" sub="From your Watch to a memory" />
          <TutorialRow glyph={shield} title="Where your memories live" sub="Private by default, in your iCloud" last />
        </div>
      </div>
    </div>
  );
}

// Toolbar entry point — shows the "?" help glyph in the main browsing header.
function ToolbarHelpDemo() {
  const G = (p) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">{p}</svg>;
  return (
    <div style={{ width: 600, background: PX.paper, fontFamily: PX.sans, color: PX.ink, padding: 30, boxSizing: 'border-box' }}>
      <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3, marginBottom: 14 }}>
        Toolbar entry — the "?" lives beside search &amp; settings
      </div>
      <div style={{ background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 16, padding: '14px 18px', display: 'flex', alignItems: 'center' }}>
        <span style={{ fontFamily: PX.serif, fontSize: 22, fontWeight: 500, color: PX.ink, letterSpacing: -0.4 }}>HiMem</span>
        <span style={{ flex: 1 }} />
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 18, color: PX.ink }}>
          {G(<><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></>)}
          {/* the new help glyph */}
          <span style={{ display: 'inline-flex', color: PX.ink }}>
            {G(<><circle cx="12" cy="12" r="9"/><path d="M9.2 9a2.8 2.8 0 015.4 1c0 1.8-2.6 2.4-2.6 2.4M12 17h.01"/></>)}
          </span>
          {G(<><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.3 1.8M4.6 9a1.7 1.7 0 00-.3-1.8"/></>)}
        </div>
      </div>
      <div style={{ fontSize: 13, color: PX.ink3, lineHeight: 1.5, marginTop: 14, maxWidth: 460 }}>
        A quiet, warm-ink <strong style={{ color: PX.ink2, fontWeight: 600 }}>?</strong> glyph (never iOS blue) sits in the top toolbar next to search and settings. Tapping it opens the Tutorials hub. Also reachable from Settings.
      </div>
    </div>
  );
}

Object.assign(window, {
  ScrSettingsMenu, ScrSettingsAppearance, ScrSettingsEditTopic, ScrCapturedClipsEmpty,
  ScrTutorialsHub, ToolbarHelpDemo,
  SGroup, SRow, SToggle, SStepper, SettingsBar,
});

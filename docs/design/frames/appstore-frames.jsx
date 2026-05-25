// Himem · App Store marketing frames
// Six 600×1300 compositions following Crucible rules:
// cream paper, ochre only for capture frame, AI blue only for project frame.

const StatusBar = ({ dark }) => (
  <div className="status" style={dark ? { color:'#fff' } : null}>
    <div>9:41</div>
    <div className="right">
      {/* signal */}
      <svg width="18" height="11" viewBox="0 0 18 11" fill="none">
        <rect x="0"  y="7" width="3" height="4" rx="0.5" fill="currentColor"/>
        <rect x="5"  y="5" width="3" height="6" rx="0.5" fill="currentColor"/>
        <rect x="10" y="3" width="3" height="8" rx="0.5" fill="currentColor"/>
        <rect x="15" y="0" width="3" height="11" rx="0.5" fill="currentColor"/>
      </svg>
      {/* wifi */}
      <svg width="16" height="11" viewBox="0 0 16 11" fill="none">
        <path d="M8 10.5a1 1 0 100-2 1 1 0 000 2z" fill="currentColor"/>
        <path d="M4 7.5c1.1-1.2 2.5-1.8 4-1.8s2.9.6 4 1.8" stroke="currentColor" strokeWidth="1.5" fill="none"/>
        <path d="M1.5 5c1.8-1.9 4-2.8 6.5-2.8s4.7.9 6.5 2.8" stroke="currentColor" strokeWidth="1.5" fill="none"/>
      </svg>
      {/* battery */}
      <svg width="26" height="12" viewBox="0 0 26 12" fill="none">
        <rect x="0.5" y="0.5" width="22" height="11" rx="2.5" stroke="currentColor" opacity="0.4" fill="none"/>
        <rect x="2" y="2" width="19" height="8" rx="1.5" fill="currentColor"/>
        <rect x="23.5" y="3.5" width="2" height="5" rx="1" fill="currentColor" opacity="0.4"/>
      </svg>
    </div>
  </div>
);

// ─────────────────────────────────────────────────────────────────────────────
// Frame 1 — "Catch the thought before it's gone."  (Watch, mid-recording)
// Ochre background; the only frame that is ochre.
// ─────────────────────────────────────────────────────────────────────────────
function Frame1() {
  return (
    <div className="frame ochre">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom:18 }}>Apple Watch</div>
        <div className="headline" style={{ fontSize:64, color:'#F7F1E8' }}>
          Catch the thought<br/>before it's gone.
        </div>
        <div style={{ marginTop:22, fontSize:20, lineHeight:1.45, color:'rgba(247,241,232,0.78)', fontFamily:'var(--sf)', maxWidth:480 }}>
          Raise your wrist. Speak. Himem holds it until you're ready to look at it.
        </div>
      </div>

      <div className="watch" style={{ left:'50%', top:780, transform:'translateX(-50%)' }}>
        <div className="screen">
          {/* Top chrome: Cancel ✕ corner glyph (left) + system time (right) */}
          <div style={{ position:'absolute', top:12, left:14, width:24, height:24, display:'flex', alignItems:'center', justifyContent:'center', color:'rgba(247,241,232,0.55)' }}>
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
              <path d="M2 2l10 10M12 2L2 12"/>
            </svg>
          </div>
          <div style={{ position:'absolute', top:14, right:16, fontSize:12, fontWeight:600, color:'rgba(247,241,232,0.7)', fontVariantNumeric:'tabular-nums' }}>
            9:41
          </div>
          {/* Recording status */}
          <div style={{ position:'absolute', top:42, left:0, right:0, textAlign:'center', fontSize:11, fontWeight:700, color:'#C64A1C', letterSpacing:'0.16em' }}>
            ● REC
          </div>
          {/* Big timer + persistent on-a-roll state line */}
          <div style={{ position:'absolute', top:'46%', left:0, right:0, transform:'translateY(-50%)', textAlign:'center' }}>
            <div style={{ fontSize:48, fontWeight:300, fontVariantNumeric:'tabular-nums', letterSpacing:'-0.02em' }}>0:23</div>
            <div style={{ marginTop:6, fontSize:13, fontWeight:600, color:'#E8946B', letterSpacing:'0.01em' }}>Clip 2 · on a roll</div>
          </div>
          {/* Live waveform */}
          <div style={{ position:'absolute', bottom:96, left:36, right:36, display:'flex', gap:3, alignItems:'center', justifyContent:'center', height:36 }}>
            {Array.from({length:34}).map((_,i)=>{
              const h = 6 + Math.abs(Math.sin(i*0.9))*28 + (i%5===0?6:0);
              return <div key={i} style={{ width:3, height:h, background: i<22 ? '#F7F1E8' : 'rgba(247,241,232,0.25)', borderRadius:2 }}/>;
            })}
          </div>
          {/* Stop & save (cream hero) + Next-clip glyph (ochre, forward-chevron-with-dot) */}
          <div style={{ position:'absolute', bottom:24, left:18, right:18, display:'flex', gap:10, justifyContent:'center' }}>
            <div style={{ flex:1, height:52, background:'#F1ECE3', color:'#000', borderRadius:26, display:'flex', alignItems:'center', justifyContent:'center', fontSize:15, fontWeight:600 }}>
              Stop & save
            </div>
            <div style={{ width:52, height:52, background:'#C64A1C', borderRadius:26, display:'flex', alignItems:'center', justifyContent:'center', color:'#fff' }}>
              <svg width="20" height="14" viewBox="0 0 20 14" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                <path d="M2 2l5 5-5 5"/>
                <circle cx="14" cy="7" r="1.4" fill="currentColor" stroke="none"/>
              </svg>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 2 — "Your voice. Kept."  (Memory detail, audio waveform as hero)
// ─────────────────────────────────────────────────────────────────────────────
function Frame2() {
  return (
    <div className="frame">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom:18 }}>Memory</div>
        <div className="headline" style={{ fontSize:64 }}>Your voice.<br/>Kept.</div>
        <div style={{ marginTop:22, fontSize:20, lineHeight:1.45, color:'var(--ink-2)', maxWidth:480 }}>
          The audio is the memory. Transcripts come after — and you can always edit them.
        </div>
      </div>

      <div className="phone" style={{ left:'50%', top:430, transform:'translateX(-50%)' }}>
        <div className="notch"/>
        <div className="screen">
          <StatusBar/>
          {/* nav */}
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', padding:'8px 22px 0', fontSize:17, fontWeight:600 }}>
            <span style={{ color:'var(--ochre)' }}>‹ Box</span>
            <span style={{ color:'var(--ochre)' }}>•••</span>
          </div>

          {/* title block */}
          <div style={{ padding:'22px 28px 0' }}>
            <div style={{ display:'flex', gap:8, alignItems:'center', fontSize:13, color:'var(--ink-2)' }}>
              <span className="dot" style={{ background:'#2F9E6B', width:7, height:7 }}/>
              <span>Garden</span>
              <span style={{ opacity:0.4 }}>·</span>
              <span>Tue, May 12</span>
            </div>
            <div style={{ fontFamily:'var(--serif)', fontWeight:500, fontSize:30, lineHeight:1.1, marginTop:10, letterSpacing:'-0.01em' }}>
              Lettuce went in earlier than last year.
            </div>
          </div>

          {/* audio hero */}
          <div style={{ margin:'22px 22px 0', padding:'22px 20px', background:'#fff', borderRadius:22, boxShadow:'0 1px 0 rgba(26,22,18,0.04)' }}>
            <div style={{ display:'flex', alignItems:'center', gap:14 }}>
              <div style={{ width:52, height:52, borderRadius:26, background:'var(--ochre)', display:'flex', alignItems:'center', justifyContent:'center' }}>
                <div style={{ width:0, height:0, borderLeft:'14px solid #fff', borderTop:'9px solid transparent', borderBottom:'9px solid transparent', marginLeft:4 }}/>
              </div>
              <div style={{ flex:1 }}>
                <div style={{ display:'flex', gap:2, alignItems:'center', height:46 }}>
                  {Array.from({length:48}).map((_,i)=>{
                    const h = 4 + Math.abs(Math.sin(i*0.7 + i*0.05))*36 + (i%4===0?4:0);
                    const played = i < 14;
                    return <div key={i} style={{ width:3, height:h, background: played ? 'var(--ochre)' : 'rgba(26,22,18,0.18)', borderRadius:2 }}/>;
                  })}
                </div>
                <div style={{ display:'flex', justifyContent:'space-between', marginTop:6, fontSize:12, color:'var(--ink-2)', fontVariantNumeric:'tabular-nums' }}>
                  <span>0:47</span><span>2:18</span>
                </div>
              </div>
            </div>
          </div>

          {/* transcript demoted below */}
          <div style={{ padding:'22px 28px 0' }}>
            <div style={{ display:'flex', alignItems:'center', gap:8, fontSize:12, color:'var(--ink-2)', textTransform:'uppercase', letterSpacing:'0.1em', fontWeight:600 }}>
              <span>Transcript</span>
              <span style={{ background:'rgba(26,22,18,0.06)', padding:'2px 8px', borderRadius:8, textTransform:'none', letterSpacing:0, fontSize:11 }}>editable</span>
            </div>
            <div style={{ marginTop:10, fontSize:15, lineHeight:1.5, color:'var(--ink)' }}>
              Put the lettuce in this morning — about three weeks earlier than last year. The soil was already warm, which surprised me. If this works, I should bring the peas forward too.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 3 — "Sort it out when you're ready."  (Captured Clips, session card)
// Operational surface: SF Pro everywhere, denser, no editorial type.
// ─────────────────────────────────────────────────────────────────────────────
function Frame3() {
  return (
    <div className="frame">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom:18 }}>Captured Clips</div>
        <div className="headline" style={{ fontSize:64 }}>Sort it out<br/>when you're ready.</div>
        <div style={{ marginTop:22, fontSize:20, lineHeight:1.45, color:'var(--ink-2)', maxWidth:480 }}>
          Watch captures bundle into sessions. Turn each one into a memory in a tap.
        </div>
      </div>

      <div className="phone" style={{ left:'50%', top:430, transform:'translateX(-50%)' }}>
        <div className="notch"/>
        <div className="screen">
          <StatusBar/>
          {/* nav */}
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'baseline', padding:'10px 24px 0' }}>
            <span style={{ color:'var(--ochre)', fontSize:17, fontWeight:600 }}>‹ Today</span>
            <span style={{ fontSize:13, color:'var(--ink-2)' }}>4 sessions</span>
          </div>
          <div style={{ padding:'12px 24px 0', fontSize:28, fontWeight:700, letterSpacing:'-0.01em' }}>
            Captured Clips
          </div>

          {/* session card (focused) */}
          <div style={{ margin:'18px 18px 0', padding:'18px 18px 16px', background:'#fff', borderRadius:18, boxShadow:'0 1px 2px rgba(0,0,0,0.04), 0 6px 18px rgba(0,0,0,0.05)' }}>
            <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', fontSize:12, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase' }}>
              <span>Today · 7:42 AM</span>
              <span>4 clips · 3:18</span>
            </div>
            <div style={{ marginTop:10, fontSize:18, fontWeight:600, lineHeight:1.3 }}>
              "…the deer fence has a gap by the back corner I keep meaning to fix…"
            </div>
            <div style={{ marginTop:8, fontSize:13, color:'var(--ink-2)', lineHeight:1.4 }}>
              4 clips captured on a roll, 16 seconds apart.
            </div>
            {/* mini waveforms in a row */}
            <div style={{ marginTop:14, display:'flex', gap:6 }}>
              {[18,22,14,20].map((n,i)=>(
                <div key={i} style={{ flex:1, height:28, background:'rgba(198,74,28,0.08)', borderRadius:6, display:'flex', alignItems:'center', justifyContent:'space-around', padding:'0 4px' }}>
                  {Array.from({length:n}).map((_,j)=>(
                    <div key={j} style={{ width:2, height: 4 + Math.abs(Math.sin(j*0.7))*16, background:'var(--ochre)', borderRadius:1, opacity:0.85 }}/>
                  ))}
                </div>
              ))}
            </div>
            {/* primary action */}
            <div style={{ marginTop:16, display:'flex', gap:8 }}>
              <div style={{ flex:1, height:44, background:'var(--ink)', color:'#F1ECE3', borderRadius:12, display:'flex', alignItems:'center', justifyContent:'center', fontSize:15, fontWeight:600 }}>
                Make a Memory
              </div>
              <div style={{ width:44, height:44, background:'rgba(26,22,18,0.06)', borderRadius:12, display:'flex', alignItems:'center', justifyContent:'center', fontSize:18 }}>›</div>
            </div>
          </div>

          {/* second session card (compressed) */}
          <div style={{ margin:'12px 18px 0', padding:'14px 18px', background:'rgba(255,255,255,0.6)', borderRadius:18, border:'1px solid var(--line-2)' }}>
            <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', fontSize:12, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase' }}>
              <span>Yesterday · 9:11 PM</span>
              <span>2 clips · 1:04</span>
            </div>
            <div style={{ marginTop:6, fontSize:15, color:'var(--ink)', lineHeight:1.35 }}>
              "…that book Mira mentioned about attention…"
            </div>
          </div>

          {/* third */}
          <div style={{ margin:'10px 18px 0', padding:'14px 18px', background:'rgba(255,255,255,0.6)', borderRadius:18, border:'1px solid var(--line-2)' }}>
            <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', fontSize:12, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase' }}>
              <span>Sun · 2:08 PM</span>
              <span>1 clip · 0:42</span>
            </div>
            <div style={{ marginTop:6, fontSize:15, color:'var(--ink)', lineHeight:1.35 }}>
              "…idea for the talk on Tuesday…"
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 4 — "Find the thread."  (Project detail, AI-blue paragraph)
// Only frame where AI blue appears.
// ─────────────────────────────────────────────────────────────────────────────
function Frame4() {
  return (
    <div className="frame">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom:18, color:'var(--ai-blue)', opacity:1 }}>Projects</div>
        <div className="headline" style={{ fontSize:64 }}>Find<br/>the thread.</div>
        <div style={{ marginTop:22, fontSize:20, lineHeight:1.45, color:'var(--ink-2)', maxWidth:480 }}>
          Group memories around what you're building toward. Himem can summarise the thread when you want it.
        </div>
      </div>

      <div className="phone" style={{ left:'50%', top:430, transform:'translateX(-50%)' }}>
        <div className="notch"/>
        <div className="screen">
          <StatusBar/>
          {/* nav */}
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', padding:'10px 24px 0' }}>
            <span style={{ color:'var(--ochre)', fontSize:17, fontWeight:600 }}>‹ Projects</span>
            <span style={{ color:'var(--ochre)', fontSize:17, fontWeight:600 }}>Edit</span>
          </div>
          <div style={{ padding:'18px 24px 0' }}>
            <div style={{ fontSize:12, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase' }}>Project</div>
            <div style={{ fontFamily:'var(--serif)', fontWeight:500, fontSize:32, lineHeight:1.1, marginTop:6, letterSpacing:'-0.01em' }}>
              Learning to grow vegetables.
            </div>
            <div style={{ marginTop:8, fontSize:14, color:'var(--ink-2)', lineHeight:1.45 }}>
              What I notice across seasons, what I want to try next.
            </div>
          </div>

          {/* AI summary card */}
          <div style={{ margin:'18px 18px 0', padding:'16px 18px', background:'rgba(30,92,142,0.06)', borderRadius:16, border:'1px solid rgba(30,92,142,0.16)' }}>
            <div style={{ display:'flex', alignItems:'center', gap:8 }}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <path d="M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4L12 2z" fill="#1E5C8E"/>
              </svg>
              <span style={{ fontSize:12, fontWeight:700, color:'var(--ai-blue)', letterSpacing:'0.06em', textTransform:'uppercase' }}>Find the thread</span>
              <span style={{ marginLeft:'auto', fontSize:11, color:'var(--ai-blue)', opacity:0.7 }}>Just now</span>
            </div>
            <div style={{ marginTop:10, fontSize:15, lineHeight:1.5, color:'var(--ink)' }}>
              You're paying close attention to timing — when you put things in the ground, and how it compares to last year. The lettuce going in three weeks early is the clearest pattern so far. Two memories mention bringing the peas forward too.
            </div>
          </div>

          {/* suggested memory */}
          <div style={{ margin:'16px 18px 0', padding:'14px 16px', background:'#fff', borderRadius:14, border:'1px dashed rgba(30,92,142,0.35)' }}>
            <div style={{ fontSize:11, fontWeight:700, color:'var(--ai-blue)', letterSpacing:'0.08em', textTransform:'uppercase' }}>Suggested</div>
            <div style={{ marginTop:6, fontSize:15, fontWeight:600 }}>"Frost dates in this valley."</div>
            <div style={{ marginTop:4, fontSize:13, color:'var(--ink-2)' }}>Apr 3 · mentions soil temperature</div>
            <div style={{ marginTop:10, display:'flex', gap:8 }}>
              <div style={{ flex:1, height:34, borderRadius:8, background:'var(--ai-blue)', color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', fontSize:13, fontWeight:600 }}>Add to project</div>
              <div style={{ width:80, height:34, borderRadius:8, background:'rgba(26,22,18,0.04)', display:'flex', alignItems:'center', justifyContent:'center', fontSize:13, color:'var(--ink-2)' }}>Dismiss</div>
            </div>
          </div>

          {/* existing memory tile */}
          <div style={{ margin:'14px 18px 0', padding:'14px 16px', background:'#fff', borderRadius:14, border:'1px solid var(--line-2)' }}>
            <div style={{ fontSize:13, color:'var(--ink-2)' }}>May 12 · Garden</div>
            <div style={{ marginTop:4, fontSize:15, fontWeight:500 }}>"Lettuce went in earlier than last year."</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 5 — "Today, quietly."  (Today landing with inbox banner)
// ─────────────────────────────────────────────────────────────────────────────
function Frame5() {
  return (
    <div className="frame">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom:18 }}>Today</div>
        <div className="headline" style={{ fontSize:64 }}>Today,<br/>quietly.</div>
        <div style={{ marginTop:22, fontSize:20, lineHeight:1.45, color:'var(--ink-2)', maxWidth:480 }}>
          Himem opens to what you wrote on this day before. No streaks. No nudges.
        </div>
      </div>

      <div className="phone" style={{ left:'50%', top:430, transform:'translateX(-50%)' }}>
        <div className="notch"/>
        <div className="screen">
          <StatusBar/>
          <div style={{ padding:'14px 24px 0', display:'flex', justifyContent:'space-between', alignItems:'center' }}>
            <span style={{ fontSize:13, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase' }}>Tuesday · May 19</span>
            <div style={{ width:32, height:32, borderRadius:16, background:'rgba(26,22,18,0.06)', display:'flex', alignItems:'center', justifyContent:'center', fontSize:14, fontWeight:600 }}>D</div>
          </div>
          <div style={{ padding:'8px 24px 0', fontFamily:'var(--serif)', fontWeight:500, fontSize:34, lineHeight:1.05, letterSpacing:'-0.015em' }}>
            Today.
          </div>

          {/* inbox banner */}
          <div style={{ margin:'18px 18px 0', padding:'14px 16px', background:'#fff', borderRadius:14, border:'1px solid var(--line-2)', display:'flex', alignItems:'center', gap:12, boxShadow:'0 1px 2px rgba(0,0,0,0.03)' }}>
            <div style={{ width:36, height:36, borderRadius:18, background:'rgba(198,74,28,0.10)', color:'var(--ochre)', display:'flex', alignItems:'center', justifyContent:'center', fontSize:18, fontWeight:700 }}>4</div>
            <div style={{ flex:1 }}>
              <div style={{ fontSize:15, fontWeight:600 }}>4 new from Apple Watch</div>
              <div style={{ fontSize:13, color:'var(--ink-2)', marginTop:2 }}>Tap when you're ready to look at them.</div>
            </div>
            <span style={{ color:'var(--ochre)', fontSize:20 }}>›</span>
          </div>

          {/* on this day section */}
          <div style={{ padding:'24px 24px 0' }}>
            <div style={{ fontSize:12, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.1em', textTransform:'uppercase' }}>One year ago</div>
            <div style={{ marginTop:10, padding:'16px 18px', background:'#fff', borderRadius:16 }}>
              <div style={{ display:'flex', alignItems:'center', gap:8, fontSize:12, color:'var(--ink-2)' }}>
                <span className="dot" style={{ background:'#8A55D1', width:7, height:7 }}/>
                <span>Family</span>
                <span style={{ opacity:0.4 }}>·</span>
                <span>May 19, 2025</span>
              </div>
              <div style={{ fontFamily:'var(--serif)', fontWeight:500, fontSize:22, lineHeight:1.2, marginTop:10, letterSpacing:'-0.005em' }}>
                Dad showed me how he sharpens the kitchen knives.
              </div>
              <div style={{ marginTop:10, fontSize:14, color:'var(--ink-2)', lineHeight:1.45 }}>
                He uses the same stone his father used. I asked him to talk through it while I recorded.
              </div>
            </div>
          </div>

          {/* footer hint */}
          <div style={{ padding:'18px 24px 0', fontSize:13, color:'var(--ink-2)' }}>
            Nothing scheduled. Nothing to clear.
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame 6 — "Your memory box."  (Memory Box grid, generous whitespace)
// ─────────────────────────────────────────────────────────────────────────────
function Frame6() {
  const items = [
    { topic:'garden',  dot:'#2F9E6B', date:'May 12', title:'Lettuce went in earlier than last year.', kind:'audio', dur:'2:18' },
    { topic:'family',  dot:'#8A55D1', date:'May 09', title:'Dad on his father\'s knife stone.', kind:'audio', dur:'4:02' },
    { topic:'ideas',   dot:'#C08A1F', date:'May 07', title:'A book on attention Mira keeps mentioning.', kind:'text' },
    { topic:'travel',  dot:'#1F8FB3', date:'Apr 28', title:'The little inn outside Kanazawa.', kind:'photo' },
    { topic:'work',    dot:'#4A5C6E', date:'Apr 22', title:'Why the Tuesday talk needs a different opening.', kind:'audio', dur:'1:47' },
    { topic:'health',  dot:'#CF3A4E', date:'Apr 18', title:'Walking again. Knee felt fine today.', kind:'text' },
  ];
  return (
    <div className="frame">
      <div className="top-text">
        <div className="eyebrow" style={{ marginBottom:18 }}>Memory Box</div>
        <div className="headline" style={{ fontSize:64 }}>Your<br/>memory box.</div>
        <div style={{ marginTop:22, fontSize:20, lineHeight:1.45, color:'var(--ink-2)', maxWidth:480 }}>
          Everything you've kept, in one warm shelf. Browse, search, or just wander.
        </div>
      </div>

      <div className="phone" style={{ left:'50%', top:430, transform:'translateX(-50%)' }}>
        <div className="notch"/>
        <div className="screen">
          <StatusBar/>
          <div style={{ padding:'12px 24px 0', display:'flex', justifyContent:'space-between', alignItems:'center' }}>
            <span style={{ color:'var(--ochre)', fontSize:17, fontWeight:600 }}>‹ Today</span>
            <span style={{ color:'var(--ochre)', fontSize:17, fontWeight:600 }}>Search</span>
          </div>
          <div style={{ padding:'14px 24px 0', fontSize:28, fontWeight:700, letterSpacing:'-0.01em' }}>
            Memory Box
          </div>
          <div style={{ padding:'4px 24px 0', fontSize:13, color:'var(--ink-2)' }}>
            218 memories · 9 topics
          </div>

          {/* topic chips */}
          <div style={{ padding:'14px 24px 0', display:'flex', gap:8, flexWrap:'wrap' }}>
            {[
              ['All', null], ['Garden','#2F9E6B'], ['Family','#8A55D1'], ['Ideas','#C08A1F'], ['Travel','#1F8FB3']
            ].map(([label,dot],i)=>(
              <div key={i} className="pill" style={i===0 ? { background:'var(--ink)', color:'#F1ECE3' } : null}>
                {dot && <span className="dot" style={{ background:dot, width:7, height:7 }}/>}
                <span>{label}</span>
              </div>
            ))}
          </div>

          {/* memory list */}
          <div style={{ padding:'18px 18px 0', display:'flex', flexDirection:'column', gap:10 }}>
            {items.map((it,i)=>(
              <div key={i} style={{ padding:'14px 16px', background:'#fff', borderRadius:14, display:'flex', gap:12, alignItems:'flex-start' }}>
                <div style={{ marginTop:5 }}>
                  <span className="dot" style={{ background:it.dot, width:8, height:8, display:'inline-block' }}/>
                </div>
                <div style={{ flex:1, minWidth:0 }}>
                  <div style={{ fontSize:11, color:'var(--ink-2)', fontWeight:600, letterSpacing:'0.06em', textTransform:'uppercase' }}>
                    {it.topic} · {it.date}
                  </div>
                  <div style={{ marginTop:4, fontSize:14, fontWeight:500, lineHeight:1.3, color:'var(--ink)' }}>
                    {it.title}
                  </div>
                </div>
                {it.kind === 'audio' && (
                  <div style={{ display:'flex', alignItems:'center', gap:4, fontSize:11, color:'var(--ochre)', fontWeight:600, fontVariantNumeric:'tabular-nums' }}>
                    <svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 1l7 4-7 4z" fill="currentColor"/></svg>
                    {it.dur}
                  </div>
                )}
                {it.kind === 'photo' && (
                  <div style={{ width:26, height:26, borderRadius:6, background:'rgba(26,22,18,0.08)' }}/>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Frame1, Frame2, Frame3, Frame4, Frame5, Frame6 });

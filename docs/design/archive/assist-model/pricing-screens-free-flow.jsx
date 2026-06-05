// pricing-screens-free-flow.jsx
//
// Builds out the FREE-TIER MEMORY-ASSIST JOURNEY and the PLUS PACK-PURCHASE
// flow. Companions to the Memory Detail decision tree in
// pricing-screens-memory-detail.jsx — that tree codifies the per-memory
// states; this file maps how a free user moves THROUGH those states over
// time, and what the Plus user sees when they run out for the month.
//
// Components:
//   ScrFreeFlow         — wide decision-tree diagram (920×760)
//   ScrBundleSheetNoAI  — bundle sheet with timestamp fallback (no AI title)
//   ScrPlusPackModal    — bottom sheet to buy an assist pack without re-subbing
//
// Reused (don't redraw) — these now take new props:
//   ScrOnboardingStarter  — onboarding starter card (settings.jsx)
//   ScrMemoryIdle         — Memory Detail idle, takes assistsLeft / fromPack
//   ScrMemoryExhausted    — Memory Detail muted, takes variant 'free'|'plus'
//
// See "Open work · pricing flow.md" for the decisions this file builds on.

// ─────────────────────────────────────────────────────────────
// ScrFreeFlow — the decision-tree diagram
// ─────────────────────────────────────────────────────────────
function FlowNode({ label, sub, xref, beat, accent, paywall }) {
  return (
    <div style={{
      width: 132, flexShrink: 0,
      background: paywall ? PX.accentTint : PX.card,
      border: '1px solid ' + (paywall ? PX.accentTint2 : PX.hairline),
      borderRadius: 12, padding: '10px 12px',
      display: 'flex', flexDirection: 'column', gap: 4,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        fontSize: 9, fontWeight: 700, letterSpacing: 1.2, textTransform: 'uppercase',
        color: paywall ? PX.accent : PX.ink3,
      }}>
        {paywall && (
          <span style={{
            width: 7, height: 7, background: PX.accent, transform: 'rotate(45deg)',
            display: 'inline-block', flexShrink: 0,
          }}/>
        )}
        <span>{beat}</span>
      </div>
      <div style={{
        fontSize: 12.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1, lineHeight: 1.2,
      }}>{label}</div>
      {sub && (
        <div style={{ fontSize: 10.5, color: PX.ink2, lineHeight: 1.4, fontFamily: PX.serif, fontStyle: 'italic' }}>
          {sub}
        </div>
      )}
      {xref && (
        <div style={{
          fontSize: 9.5, color: PX.ink3, fontFamily: PX.mono, letterSpacing: 0.1,
          marginTop: 2, paddingTop: 4, borderTop: '1px solid ' + PX.divider,
        }}>{xref}</div>
      )}
    </div>
  );
}

function FlowArrow({ length = 24, dashed = false, label }) {
  return (
    <div style={{
      flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', padding: '0 2px',
    }}>
      {label && (
        <div style={{
          fontSize: 9.5, color: PX.ink3, fontFamily: PX.mono, marginBottom: 2, letterSpacing: 0.1,
        }}>{label}</div>
      )}
      <svg width={length} height="10" viewBox={`0 0 ${length} 10`} fill="none">
        <path
          d={`M0 5h${length - 4}`}
          stroke={PX.ink4} strokeWidth="1.4" strokeLinecap="round"
          strokeDasharray={dashed ? '3 3' : undefined}
        />
        <path d={`M${length - 6} 1l5 4-5 4`} stroke={PX.ink4} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </div>
  );
}

function ScrFreeFlow() {
  return (
    <div style={{
      width: '100%', height: '100%', background: PX.paper,
      fontFamily: PX.sans, color: PX.ink, padding: 28,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      {/* Header */}
      <div style={{ marginBottom: 16 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
          Free tier · memory-assist journey
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 24, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, lineHeight: 1.15 }}>
          Where the paywalls land.
        </div>
        <div style={{ fontSize: 12.5, color: PX.ink2, lineHeight: 1.55, marginTop: 6, maxWidth: 720 }}>
          A free user gets <strong style={{ color: PX.ink, fontWeight: 600 }}>3 starter assists</strong> for AI Organize. The product never blocks capture, storage, manual organize, or search — those stay free forever. Only the AI-helper path is metered. Three ochre diamonds mark where the meter <em>shows</em>, not where the app stops.
        </div>
      </div>

      {/* Flow row */}
      <div style={{
        background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
        padding: '22px 18px', marginBottom: 16,
      }}>
        <div style={{
          display: 'flex', alignItems: 'stretch', gap: 0, justifyContent: 'flex-start',
        }}>
          <FlowNode
            beat="Beat 1"
            label="Signup"
            sub="No paywall. Capture works on day zero."
          />
          <FlowArrow length={28}/>
          <FlowNode
            beat="Beat 2"
            label="Starter granted"
            sub="3 of 3 assists, on the house."
            xref="→ free-start"
          />
          <FlowArrow length={28}/>
          <FlowNode
            beat="Beat 3"
            label="First Organize"
            sub="User spends 1. Two left."
            xref="→ free-3-left"
          />
          <FlowArrow length={28}/>
          <FlowNode
            beat="Paywall 1"
            label="1 assist left"
            sub="Ambient cue, no modal."
            xref="→ free-1-left"
            paywall
          />
          <FlowArrow length={28}/>
          <FlowNode
            beat="Paywall 2"
            label="Exhausted"
            sub="Card mutes. Upgrade CTA in place."
            xref="→ free-mem-exhaust"
            paywall
          />
          <FlowArrow length={28}/>
          <FlowNode
            beat="Convert"
            label="Upgrade Hub"
            sub="Plus monthly · yearly · Founders · packs."
            xref="→ ScrUpgradeHub"
          />
        </div>

        {/* Side branch — bundle sheet without assists */}
        <div style={{ marginTop: 24, paddingTop: 16, borderTop: '1px solid ' + PX.divider, display: 'flex', alignItems: 'center', gap: 0 }}>
          <div style={{ width: 132, flexShrink: 0, paddingLeft: 0 }}>
            <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase', color: PX.ink3, marginBottom: 4 }}>
              Side branch
            </div>
            <div style={{ fontSize: 11.5, color: PX.ink2, lineHeight: 1.4, fontFamily: PX.serif, fontStyle: 'italic' }}>
              Bundling a session after assists run out.
            </div>
          </div>
          <FlowArrow length={28} dashed/>
          <FlowNode
            beat="Bundle sheet"
            label="0 assists"
            sub="Timestamp title fallback. AI link routes to Upgrade."
            xref="→ free-bundle-no-ai"
          />
          <FlowArrow length={28} dashed label="opt-in"/>
          <FlowNode
            beat="Convert"
            label="Upgrade Hub"
            sub="Same destination as the main path."
            xref="→ ScrUpgradeHub"
          />
        </div>
      </div>

      {/* Legend / rules */}
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 18,
        fontSize: 11, color: PX.ink3, lineHeight: 1.55,
      }}>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>
            <span style={{ display: 'inline-block', width: 7, height: 7, background: PX.accent, transform: 'rotate(45deg)', marginRight: 8, verticalAlign: 'middle' }}/>
            Paywall rule
          </div>
          <div>Three moments where free users <em>see</em> the meter: 1-left, exhausted, and the bundle-sheet AI link. Capture, storage, manual organize and search never trigger any of these.</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Decrement rule</div>
          <div>A starter assist is consumed only on a committed whole-memory pass. Accept / edit / skip / failed pass all cost <strong style={{ color: PX.ink, fontWeight: 600 }}>0</strong>. Matches the Plus rule — tier never changes <em>what</em> consumes an assist.</div>
        </div>
        <div>
          <div style={{ fontSize: 10, fontWeight: 700, color: PX.ink3, letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: 6 }}>Routing</div>
          <div>All free terminal CTAs go to <code style={{ fontFamily: PX.mono, fontSize: 10.5 }}>ScrUpgradeHub</code>. No mid-flow pack purchase for free — packs are a Plus tool. See <code style={{ fontFamily: PX.mono, fontSize: 10.5 }}>plus-pack</code> section below.</div>
        </div>
      </div>

      <div style={{ flex: 1 }}/>
      <div style={{
        fontSize: 10.5, color: PX.ink3, lineHeight: 1.5, fontFamily: PX.serif, fontStyle: 'italic',
        paddingTop: 14, borderTop: '1px solid ' + PX.divider,
      }}>
        Plus users hitting the same per-month exhaustion follow a different route: see <strong style={{ fontWeight: 600, fontStyle: 'normal', fontFamily: PX.mono }}>§ plus-pack</strong> for the additive assist-pack flow.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// ScrBundleSheetNoAI — bundle sheet, 0 assists
// Free user has consolidated a watch session into a new memory.
// Without assists, the sheet skips the AI title and falls back
// to a timestamp. Inline "Get AI title · 1 assist" link routes
// to the Upgrade Hub (handoff doc Gap 1 — confirmed).
// ─────────────────────────────────────────────────────────────
function BehindCapturedClips() {
  // A thin mock of Captured Clips behind the sheet, just so the
  // scrim has something to dim. Not a full re-mock of that surface.
  return (
    <div style={{ width: 340, height: 735, background: PX.paper, padding: '48px 0 0', fontFamily: PX.sans }}>
      <div style={{ padding: '14px 20px 12px' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase', color: PX.ink3 }}>
          From Apple Watch
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 28, fontWeight: 400, letterSpacing: -0.4, color: PX.ink, marginTop: 6 }}>
          Captured Clips
        </div>
      </div>
      <div style={{ padding: '0 14px' }}>
        <div style={{
          background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 14,
          padding: '12px 14px',
        }}>
          <div style={{ fontSize: 11, color: PX.ink3, marginBottom: 4, letterSpacing: 0.2 }}>Session · 4 clips · 12 min</div>
          <div style={{ fontFamily: PX.serif, fontSize: 14, color: PX.ink, lineHeight: 1.4 }}>
            <em>Today · 4:32 pm</em>
          </div>
        </div>
      </div>
    </div>
  );
}

function BundleClipRow({ time, body, isLast }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 10,
      padding: '10px 0', borderBottom: isLast ? 'none' : '1px solid ' + PX.divider,
    }}>
      <span style={{
        width: 6, height: 6, borderRadius: 3, background: PX.accent,
        marginTop: 7, flexShrink: 0,
      }}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 10.5, color: PX.ink3, marginBottom: 2, letterSpacing: 0.2, fontFamily: PX.mono }}>
          {time}
        </div>
        <div style={{ fontFamily: PX.serif, fontSize: 13, lineHeight: 1.4, color: PX.ink, letterSpacing: -0.05 }}>
          {body}
        </div>
      </div>
    </div>
  );
}

function ScrBundleSheetNoAI() {
  return (
    <PhoneScreen>
      <Sheet behind={<BehindCapturedClips/>} height="88%">
        <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
          {/* Sheet header */}
          <div style={{
            display: 'flex', alignItems: 'center',
            padding: '14px 18px 10px',
            borderBottom: '1px solid ' + PX.divider,
          }}>
            <span style={{
              width: 28, height: 28, borderRadius: 14, background: PX.sunk,
              color: PX.ink3, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0, fontSize: 14, lineHeight: 1,
            }}>×</span>
            <span style={{ flex: 1 }}/>
            <span style={{ fontSize: 15, fontWeight: 600, color: PX.ink, letterSpacing: -0.15 }}>Bundle to memory</span>
            <span style={{ flex: 1 }}/>
            <span style={{ width: 28, flexShrink: 0 }}/>
          </div>

          {/* Body */}
          <div style={{ padding: '14px 18px 6px', overflow: 'auto', flex: 1 }}>

            {/* Title field — timestamp fallback */}
            <div style={{
              fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
              color: PX.ink3, marginBottom: 6,
            }}>Title</div>
            <div style={{
              background: PX.card, border: '1px solid ' + PX.hairline, borderRadius: 12,
              padding: '12px 14px', marginBottom: 8,
            }}>
              <div style={{
                fontFamily: PX.serif, fontSize: 17, lineHeight: 1.22, color: PX.ink,
                letterSpacing: -0.2, fontWeight: 400,
              }}>
                Voice clips · May 27, 4:32 PM
              </div>
              <div style={{ fontSize: 10.5, color: PX.ink3, marginTop: 4, fontFamily: PX.mono, letterSpacing: 0.2 }}>
                placeholder · edit any time
              </div>
            </div>

            {/* AI title affordance — costs an assist the user doesn't have */}
            <div style={{
              background: PX.sunk, borderRadius: 12,
              padding: '10px 12px', marginBottom: 18,
              display: 'flex', alignItems: 'center', gap: 10,
            }}>
              <span style={{
                width: 24, height: 24, borderRadius: 6, background: PX.accentTint, color: PX.accent,
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              }}>
                <Spark size={12}/>
              </span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12.5, fontWeight: 600, color: PX.ink, letterSpacing: -0.1 }}>
                  Get AI title
                </div>
                <div style={{ fontSize: 10.5, color: PX.ink3, marginTop: 1, lineHeight: 1.35 }}>
                  Summarizes the session in a few words.
                </div>
              </div>
              {/* Quiet "1 assist" link that routes to Upgrade Hub for 0-assist free users */}
              <span style={{
                flexShrink: 0, fontSize: 11.5, fontWeight: 600, color: PX.accent, letterSpacing: -0.05,
              }}>1 assist →</span>
            </div>

            {/* Clip list */}
            <div style={{
              fontSize: 10, fontWeight: 700, letterSpacing: 1.4, textTransform: 'uppercase',
              color: PX.ink3, marginBottom: 4,
            }}>4 clips included</div>
            <div>
              <BundleClipRow time="4:32 PM" body={<>The pear tree finally fruited. Three pears, hidden behind the leaves near the fence.</>}/>
              <BundleClipRow time="4:35 PM" body={<>Also — the marigolds are taking over the bed by the back door.</>}/>
              <BundleClipRow time="4:38 PM" body={<><em>(15-second clip · ambient sound)</em></>}/>
              <BundleClipRow time="4:44 PM" body={<>Note to self: take a photo of the pears before frost.</>} isLast/>
            </div>

            <div style={{ height: 12 }}/>
          </div>

          {/* Footer */}
          <div style={{
            padding: '12px 18px 20px',
            borderTop: '1px solid ' + PX.divider,
            background: PX.paper,
          }}>
            <Btn kind="primary">Save as memory</Btn>
            <div style={{
              fontSize: 10.5, color: PX.ink3, textAlign: 'center', marginTop: 8, lineHeight: 1.5,
            }}>
              Original audio is kept. You can rename or organize later — assists are optional.
            </div>
          </div>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

// ─────────────────────────────────────────────────────────────
// ScrPlusPackModal — buy an assist pack without changing subscription
// Triggered from ScrMemoryExhausted (variant='plus'). The user is
// staying Plus; the pack is additive and never expires.
// ─────────────────────────────────────────────────────────────
function BehindPlusExhausted() {
  // The Memory Detail screen dimmed behind the modal.
  return (
    <div style={{ width: 340, height: 735, background: PX.paper, padding: 0, fontFamily: PX.sans }}>
      <ScrMemoryExhausted variant="plus"/>
    </div>
  );
}

function ScrPlusPackModal() {
  return (
    <PhoneScreen>
      <Sheet behind={<BehindPlusExhausted/>} height="66%">
        <div style={{ padding: '14px 22px 26px', display: 'flex', flexDirection: 'column', height: '100%' }}>

          {/* Header */}
          <div style={{
            width: 36, height: 36, borderRadius: 10, background: PX.accentTint, color: PX.accent,
            display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14,
          }}>
            <Spark size={20}/>
          </div>
          <div style={{
            fontFamily: PX.serif, fontSize: 22, lineHeight: 1.2, letterSpacing: -0.3,
            color: PX.ink, marginBottom: 8,
          }}>
            Add more AI assists.
          </div>
          <div style={{ fontSize: 13.5, color: PX.ink2, lineHeight: 1.5, marginBottom: 18 }}>
            You&rsquo;ve used this month&rsquo;s 50. Buy a pack to keep going — your Plus subscription stays the same.
          </div>

          {/* PackTiles — reuses the existing component from settings.jsx */}
          <div style={{ display: 'flex', gap: 10, marginBottom: 14 }}>
            <PackTile assists={20} price="$4.99" per="$0.25 each"/>
            <PackTile assists={100} price="$19.99" per="$0.20 each" tag="Better value"/>
          </div>

          {/* Quiet reassurance — the two things a Plus user is uncertain about */}
          <div style={{
            background: PX.sunk, borderRadius: 12, padding: '10px 12px',
            display: 'flex', flexDirection: 'column', gap: 6,
            fontSize: 11.5, color: PX.ink2, lineHeight: 1.45,
          }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
              <Check size={11} color={PX.confirmed}/>
              <span>Packs never expire. They roll over month to month.</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
              <Check size={11} color={PX.confirmed}/>
              <span>Your $4.99/month Plus plan keeps going, untouched.</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
              <Check size={11} color={PX.confirmed}/>
              <span>Used after the included 50 each month — never before.</span>
            </div>
          </div>

          <div style={{ flex: 1 }}/>

          <Btn kind="primary">Buy 100 assists · $19.99</Btn>
          <Btn kind="ghost" size="md">Not now</Btn>
        </div>
      </Sheet>
    </PhoneScreen>
  );
}

Object.assign(window, {
  ScrFreeFlow, ScrBundleSheetNoAI, ScrPlusPackModal,
  FlowNode, FlowArrow, BehindCapturedClips, BehindPlusExhausted,
});

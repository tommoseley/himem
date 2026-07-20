# Release-hardening — submit in ~10 days (2026-07-20)

**For:** Claude Code · **From:** design/spec side. **Supersedes the "While Tom is away" ordering** in `Handoff · carry-forward punch list · 2026-07-14.md` for the pre-submit window — do that list's items *after* these unless noted.

**Context:** v1 core loop is dogfooding clean. Two independent reviews (CC's as-built §13 Divergences + GPT's critique) converged on the same short list. This is a **release-hardening pass, not architecture** — the product model is done enough. Ship path below, ordered.

**Discipline unchanged:** each item its own branch, Bug-First, four-part handoff, additive-then-device-verify, `[HiMem][TranscriptWipe]` arbiter live on clip-writing paths. **No Production CloudKit deploy while Apple's account migration is in progress** (see RH-2). Raise concerns, don't deviate.

---

## BLOCKERS — must land before submit

### RH-1 · Notifications → passive-only (the one North-Star violation)
**Ruling (Tom, July 20):** the whole passive rule, no finesse. Fix D1–D5:
- **Delete** the burst (≥3/5min), inbox-threshold (>10), and stale (>24h unreviewed) notification classes entirely — do not preserve them because they exist. The stale-clip buzz is "the app raising the skipped thing," forbidden by the North Star and the App Store "no nudges" promise.
- **All** Captured-Clips notifications: `.passive`, **no sound**, **no numeric badge** in any payload (`content.badge = nil`).
- **Honor quiet hours (22:00–06:59)** on the passive push too — first-of-stretch defers to 7am (currently only the deleted active classes checked).
- **One persisted user control**: wire the onboarding/Settings toggle so its state is actually consulted (today it's cosmetic; arrivals fire on OS permission alone). Settings shows the toggle, not just a permission row.
- Net end state = exactly `CLAUDE.md` §Notifications. Files: `WatchInboxNotificationCoordinator.swift`, `NotificationService.swift`, onboarding/Settings notification UI.

### RH-2 · CloudKit schema — reconcile truth, then deploy
- The **dashboard is truth.** Produce one definitive ledger: what's actually in **Production** (V6 `Project.recycledAt`, V7 mentions batch + `MediaReference.sourceDevice`) vs staged on Dev — the code comments and the 2026-07-18 session log disagree (D-schema). Record it in the eng doc §12.
- **V8 `MediaReference.recycledAt`** (P8 clip-level Recently Deleted) is **held for Apple's account migration**. When the migration clears: Dev → verify in dashboard → Deploy Schema Changes to Production **before** the next TestFlight. No release on inferred deploy state — an undeployed field saves locally and silently fails to propagate.
- (P8 *decision* logic is pure edge-count, needs no schema; `InboxClip.recycledAt` is a per-device manifest field that never deploys.)

---

## PRE-TRIP RELIABILITY — before the 45-day trip (not necessarily before submit)

### RH-3 · Watch: skip-if-AAC (D6)
`acceptArrivedClip` re-runs the already-mono/16k/AAC watch clip through `AudioCompressor.compressInPlace` — a measured ~2.7× attenuation on the signature capture path. Sniff the arrived format; skip recompression when it already conforms to the transfer contract. Fix the stale "raw Float32 PCM" header comment. Cheap, real quality win.

### RH-4 · Watch: contain the ack-storm (D7)
Dual-path `sendConfirmation` + full-inbox `reconcileWatchAcks` fan-out on every arrival + rollGroup fan-out, no emit-side coalescing → duplicate-ack storm. Add emit-side dedup/coalescing. Not a store blocker, but 45 days of heavy watch use turns this into battery drain / log noise / transfer churn / hard-to-repro races. Land before the trip.

---

## AI DIVERGENCES — rulings given, execute (docs + small code)

### RH-5 · Manual-only reorganize is correct; fix the spec, not the code (D12)
**Ruling:** the code wins — a completed organize pass stays until manual Reorganize; **no silent frontier repolish-on-reconnect.** Silent rewrites break trust. **Update `AI Organize · spec.md` §2/§9** to the explicit/manual model; leave the code (`feedback_no_auto_reprocess`). Doc-only.

### RH-6 · Cut `nextSteps` from v1 (D11)
**Ruling:** stop decoding output the model can't retain. Remove `nextSteps` from the client contract + any UI that consumes it (it's Plus-only, unpersisted — no `OrganizePass.nextStepsMarkdown` since V2). Keep the `AcceptedRowKey.nextSteps` enum case dormant. Re-add post-v1 *with* a durable editable home if it earns its place.

### RH-7 · On-device mentions: honest confidence, don't block (D14)
**Ruling:** accept the 3B-model limit. On-device/Free memories store mentions untyped → render the **neutral `.idea` glyph**, never a wrongly-typed person/place/org. Frontier/Plus types them. No blocking work; just ensure the UI never implies a type the on-device pass didn't produce.

---

## TRAILING CLEANUP — can follow the release (coherence, no ruling)
- D17 stale comments/refs (assist-metering doc comment in `appendClips`; "(Make a Memory · confirm sheet)"; `CLAUDE.md:149` "Loose"→"Unconnected"; "raw Float32 PCM").
- D18 build hygiene (stale base `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; verify `AudioCompressor.swift` target membership).
- D15 confirm the "Let Go" dynamic footnote is the intended surface (not a sheet).
- Search back-navigation (from the July-20 directive): memory detail returns to its origin (Search → Search with query+scroll preserved; list → list; project → project); back-label names the origin, not the day-group. Pure navigation, no deploy — safe during the migration. **Verify the typed query + results survive the round-trip.**
- P4(a) OPEN DECISION for Tom: Topics-list `.onDelete` in Settings — keep native swipe or convert to full-width Delete.

---

## After release-hardening, the earlier carry-forward queue resumes
P7 fast-follows (add-to-existing-memory; detach/reorg everConnected edge), associations remainder (ManageProjectsSheet / project read-section), 3/3b standing cleanups. Post-v1 candidates untouched: voice-register picker + AI alternative-summaries; Studio; project templates + domain-metadata schemas (`Project Templates · engineering design.md`).

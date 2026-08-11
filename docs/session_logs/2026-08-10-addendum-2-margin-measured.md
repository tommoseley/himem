# Session log · 2026-08-10 (addendum 2) · the margin measured · B19 · B20

Facts only. Immutable. **Written for a context-free reader.**

**No commits landed after `b1c8f13`.** This addendum exists because the previous log **records an absence that has since been closed**, and logs are never edited. `2026-08-10-addendum-probe-and-inflight.md` states under *What was NOT verified*:

> *"The absorber/grouper margin shift. The only remaining unknown in the swap. Needs a bench with media."*

That is now measured. Everything below happened after that file was sealed.

---

## Repo position (unchanged)

- Branch **`f8-overlay-and-wiring`** @ **`b1c8f13`**, **9 ahead of origin, UNPUSHED**.
- **`main` @ `36ce159`** — never involved at any point in this stretch.
- Tree clean of tracked code **except the 2b-ii-b red**, still deliberately uncommitted so the branch never carries a knowingly-failing gate. `docs/design/` holds Tom's uncommitted work plus **B14–B20**.

### Gate — re-run cold at close, both from result bundles

| Scheme | Result | Destination |
|---|---|---|
| `MemoryStream` | **1406 cases / 192 suites** — 1395 passed, 3 skips, **8 deliberate failures** | sim `E3C0710E` (**iOS 26.4.1**) |
| `Himem Watch Watch App` | **34 cases / 6 suites, 0 failed** | watch `B17233F6` + paired `74EED5FE` (**watchOS 26.5**) |

Phone exited 65 with **0 compile errors** and a `Test run with` line — an assertion red, not a launch or build failure. The 8 are `SpeechAssetGate`, membership byte-identical. **The 2b-ii-b red was held aside for this run**, so these numbers describe the committed tree rather than the working one. Runtimes held; no rotation.

---

## THE MARGIN SHIFT IS MEASURED — zero divergence

Device run **with media present**, including through the photo capture and multiple retry sweeps: **every `bench` reading `AGREE`. No `DIFFER` in 585 log lines.**

The prior all-AGREE result was explicitly caveated in the last addendum as a **media-free** bench, and therefore as *untested, not disproven*. That caveat is now discharged: the absorber's ±5-minute-from-span rule and the grouper's ≤10-minute-adjacency-with-chaining rule produce **no divergence on this data**, on both count arithmetic *and* media assignment.

**C2 step 2b-ii-c2 is therefore fully mechanical — a known-equal target on both axes.**

*Reach of the measurement, stated so it is not over-read:* this is **zero divergence observed at the placements this bench contains**, not a proof that the two rules coincide. They differ only in the 5–10 minute band, so a photo landing inside a session's core does not exercise it. The practical risk is low and the swap is one revertible commit behind guards; the distinction matters only if a future bench misbehaves at a boundary.

---

## B19 · a single 325 ms regroup

One `regroup` at **325 ms — 30× the usual 10–20 ms** — at the moment a new clip landed. **One occurrence in 585 lines**; every other regroup in the same run sat in the normal band.

**Noted, not chased** (ruled). Recorded with the **discriminator rather than a hypothesis**: a one-time cold-path cost at clip-landing (Core Data fault-in for the newly materialized ref, the manifest write, first read of the new transcript) and a spike that *recurs* or *scales with bench size* are different animals. `[BenchPerf]`'s `regroup` line already carries the ms and the session count needed to tell them apart if it returns.

## B20 · the silent-capture gate fired correctly on hardware — first time

Three recordings in one run:

- two silent — **`in_peak = 0.0000`** across **87** and **33** buffers
- one healthy — **`in_peak` 0.03–0.15**, compression **46.7×**

**The gate discriminated.** It did not fire on everything: 46.7× is a real recording, where silence compresses at ~831× (the ratio `AudioCompressorTests` once approved under a floor-only assertion, which is why *Assertions Need a Ceiling* exists).

The banner was **suppressed with the suppression announced** — `capture was silent — banner suppressed (debugger attached)` — which is the `P_TRACED` design working exactly as ruled 2026-08-02: detection always runs, the banner is withheld only under a debugger so an untethered TestFlight build still speaks, and the withholding is stated so it is never a silent skip.

**This closes an absence the 2026-08-02 addendum recorded as untested:**

> *"The capture gate's banner has never rendered… `DebuggerAttachment.isAttached` under a real debugger is **untested**."*

Both halves are now exercised on hardware. The silence itself is the **B10 Device Hub** state — previously mysterious, now instrumented.

---

## Open threads

- **2b-ii-c2 — the swap. FIRST THING NEXT SESSION, ONE COMMIT or not at all.** Composed state; `resolve` with premise 2 built in from the start; **F37's group-then-admit inversion**; header label **"N clips · M sessions"**; cards and header together; absorber retired; the held 2b-ii-b red turned green; paired gate before anything commits.
- **Every question that could stop it mid-edit is answered in advance** — the four premises, the F37 ruling, the header label, the session-term drop, and now both measured axes. That is the difference from the attempt that was reverted.
- Carried: B14 · B15 ▶ · B17 · B18 · B19 · D1 · D3 · D4 · D7 · F34/C15 · D9b · C1–C15.

## Risks

- **The swap is all-or-nothing** — intermediate states do not compile, so there is no green place to stop. It needs a full pass, not the tail of one.
- **`AGREE` is still easy to over-read.** It is now a *media-present* result, which is much stronger, but it remains "no divergence observed," not "the rules coincide."
- Disk cleared at close; derived-data trees removed per the exit-73 rule.

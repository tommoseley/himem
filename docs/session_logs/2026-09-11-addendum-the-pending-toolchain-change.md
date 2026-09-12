# Session log · 2026-09-11 (addendum) · the pending macOS + Command Line Tools change

Facts only. Immutable. **Written for a context-free reader.**

**This is an addendum, not a revision.** `2026-09-10-the-control-run-and-the-scope.md` stands as written and contains none of the below. It was sealed before this change was announced.

**No commits, no code, no gate.** This file exists to record an environment change that is **about to happen** and the baseline to diff it against — because the thing most likely to be misread next session is a toolchain that moved silently.

---

## What is changing, and when

Announced by Tom at session close, **after** the closing gate was run and the log sealed: **macOS is being updated, and Command Line Tools for Xcode 27.0 is being installed**, between this session and the next.

Both findings below are CD's, recorded as received.

---

## ① The OS moved again — that is THREE updates across the gap

The 09-10 log records the watch test-runner install failure (five consecutive `Invalid device state` / `Mach error -308` at `installApplication`) as **restored, cause unestablished**, with macOS a **candidate rather than a finding** because the failure no longer reproduces and no control can be run against it.

The timeline in that log named two updates:

```
08-25 09:30 local   first runner-install failure
08-26 19:00         last commit of the failing session
08-26 21:34         macOS update      ← 2h34m later
09-03 22:28         reboot
09-03 22:29         macOS update
09-11 (pending)     macOS update      ← THE THIRD
```

**Consequence, stated so it is not re-derived as a mystery: if the runner-install failure returns, the OS update is a CANDIDATE AGAIN, not a new phenomenon.** The failure was already correlated with the first two; a third update in the same series is the nearest environmental antecedent, and *Don't Go Looking for Zebras*' procedure applies — enumerate our own actions first, then reach outward, and name which listed action each outward hypothesis rules out.

**What this does NOT license.** Correlation across three updates is still not attribution. The clone hypothesis had a real asymmetry behind it and was disconfirmed by one control run; the OS hypothesis has no control available at all, which makes it **weaker evidence than the one already discarded, not stronger**. It is a place to look, never a conclusion to report.

**Where to look first, unchanged:** `~/Library/Logs/CoreSimulator/CoreSimulator.log` — 28,951 lines at last reading, spanning weeks, and the artifact that produced the clone finding. Note two limits already established: **`installApplication` appears 0 times in it** (the failing call is not recorded there), and **`DiagnosticReports` ages out in ~2 days**, so a crash report for a recurrence must be collected *while it is fresh* or it is gone.

---

## ② Command Line Tools may repoint `xcode-select`, and the failure mode INVERTS

Every gate in this project runs with an explicit `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, **precisely because `xcode-select -p` points at CommandLineTools**. That is a deliberate arrangement dating to 2026-07-30, not an accident, and it means no `sudo` has ever been required.

**The explicit `DEVELOPER_DIR` still protects the gates after the install.** It is an environment variable that overrides `xcode-select` outright. That is the reassuring half and it is true.

**The unreassuring half is what happens to the SAFETY NET.** Measured today, before the change:

```
$ xcodebuild -version                    # no DEVELOPER_DIR
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

**Today a naive invocation FAILS LOUDLY.** Anyone who forgets `DEVELOPER_DIR` gets an error, not a result.

**If the CLT install repoints `xcode-select` at an Xcode, that failure becomes a SUCCESS** — against whatever toolchain `xcode-select` now names, which may or may not be `27A5237l`. A missing `DEVELOPER_DIR` would stop being an error and start being a **silent toolchain substitution**, producing a well-formed gate number measured against something nobody chose.

That is the fifth measurement class exactly — a clean reading of the wrong quantity — and this project has already paid for its cousin: **the TestFlight seed rejection (08-22), where a toolchain that had not actually moved was assumed to have moved**, caught only because ruling 3 of that session required verifying `DTXcodeBuild` before archiving. The reverse case is the one arriving now.

**So: confirm, do not assume.** One command answers it, and the answer belongs in the next session's opening report either way.

---

## THE BASELINE TO DIFF AGAINST — measured 2026-09-11 21:45, BEFORE the change

This is the whole point of this file. A "nothing changed" claim next session must rest on a comparison, not on memory.

| Quantity | Value before the update |
|---|---|
| macOS | **27.0 (`26A5425a`)** |
| `xcode-select -p` | **`/Library/Developer/CommandLineTools`** |
| `xcodebuild -version` *(no `DEVELOPER_DIR`)* | **errors** — "requires Xcode … is a command line tools instance" |
| `xcodebuild -version` *(with `DEVELOPER_DIR`)* | **Xcode 27.0, build `27A5237l`** |
| `/Applications/Xcode-beta.app` | 27.0 (**`27A5237l`**) — the gate toolchain |
| `/Applications/Xcode-beta-27A5228h.app` | 27.0 (`27A5228h`) — Beta 4, preserved per the 08-22 ruling until Judi has run the build |
| iPhoneOS / iPhoneSimulator SDK | **`24A5408c`** |
| WatchOS / WatchSimulator SDK | **`24R5346a`** |
| Simulator runtimes (gate pins) | **iOS 26.4.1 `23E254a`** · **watchOS 26.5 `23T570`** |
| CommandLineTools pkg | version `27.0.0.0.1787197235`, installed `1787798747` |

**The SDK builds are the seed-rejection axis.** `24A5408c` is what the accepted TestFlight upload was built against. If it moves, the F6h expiry rule applies: *an empirical claim about a moving target must carry its seed and date inside the claim*, and TestFlight acceptance must be re-verified rather than inherited.

**The runtime pins are the gate's comparability.** The 8 deliberate `SpeechAssetGate` failures exist *because* the en_US asset is `unsupported` on **26.4.1**. A runtime that moves silently would change that count, and a run returning 5 failures or 0 is not good news — it is an **incomparable measurement that destroys the baseline while looking like a fix**.

---

## What the next session must do before trusting any number

Codified as a pre-flight step in the session-start process file, and repeated here so it survives even if that file is not read:

1. **`xcode-select -p`** — did it move? Record the answer either way.
2. **`xcodebuild -version` with and without `DEVELOPER_DIR`** — if the bare form now *succeeds*, the loud guard is gone; say so explicitly in the opening report.
3. **`sw_vers -buildVersion`** — against `26A5425a`.
4. **SDK builds** — against `24A5408c` / `24R5346a`.
5. **`xcrun simctl list runtimes`** — the pins must still read 26.4.1 and 26.5. **Never rotate onto a different runtime to fix a launch denial; erase and recreate on the same one.**
6. **Then run the paired gate** and compare to **1537 / 216** (8 deliberate, 0 crash lines) and **34 / 6**.

**Any of 1–5 moving makes the resulting gate a NEW BASELINE, not a confirmation** — the same rule applied when Xcode Beta 5 landed on 08-22, where the counts coincided and *the coincidence was explicitly recorded as not being continuity*.

---

## Open threads (unchanged from the 09-10 log, plus this)

- **The toolchain change above** — verify before trusting a gate; report the comparison either way.
- **The watch gate may fail again**; if it does, the OS update is a candidate again, and `CoreSimulator.log` is the first read.
- **One wiped-install pass answers reading #2 and B29 together** — `[HiMem][CKArc] setup ended ok +…ms` and `ubiquity update — re-entering sweep`, via the persistent log store, not a console bridge.
- **Nothing from the 09-10 session is device-verified.** Four items were found on hardware; all four fixes are simulator-only.
- Carried: B26's reconcile (held) · B27's partition axis · B30 · the layout flip · C2 step 5 · C1/C8 · D1 · D3 · D4 · D7 · D9b · F34/C15 · B19.

## Risks

- **A silent toolchain swap is the specific risk this file exists to prevent.** The protective failure mode that exists today may not exist tomorrow.
- **Three OS updates now sit across the watch-gate gap.** Correlation is not attribution, and no control is available.
- `main` and `f8` are **79 apart** (pushed). Conflict-watch files: `ClipsTabView.swift`, `EntryExpandedView.swift`, and now `ChronologicalCaptureStream.swift`.

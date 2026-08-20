#!/bin/bash
# Read a gate honestly, from the result bundle.
#
# WHY THIS EXISTS. On 2026-08-19 a hand-written crash grep matched only
# `crashed with signal abrt` — one of the phrasings — and reported "0 crashes in
# bundle" on a run carrying 51 of them under `Crash: HiMem at
# <deduplicated_symbol>`. CLAUDE.md § Test Concurrency already named BOTH
# phrasings; the narrow pattern was typed anyway, while citing that section.
#
# Per the CLAUDE.md non-negotiable — *"When a rule has failed while being cited,
# it has proven it cannot be carried by memory — attach a procedure or a
# mechanism"* — the pattern lives here, once, instead of being retyped per run.
#
# A crash detector matching one phrasing of a multi-phrasing signature is the
# same shape as a guard that passes its own mutation: it reports success by
# failing to look properly.
#
# Usage:
#   scripts/gate-report.sh <path.xcresult> [expected-failures.txt]
#
# Exits 1 if the host crashed, or if a membership file was given and differs.
# A NONZERO xcodebuild exit is NOT interpreted here — exit 65 alone means
# compile failure, assertion failure, launch denial, or a platform mismatch, and
# only the bundle distinguishes them.

set -uo pipefail

BUNDLE="${1:?usage: gate-report.sh <path.xcresult> [expected-failures.txt]}"
EXPECTED="${2:-}"
: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

[ -d "$BUNDLE" ] || { echo "FATAL: no result bundle at $BUNDLE"; exit 1; }

SUMMARY="$(xcrun xcresulttool get test-results summary --path "$BUNDLE" 2>/dev/null)"
[ -n "$SUMMARY" ] || { echo "FATAL: could not read $BUNDLE"; exit 1; }

# Every phrasing CLAUDE.md § Test Concurrency names, plus the abrt variant seen
# 2026-08-18. Add here — never at a call site.
CRASH_RE='Crash: HiMem|crashed with signal|deduplicated_symbol|signal (abrt|segv)|Abort Cause|libsystem_malloc'

CRASHES="$(printf '%s' "$SUMMARY" | grep -icE "$CRASH_RE")"

printf '%s' "$SUMMARY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("result   :", d.get("result"))
print("passed   :", d.get("passedTests"), "  failed:", d.get("failedTests"), "  skipped:", d.get("skippedTests"))
for dc in d.get("devicesAndConfigurations", []):
    dev = dc["device"]
    print("device   :", dev["deviceName"], dev["deviceId"], "os", dev["osVersion"], "(" + dev["platform"] + ")")
'

xcrun xcresulttool get test-results tests --path "$BUNDLE" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
suites, cases = set(), 0
def walk(n):
    global cases
    t = n.get("nodeType")
    if t == "Test Case": cases += 1
    if t == "Test Suite": suites.add(n.get("name"))
    for c in n.get("children", []) or []: walk(c)
for n in d.get("testNodes", []): walk(n)
print(f"cases    : {cases}   suites: {len(suites)}")
'

echo "crashlines: $CRASHES"
if [ "$CRASHES" -gt 0 ]; then
  echo
  echo "*** HOST CRASH — THE FAILURE COUNT IS MEANINGLESS ***"
  echo "One crash takes down the test host; everything scheduled after it fails as"
  echo "collateral. Do not diagnose the spread. Re-run the identical tree, then read"
  echo "the number. (CLAUDE.md § Test Concurrency, THE READING TRAP.)"
fi

MEMBERSHIP="$(printf '%s' "$SUMMARY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("\n".join(sorted(f["testIdentifierString"] for f in d.get("testFailures", []))))
')"

echo
echo "failing membership:"
printf '%s\n' "$MEMBERSHIP" | sed 's/^/  /'

RC=0
[ "$CRASHES" -gt 0 ] && RC=1

if [ -n "$EXPECTED" ]; then
  echo
  if printf '%s\n' "$MEMBERSHIP" | diff "$EXPECTED" - >/dev/null; then
    echo "membership: BYTE-IDENTICAL to $EXPECTED"
  else
    echo "membership: DIFFERS from $EXPECTED"
    printf '%s\n' "$MEMBERSHIP" | diff "$EXPECTED" - | sed 's/^/  /'
    RC=1
  fi
fi

exit $RC

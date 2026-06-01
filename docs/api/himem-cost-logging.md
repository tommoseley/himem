# HiMem AI Cost Logging — Contract (v1, JSONL)

Cost-of-goods-sold instrumentation for HiMem's Anthropic-backed API.
Added 2026-06-01. The iOS client sends `tier` and `action` on every
paid request; the server captures the Anthropic `usage` block,
computes per-call cost from a server-side price table, and appends
one JSON Lines event to a daily file. A `/himem/cost-report`
endpoint returns aggregate totals for the named periods the iOS
client knows about; a `/himem/cost-export` endpoint streams the raw
events as a downloadable JSONL.

**Design stance for v1: low-tech, single provider.** No database, no
extra service. One file per UTC day, append-only. When call volume
+ analysis needs outgrow `cat | jq`, this migrates cleanly — the
event shape is the same shape a Postgres row would have.

## Architecture

```
iOS client (ProcessingEngine)
   │
   │  POST /himem/analyze  { text, existing_topics, tier, action }
   │  POST /himem/cleanup  { text, tier, action }
   ▼
HiMem API server (~/dev/himem/api/main.py — EC2)
   │
   │  POST https://api.anthropic.com/v1/messages
   ▼
Anthropic — returns usage.{input_tokens, output_tokens}
   │
   │  append JSON line to ~/himem-api/logs/YYYY-MM-DD.jsonl
   ▼
Local filesystem (persistent EC2 volume)
   ▲
   │  read matching daily files → aggregate in Python
   │  GET /himem/cost-report?period=…
   │  GET /himem/cost-export?period=…
   │
Operator (Tom) or future iOS Settings → Cost Report
```

Logging is **best-effort** — a filesystem hiccup is logged
server-side but does not propagate to the API response. A paid call
is never broken by a logging failure.

## On-disk format

One file per UTC day, named `YYYY-MM-DD.jsonl`, located at
`HIMEM_LOG_DIR` (default `~/himem-api/logs/`). Each line is one JSON
object terminated by `\n`:

```json
{"timestamp":"2026-06-01T14:23:11.482Z","tier":"plus_monthly","action":"memory_organize","endpoint":"analyze","model":"claude-haiku-4-5-20251001","input_tokens":1247,"output_tokens":312,"cost_usd":0.000702}
```

**Concurrency safety.** Each event is built in memory and written
in a single `write()` call ending with `\n`. POSIX guarantees
append-mode `write()` is atomic — concurrent uvicorn workers can
safely write to the same daily file without interleaving.

**Crash safety.** A partial last line (e.g., from a process kill
mid-write) is skipped by the reader with a log warning. Bounded
recovery; no fatal errors.

**Rotation.** None. Each day gets a fresh file because the filename
contains the day. No log-rotate config needed.

**Retention.** None in v1. Files accumulate forever. At ~200 bytes
per event and at expected volumes (low thousands of calls / month),
even a year of logs is < 100 MB. Revisit if call volume crosses
~1k events / day for sustained periods.

## Server-side price table (v1)

Lives in `~/dev/himem/api/main.py` as `_MODEL_PRICING`. **Single
provider, single model** until product needs say otherwise:

| Model                     | Input ($/M tokens) | Output ($/M tokens) |
|---------------------------|--------------------|---------------------|
| claude-haiku-4-5-20251001 | $0.25              | $1.25               |

`cost_usd` is computed at the moment of the call. Updating the
table later only affects future events — past spend math stays
correct.

If a call lands with a model not in the table, the event still logs
(with the model name) but `cost_usd: 0.0` and a server warning fires.
That surfaces the missing-pricing case in reports rather than
silently dropping events.

## Tier vocabulary

The `tier` field is the iOS client's `EntitlementService.Tier`
rawValue, sent verbatim. As of 2026-06-01:

- `free`
- `plus_monthly`
- `plus_yearly`
- `founders`

Reporting groups `plus_monthly` and `plus_yearly` together for
"Plus tier" cohort analysis; treats each as its own bucket for
revenue accounting (different monthly recognition).

Unknown / pre-instrumentation clients land as `anonymous`.

## Action vocabulary (locked)

These strings must not be renamed after data starts landing —
historical aggregations break across the rename boundary. Add new
actions by extending the list, not by repurposing existing keys.

| `action` string         | Triggered by                                                   |
|-------------------------|----------------------------------------------------------------|
| `memory_organize`       | `POST /himem/analyze` from `ProcessingEngine.processWithCloud` |
| `project_assist`        | `POST /himem/analyze` from Find-the-thread (when wired)        |
| `bundle_title`          | `POST /himem/analyze` for the bundle-sheet title (when wired)  |
| `transcript_cleanup`    | `POST /himem/cleanup` (currently unused but reserved)          |
| `anonymous` / `unknown` | Pre-instrumentation iOS clients or unknown action — fallback   |

## Endpoint contracts

### `POST /himem/analyze`

Request body adds `tier` and `action` to the existing fields:

```json
{
  "text": "Met with Sarah about the garden.",
  "existing_topics": ["Garden"],
  "existing_mentions": ["Sarah"],
  "tier": "plus_monthly",
  "action": "memory_organize"
}
```

`tier` and `action` are optional on the wire (server defaults to
`anonymous` / `memory_organize`) so older iOS clients keep working
unchanged. Response shape is unchanged from the pre-COGS version.

### `POST /himem/cleanup`

Same pattern:

```json
{
  "text": "uh so I was thinking",
  "tier": "plus_monthly",
  "action": "transcript_cleanup"
}
```

### `GET /himem/cost-report?period=...`

Aggregate report — sums + per-cohort breakdowns. Period values:

| `period=`              | Meaning                                       |
|------------------------|-----------------------------------------------|
| `yesterday`            | Calendar yesterday in UTC                     |
| `last-week`            | Most recently completed Monday–Sunday in UTC  |
| `last-month`           | Previous calendar month in UTC                |
| `month-YYYY-MM`        | Specific calendar month (e.g., `month-2026-06`) |

Response:

```json
{
  "period_label": "June 2026",
  "from_iso": "2026-06-01T00:00:00Z",
  "to_iso": "2026-07-01T00:00:00Z",
  "event_count": 1247,
  "total_usd": 234.56,
  "by_tier":   { "free": 12.10, "plus_monthly": 189.42, "founders": 33.04 },
  "by_action": { "memory_organize": 134.20, "project_assist": 78.30 },
  "by_model":  { "claude-haiku-4-5-20251001": 234.56 }
}
```

`from_iso` is inclusive; `to_iso` is exclusive (one-past-end —
matches the file scan `cur < end.date()`).

Errors:

- `400` — unknown / unparseable `period` value
- (logging-only) — missing log directory returns `event_count: 0`,
  empty buckets, `total_usd: 0.0`

**Need an ad-hoc period (e.g., "last Tuesday")?** Pull last week's
report and filter the bucket — or use the export endpoint and `jq`
the raw events.

### `GET /himem/cost-export?period=...`

Streams the raw JSONL events for the period as a downloadable file
(`Content-Disposition: attachment; filename="ai-cost-<label>.jsonl"`).
Same period vocabulary as `/cost-report`. Useful for:

- Loading a month of events into Excel / Pandas for arbitrary
  analysis beyond what `/cost-report` summarizes.
- One-shot regulatory / accounting exports.
- `jq` queries on the host while logged in:
  `curl -s '.../cost-export?period=last-month' | jq -c 'select(.tier=="founders")'`

The file is the byte-for-byte concatenation of the matching daily
files. Empty if no events landed in the period.

## Server environment

One env var on the EC2 host (configured via systemd unit or `.env`
next to main.py):

```
ANTHROPIC_API_KEY=sk-...
```

Optional override:

```
HIMEM_LOG_DIR=/var/log/himem    # default: ~/himem-api/logs
```

## Deploy

`./api/deploy.sh` scp's `main.py` to the EC2 host and bounces the
systemd service. No dep changes since v0 — `requirements.txt` is
unchanged.

```bash
./api/deploy.sh
```

## Manual queries (during the v1 window)

Until a Settings → Cost Report UI ships in the iOS app, queries
run directly against the report / export endpoints:

```bash
# Aggregate
curl 'https://api.thecombine.ai/himem/cost-report?period=last-month'

# Raw events for ad-hoc analysis
curl -o june.jsonl 'https://api.thecombine.ai/himem/cost-export?period=month-2026-06'
jq -c 'select(.tier=="plus_monthly") | {ts:.timestamp, action:.action, cost:.cost_usd}' june.jsonl
```

For top-spending days last month:

```bash
curl -s 'https://api.thecombine.ai/himem/cost-export?period=last-month' \
  | jq -s 'group_by(.timestamp[:10])
           | map({day: .[0].timestamp[:10],
                  spend: (map(.cost_usd) | add),
                  calls: length})
           | sort_by(-.spend) | .[:10]'
```

## What's NOT in v1

- **No per-user attribution.** Cohort-only by `tier`. No `user_id`,
  no `installation_id`. Privacy-positive.
- **No retention sweep.** Files accumulate forever. Add a cron-based
  TTL if/when storage becomes a concern.
- **No iOS UI.** `ClaudeAPIService.fetchCostReport(period:)` exists
  but isn't wired to any screen yet. Easy add when needed.
- **No multi-provider gateway.** Single provider (Anthropic), single
  model (Haiku 4.5). The proper Kingfisher Studio AI passthrough —
  with provider abstraction, request/response capture, retry policy,
  per-product identity — is post-launch design work. This v1 is the
  bridge that lets us answer "are we making money?" while that
  larger system is designed.
- **No per-call request/response capture.** Token counts and cost
  only — not the prompt text or the model output.

## Migration path (when v1 isn't enough)

When call volume / analytics needs grow past the JSONL approach,
this migrates cleanly:

1. Replace `_log_call` with an `INSERT` into the same-shaped
   Postgres table.
2. Backfill historical files: stream every `.jsonl` line into
   `INSERT`. Order doesn't matter; `timestamp` is in every event.
3. Replace `_aggregate_costs` with a SQL `GROUP BY`.
4. Replace `_iter_event_files` with a `SELECT` over the time range.

The wire contract on both endpoints stays identical, so iOS doesn't
change. That's the point of doing the simple thing first.

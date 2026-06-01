"""Hi Mem API — journal entry analysis proxy backed by Claude Haiku.

Cost-of-goods-sold logging added 2026-06-01: every successful
Anthropic round-trip appends one JSON Lines event to a daily file
(`HIMEM_LOG_DIR/YYYY-MM-DD.jsonl`, default `~/himem-api/logs/`). The
`/himem/cost-report` endpoint summarizes a named period; the
`/himem/cost-export` endpoint streams the raw JSONL for download.
See `docs/api/himem-cost-logging.md`.

Deliberately low-tech for v1: no DB, no extra service deps. When
volume + analysis needs grow past `cat | jq`, this migrates cleanly
to Postgres (the schema's the same — `tier, action, endpoint, model,
input_tokens, output_tokens, cost_usd, occurred_at`).
"""

import json
import logging
import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone, date
from decimal import Decimal
from typing import Iterator

import httpx
from fastapi import FastAPI, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Hi Mem API", docs_url=None, redoc_url=None)

_ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5-20251001"
_API_VERSION = "2023-06-01"

# Per-million-tokens USD pricing. v1: single provider (Anthropic),
# single model (the one `_MODEL` above resolves to). When we add a
# second model or provider, extend this table — and not before.
# Historical `cost_usd` is captured at the moment of the call, so
# changing prices later only affects future events.
_MODEL_PRICING: dict[str, dict[str, Decimal]] = {
    "claude-haiku-4-5-20251001": {
        "input": Decimal("0.25"),
        "output": Decimal("1.25"),
    },
}

# Daily JSONL files live here. Override via env var for local dev /
# tests. On the EC2 host this resolves to `~/himem-api/logs/` which
# is on the persistent volume.
_LOG_DIR = os.environ.get("HIMEM_LOG_DIR", os.path.expanduser("~/himem-api/logs"))

_PROMPT = """\
Analyze this journal entry and extract structured data. Return JSON only, no other text.

Journal entry:
\"\"\"{text}\"\"\"

Return this exact JSON structure:
{{
  "entities": [
    {{"type": "project|person|issue|idea|next_action", "value": "short label", "confidence": 0.0-1.0}}
  ],
  "topics": ["Topic Name"],
  "summary": "One or two sentence natural-language summary of what the AI inferred from this entry.",
  "title": "Short descriptive title for this entry or null"
}}

Entity types:
- project: A project, location, or named thing being worked on (e.g., "Bed 4", "Kitchen remodel")
- person: A person mentioned by name
- issue: A problem, concern, or thing needing attention (e.g., "Water stress", "pest damage")
- idea: A creative thought or future possibility (e.g., "YouTube idea", "try drip irrigation")
- next_action: A concrete, actionable task the user intends to do. Start with a verb. (e.g., "Water Bed 4", "Film YouTube video", "Buy compost")

Rules for entity values:
- Keep values SHORT: 1-4 words max. These are searchable tags, not sentences.
- Normalize names consistently: always use digits for numbers ("Bed 4" not "Bed Four"). Always use singular form ("Bed 3" not "Beds 3"). Capitalize proper references ("Bed 4" not "bed 4").
- Split compound references: "beds 3, 5, and 7" becomes three entities: "Bed 3", "Bed 5", "Bed 7".
- next_action must be clearly actionable — suitable to add to a reminders list as-is.
- Do not quote or echo full sentences from the entry as entity values.

Topic: A high-level category this entry belongs to. One or two words max.
{existing_topics_block}
Summary: Write as if explaining to the user what the app understood. Use "linked to...", "flagged as...", "identified as...".
Only include entities with confidence >= 0.7. Be precise, not exhaustive.\
"""

_CLEANUP_PROMPT = """\
Fix grammar, spelling, and punctuation in this voice transcription. \
Keep the meaning and tone identical. Return only the corrected text, nothing else.

\"\"\"{text}\"\"\"\
"""


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class AnalyzeRequest(BaseModel):
    text: str
    existing_topics: list[str] = []
    # COGS-logging metadata. Defaults keep backward compat with older
    # iOS clients that haven't been updated. The client passes its
    # entitlement tier raw string ("free", "plus_monthly", "founders",
    # etc.) and a canonical action string from a locked vocabulary —
    # see `docs/api/himem-cost-logging.md`.
    tier: str = "anonymous"
    action: str = "memory_organize"


class EntityResult(BaseModel):
    type: str
    value: str
    confidence: float


class AnalyzeResponse(BaseModel):
    entities: list[EntityResult]
    topics: list[str]
    summary: str
    title: str | None


class CleanupRequest(BaseModel):
    text: str
    tier: str = "anonymous"
    action: str = "transcript_cleanup"


class CleanupResponse(BaseModel):
    text: str


class CostReport(BaseModel):
    period_label: str
    from_iso: str
    to_iso: str
    event_count: int
    total_usd: float
    by_tier: dict[str, float]
    by_action: dict[str, float]
    by_model: dict[str, float]


# ---------------------------------------------------------------------------
# JSONL file logging
# ---------------------------------------------------------------------------


def _compute_cost_usd(model: str, input_tokens: int, output_tokens: int) -> Decimal:
    """Per-million-tokens × token counts. Returns Decimal("0") when
    the model is unknown — the event still logs (with the model
    name) so missing-pricing cases surface in reports rather than
    being silently dropped."""
    pricing = _MODEL_PRICING.get(model)
    if not pricing:
        logger.warning("No pricing for model %s — cost_usd will be 0", model)
        return Decimal("0")
    input_cost = Decimal(input_tokens) / Decimal(1_000_000) * pricing["input"]
    output_cost = Decimal(output_tokens) / Decimal(1_000_000) * pricing["output"]
    return input_cost + output_cost


def _log_call(
    *,
    tier: str,
    action: str,
    endpoint: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
) -> None:
    """Append one JSON line to the daily log file. Best-effort —
    a filesystem hiccup logs the exception but never breaks the
    paid API call.

    POSIX guarantees a single `write()` syscall to an append-mode
    file is atomic (no interleaving with concurrent writers). Each
    event is built in memory then written in one shot, ending with
    `\\n`, so concurrent uvicorn workers can write safely to the
    same file.
    """
    try:
        os.makedirs(_LOG_DIR, exist_ok=True)
        now = datetime.now(timezone.utc)
        cost = _compute_cost_usd(model, input_tokens, output_tokens)
        event = {
            "timestamp": now.isoformat().replace("+00:00", "Z"),
            "tier": tier,
            "action": action,
            "endpoint": endpoint,
            "model": model,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cost_usd": float(cost),
        }
        line = json.dumps(event, separators=(",", ":")) + "\n"
        path = os.path.join(_LOG_DIR, now.strftime("%Y-%m-%d") + ".jsonl")
        with open(path, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:  # noqa: BLE001 - best-effort logging
        logger.exception("ai_call_log write failed (tier=%s action=%s)", tier, action)


# ---------------------------------------------------------------------------
# Period parsing + report aggregation
# ---------------------------------------------------------------------------


def _resolve_period(period: str) -> tuple[datetime, datetime, str]:
    """Map a period query value to (start_utc, end_utc, label).

    Supported:
        yesterday          — calendar yesterday in UTC
        last-week          — last completed Mon–Sun in UTC
        last-month         — previous calendar month in UTC
        month-YYYY-MM      — specific calendar month

    `end_utc` is exclusive (one-past-end) so reads are
    `occurred_at >= start AND occurred_at < end` — clean across DST
    and leap seconds.
    """
    today_utc = datetime.now(timezone.utc).date()

    if period == "yesterday":
        d = today_utc - timedelta(days=1)
        start = datetime.combine(d, datetime.min.time(), tzinfo=timezone.utc)
        end = datetime.combine(today_utc, datetime.min.time(), tzinfo=timezone.utc)
        return start, end, "Yesterday"

    if period == "last-week":
        # Calendar week Mon=0 .. Sun=6. "Last week" is the most
        # recently completed Mon–Sun bracket.
        weekday = today_utc.weekday()  # Mon=0, Sun=6
        last_sunday = today_utc - timedelta(days=weekday + 1)
        last_monday = last_sunday - timedelta(days=6)
        start = datetime.combine(last_monday, datetime.min.time(), tzinfo=timezone.utc)
        end = datetime.combine(last_sunday + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)
        return start, end, "Last week"

    if period == "last-month":
        first_of_this_month = date(today_utc.year, today_utc.month, 1)
        last_of_prev_month = first_of_this_month - timedelta(days=1)
        first_of_prev_month = date(last_of_prev_month.year, last_of_prev_month.month, 1)
        start = datetime.combine(first_of_prev_month, datetime.min.time(), tzinfo=timezone.utc)
        end = datetime.combine(first_of_this_month, datetime.min.time(), tzinfo=timezone.utc)
        return start, end, first_of_prev_month.strftime("%B %Y")

    if period.startswith("month-"):
        try:
            _, year_s, month_s = period.split("-")
            year, month = int(year_s), int(month_s)
            if not (1 <= month <= 12):
                raise ValueError(f"month out of range: {month}")
            start_d = date(year, month, 1)
            end_d = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
            start = datetime.combine(start_d, datetime.min.time(), tzinfo=timezone.utc)
            end = datetime.combine(end_d, datetime.min.time(), tzinfo=timezone.utc)
            return start, end, start_d.strftime("%B %Y")
        except (ValueError, IndexError) as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid month format (expected month-YYYY-MM): {e}",
            )

    raise HTTPException(
        status_code=400,
        detail=(
            f"Unknown period '{period}'. Supported: "
            "yesterday, last-week, last-month, month-YYYY-MM"
        ),
    )


def _iter_event_files(start: datetime, end: datetime) -> Iterator[str]:
    """Yield the daily-file paths that fall in [start.date(), end.date()).
    Since each file is named by the UTC day at write time, every
    event in a file shares that day — no per-event timestamp filter
    needed for our day-aligned periods."""
    if not os.path.isdir(_LOG_DIR):
        return
    cur = start.date()
    while cur < end.date():
        path = os.path.join(_LOG_DIR, cur.isoformat() + ".jsonl")
        if os.path.exists(path):
            yield path
        cur += timedelta(days=1)


def _iter_events(start: datetime, end: datetime) -> Iterator[dict]:
    """Yield parsed events from the matching daily files. Malformed
    lines (e.g., a partial last line after a crash) are skipped
    silently — bounded recovery, no fatal errors mid-iteration."""
    for path in _iter_event_files(start, end):
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    logger.warning("Skipping malformed line in %s", path)
                    continue


def _aggregate_costs(start: datetime, end: datetime) -> dict:
    by_tier: dict[str, Decimal] = defaultdict(Decimal)
    by_action: dict[str, Decimal] = defaultdict(Decimal)
    by_model: dict[str, Decimal] = defaultdict(Decimal)
    total = Decimal("0")
    count = 0

    for event in _iter_events(start, end):
        cost = Decimal(str(event.get("cost_usd", 0)))
        total += cost
        by_tier[event.get("tier", "unknown")] += cost
        by_action[event.get("action", "unknown")] += cost
        by_model[event.get("model", "unknown")] += cost
        count += 1

    def _r(d: dict[str, Decimal]) -> dict[str, float]:
        return {k: float(round(v, 6)) for k, v in d.items()}

    return {
        "event_count": count,
        "total_usd": float(round(total, 6)),
        "by_tier": _r(by_tier),
        "by_action": _r(by_action),
        "by_model": _r(by_model),
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/himem/analyze", response_model=AnalyzeResponse)
async def analyze_entry(request: AnalyzeRequest) -> AnalyzeResponse:
    # TODO: add per-device auth token before public release
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="ANTHROPIC_API_KEY not configured")

    if request.existing_topics:
        topics_list = ", ".join(f'"{t}"' for t in request.existing_topics)
        topics_block = (
            f"The user already has these topics: [{topics_list}]. "
            "STRONGLY prefer assigning to one of these existing topics. "
            "Only suggest a new topic if the entry clearly doesn't fit any existing one. "
            "Match semantically — e.g. if 'Photography' exists, do NOT suggest 'Photo' or 'Photos'."
        )
    else:
        topics_block = 'Suggest a short topic name (e.g., "Garden", "Work", "Health").'

    body = {
        "model": _MODEL,
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": _PROMPT.format(
            text=request.text,
            existing_topics_block=topics_block,
        )}],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": _API_VERSION,
        "content-type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(_ANTHROPIC_URL, json=body, headers=headers)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Anthropic API timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Request failed: {e}")

    if resp.status_code != 200:
        logger.error("Anthropic error %s: %s", resp.status_code, resp.text)
        raise HTTPException(status_code=502, detail=f"Anthropic error {resp.status_code}")

    response_json = resp.json()

    # Capture usage for cost logging. Anthropic always returns a
    # `usage` block on success.
    usage = response_json.get("usage", {})
    _log_call(
        tier=request.tier,
        action=request.action,
        endpoint="analyze",
        model=_MODEL,
        input_tokens=int(usage.get("input_tokens", 0)),
        output_tokens=int(usage.get("output_tokens", 0)),
    )

    text = ""
    for block in response_json.get("content", []):
        if block.get("type") == "text":
            text += block.get("text", "")

    try:
        start = text.index("{")
        end = text.rindex("}") + 1
        data = json.loads(text[start:end])
    except (ValueError, json.JSONDecodeError) as e:
        logger.error("JSON parse failed: %s | raw: %s", e, text)
        raise HTTPException(status_code=502, detail="AI response was not valid JSON")

    return AnalyzeResponse(
        entities=[EntityResult(**e) for e in data.get("entities", [])],
        topics=data.get("topics", []),
        summary=data.get("summary", ""),
        title=data.get("title"),
    )


@app.post("/himem/cleanup", response_model=CleanupResponse)
async def cleanup_text(request: CleanupRequest) -> CleanupResponse:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise HTTPException(status_code=500, detail="ANTHROPIC_API_KEY not configured")

    body = {
        "model": _MODEL,
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": _CLEANUP_PROMPT.format(text=request.text)}],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": _API_VERSION,
        "content-type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(_ANTHROPIC_URL, json=body, headers=headers)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Anthropic API timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Request failed: {e}")

    if resp.status_code != 200:
        logger.error("Anthropic error %s: %s", resp.status_code, resp.text)
        raise HTTPException(status_code=502, detail=f"Anthropic error {resp.status_code}")

    response_json = resp.json()

    usage = response_json.get("usage", {})
    _log_call(
        tier=request.tier,
        action=request.action,
        endpoint="cleanup",
        model=_MODEL,
        input_tokens=int(usage.get("input_tokens", 0)),
        output_tokens=int(usage.get("output_tokens", 0)),
    )

    corrected = ""
    for block in response_json.get("content", []):
        if block.get("type") == "text":
            corrected += block.get("text", "")

    return CleanupResponse(text=corrected.strip())


@app.get("/himem/cost-report", response_model=CostReport)
def cost_report(period: str = Query(...)) -> CostReport:
    """Aggregate cost report for one of the named periods. See
    `docs/api/himem-cost-logging.md` for the contract."""
    start, end, label = _resolve_period(period)
    agg = _aggregate_costs(start, end)
    return CostReport(
        period_label=label,
        from_iso=start.isoformat().replace("+00:00", "Z"),
        to_iso=end.isoformat().replace("+00:00", "Z"),
        event_count=agg["event_count"],
        total_usd=agg["total_usd"],
        by_tier=agg["by_tier"],
        by_action=agg["by_action"],
        by_model=agg["by_model"],
    )


@app.get("/himem/cost-export")
def cost_export(period: str = Query(...)) -> StreamingResponse:
    """Streams the raw JSONL events for the period as a downloadable
    file. The file is the concatenation of the matching daily files
    — caller can `jq` or load into Excel / Pandas for arbitrary
    analysis beyond what `/cost-report` summarizes."""
    start, end, label = _resolve_period(period)

    def _stream() -> Iterator[bytes]:
        for path in _iter_event_files(start, end):
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(64 * 1024)
                    if not chunk:
                        break
                    yield chunk

    safe_label = label.replace(" ", "-").lower()
    headers = {
        "Content-Disposition": f'attachment; filename="ai-cost-{safe_label}.jsonl"',
    }
    return StreamingResponse(_stream(), media_type="application/x-ndjson", headers=headers)

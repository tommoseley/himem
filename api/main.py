"""Hi Mem API — journal entry analysis proxy backed by Claude Haiku."""

import json
import logging
import os

import httpx
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Hi Mem API", docs_url=None, redoc_url=None)

_ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5-20251001"
_API_VERSION = "2023-06-01"

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


class AnalyzeRequest(BaseModel):
    text: str
    existing_topics: list[str] = []


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


class CleanupResponse(BaseModel):
    text: str


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

    text = ""
    for block in resp.json().get("content", []):
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

    corrected = ""
    for block in resp.json().get("content", []):
        if block.get("type") == "text":
            corrected += block.get("text", "")

    return CleanupResponse(text=corrected.strip())

from __future__ import annotations

import json
from typing import Any

from fastapi import FastAPI, HTTPException


app = FastAPI(
    title="FitLoop deterministic Agent model stub",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
)


COACH_TOOL = "get_coach_evidence"
APPEAL_TOOL = "get_appeal_review_context"

COACH_OUTPUT = {
    "answer": "Your evidence supports a gradual two-session plan with recovery between sessions.",
    "rationale": [
        "The recent workload is below the configured high-load threshold.",
        "The plan remains reversible and requires user confirmation before it is stored.",
    ],
    "safety_notices": [
        "Stop the session and seek qualified help if pain, dizziness, or unusual symptoms occur."
    ],
    "proposal": {
        "title": "FitLoop E2E gradual running plan",
        "goal": "Build a repeatable weekly running habit without a sudden load increase.",
        "days": [
            {
                "day": 1,
                "session_type": "easy run",
                "duration_minutes": 25,
                "intensity": "LOW",
                "notes": "Keep a conversational pace.",
            },
            {
                "day": 4,
                "session_type": "steady run",
                "duration_minutes": 30,
                "intensity": "MODERATE",
                "notes": "Reduce duration if recovery is incomplete.",
            },
        ],
    },
}

APPEAL_OUTPUT = {
    "decision": "APPROVE",
    "confidence": 0.91,
    "evidence": [
        "The appeal evidence and deterministic anomaly rules were both inspected.",
        "The seeded workout contains an isolated location spike consistent with the demo scenario.",
    ],
    "risk_flags": ["Administrator confirmation is required before changing the appeal."],
    "reason": "The evidence supports approval, but the model result remains advisory.",
}


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "UP"}


@app.post("/v1/chat/completions")
async def chat_completions(payload: dict[str, Any]) -> dict[str, Any]:
    messages = payload.get("messages")
    if not isinstance(messages, list):
        raise HTTPException(status_code=422, detail="messages must be a list")

    completed_tool = _completed_tool(messages)
    if completed_tool is not None:
        return _final_response(payload, completed_tool)

    selected_tool = _selected_tool(payload)
    if selected_tool not in {COACH_TOOL, APPEAL_TOOL}:
        raise HTTPException(status_code=422, detail="a supported evidence tool must be selected")
    if selected_tool not in _available_tools(payload):
        raise HTTPException(status_code=422, detail="selected evidence tool is not available")
    return _tool_call_response(payload, selected_tool)


def _selected_tool(payload: dict[str, Any]) -> str | None:
    choice = payload.get("tool_choice")
    if isinstance(choice, str):
        return choice if choice not in {"auto", "none", "required"} else None
    if isinstance(choice, dict):
        function = choice.get("function")
        if isinstance(function, dict) and isinstance(function.get("name"), str):
            return function["name"]
    return None


def _available_tools(payload: dict[str, Any]) -> set[str]:
    result: set[str] = set()
    for tool in payload.get("tools") or []:
        if not isinstance(tool, dict):
            continue
        function = tool.get("function")
        if isinstance(function, dict) and isinstance(function.get("name"), str):
            result.add(function["name"])
    return result


def _completed_tool(messages: list[Any]) -> str | None:
    for message in reversed(messages):
        if not isinstance(message, dict) or message.get("role") != "tool":
            continue
        name = message.get("name")
        if isinstance(name, str):
            return name
        tool_call_id = message.get("tool_call_id")
        if isinstance(tool_call_id, str):
            if COACH_TOOL in tool_call_id:
                return COACH_TOOL
            if APPEAL_TOOL in tool_call_id:
                return APPEAL_TOOL
    return None


def _tool_call_response(payload: dict[str, Any], tool_name: str) -> dict[str, Any]:
    return {
        "id": f"chatcmpl-fitloop-e2e-{tool_name}",
        "object": "chat.completion",
        "created": 0,
        "model": str(payload.get("model") or "fitloop-e2e-model"),
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [
                        {
                            "id": f"call-{tool_name}",
                            "type": "function",
                            "function": {"name": tool_name, "arguments": "{}"},
                        }
                    ],
                },
                "finish_reason": "tool_calls",
            }
        ],
        "usage": {"prompt_tokens": 32, "completion_tokens": 8, "total_tokens": 40},
    }


def _final_response(payload: dict[str, Any], completed_tool: str) -> dict[str, Any]:
    if completed_tool == COACH_TOOL:
        output = COACH_OUTPUT
    elif completed_tool == APPEAL_TOOL:
        output = APPEAL_OUTPUT
    else:
        raise HTTPException(status_code=422, detail="unsupported completed tool")
    return {
        "id": f"chatcmpl-fitloop-e2e-final-{completed_tool}",
        "object": "chat.completion",
        "created": 0,
        "model": str(payload.get("model") or "fitloop-e2e-model"),
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": json.dumps(output)},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 96, "completion_tokens": 64, "total_tokens": 160},
    }

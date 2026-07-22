import json

import httpx
import pytest

from fitloop_agent.model_stub import APPEAL_TOOL, COACH_TOOL, app
from fitloop_agent.schemas import AppealDecision, CoachOutput


def request_payload(tool_name: str) -> dict:
    return {
        "model": "fitloop-e2e-model",
        "messages": [{"role": "user", "content": "Use evidence."}],
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": tool_name,
                    "description": "Read evidence.",
                    "parameters": {"type": "object", "properties": {}},
                },
            }
        ],
        "tool_choice": {"type": "function", "function": {"name": tool_name}},
    }


async def post(payload: dict) -> httpx.Response:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://model-stub") as client:
        return await client.post("/v1/chat/completions", json=payload)


@pytest.mark.asyncio
async def test_stub_forces_the_requested_coach_evidence_tool() -> None:
    response = await post(request_payload(COACH_TOOL))

    assert response.status_code == 200
    choice = response.json()["choices"][0]
    assert choice["finish_reason"] == "tool_calls"
    assert choice["message"]["tool_calls"][0]["function"]["name"] == COACH_TOOL


@pytest.mark.asyncio
async def test_stub_returns_schema_valid_coach_output_after_tool_result() -> None:
    payload = request_payload(COACH_TOOL)
    payload["tool_choice"] = "auto"
    payload["messages"].append(
        {
            "role": "tool",
            "name": COACH_TOOL,
            "tool_call_id": f"call-{COACH_TOOL}",
            "content": '{"trainingLoad":{"assessment":"LOW"}}',
        }
    )

    response = await post(payload)

    assert response.status_code == 200
    output = CoachOutput.model_validate(json.loads(response.json()["choices"][0]["message"]["content"]))
    assert output.proposal is not None
    assert output.proposal.days[0].duration_minutes >= 5


@pytest.mark.asyncio
async def test_stub_returns_schema_valid_appeal_output_after_tool_result() -> None:
    payload = request_payload(APPEAL_TOOL)
    payload["tool_choice"] = "auto"
    payload["messages"].append(
        {
            "role": "tool",
            "name": APPEAL_TOOL,
            "tool_call_id": f"call-{APPEAL_TOOL}",
            "content": '{"evidence":{},"rules":{}}',
        }
    )

    response = await post(payload)

    assert response.status_code == 200
    output = AppealDecision.model_validate(
        json.loads(response.json()["choices"][0]["message"]["content"])
    )
    assert output.decision == "APPROVE"
    assert output.confidence > 0.8


@pytest.mark.asyncio
async def test_stub_rejects_unknown_tools() -> None:
    response = await post(request_payload("delete_user"))

    assert response.status_code == 422

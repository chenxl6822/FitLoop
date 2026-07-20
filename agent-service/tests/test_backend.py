import json

import httpx
import pytest

from fitloop_agent.backend import BackendClient
from fitloop_agent.config import Settings


def settings() -> Settings:
    return Settings(
        deepseek_api_key="test-deepseek-key",
        agent_service_key="s" * 48,
        backend_base_url="http://backend.test",
        agent_worker_enabled=False,
    )


@pytest.mark.asyncio
async def test_exchange_claim_and_callbacks_keep_secrets_in_headers() -> None:
    seen: list[httpx.Request] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        path = request.url.path
        if path.endswith("/delegation-token"):
            return httpx.Response(200, json={"accessToken": "delegated", "expiresIn": 300})
        if path.endswith("/claim"):
            return httpx.Response(
                200,
                json={
                    "runId": "run-1",
                    "type": "COACH",
                    "inputJson": '{"objective":"5k"}',
                    "subjectUserId": 7,
                    "subjectResourceId": None,
                    "traceId": "trace-1",
                },
            )
        if path.endswith("/proposals"):
            return httpx.Response(200, json={"proposalId": 3, "status": "PENDING"})
        return httpx.Response(204)

    http = httpx.AsyncClient(
        base_url="http://backend.test", transport=httpx.MockTransport(handler)
    )
    backend = BackendClient(settings(), client=http)

    token = await backend.exchange_token("run-1")
    claim = await backend.claim("run-1", token)
    await backend.propose("run-1", token, "CREATE_TRAINING_PLAN", "{}", False)
    await backend.complete(
        "run-1",
        token,
        status="SUCCEEDED",
        result_json="{}",
        model="deepseek-v4-flash",
        prompt_version="coach-v1",
        input_tokens=10,
        output_tokens=5,
        cost_micros=1,
        latency_ms=100,
    )

    assert claim.subjectUserId == 7
    assert seen[0].headers["X-Agent-Service-Key"] == "s" * 48
    assert all(request.headers.get("Authorization") == "Bearer delegated" for request in seen[1:])
    assert "test-deepseek-key" not in json.dumps([str(request.url) for request in seen])
    await backend.close()

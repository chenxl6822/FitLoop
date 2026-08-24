from __future__ import annotations

from types import SimpleNamespace

import httpx
import pytest

from fitloop_agent.config import Settings
from fitloop_agent.schemas import AppealDecision, ClaimResponse
from fitloop_agent.worker import AgentWorker


class RecordingRedis:
    def __init__(self, events: list[str] | None = None) -> None:
        self.acked: list[str] = []
        self.events = events

    async def xack(self, _stream: str, _group: str, message_id: str) -> None:
        self.acked.append(message_id)
        if self.events is not None:
            self.events.append(f"ack:{message_id}")


class FakeProvider:
    pass


class AppealHalfSuccessBackend:
    """Persist the proposal, then lose both first-attempt completion responses."""

    def __init__(self, events: list[str]) -> None:
        self.events = events
        self.messages: list[tuple[str, str]] = []
        self.proposals: list[dict[str, object]] = []
        self.completions: list[dict[str, object]] = []
        self.complete_attempts = 0
        self.propose_attempts = 0

    async def exchange_token(self, _run_id: str) -> str:
        return "synthetic-delegation"

    async def claim(self, run_id: str, _token: str) -> ClaimResponse:
        return ClaimResponse(
            runId=run_id,
            type="APPEAL_REVIEW",
            inputJson='{"appealId":42}',
            subjectUserId=7,
            subjectResourceId=42,
            traceId="synthetic-trace",
        )

    async def add_message(
        self, _run_id: str, _token: str, role: str, content: str
    ) -> None:
        self.messages.append((role, content))

    async def propose(
        self,
        run_id: str,
        _token: str,
        action_type: str,
        payload_json: str,
        requires_admin: bool,
    ) -> dict[str, object]:
        self.propose_attempts += 1
        request = {
            "actionType": action_type,
            "payloadJson": payload_json,
            "requiresAdmin": requires_admin,
        }
        if not self.proposals:
            self.proposals.append(request)
            return {"proposalId": 1}
        http_request = httpx.Request(
            "POST", f"http://backend.test/internal/v1/agent/runs/{run_id}/proposals"
        )
        response = httpx.Response(
            409,
            request=http_request,
            json={
                "actionType": action_type,
                "payloadJson": payload_json,
                "requiresAdmin": requires_admin,
            },
        )
        raise httpx.HTTPStatusError(
            "Synthetic persisted proposal conflict",
            request=http_request,
            response=response,
        )

    async def complete(self, _run_id: str, _token: str, **values: object) -> None:
        self.complete_attempts += 1
        if self.complete_attempts <= 2:
            request = httpx.Request(
                "POST", "http://backend.test/internal/v1/agent/runs/run-appeal/result"
            )
            raise httpx.ReadTimeout(
                "Synthetic result callback response loss", request=request
            )
        self.completions.append(values)
        self.events.append(f"complete:{values['status']}")


class ProposalConflictBackend:
    def __init__(self, existing: dict[str, object] | None) -> None:
        self.existing = existing

    async def propose(self, run_id: str, *_args: object) -> dict[str, object]:
        request = httpx.Request(
            "POST", f"http://backend.test/internal/v1/agent/runs/{run_id}/proposals"
        )
        response = httpx.Response(
            409,
            request=request,
            json=self.existing if self.existing is not None else {},
        )
        raise httpx.HTTPStatusError(
            "Synthetic proposal conflict", request=request, response=response
        )


def settings() -> Settings:
    return Settings(
        deepseek_api_key="not-used",
        agent_service_key="s" * 48,
        agent_worker_enabled=False,
    )


def appeal_output() -> AppealDecision:
    return AppealDecision(
        decision="APPROVE",
        confidence=0.91,
        evidence=["Only deterministic synthetic evidence was used."],
        risk_flags=["Administrator confirmation remains mandatory."],
        reason="The synthetic rule was not triggered.",
    )


async def run_appeal_retry(
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[RecordingRedis, AppealHalfSuccessBackend]:
    events: list[str] = []
    redis = RecordingRedis(events)
    backend = AppealHalfSuccessBackend(events)
    worker = AgentWorker(settings(), redis=redis, backend=backend, provider=FakeProvider())
    fake_result = SimpleNamespace(raw_responses=[])

    async def fake_run_appeal(*_args: object, **_kwargs: object):
        return appeal_output(), fake_result

    monkeypatch.setattr("fitloop_agent.worker.run_appeal", fake_run_appeal)
    message = {
        "runId": "run-appeal",
        "type": "APPEAL_REVIEW",
        "traceId": "synthetic-trace",
    }
    await worker._process("appeal-first", message)
    await worker._process("appeal-retry", message)
    return redis, backend


@pytest.mark.asyncio
async def test_appeal_half_success_retry_completes_before_ack(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    redis, backend = await run_appeal_retry(monkeypatch)

    assert redis.acked == ["appeal-first", "appeal-retry"]
    assert backend.propose_attempts == 2
    assert len(backend.proposals) == 1
    assert backend.complete_attempts == 3
    assert backend.completions[-1]["status"] == "WAITING_APPROVAL"
    assert backend.events.index("complete:WAITING_APPROVAL") < backend.events.index(
        "ack:appeal-retry"
    )


@pytest.mark.asyncio
async def test_appeal_retry_does_not_duplicate_assistant_message(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _redis, backend = await run_appeal_retry(monkeypatch)

    assert backend.messages == [
        ("assistant", appeal_output().model_dump_json())
    ], "Retrying only the result callback must not append the assistant message twice."


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "existing",
    [
        None,
        {
            "actionType": "REVIEW_APPEAL",
            "payloadJson": '{"decision":"REJECT"}',
            "requiresAdmin": False,
        },
        {
            "actionType": "CREATE_TRAINING_PLAN",
            "payloadJson": '{"decision":"REJECT"}',
            "requiresAdmin": True,
        },
        {
            "actionType": "REVIEW_APPEAL",
            "payloadJson": '{"decision":"APPROVE"}',
            "requiresAdmin": True,
        },
    ],
    ids=[
        "no-equivalence-proof",
        "different-approval-role",
        "different-action",
        "different-payload",
    ],
)
async def test_proposal_conflict_is_not_reused_without_equivalence_proof(
    existing: dict[str, object] | None,
) -> None:
    worker = AgentWorker(
        settings(),
        redis=RecordingRedis(),
        backend=ProposalConflictBackend(existing),
        provider=FakeProvider(),
    )

    with pytest.raises(httpx.HTTPStatusError) as conflict:
        await worker._propose_or_reuse(
            "run-appeal",
            "synthetic-delegation",
            "REVIEW_APPEAL",
            '{"decision":"REJECT"}',
            True,
        )

    assert conflict.value.response.status_code == 409

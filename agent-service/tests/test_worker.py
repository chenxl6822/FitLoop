import asyncio
from contextlib import suppress
from types import SimpleNamespace

import pytest
from pydantic import SecretStr

from fitloop_agent.config import Settings
from fitloop_agent.schemas import (
    AppealDecision,
    ClaimResponse,
    CoachOutput,
    TrainingDay,
    TrainingPlanProposal,
)
from fitloop_agent.worker import AgentWorker


class FakeRedis:
    def __init__(self) -> None:
        self.acked: list[str] = []

    async def xack(self, _stream: str, _group: str, message_id: str) -> None:
        self.acked.append(message_id)

    async def ping(self) -> bool:
        return True


class FakeBackend:
    def __init__(self, claim_type: str = "COACH") -> None:
        self.claim_type = claim_type
        self.proposals: list[dict] = []
        self.completions: list[dict] = []
        self.messages: list[tuple[str, str]] = []

    async def exchange_token(self, _run_id: str) -> str:
        return "delegated"

    async def claim(self, run_id: str, _token: str) -> ClaimResponse:
        appeal = self.claim_type == "APPEAL_REVIEW"
        return ClaimResponse(
            runId=run_id,
            type=self.claim_type,
            inputJson='{"appealId":42}' if appeal else '{"objective":"safe 5k"}',
            subjectUserId=7,
            subjectResourceId=42 if appeal else None,
            traceId="trace-1",
        )

    async def add_message(self, _run_id: str, _token: str, role: str, content: str) -> None:
        self.messages.append((role, content))

    async def propose(self, _run_id: str, _token: str, action_type: str, payload_json: str,
                      requires_admin: bool) -> dict:
        self.proposals.append(
            {"actionType": action_type, "payloadJson": payload_json, "requiresAdmin": requires_admin}
        )
        return {"proposalId": 1}

    async def complete(self, _run_id: str, _token: str, **values) -> None:
        self.completions.append(values)


class FakeProvider:
    pass


def settings() -> Settings:
    return Settings(
        deepseek_api_key="not-used",
        agent_service_key="s" * 48,
        agent_worker_enabled=False,
        flash_input_usd_per_million=0.14,
        flash_output_usd_per_million=0.28,
    )


@pytest.mark.asyncio
async def test_mocked_coach_workflow_creates_proposal_without_calling_deepseek(monkeypatch) -> None:
    redis = FakeRedis()
    backend = FakeBackend()
    worker = AgentWorker(settings(), redis=redis, backend=backend, provider=FakeProvider())
    output = CoachOutput(
        answer="A gradual plan is ready.",
        rationale=["Recent training load is low."],
        proposal=TrainingPlanProposal(
            title="Safe 5K starter",
            goal="Complete 5K gradually",
            days=[TrainingDay(day=1, session_type="easy run", duration_minutes=20, intensity="LOW")],
        ),
    )
    usage = SimpleNamespace(input_tokens=100, output_tokens=50)
    fake_result = SimpleNamespace(raw_responses=[SimpleNamespace(usage=usage)])

    async def fake_run_coach(*_args, **_kwargs):
        return output, fake_result

    monkeypatch.setattr("fitloop_agent.worker.run_coach", fake_run_coach)
    await worker._process("1-0", {"runId": "run-1", "type": "COACH", "traceId": "trace-1"})

    assert redis.acked == ["1-0"]
    assert backend.proposals[0]["actionType"] == "CREATE_TRAINING_PLAN"
    assert backend.proposals[0]["requiresAdmin"] is False
    assert backend.completions[0]["status"] == "WAITING_APPROVAL"
    assert backend.completions[0]["input_tokens"] == 100
    assert backend.completions[0]["output_tokens"] == 50


@pytest.mark.asyncio
async def test_mocked_appeal_approval_creates_admin_proposal(monkeypatch) -> None:
    redis = FakeRedis()
    backend = FakeBackend("APPEAL_REVIEW")
    worker = AgentWorker(settings(), redis=redis, backend=backend, provider=FakeProvider())
    output = AppealDecision(
        decision="APPROVE",
        confidence=0.91,
        evidence=["The isolated speed spike was shorter than the deterministic threshold."],
        risk_flags=["Administrator confirmation is still required."],
        reason="The rule was not triggered, so approval is recommended.",
    )
    usage = SimpleNamespace(input_tokens=220, output_tokens=80)
    fake_result = SimpleNamespace(raw_responses=[SimpleNamespace(usage=usage)])

    async def fake_run_appeal(*_args, **_kwargs):
        return output, fake_result

    monkeypatch.setattr("fitloop_agent.worker.run_appeal", fake_run_appeal)
    await worker._process(
        "2-0", {"runId": "run-2", "type": "APPEAL_REVIEW", "traceId": "trace-2"}
    )

    assert redis.acked == ["2-0"]
    assert backend.proposals[0]["actionType"] == "REVIEW_APPEAL"
    assert backend.proposals[0]["requiresAdmin"] is True
    assert backend.completions[0]["status"] == "WAITING_APPROVAL"
    assert backend.completions[0]["input_tokens"] == 220
    assert backend.completions[0]["output_tokens"] == 80
    assert '"decision":"APPROVE"' in backend.messages[0][1]


@pytest.mark.asyncio
async def test_mocked_appeal_needing_more_info_does_not_create_proposal(monkeypatch) -> None:
    redis = FakeRedis()
    backend = FakeBackend("APPEAL_REVIEW")
    worker = AgentWorker(settings(), redis=redis, backend=backend, provider=FakeProvider())
    output = AppealDecision(
        decision="NEED_MORE_INFO",
        confidence=0.72,
        evidence=["The available trace summary is incomplete."],
        reason="An administrator should request the detailed trace before deciding.",
    )
    fake_result = SimpleNamespace(raw_responses=[])

    async def fake_run_appeal(*_args, **_kwargs):
        return output, fake_result

    monkeypatch.setattr("fitloop_agent.worker.run_appeal", fake_run_appeal)
    await worker._process(
        "3-0", {"runId": "run-3", "type": "APPEAL_REVIEW", "traceId": "trace-3"}
    )

    assert redis.acked == ["3-0"]
    assert backend.proposals == []
    assert backend.completions[0]["status"] == "SUCCEEDED"


def test_timeout_and_network_errors_are_retryable() -> None:
    assert AgentWorker._is_retryable(TimeoutError())
    assert not AgentWorker._is_retryable(type("PermanentAgentError", (RuntimeError,), {})())
    assert not AgentWorker._is_retryable(type("PaymentRequired", (RuntimeError,), {"status_code": 402})())
    assert AgentWorker._is_retryable(type("RateLimited", (RuntimeError,), {"status_code": 429})())


@pytest.mark.asyncio
async def test_readiness_requires_a_live_worker_and_redis() -> None:
    worker = AgentWorker(
        settings(), redis=FakeRedis(), backend=FakeBackend(), provider=FakeProvider()
    )
    assert not await worker.ready()

    task = asyncio.create_task(asyncio.sleep(10))
    worker._task = task
    try:
        assert await worker.ready()
    finally:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task


@pytest.mark.asyncio
async def test_readiness_fails_closed_without_model_credentials() -> None:
    missing_key_settings = settings().model_copy(
        update={"deepseek_api_key": SecretStr("")}
    )
    worker = AgentWorker(
        missing_key_settings,
        redis=FakeRedis(),
        backend=FakeBackend(),
        provider=FakeProvider(),
    )
    task = asyncio.create_task(asyncio.sleep(10))
    worker._task = task
    try:
        assert not await worker.ready()
    finally:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task

from types import SimpleNamespace

import pytest

from fitloop_agent.config import Settings
from fitloop_agent.schemas import ClaimResponse, CoachOutput, TrainingDay, TrainingPlanProposal
from fitloop_agent.worker import AgentWorker


class FakeRedis:
    def __init__(self) -> None:
        self.acked: list[str] = []

    async def xack(self, _stream: str, _group: str, message_id: str) -> None:
        self.acked.append(message_id)


class FakeBackend:
    def __init__(self) -> None:
        self.proposals: list[dict] = []
        self.completions: list[dict] = []
        self.messages: list[tuple[str, str]] = []

    async def exchange_token(self, _run_id: str) -> str:
        return "delegated"

    async def claim(self, run_id: str, _token: str) -> ClaimResponse:
        return ClaimResponse(
            runId=run_id,
            type="COACH",
            inputJson='{"objective":"safe 5k"}',
            subjectUserId=7,
            subjectResourceId=None,
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


def test_timeout_and_network_errors_are_retryable() -> None:
    assert AgentWorker._is_retryable(TimeoutError())
    assert not AgentWorker._is_retryable(type("PermanentAgentError", (RuntimeError,), {})())
    assert not AgentWorker._is_retryable(type("PaymentRequired", (RuntimeError,), {"status_code": 402})())
    assert AgentWorker._is_retryable(type("RateLimited", (RuntimeError,), {"status_code": 429})())

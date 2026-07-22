from types import SimpleNamespace

import pytest

from fitloop_agent import demo
from fitloop_agent.config import Settings
from fitloop_agent.schemas import AppealDecision, CoachOutput


def settings() -> Settings:
    return Settings(
        deepseek_api_key="not-used",
        agent_service_key="demo-backend-not-used",
        agent_worker_enabled=False,
    )


@pytest.mark.asyncio
async def test_live_demo_runs_both_workflows_with_required_tools(monkeypatch) -> None:
    async def fake_run_coach(_provider, context, _input_text, _settings):
        for tool_name in sorted(demo.COACH_REQUIRED_TOOLS):
            await context.backend.tool("/demo", context.token, tool_name)
        return (
            CoachOutput(answer="A gradual plan based on evidence.", rationale=["Normal load."]),
            SimpleNamespace(raw_responses=[]),
        )

    async def fake_run_appeal(_provider, context, _input_text, _settings):
        for tool_name in sorted(demo.APPEAL_REQUIRED_TOOLS):
            await context.backend.tool("/demo", context.token, tool_name)
        return (
            AppealDecision(
                decision="APPROVE",
                confidence=0.85,
                evidence=["The spike was shorter than the configured threshold."],
                reason="The deterministic rule was not triggered.",
            ),
            SimpleNamespace(raw_responses=[]),
        )

    monkeypatch.setattr(demo, "run_coach", fake_run_coach)
    monkeypatch.setattr(demo, "run_appeal", fake_run_appeal)

    results = await demo.run_live_demo(settings())

    assert [result["workflow"] for result in results] == ["coach", "appeal"]
    assert set(results[0]["tools"]) == demo.COACH_REQUIRED_TOOLS
    assert set(results[1]["tools"]) == demo.APPEAL_REQUIRED_TOOLS


@pytest.mark.asyncio
async def test_demo_backend_rejects_unknown_tools() -> None:
    backend = demo.DemoBackend()

    with pytest.raises(KeyError, match="does not allow tool"):
        await backend.tool("/demo", "demo-token", "delete_user")

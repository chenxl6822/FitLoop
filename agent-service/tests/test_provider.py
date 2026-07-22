from unittest.mock import AsyncMock

import pytest
from agents import AgentOutputSchema, ModelTracing
from openai.types.chat import ChatCompletion, ChatCompletionMessage
from openai.types.chat.chat_completion import Choice

from fitloop_agent.config import Settings
from fitloop_agent.provider import DeepSeekProvider
from fitloop_agent.schemas import CoachOutput
from fitloop_agent.workflows import build_appeal_agent, build_coach_agent


def settings() -> Settings:
    return Settings(
        deepseek_api_key="not-used",
        agent_service_key="s" * 48,
        agent_worker_enabled=False,
    )


@pytest.mark.asyncio
async def test_structured_output_uses_deepseek_json_object_mode() -> None:
    provider = DeepSeekProvider(settings())
    completion = ChatCompletion(
        id="chatcmpl-test",
        choices=[
            Choice(
                finish_reason="stop",
                index=0,
                message=ChatCompletionMessage(
                    role="assistant",
                    content=(
                        '{"answer":"Keep the load gradual.","rationale":[],'
                        '"safety_notices":[],"proposal":null}'
                    ),
                ),
            )
        ],
        created=0,
        model="deepseek-v4-flash",
        object="chat.completion",
    )
    create = AsyncMock(return_value=completion)
    provider.client.chat.completions.create = create

    try:
        await provider.coach_model.get_response(
            system_instructions="Return a coaching result.",
            input="Build a safe plan.",
            model_settings=provider.non_thinking_settings(),
            tools=[],
            output_schema=AgentOutputSchema(CoachOutput),
            handoffs=[],
            tracing=ModelTracing.DISABLED,
        )
    finally:
        await provider.close()

    request = create.await_args.kwargs
    assert request["response_format"] == {"type": "json_object"}
    assert "JSON Schema" in request["messages"][0]["content"]
    assert '"answer"' in request["messages"][0]["content"]


@pytest.mark.asyncio
async def test_agents_force_their_evidence_aggregation_tool_on_the_first_turn() -> None:
    provider = DeepSeekProvider(settings())
    try:
        coach = build_coach_agent(provider)
        appeal = build_appeal_agent(provider)
    finally:
        await provider.close()

    assert coach.model_settings.tool_choice == "get_coach_evidence"
    assert [tool.name for tool in coach.tools] == ["get_coach_evidence"]
    assert appeal.model_settings.tool_choice == "get_appeal_review_context"
    assert [tool.name for tool in appeal.tools] == ["get_appeal_review_context"]

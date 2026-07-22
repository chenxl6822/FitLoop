import json
from dataclasses import replace
from typing import Any

from agents import ModelSettings, OpenAIChatCompletionsModel, set_tracing_disabled
from openai import AsyncOpenAI

from .config import Settings


class DeepSeekChatCompletionsModel(OpenAIChatCompletionsModel):
    """Adapt Agents SDK structured output to DeepSeek's JSON object mode."""

    async def get_response(
        self,
        system_instructions: str | None,
        input: Any,
        model_settings: ModelSettings,
        tools: list[Any],
        output_schema: Any,
        handoffs: list[Any],
        tracing: Any,
        previous_response_id: str | None = None,
        conversation_id: str | None = None,
        prompt: Any = None,
    ) -> Any:
        provider_output_schema = output_schema
        if output_schema is not None and not output_schema.is_plain_text():
            schema = json.dumps(output_schema.json_schema(), ensure_ascii=False, separators=(",", ":"))
            schema_instructions = (
                "Return only one valid JSON object that matches the following JSON Schema. "
                "Do not wrap the JSON in Markdown fences.\nJSON Schema:\n"
                f"{schema}"
            )
            system_instructions = (
                f"{system_instructions.rstrip()}\n\n{schema_instructions}"
                if system_instructions
                else schema_instructions
            )
            extra_args = dict(model_settings.extra_args or {})
            extra_args["response_format"] = {"type": "json_object"}
            model_settings = replace(model_settings, extra_args=extra_args)

            # DeepSeek accepts json_object, not OpenAI's json_schema response format.
            # The Runner still owns the original schema and validates the returned JSON locally.
            provider_output_schema = None

        return await super().get_response(
            system_instructions=system_instructions,
            input=input,
            model_settings=model_settings,
            tools=tools,
            output_schema=provider_output_schema,
            handoffs=handoffs,
            tracing=tracing,
            previous_response_id=previous_response_id,
            conversation_id=conversation_id,
            prompt=prompt,
        )


class DeepSeekProvider:
    """The only layer that knows which model vendor FitLoop uses."""

    def __init__(self, settings: Settings) -> None:
        set_tracing_disabled(True)
        self.settings = settings
        self.client = AsyncOpenAI(
            api_key=settings.deepseek_api_key.get_secret_value(),
            base_url=settings.deepseek_base_url,
            timeout=settings.deepseek_timeout_seconds,
            max_retries=0,
        )
        self.coach_model = DeepSeekChatCompletionsModel(
            model=settings.deepseek_coach_model,
            openai_client=self.client,
        )
        self.appeal_model = DeepSeekChatCompletionsModel(
            model=settings.deepseek_appeal_model,
            openai_client=self.client,
        )

    @staticmethod
    def non_thinking_settings(tool_choice: str = "auto") -> ModelSettings:
        return ModelSettings(
            temperature=0.2,
            tool_choice=tool_choice,
            extra_body={"thinking": {"type": "disabled"}},
        )

    async def close(self) -> None:
        await self.client.close()

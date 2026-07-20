from agents import ModelSettings, OpenAIChatCompletionsModel, set_tracing_disabled
from openai import AsyncOpenAI

from .config import Settings


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
        self.coach_model = OpenAIChatCompletionsModel(
            model=settings.deepseek_coach_model,
            openai_client=self.client,
        )
        self.appeal_model = OpenAIChatCompletionsModel(
            model=settings.deepseek_appeal_model,
            openai_client=self.client,
        )

    @staticmethod
    def non_thinking_settings() -> ModelSettings:
        return ModelSettings(
            temperature=0.2,
            tool_choice="auto",
            extra_body={"thinking": {"type": "disabled"}},
        )

    async def close(self) -> None:
        await self.client.close()

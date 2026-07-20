from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    deepseek_api_key: SecretStr
    deepseek_base_url: str = "https://api.deepseek.com"
    deepseek_coach_model: str = "deepseek-v4-flash"
    deepseek_appeal_model: str = "deepseek-v4-pro"

    backend_base_url: str = "http://backend:8080"
    agent_service_key: SecretStr
    redis_url: str = "redis://redis:6379/0"
    agent_stream_key: str = "fitloop:agent:runs"
    agent_consumer_group: str = "fitloop-agent-service"
    agent_consumer_name: str = "agent-1"
    agent_worker_enabled: bool = True
    otel_exporter_otlp_endpoint: str | None = None
    otel_service_name: str = "fitloop-agent-service"

    agent_max_turns: int = Field(default=8, ge=1, le=8)
    agent_timeout_seconds: int = Field(default=45, ge=5, le=45)
    backend_timeout_seconds: float = Field(default=10.0, ge=1, le=30)
    deepseek_timeout_seconds: float = Field(default=40.0, ge=5, le=45)

    coach_prompt_version: str = "coach-v1"
    appeal_prompt_version: str = "appeal-v1"
    flash_input_usd_per_million: float = 0.0
    flash_output_usd_per_million: float = 0.0
    pro_input_usd_per_million: float = 0.0
    pro_output_usd_per_million: float = 0.0


@lru_cache
def get_settings() -> Settings:
    return Settings()

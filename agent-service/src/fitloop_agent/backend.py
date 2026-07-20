from __future__ import annotations

from typing import Any

import httpx

from .config import Settings
from .metrics import TOOL_CALLS
from .schemas import ClaimResponse


class BackendClient:
    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self.settings = settings
        self.client = client or httpx.AsyncClient(
            base_url=settings.backend_base_url.rstrip("/"),
            timeout=settings.backend_timeout_seconds,
        )

    async def close(self) -> None:
        await self.client.aclose()

    async def exchange_token(self, run_id: str) -> str:
        response = await self.client.post(
            f"/internal/v1/agent/runs/{run_id}/delegation-token",
            headers={"X-Agent-Service-Key": self.settings.agent_service_key.get_secret_value()},
        )
        response.raise_for_status()
        return response.json()["accessToken"]

    async def claim(self, run_id: str, token: str) -> ClaimResponse:
        response = await self.client.post(
            f"/internal/v1/agent/runs/{run_id}/claim", headers=self._authorization(token)
        )
        response.raise_for_status()
        return ClaimResponse.model_validate(response.json())

    async def tool(self, path: str, token: str, tool_name: str) -> Any:
        try:
            response = await self.client.get(path, headers=self._authorization(token))
            response.raise_for_status()
            TOOL_CALLS.labels(tool_name, "success").inc()
            return response.json()
        except Exception:
            TOOL_CALLS.labels(tool_name, "failed").inc()
            raise

    async def add_message(self, run_id: str, token: str, role: str, content: str) -> None:
        response = await self.client.post(
            f"/internal/v1/agent/runs/{run_id}/messages",
            headers=self._authorization(token),
            json={"role": role, "content": content},
        )
        response.raise_for_status()

    async def propose(
        self, run_id: str, token: str, action_type: str, payload_json: str, requires_admin: bool
    ) -> dict[str, Any]:
        response = await self.client.post(
            f"/internal/v1/agent/runs/{run_id}/proposals",
            headers=self._authorization(token),
            json={
                "actionType": action_type,
                "payloadJson": payload_json,
                "requiresAdmin": requires_admin,
            },
        )
        response.raise_for_status()
        return response.json()

    async def complete(
        self,
        run_id: str,
        token: str,
        *,
        status: str,
        result_json: str | None,
        model: str,
        prompt_version: str,
        input_tokens: int,
        output_tokens: int,
        cost_micros: int,
        latency_ms: int,
        error_message: str | None = None,
        retryable: bool = False,
    ) -> None:
        response = await self.client.post(
            f"/internal/v1/agent/runs/{run_id}/result",
            headers=self._authorization(token),
            json={
                "status": status,
                "resultJson": result_json,
                "model": model,
                "promptVersion": prompt_version,
                "inputTokens": input_tokens,
                "outputTokens": output_tokens,
                "costMicros": cost_micros,
                "latencyMs": latency_ms,
                "errorMessage": error_message,
                "retryable": retryable,
            },
        )
        response.raise_for_status()

    @staticmethod
    def _authorization(token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

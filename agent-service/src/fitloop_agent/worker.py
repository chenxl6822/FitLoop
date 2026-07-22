from __future__ import annotations

import asyncio
import json
import logging
import time
from contextlib import suppress
from typing import Any

import httpx
from redis.asyncio import Redis
from redis.exceptions import ResponseError

from .backend import BackendClient
from .config import Settings
from .metrics import MODEL_COST, MODEL_TOKENS, RUN_LATENCY, RUNS
from .provider import DeepSeekProvider
from .schemas import AgentContext, AppealDecision, CoachOutput, UsageSummary
from .workflows import run_appeal, run_coach

logger = logging.getLogger(__name__)


class AgentWorker:
    def __init__(
        self,
        settings: Settings,
        *,
        redis: Redis | None = None,
        backend: BackendClient | None = None,
        provider: DeepSeekProvider | None = None,
    ) -> None:
        self.settings = settings
        self.redis = redis or Redis.from_url(settings.redis_url, decode_responses=True)
        self.backend = backend or BackendClient(settings)
        self.provider = provider or DeepSeekProvider(settings)
        self._task: asyncio.Task[None] | None = None

    async def start(self) -> None:
        try:
            await self.redis.xgroup_create(
                self.settings.agent_stream_key,
                self.settings.agent_consumer_group,
                id="0",
                mkstream=True,
            )
        except ResponseError as exc:
            if "BUSYGROUP" not in str(exc):
                raise
        self._task = asyncio.create_task(self._consume(), name="fitloop-agent-worker")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            with suppress(asyncio.CancelledError):
                await self._task
        await self.backend.close()
        await self.provider.close()
        await self.redis.aclose()

    async def ready(self) -> bool:
        """Return whether the worker can consume new jobs right now."""
        if self._task is None or self._task.done():
            return False
        if not self.settings.deepseek_api_key.get_secret_value().strip():
            return False
        if not self.settings.agent_service_key.get_secret_value().strip():
            return False
        try:
            return bool(await self.redis.ping())
        except Exception:
            return False

    async def _consume(self) -> None:
        while True:
            try:
                batches = await self.redis.xreadgroup(
                    groupname=self.settings.agent_consumer_group,
                    consumername=self.settings.agent_consumer_name,
                    streams={self.settings.agent_stream_key: ">"},
                    count=1,
                    block=5000,
                )
                for _stream, entries in batches:
                    for message_id, fields in entries:
                        await self._process(message_id, fields)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("agent_worker_loop_failed")
                await asyncio.sleep(1)

    async def _process(self, message_id: str, fields: dict[str, str]) -> None:
        run_id = fields.get("runId")
        declared_type = fields.get("type", "UNKNOWN")
        if not run_id:
            await self._ack(message_id)
            return

        token: str | None = None
        started = time.monotonic()
        try:
            token = await self.backend.exchange_token(run_id)
            claim = await self.backend.claim(run_id, token)
            context = AgentContext(
                run_id=claim.runId,
                subject_user_id=claim.subjectUserId,
                subject_resource_id=claim.subjectResourceId,
                run_type=claim.type,
                trace_id=claim.traceId,
                token=token,
                backend=self.backend,
            )
            async with asyncio.timeout(self.settings.agent_timeout_seconds):
                if claim.type == "COACH":
                    output, raw_result = await run_coach(
                        self.provider, context, self._coach_input(claim.inputJson), self.settings
                    )
                    await self._finish_coach(context, output, raw_result, started)
                elif claim.type == "APPEAL_REVIEW":
                    output, raw_result = await run_appeal(
                        self.provider, context, self._appeal_input(claim.inputJson), self.settings
                    )
                    await self._finish_appeal(context, output, raw_result, started)
                else:
                    raise PermanentAgentError(f"Unsupported run type: {claim.type}")
            await self._ack(message_id)
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            if status in (400, 404, 409):
                logger.info("agent_message_discarded run_id=%s status=%s", run_id, status)
                await self._ack(message_id)
                return
            await self._report_failure(run_id, declared_type, token, exc, started, retryable=status >= 500 or status == 429)
            await self._ack(message_id)
        except Exception as exc:
            retryable = self._is_retryable(exc)
            await self._report_failure(run_id, declared_type, token, exc, started, retryable=retryable)
            await self._ack(message_id)

    async def _finish_coach(
        self, context: AgentContext, output: CoachOutput, raw_result: Any, started: float
    ) -> None:
        usage = self._usage(raw_result, "COACH")
        result_json = output.model_dump_json()
        await self.backend.add_message(context.run_id, context.token, "assistant", output.answer)
        status = "SUCCEEDED"
        if output.proposal is not None:
            await self.backend.propose(
                context.run_id,
                context.token,
                "CREATE_TRAINING_PLAN",
                output.proposal.model_dump_json(),
                False,
            )
            status = "WAITING_APPROVAL"
        await self._complete(context, status, result_json, usage, started)

    async def _finish_appeal(
        self, context: AgentContext, output: AppealDecision, raw_result: Any, started: float
    ) -> None:
        usage = self._usage(raw_result, "APPEAL_REVIEW")
        result_json = output.model_dump_json()
        await self.backend.add_message(context.run_id, context.token, "assistant", result_json)
        status = "SUCCEEDED"
        if output.decision in ("APPROVE", "REJECT"):
            await self.backend.propose(
                context.run_id, context.token, "REVIEW_APPEAL", result_json, True
            )
            status = "WAITING_APPROVAL"
        await self._complete(context, status, result_json, usage, started)

    async def _complete(
        self,
        context: AgentContext,
        status: str,
        result_json: str,
        usage: UsageSummary,
        started: float,
    ) -> None:
        elapsed = time.monotonic() - started
        model = (
            self.settings.deepseek_coach_model
            if context.run_type == "COACH"
            else self.settings.deepseek_appeal_model
        )
        prompt_version = (
            self.settings.coach_prompt_version
            if context.run_type == "COACH"
            else self.settings.appeal_prompt_version
        )
        await self.backend.complete(
            context.run_id,
            context.token,
            status=status,
            result_json=result_json,
            model=model,
            prompt_version=prompt_version,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cost_micros=usage.cost_micros,
            latency_ms=int(elapsed * 1000),
        )
        RUNS.labels(context.run_type, status).inc()
        RUN_LATENCY.labels(context.run_type).observe(elapsed)

    async def _report_failure(
        self,
        run_id: str,
        run_type: str,
        token: str | None,
        exc: Exception,
        started: float,
        *,
        retryable: bool,
    ) -> None:
        RUNS.labels(run_type, "FAILED_RETRYABLE" if retryable else "FAILED_FINAL").inc()
        logger.warning(
            "agent_run_failed run_id=%s type=%s retryable=%s error=%s",
            run_id,
            run_type,
            retryable,
            type(exc).__name__,
        )
        if token is None:
            return
        model = (
            self.settings.deepseek_coach_model
            if run_type == "COACH"
            else self.settings.deepseek_appeal_model
        )
        prompt_version = (
            self.settings.coach_prompt_version
            if run_type == "COACH"
            else self.settings.appeal_prompt_version
        )
        with suppress(Exception):
            await self.backend.complete(
                run_id,
                token,
                status="FAILED_RETRYABLE" if retryable else "FAILED_FINAL",
                result_json=None,
                model=model,
                prompt_version=prompt_version,
                input_tokens=0,
                output_tokens=0,
                cost_micros=0,
                latency_ms=int((time.monotonic() - started) * 1000),
                error_message=f"{type(exc).__name__}: {str(exc)[:400]}",
                retryable=retryable,
            )

    async def _ack(self, message_id: str) -> None:
        await self.redis.xack(
            self.settings.agent_stream_key, self.settings.agent_consumer_group, message_id
        )

    def _usage(self, result: Any, run_type: str) -> UsageSummary:
        input_tokens = 0
        output_tokens = 0
        for response in getattr(result, "raw_responses", []) or []:
            usage = getattr(response, "usage", None)
            if usage is not None:
                input_tokens += int(getattr(usage, "input_tokens", 0) or 0)
                output_tokens += int(getattr(usage, "output_tokens", 0) or 0)
        if run_type == "COACH":
            cost = (
                input_tokens * self.settings.flash_input_usd_per_million
                + output_tokens * self.settings.flash_output_usd_per_million
            ) / 1_000_000
        else:
            cost = (
                input_tokens * self.settings.pro_input_usd_per_million
                + output_tokens * self.settings.pro_output_usd_per_million
            ) / 1_000_000
        MODEL_TOKENS.labels(run_type, "input").inc(input_tokens)
        MODEL_TOKENS.labels(run_type, "output").inc(output_tokens)
        MODEL_COST.labels(run_type).inc(cost)
        return UsageSummary(input_tokens, output_tokens, round(cost * 1_000_000))

    @staticmethod
    def _coach_input(input_json: str) -> str:
        payload = json.loads(input_json)
        objective = str(payload.get("objective", "")).strip()
        return objective or "Review my structured fitness data and suggest a safe, gradual weekly plan."

    @staticmethod
    def _appeal_input(input_json: str) -> str:
        payload = json.loads(input_json)
        return f"Review appeal {int(payload['appealId'])} using all required evidence tools."

    @staticmethod
    def _is_retryable(exc: Exception) -> bool:
        if isinstance(exc, (asyncio.TimeoutError, TimeoutError, httpx.TimeoutException, httpx.NetworkError)):
            return True
        status_code = getattr(exc, "status_code", None)
        if status_code in {400, 401, 402, 403, 404, 422}:
            return False
        if status_code == 429 or (isinstance(status_code, int) and status_code >= 500):
            return True
        name = type(exc).__name__
        if name in {"InputGuardrailTripwireTriggered", "OutputGuardrailTripwireTriggered", "PermanentAgentError"}:
            return False
        return True


class PermanentAgentError(RuntimeError):
    pass

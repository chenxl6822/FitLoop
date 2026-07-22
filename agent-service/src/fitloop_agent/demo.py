from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Any, Literal

from .config import Settings
from .provider import DeepSeekProvider
from .schemas import AgentContext
from .workflows import run_appeal, run_coach


DemoMode = Literal["all", "coach", "appeal"]

COACH_REQUIRED_TOOLS = {
    "get_user_goals",
    "get_recent_workouts",
    "calculate_training_load",
}
APPEAL_REQUIRED_TOOLS = {"get_appeal_evidence", "get_anomaly_rules"}

DEMO_TOOL_PAYLOADS: dict[str, Any] = {
    "get_user_goals": {
        "goals": [
            {"type": "WEEKLY_DISTANCE", "target": 15, "unit": "km", "progress": 8.2}
        ]
    },
    "get_recent_workouts": {
        "workouts": [
            {
                "date": "2026-07-20",
                "type": "RUN",
                "durationMinutes": 32,
                "distanceKm": 5.1,
                "perceivedExertion": 6,
            },
            {
                "date": "2026-07-18",
                "type": "RUN",
                "durationMinutes": 25,
                "distanceKm": 3.1,
                "perceivedExertion": 4,
            },
        ]
    },
    "get_health_trends": {
        "sleepHoursAverage": 7.1,
        "weightTrend": "STABLE",
        "dataCompleteness": "GOOD",
    },
    "get_goal_completion": [{"goalType": "WEEKLY_DISTANCE", "completionRate": 0.55}],
    "calculate_training_load": {
        "acuteLoad7d": 96,
        "chronicLoad28d": 82,
        "acuteChronicRatio": 1.17,
        "riskBand": "NORMAL",
    },
    "get_appeal_evidence": {
        "appeal": {"id": 2001, "reason": "手表在隧道路段出现定位漂移，请复核。"},
        "workout": {"type": "RUN", "distanceKm": 5.0, "durationMinutes": 31},
        "speedSummary": {"medianKmh": 9.7, "maxKmh": 42.0, "spikeDurationSeconds": 4},
        "recentHistory": {"runs": 12, "medianSpeedKmh": 9.4, "priorViolations": 0},
    },
    "get_anomaly_rules": {
        "rulesVersion": "2026-07-demo",
        "rules": [
            {
                "id": "RUN_SPEED_SPIKE",
                "thresholdKmh": 25,
                "minimumDurationSeconds": 10,
            }
        ],
        "policy": (
            "A sub-threshold-duration isolated spike may be GPS drift; "
            "final action requires administrator confirmation."
        ),
    },
}


class DemoBackend:
    """Deterministic, privacy-safe tool fixture used only by the live model demo."""

    def __init__(self) -> None:
        self.calls: list[str] = []

    async def tool(self, _path: str, _token: str, tool_name: str) -> Any:
        if tool_name not in DEMO_TOOL_PAYLOADS:
            raise KeyError(f"Demo fixture does not allow tool: {tool_name}")
        self.calls.append(tool_name)
        return DEMO_TOOL_PAYLOADS[tool_name]


def _usage(result: Any) -> dict[str, int]:
    input_tokens = 0
    output_tokens = 0
    for response in result.raw_responses:
        input_tokens += getattr(response.usage, "input_tokens", 0) or 0
        output_tokens += getattr(response.usage, "output_tokens", 0) or 0
    return {"inputTokens": input_tokens, "outputTokens": output_tokens}


def _require_tools(workflow: str, calls: list[str], required: set[str]) -> None:
    missing = sorted(required.difference(calls))
    if missing:
        raise RuntimeError(f"{workflow} did not call required tools: {', '.join(missing)}")


async def _run_coach_demo(provider: DeepSeekProvider, settings: Settings) -> dict[str, Any]:
    backend = DemoBackend()
    context = AgentContext(
        run_id="live-demo-coach",
        subject_user_id=1001,
        subject_resource_id=None,
        run_type="COACH",
        trace_id="live-demo-coach",
        token="demo-token",
        backend=backend,
    )
    output, result = await run_coach(
        provider,
        context,
        "Use my evidence to create a gradual seven-day outlook for a 15 km weekly running goal. "
        "Answer in Chinese.",
        settings,
    )
    _require_tools("coach", backend.calls, COACH_REQUIRED_TOOLS)
    return {
        "workflow": "coach",
        "model": settings.deepseek_coach_model,
        "tools": backend.calls,
        "usage": _usage(result),
        "output": output.model_dump(),
    }


async def _run_appeal_demo(provider: DeepSeekProvider, settings: Settings) -> dict[str, Any]:
    backend = DemoBackend()
    context = AgentContext(
        run_id="live-demo-appeal",
        subject_user_id=1001,
        subject_resource_id=2001,
        run_type="APPEAL_REVIEW",
        trace_id="live-demo-appeal",
        token="demo-token",
        backend=backend,
    )
    output, result = await run_appeal(
        provider,
        context,
        "Review appeal 2001 using only structured evidence and rules. "
        "Return the advisory decision in Chinese.",
        settings,
    )
    _require_tools("appeal", backend.calls, APPEAL_REQUIRED_TOOLS)
    return {
        "workflow": "appeal",
        "model": settings.deepseek_appeal_model,
        "tools": backend.calls,
        "usage": _usage(result),
        "output": output.model_dump(),
    }


async def run_live_demo(settings: Settings, mode: DemoMode = "all") -> list[dict[str, Any]]:
    provider = DeepSeekProvider(settings)
    results: list[dict[str, Any]] = []
    try:
        if mode in ("all", "coach"):
            results.append(await _run_coach_demo(provider, settings))
        if mode in ("all", "appeal"):
            results.append(await _run_appeal_demo(provider, settings))
        return results
    finally:
        await provider.close()


def _discover_env_file() -> Path | None:
    candidates = (Path.cwd() / ".env", Path.cwd().parent / ".env")
    return next((path for path in candidates if path.is_file()), None)


def _load_settings(env_file: Path | None) -> Settings:
    values: dict[str, Any] = {"agent_service_key": "demo-backend-not-used"}
    if env_file is not None:
        values["_env_file"] = env_file
    return Settings(**values)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run the real DeepSeek coach and appeal agents against deterministic demo tools."
    )
    parser.add_argument("--mode", choices=("all", "coach", "appeal"), default="all")
    parser.add_argument("--env-file", type=Path, default=None)
    parser.add_argument(
        "--confirm-live-api",
        action="store_true",
        help="Confirm that this command may consume DeepSeek API quota.",
    )
    args = parser.parse_args()
    if not args.confirm_live_api:
        parser.error("--confirm-live-api is required because this command consumes DeepSeek API quota")

    env_file = args.env_file or _discover_env_file()
    if env_file is not None and not env_file.is_file():
        parser.error(f"environment file does not exist: {env_file}")

    try:
        settings = _load_settings(env_file)
        results = asyncio.run(run_live_demo(settings, args.mode))
    except Exception as exc:
        print(f"live-agent-demo=FAILED ({type(exc).__name__}): {exc}", file=sys.stderr)
        return 1

    print("live-agent-demo=SUCCESS")
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from prometheus_client import Counter, Gauge, Histogram

RUNS = Counter("fitloop_agent_runs_total", "Agent runs", ["type", "outcome"])
RUN_LATENCY = Histogram(
    "fitloop_agent_run_duration_seconds",
    "End-to-end agent run duration",
    ["type"],
    buckets=(0.5, 1, 2, 5, 8, 12, 20, 25, 45),
)
MODEL_TOKENS = Counter("fitloop_agent_model_tokens_total", "Model tokens", ["type", "direction"])
MODEL_COST = Counter("fitloop_agent_model_cost_usd", "Estimated model cost", ["type"])
TOOL_CALLS = Counter("fitloop_agent_tool_calls_total", "Backend tool calls", ["tool", "outcome"])
QUEUE_LAG = Gauge("fitloop_agent_queue_lag", "Redis Stream consumer lag when available")

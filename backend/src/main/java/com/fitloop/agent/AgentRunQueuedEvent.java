package com.fitloop.agent;

public record AgentRunQueuedEvent(String runId, AgentRunType type, String traceId) { }

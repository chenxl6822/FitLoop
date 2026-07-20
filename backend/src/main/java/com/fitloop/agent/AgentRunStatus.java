package com.fitloop.agent;

public enum AgentRunStatus {
    QUEUED,
    RUNNING,
    WAITING_APPROVAL,
    SUCCEEDED,
    FAILED_RETRYABLE,
    FAILED_FINAL
}

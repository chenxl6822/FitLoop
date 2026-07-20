package com.fitloop.agent;

import java.time.Instant;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AgentRunRecoveryService {
    private final AgentRunRepository runs;
    private final ApplicationEventPublisher events;

    public AgentRunRecoveryService(AgentRunRepository runs, ApplicationEventPublisher events) {
        this.runs = runs;
        this.events = events;
    }

    @Transactional
    public void recover(String runId, Instant staleBefore) {
        AgentRun run = runs.findForUpdate(runId).orElse(null);
        if (run == null || run.getStatus() != AgentRunStatus.RUNNING
                || run.getUpdatedAt() == null || !run.getUpdatedAt().isBefore(staleBefore)) {
            return;
        }
        run.fail("Agent worker heartbeat timed out", true);
        if (run.getStatus() == AgentRunStatus.FAILED_RETRYABLE) {
            events.publishEvent(new AgentRunQueuedEvent(run.getRunId(), run.getRunType(), run.getTraceId()));
        }
    }
}

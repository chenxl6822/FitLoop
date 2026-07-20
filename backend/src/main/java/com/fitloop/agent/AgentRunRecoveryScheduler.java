package com.fitloop.agent;

import java.time.Instant;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class AgentRunRecoveryScheduler {
    private final AgentRunRepository runs;
    private final AgentRunRecoveryService recovery;

    public AgentRunRecoveryScheduler(AgentRunRepository runs, AgentRunRecoveryService recovery) {
        this.runs = runs;
        this.recovery = recovery;
    }

    @Scheduled(fixedDelayString = "${fitloop.agent.stuck-run-scan-ms:15000}")
    public void recoverStuckRuns() {
        Instant stale = Instant.now().minusSeconds(60);
        runs.findTop100ByStatusAndUpdatedAtBeforeOrderByCreatedAtAsc(AgentRunStatus.RUNNING, stale)
                .forEach(run -> recovery.recover(run.getRunId(), stale));
    }
}

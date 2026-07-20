package com.fitloop.agent;

import io.micrometer.core.instrument.MeterRegistry;
import java.time.Instant;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@Component
public class AgentQueuePublisher {
    private final AgentRunRepository runs;
    private final StringRedisTemplate redis;
    private final MeterRegistry meters;
    private final String streamKey;

    public AgentQueuePublisher(AgentRunRepository runs, StringRedisTemplate redis, MeterRegistry meters,
                               @Value("${fitloop.agent.stream-key:fitloop:agent:runs}") String streamKey) {
        this.runs = runs;
        this.redis = redis;
        this.meters = meters;
        this.streamKey = streamKey;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onQueued(AgentRunQueuedEvent event) { publish(event); }

    @Scheduled(fixedDelayString = "${fitloop.agent.recovery-delay-ms:30000}")
    public void recoverUnpublishedRuns() {
        Instant stale = Instant.now().minusSeconds(30);
        runs.findTop100ByStatusAndUpdatedAtBeforeOrderByCreatedAtAsc(AgentRunStatus.QUEUED, stale)
                .forEach(run -> publish(new AgentRunQueuedEvent(run.getRunId(), run.getRunType(), run.getTraceId())));
        runs.findTop100ByStatusAndUpdatedAtBeforeOrderByCreatedAtAsc(AgentRunStatus.FAILED_RETRYABLE, stale)
                .forEach(run -> publish(new AgentRunQueuedEvent(run.getRunId(), run.getRunType(), run.getTraceId())));
    }

    private void publish(AgentRunQueuedEvent event) {
        try {
            redis.opsForStream().add(StreamRecords.mapBacked(Map.of(
                    "runId", event.runId(),
                    "type", event.type().name(),
                    "traceId", event.traceId())).withStreamKey(streamKey));
            meters.counter("fitloop.agent.queue.published", "type", event.type().name()).increment();
        } catch (RuntimeException ex) {
            meters.counter("fitloop.agent.queue.failed", "type", event.type().name()).increment();
        }
    }
}

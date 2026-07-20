package com.fitloop.social;

import com.fitloop.common.OutboxEvent;
import com.fitloop.common.OutboxEventRepository;
import com.fitloop.sport.WorkoutCompletedEvent;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Instant;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;

@Component
public class RankingOutboxProcessor {
    private final OutboxEventRepository events;
    private final LeaderboardService leaderboard;
    private final ObjectMapper objectMapper;
    private final MeterRegistry meters;

    public RankingOutboxProcessor(OutboxEventRepository events, LeaderboardService leaderboard,
                                  ObjectMapper objectMapper, MeterRegistry meters) {
        this.events = events;
        this.leaderboard = leaderboard;
        this.objectMapper = objectMapper;
        this.meters = meters;
    }

    @Scheduled(fixedDelayString = "${fitloop.outbox.poll-delay-ms:1000}")
    @Transactional
    public void process() {
        meters.gauge("fitloop.outbox.pending", events, OutboxEventRepository::countByProcessedAtIsNull);
        for (OutboxEvent event : events.findTop100ByProcessedAtIsNullAndAvailableAtBeforeOrderByIdAsc(Instant.now())) {
            if (!"WORKOUT_COMPLETED".equals(event.getEventType())) continue;
            try {
                WorkoutCompletedEvent payload = objectMapper.readValue(event.getPayload(), WorkoutCompletedEvent.class);
                leaderboard.project(event.getId(), payload);
                event.setProcessedAt(Instant.now());
                meters.counter("fitloop.outbox.processed", "type", event.getEventType()).increment();
            } catch (Exception ex) {
                int attempts = event.getAttempts() + 1;
                event.setAttempts(attempts);
                event.setLastError(ex.getMessage() == null ? ex.getClass().getSimpleName()
                        : ex.getMessage().substring(0, Math.min(ex.getMessage().length(), 500)));
                event.setAvailableAt(Instant.now().plusSeconds(Math.min(60, 1L << Math.min(attempts, 6))));
                meters.counter("fitloop.outbox.failed", "type", event.getEventType()).increment();
            }
        }
    }
}

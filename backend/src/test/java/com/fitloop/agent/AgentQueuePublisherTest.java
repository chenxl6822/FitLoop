package com.fitloop.agent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.core.StreamOperations;
import org.springframework.data.redis.core.StringRedisTemplate;

@ExtendWith(MockitoExtension.class)
class AgentQueuePublisherTest {
    @Mock AgentRunRepository runs;
    @Mock StringRedisTemplate redis;
    @Mock StreamOperations<String, String, String> streams;

    private SimpleMeterRegistry meters;
    private AgentQueuePublisher publisher;

    @BeforeEach
    void setUp() {
        meters = new SimpleMeterRegistry();
        when(redis.<String, String>opsForStream()).thenReturn(streams);
        publisher = new AgentQueuePublisher(runs, redis, meters, "fitloop:agent:runs");
    }

    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void queuedEventPublishesThePythonWorkerContractToRedisStream() {
        publisher.onQueued(new AgentRunQueuedEvent("run-42", AgentRunType.APPEAL_REVIEW, "trace-42"));

        ArgumentCaptor<MapRecord<String, String, String>> captor =
                (ArgumentCaptor) ArgumentCaptor.forClass(MapRecord.class);
        verify(streams).add(captor.capture());
        MapRecord<String, String, String> record = captor.getValue();

        assertThat(record.getStream()).isEqualTo("fitloop:agent:runs");
        assertThat(record.getValue()).isEqualTo(Map.of(
                "runId", "run-42",
                "type", "APPEAL_REVIEW",
                "traceId", "trace-42"));
        assertThat(meters.counter("fitloop.agent.queue.published", "type", "APPEAL_REVIEW").count())
                .isEqualTo(1.0);
    }
}

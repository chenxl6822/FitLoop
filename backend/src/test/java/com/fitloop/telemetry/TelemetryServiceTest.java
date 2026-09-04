package com.fitloop.telemetry;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.telemetry.TelemetryDtos.EventItem;
import com.fitloop.telemetry.TelemetryDtos.IngestEventsRequest;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import tools.jackson.databind.ObjectMapper;

@DataJpaTest
@Import({TelemetryService.class, TelemetryServiceTest.TelemetryTestConfig.class})
class TelemetryServiceTest {
    @TestConfiguration
    static class TelemetryTestConfig {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }

        @Bean
        MeterRegistry meterRegistry() {
            return new SimpleMeterRegistry();
        }
    }

    @Autowired
    private TelemetryService telemetry;

    @Autowired
    private TelemetryEventRepository events;

    @Autowired
    private ObjectMapper objectMapper;

    @BeforeEach
    void clear() {
        events.deleteAll();
    }

    @Test
    void acceptsAllowedEventWithoutSensitiveProps() {
        var response = telemetry.ingest(7L, new IngestEventsRequest(List.of(
                new EventItem("workout_finish", Instant.parse("2026-09-04T12:00:00Z"),
                        Map.of("result", "saved", "checkin_mode", "gps")))));

        assertThat(response.accepted()).isEqualTo(1);
        assertThat(events.findAll()).hasSize(1);
        TelemetryEvent stored = events.findAll().getFirst();
        assertThat(stored.getUserId()).isEqualTo(7L);
        assertThat(stored.getEventName()).isEqualTo("workout_finish");
        assertThat(stored.getPropsJson()).doesNotContain("\"lat\"");
        assertThat(stored.getPropsJson()).doesNotContain("token");
        assertThat(stored.getPropsJson()).doesNotContain("phone");
    }

    @Test
    void rejectsUnknownEventName() {
        assertThatThrownBy(() -> telemetry.ingest(1L, new IngestEventsRequest(List.of(
                        new EventItem("hack_event", null, Map.of())))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("不支持的事件");
        assertThat(events.count()).isZero();
    }

    @Test
    void rejectsLatitudePropKeys() {
        assertThatThrownBy(() -> telemetry.sanitizeProps(Map.of("lat", 28.1)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("禁止的 props 键");
        assertThatThrownBy(() -> telemetry.sanitizeProps(Map.of("start_lng", 112.9)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> telemetry.sanitizeProps(Map.of("phone", "13800138000")))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> telemetry.sanitizeProps(Map.of("access_token", "abc")))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsNestedOrComplexPropValues() {
        assertThatThrownBy(() -> telemetry.sanitizeProps(Map.of("meta", Map.of("a", 1))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("类型不支持");
    }

    @Test
    void serializesBooleanAndCounts() {
        Map<String, Object> clean = telemetry.sanitizeProps(Map.of(
                "granted", true,
                "synced_count", 2,
                "failed_count", 1));
        String json = objectMapper.writeValueAsString(clean);
        assertThat(json).contains("\"granted\":true");
        assertThat(json).doesNotContain("@");
    }
}

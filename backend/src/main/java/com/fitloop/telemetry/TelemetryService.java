package com.fitloop.telemetry;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fitloop.telemetry.TelemetryDtos.EventItem;
import com.fitloop.telemetry.TelemetryDtos.IngestEventsRequest;
import com.fitloop.telemetry.TelemetryDtos.IngestEventsResponse;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class TelemetryService {
    static final Set<String> ALLOWED_EVENTS = Set.of(
            "location_auth_result",
            "workout_start",
            "workout_finish",
            "queue_retry",
            "map_consent",
            "today_plan_complete",
            "export_result",
            "account_delete_result");

    private static final Pattern PROP_KEY = Pattern.compile("^[a-z][a-z0-9_]{0,31}$");
    private static final Pattern FORBIDDEN_KEY = Pattern.compile(
            "(?i).*(lat|lng|lon|phone|mobile|token|password|passwd|email|authorization|secret|refresh|track|coord|address|id_card).*");
    private static final int MAX_PROPS = 16;
    private static final int MAX_STRING_LEN = 64;

    private final TelemetryEventRepository events;
    private final ObjectMapper objectMapper;
    private final MeterRegistry meters;

    public TelemetryService(TelemetryEventRepository events, ObjectMapper objectMapper, MeterRegistry meters) {
        this.events = events;
        this.objectMapper = objectMapper;
        this.meters = meters;
    }

    @Transactional
    public IngestEventsResponse ingest(Long userId, IngestEventsRequest request) {
        Objects.requireNonNull(userId, "userId");
        Objects.requireNonNull(request, "request");
        int accepted = 0;
        for (EventItem item : request.events()) {
            events.save(toEntity(userId, item));
            accepted++;
            meters.counter("fitloop.telemetry.accepted", "event", item.eventName()).increment();
        }
        return new IngestEventsResponse(accepted);
    }

    TelemetryEvent toEntity(Long userId, EventItem item) {
        String eventName = requireAllowedEvent(item.eventName());
        Map<String, Object> sanitized = sanitizeProps(item.props());
        String propsJson;
        try {
            propsJson = objectMapper.writeValueAsString(sanitized);
        } catch (JsonProcessingException ex) {
            throw new IllegalArgumentException("props 无法序列化");
        }
        if (propsJson.length() > 2000) {
            throw new IllegalArgumentException("props 过长");
        }
        Instant clientTs = item.clientTimestamp();
        if (clientTs != null && clientTs.isAfter(Instant.now().plusSeconds(300))) {
            throw new IllegalArgumentException("clientTimestamp 无效");
        }
        return new TelemetryEvent(userId, eventName, clientTs, propsJson);
    }

    private String requireAllowedEvent(String raw) {
        if (!StringUtils.hasText(raw)) {
            throw new IllegalArgumentException("eventName 不能为空");
        }
        String eventName = raw.trim();
        if (!ALLOWED_EVENTS.contains(eventName)) {
            meters.counter("fitloop.telemetry.rejected", "reason", "event_name").increment();
            throw new IllegalArgumentException("不支持的事件: " + eventName);
        }
        return eventName;
    }

    Map<String, Object> sanitizeProps(Map<String, Object> raw) {
        if (raw == null || raw.isEmpty()) {
            return Map.of();
        }
        if (raw.size() > MAX_PROPS) {
            meters.counter("fitloop.telemetry.rejected", "reason", "props_size").increment();
            throw new IllegalArgumentException("props 最多 " + MAX_PROPS + " 个字段");
        }
        Map<String, Object> clean = new LinkedHashMap<>();
        for (Map.Entry<String, Object> entry : raw.entrySet()) {
            String key = entry.getKey();
            if (key == null || !PROP_KEY.matcher(key).matches()) {
                meters.counter("fitloop.telemetry.rejected", "reason", "prop_key").increment();
                throw new IllegalArgumentException("非法 props 键: " + key);
            }
            if (FORBIDDEN_KEY.matcher(key).matches()) {
                meters.counter("fitloop.telemetry.rejected", "reason", "forbidden_key").increment();
                throw new IllegalArgumentException("禁止的 props 键: " + key);
            }
            clean.put(key, sanitizeValue(key, entry.getValue()));
        }
        return clean;
    }

    private Object sanitizeValue(String key, Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean || value instanceof Integer || value instanceof Long) {
            return value;
        }
        if (value instanceof Double number) {
            if (!Double.isFinite(number)) {
                throw new IllegalArgumentException("props." + key + " 数值无效");
            }
            return number;
        }
        if (value instanceof Float number) {
            if (!Float.isFinite(number)) {
                throw new IllegalArgumentException("props." + key + " 数值无效");
            }
            return number.doubleValue();
        }
        if (value instanceof String text) {
            String trimmed = text.trim();
            if (trimmed.length() > MAX_STRING_LEN) {
                throw new IllegalArgumentException("props." + key + " 过长");
            }
            String lower = trimmed.toLowerCase(Locale.ROOT);
            if (FORBIDDEN_KEY.matcher(lower).matches() && looksLikeCredential(lower)) {
                throw new IllegalArgumentException("props." + key + " 含敏感内容");
            }
            return trimmed;
        }
        meters.counter("fitloop.telemetry.rejected", "reason", "prop_type").increment();
        throw new IllegalArgumentException("props." + key + " 类型不支持");
    }

    private static boolean looksLikeCredential(String lower) {
        return lower.contains("bearer ")
                || lower.contains("@")
                || lower.matches(".*\\+?\\d{8,}.*");
    }
}

package com.fitloop.telemetry;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.Map;

public final class TelemetryDtos {
    private TelemetryDtos() {}

    public record IngestEventsRequest(
            @NotEmpty
            @Size(max = 20)
            List<@Valid EventItem> events) {}

    public record EventItem(
            @NotBlank
            @Size(max = 64)
            String eventName,
            Instant clientTimestamp,
            Map<String, Object> props) {}

    public record IngestEventsResponse(int accepted) {}
}

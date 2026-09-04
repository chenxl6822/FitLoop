package com.fitloop.telemetry;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import com.fitloop.telemetry.TelemetryDtos.IngestEventsRequest;
import com.fitloop.telemetry.TelemetryDtos.IngestEventsResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/telemetry")
public class TelemetryController {
    private final TelemetryService telemetry;

    public TelemetryController(TelemetryService telemetry) {
        this.telemetry = telemetry;
    }

    @PostMapping("/events")
    public ApiResponse<IngestEventsResponse> ingest(@Valid @RequestBody IngestEventsRequest request) {
        return ApiResponse.ok(telemetry.ingest(AuthSupport.currentUserId(), request));
    }
}

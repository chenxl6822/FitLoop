package com.fitloop.sport;

import com.fitloop.security.AuthSupport;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.SportCursorPage;
import com.fitloop.sport.SportDtos.SportRecordResponse;
import com.fitloop.sport.SportDtos.TrackBatchRequest;
import com.fitloop.sport.SportDtos.TrackBatchResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/workouts")
public class V1SportController {
    private final SportService workouts;

    public V1SportController(SportService workouts) {
        this.workouts = workouts;
    }

    @PostMapping("/{sessionId}/track-points:batch")
    public TrackBatchResponse appendTrack(@PathVariable String sessionId,
                                          @Valid @RequestBody TrackBatchRequest request) {
        return workouts.appendTrackBatch(AuthSupport.currentUserId(), sessionId, request);
    }

    @PostMapping("/{sessionId}/finish")
    public SportRecordResponse finish(@PathVariable String sessionId,
                                      @RequestHeader("Idempotency-Key") String idempotencyKey,
                                      @Valid @RequestBody FinishSessionRequest request) {
        if (!sessionId.equals(request.sessionId())) {
            throw new IllegalArgumentException("Path sessionId must match request sessionId");
        }
        return workouts.finish(AuthSupport.currentUserId(), request, idempotencyKey);
    }

    @GetMapping
    public SportCursorPage list(@RequestParam(required = false) Long cursor,
                                @RequestParam(defaultValue = "20") int size) {
        return workouts.list(AuthSupport.currentUserId(), cursor, size);
    }
}

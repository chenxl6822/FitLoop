package com.fitloop.sport;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;

public final class SportDtos {
    private SportDtos() {
    }

    public record StartSessionRequest(@NotBlank String sportType, @NotBlank String checkinMode) {
    }

    public record StartSessionResponse(String sessionId, Instant startTime) {
    }

    public record TrackPointRequest(@NotBlank String sessionId, @NotNull Double lat, @NotNull Double lng,
                                    Double accuracy, @NotNull Instant timestamp) {
    }

    public record FinishSessionRequest(@NotBlank String sessionId, Long durationSeconds, Double distanceKm,
                                       Double calorie, Double weightKg, String photoUrl) {
    }

    public record SportRecordResponse(Long recordId, String sessionId, String sportType, String checkinMode,
                                      long durationSeconds, double distanceKm, double calorie, int status,
                                      String abnormalReason, Instant startedAt, Instant endedAt) {
        public static SportRecordResponse from(SportRecord record) {
            return new SportRecordResponse(record.getRecordId(), record.getSessionId(), record.getSportType(),
                    record.getCheckinMode(), record.getDurationSeconds(), record.getDistanceKm(),
                    record.getCalorie(), record.getStatus(), record.getAbnormalReason(),
                    record.getStartedAt(), record.getEndedAt());
        }
    }

    public record SportListResponse(List<SportRecordResponse> records) {
    }
}

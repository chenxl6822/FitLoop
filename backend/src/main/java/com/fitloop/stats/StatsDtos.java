package com.fitloop.stats;

import java.time.LocalDate;

public final class StatsDtos {
    private StatsDtos() {
    }

    public record HealthRequest(Double weightKg, Double sleepHours, String dietNote, LocalDate dataDate) {
    }

    public record HealthResponse(Long healthId, Double weightKg, Double sleepHours, String dietNote, LocalDate dataDate) {
        public static HealthResponse from(HealthData data) {
            return new HealthResponse(data.getHealthId(), data.getWeightKg(), data.getSleepHours(),
                    data.getDietNote(), data.getDataDate());
        }
    }

    public record SportStatsResponse(String period, long checkinCount, long durationSeconds,
                                     double distanceKm, double calorie) {
    }
}

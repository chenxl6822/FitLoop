package com.fitloop.stats;

import java.time.LocalDate;
import java.util.List;

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

    // ── 历史统计 ──

    public record SportHistoryPoint(LocalDate date, long count, long durationSeconds,
                                    double distanceKm, double calorie) {
    }

    public record SportHistoryResponse(String period, String metric, List<SportHistoryPoint> points) {
    }

    public record WeightHistoryPoint(LocalDate date, Double weightKg) {
        public static WeightHistoryPoint from(HealthData data) {
            return new WeightHistoryPoint(data.getDataDate(), data.getWeightKg());
        }
    }

    public record WeightHistoryResponse(List<WeightHistoryPoint> points) {
    }
}

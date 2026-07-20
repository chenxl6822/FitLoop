package com.fitloop.agent;

import com.fitloop.target.TargetDtos.TargetResponse;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public final class AgentToolDtos {
    private AgentToolDtos() { }

    public record GoalToolResponse(List<TargetResponse> goals) { }
    public record WorkoutSummary(Long recordId, String sportType, long durationSeconds, double distanceKm,
                                 double calorie, int status, String abnormalReason, Instant startedAt) { }
    public record WorkoutToolResponse(List<WorkoutSummary> workouts) { }
    public record HealthPoint(LocalDate date, Double weightKg, Double sleepHours) { }
    public record HealthTrendResponse(List<HealthPoint> points) { }
    public record AppealEvidenceResponse(Long appealId, String reason, String evidenceUrl, String appealStatus,
                                         WorkoutSummary workout, double averageSpeedKmh,
                                         List<WorkoutSummary> recentHistory) { }
    public record RuleEvidence(String code, String description, String threshold) { }
    public record RuleToolResponse(List<RuleEvidence> rules) { }
}

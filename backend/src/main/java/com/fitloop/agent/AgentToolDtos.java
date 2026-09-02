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

    public record AcademicScheduleCourseRow(
            String name,
            String classroom,
            int dayOfWeek,
            String startTime,
            String endTime
    ) { }

    public record AcademicScheduleExamRow(String name, String startTime, String location) { }

    public record AcademicScheduleWindowRow(String startTime, String endTime) { }

    /** Suggested free workout slot for a weekday (1=Monday … 7=Sunday). */
    public record AcademicScheduleWeeklyWindowRow(
            int dayOfWeek,
            String weekdayLabel,
            String startTime,
            String endTime
    ) { }

    public record AcademicScheduleToolResponse(
            boolean synced,
            String termYear,
            String termCode,
            List<AcademicScheduleCourseRow> weekCourses,
            List<AcademicScheduleCourseRow> todayCourses,
            AcademicScheduleCourseRow nextCourseToday,
            List<AcademicScheduleWindowRow> suggestedWorkoutWindows,
            List<AcademicScheduleWeeklyWindowRow> weeklyWorkoutWindows,
            List<AcademicScheduleExamRow> upcomingExams
    ) {
        public static AcademicScheduleToolResponse empty() {
            return new AcademicScheduleToolResponse(
                    false, null, null, List.of(), List.of(), null, List.of(), List.of(), List.of());
        }
    }
}

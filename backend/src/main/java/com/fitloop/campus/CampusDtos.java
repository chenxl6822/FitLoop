package com.fitloop.campus;

import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.List;

public final class CampusDtos {
    private CampusDtos() {
    }

    public record CampusStatusResponse(
            boolean verified,
            String college,
            String className,
            String major,
            String grade,
            Instant verifiedAt
    ) {
        public static CampusStatusResponse unverified() {
            return new CampusStatusResponse(false, null, null, null, null, null);
        }

        public static CampusStatusResponse from(CampusVerification verification) {
            return new CampusStatusResponse(
                    true,
                    verification.getCollege(),
                    verification.getClassName(),
                    verification.getMajor(),
                    verification.getGrade(),
                    verification.getVerifiedAt()
            );
        }
    }

    public record CampusVerifyRequest(@NotBlank String studentId, @NotBlank String password) {
    }

    public record CampusScheduleSyncRequest(@NotBlank String studentId, @NotBlank String password) {
    }

    public record ScheduleCourseRow(
            String name,
            String teacher,
            String classroom,
            int dayOfWeek,
            int startSection,
            int sectionCount,
            String weeks,
            String startTime,
            String endTime
    ) {
    }

    public record ScheduleExamRow(
            String name,
            String startTime,
            String endTime,
            String location,
            String examType
    ) {
    }

    public record WorkoutWindowRow(String startTime, String endTime) {
    }

    public record CampusScheduleResponse(
            boolean synced,
            Instant lastSyncedAt,
            String termYear,
            String termCode,
            List<ScheduleCourseRow> courses,
            List<ScheduleExamRow> exams,
            List<ScheduleCourseRow> todayCourses,
            ScheduleCourseRow nextCourseToday,
            List<WorkoutWindowRow> suggestedWorkoutWindows,
            List<ScheduleExamRow> upcomingExams
    ) {
        public static CampusScheduleResponse empty() {
            return new CampusScheduleResponse(
                    false, null, null, null, List.of(), List.of(), List.of(), null, List.of(), List.of());
        }
    }

    public record CampusLinkRequest(
            Long userId,
            @NotBlank String studentIdHash,
            @NotBlank String college,
            @NotBlank String className,
            String major,
            String grade,
            Instant verifiedAt,
            String provider
    ) {
    }
}

package com.fitloop.campus;

import com.fitloop.campus.CampusAuthClient.CampusScheduleSyncResult;
import com.fitloop.campus.CampusDtos.CampusScheduleResponse;
import com.fitloop.campus.CampusDtos.CampusScheduleSyncRequest;
import com.fitloop.campus.CampusDtos.ScheduleCourseRow;
import com.fitloop.campus.CampusDtos.ScheduleExamRow;
import com.fitloop.campus.CampusDtos.WorkoutWindowRow;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class CampusScheduleService {
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final LocalTime DAY_START = LocalTime.of(7, 0);
    private static final LocalTime DAY_END = LocalTime.of(22, 0);
    private static final int MIN_WORKOUT_MINUTES = 30;

    private final CampusVerificationRepository verifications;
    private final CampusScheduleCourseRepository courses;
    private final CampusScheduleExamRepository exams;
    private final CampusScheduleMetaRepository meta;
    private final CampusAuthClient campusAuthClient;

    public CampusScheduleService(CampusVerificationRepository verifications,
                                 CampusScheduleCourseRepository courses,
                                 CampusScheduleExamRepository exams,
                                 CampusScheduleMetaRepository meta,
                                 CampusAuthClient campusAuthClient) {
        this.verifications = verifications;
        this.courses = courses;
        this.exams = exams;
        this.meta = meta;
        this.campusAuthClient = campusAuthClient;
    }

    @Transactional
    public CampusScheduleResponse syncSchedule(Long userId, CampusScheduleSyncRequest request) {
        requireVerified(userId);
        CampusScheduleSyncResult payload = campusAuthClient.syncSchedule(
                userId, request.studentId().trim(), request.password());
        Instant syncedAt = Instant.now();
        courses.deleteByUserId(userId);
        exams.deleteByUserId(userId);
        for (var course : payload.courses()) {
            var row = new CampusScheduleCourse();
            row.setUserId(userId);
            row.setCourseName(course.name());
            row.setTeacher(course.teacher());
            row.setClassroom(course.classroom());
            row.setDayOfWeek(course.dayOfWeek());
            row.setStartSection(course.startSection());
            row.setSectionCount(course.sectionCount());
            row.setWeeks(course.weeks());
            row.setTermYear(payload.termYear());
            row.setTermCode(payload.termCode());
            row.setSyncedAt(syncedAt);
            courses.save(row);
        }
        for (var exam : payload.exams()) {
            var row = new CampusScheduleExam();
            row.setUserId(userId);
            row.setExamName(exam.name());
            row.setStartTime(parseInstant(exam.startTime()));
            row.setEndTime(exam.endTime() == null || exam.endTime().isBlank()
                    ? null : parseInstant(exam.endTime()));
            row.setLocation(exam.location());
            row.setExamType(exam.examType());
            row.setTermYear(payload.termYear());
            row.setTermCode(payload.termCode());
            row.setSyncedAt(syncedAt);
            exams.save(row);
        }
        var scheduleMeta = meta.findByUserId(userId).orElseGet(CampusScheduleMeta::new);
        scheduleMeta.setUserId(userId);
        scheduleMeta.setTermYear(payload.termYear());
        scheduleMeta.setTermCode(payload.termCode());
        scheduleMeta.setLastSyncedAt(syncedAt);
        meta.save(scheduleMeta);
        return buildResponse(userId);
    }

    @Transactional(readOnly = true)
    public CampusScheduleResponse getSchedule(Long userId) {
        requireVerified(userId);
        return buildResponse(userId);
    }

    @Transactional
    public void deleteForUser(Long userId) {
        courses.deleteByUserId(userId);
        exams.deleteByUserId(userId);
        meta.findByUserId(userId).ifPresent(meta::delete);
    }

    private CampusScheduleResponse buildResponse(Long userId) {
        var scheduleMeta = meta.findByUserId(userId).orElse(null);
        var courseRows = courses.findByUserIdOrderByDayOfWeekAscStartSectionAsc(userId);
        var examRows = exams.findByUserIdOrderByStartTimeAsc(userId);
        boolean synced = scheduleMeta != null;
        var mappedCourses = courseRows.stream().map(this::toCourseRow).toList();
        var mappedExams = examRows.stream().map(this::toExamRow).toList();
        LocalDate today = LocalDate.now(ZONE);
        int todayDow = dayOfWeekNumber(today.getDayOfWeek());
        LocalTime now = LocalTime.now(ZONE);
        var todayCourses = mappedCourses.stream()
                .filter(course -> course.dayOfWeek() == todayDow)
                .sorted(Comparator.comparingInt(ScheduleCourseRow::startSection))
                .toList();
        ScheduleCourseRow nextCourse = todayCourses.stream()
                .filter(course -> sectionEndTime(course).isAfter(now))
                .findFirst()
                .orElse(null);
        var workoutWindows = suggestWorkoutWindows(todayCourses, now);
        var upcomingExams = mappedExams.stream()
                .filter(exam -> !parseInstant(exam.startTime()).isBefore(Instant.now()))
                .limit(5)
                .toList();
        return new CampusScheduleResponse(
                synced,
                scheduleMeta == null ? null : scheduleMeta.getLastSyncedAt(),
                scheduleMeta == null ? null : scheduleMeta.getTermYear(),
                scheduleMeta == null ? null : scheduleMeta.getTermCode(),
                mappedCourses,
                mappedExams,
                todayCourses,
                nextCourse,
                workoutWindows,
                upcomingExams
        );
    }

    private List<WorkoutWindowRow> suggestWorkoutWindows(List<ScheduleCourseRow> todayCourses, LocalTime now) {
        List<LocalTime[]> busy = new ArrayList<>();
        for (var course : todayCourses) {
            LocalTime start = sectionStartTime(course);
            LocalTime end = sectionEndTime(course);
            busy.add(new LocalTime[] {start, end});
        }
        busy.sort(Comparator.comparing(interval -> interval[0]));
        List<WorkoutWindowRow> windows = new ArrayList<>();
        LocalTime cursor = DAY_START.isBefore(now) ? now : DAY_START;
        for (var interval : busy) {
            if (interval[0].isAfter(DAY_END)) {
                break;
            }
            if (minutesBetween(cursor, interval[0]) >= MIN_WORKOUT_MINUTES) {
                windows.add(new WorkoutWindowRow(formatTime(cursor), formatTime(interval[0])));
            }
            if (interval[1].isAfter(cursor)) {
                cursor = interval[1];
            }
        }
        if (minutesBetween(cursor, DAY_END) >= MIN_WORKOUT_MINUTES) {
            windows.add(new WorkoutWindowRow(formatTime(cursor), formatTime(DAY_END)));
        }
        return windows.stream().limit(3).toList();
    }

    private ScheduleCourseRow toCourseRow(CampusScheduleCourse course) {
        return new ScheduleCourseRow(
                course.getCourseName(),
                course.getTeacher(),
                course.getClassroom(),
                course.getDayOfWeek(),
                course.getStartSection(),
                course.getSectionCount(),
                course.getWeeks(),
                formatTime(sectionStartTime(course)),
                formatTime(sectionEndTime(course))
        );
    }

    private ScheduleExamRow toExamRow(CampusScheduleExam exam) {
        return new ScheduleExamRow(
                exam.getExamName(),
                exam.getStartTime().toString(),
                exam.getEndTime() == null ? null : exam.getEndTime().toString(),
                exam.getLocation(),
                exam.getExamType()
        );
    }

    private LocalTime sectionStartTime(ScheduleCourseRow course) {
        return CampusSectionTimes.sectionStart(course.startSection());
    }

    private LocalTime sectionEndTime(ScheduleCourseRow course) {
        int lastSection = course.startSection() + Math.max(course.sectionCount(), 1) - 1;
        return CampusSectionTimes.sectionEnd(lastSection);
    }

    private LocalTime sectionStartTime(CampusScheduleCourse course) {
        return CampusSectionTimes.sectionStart(course.getStartSection());
    }

    private LocalTime sectionEndTime(CampusScheduleCourse course) {
        int lastSection = course.getStartSection() + Math.max(course.getSectionCount(), 1) - 1;
        return CampusSectionTimes.sectionEnd(lastSection);
    }

    private static int dayOfWeekNumber(DayOfWeek dayOfWeek) {
        return dayOfWeek.getValue();
    }

    private static long minutesBetween(LocalTime start, LocalTime end) {
        return java.time.Duration.between(start, end).toMinutes();
    }

    private static String formatTime(LocalTime time) {
        return time.format(DateTimeFormatter.ofPattern("HH:mm"));
    }

    private static Instant parseInstant(String value) {
        if (value == null || value.isBlank()) {
            return Instant.now();
        }
        try {
            return Instant.parse(value);
        } catch (DateTimeParseException ignored) {
            // continue
        }
        try {
            return LocalDateTime.parse(value, DateTimeFormatter.ISO_LOCAL_DATE_TIME)
                    .atZone(ZONE)
                    .toInstant();
        } catch (DateTimeParseException ignored) {
            // continue
        }
        return LocalDate.parse(value.substring(0, Math.min(10, value.length())))
                .atStartOfDay(ZONE)
                .toInstant();
    }

    private void requireVerified(Long userId) {
        if (verifications.findByUserId(userId).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Campus identity required");
        }
    }
}

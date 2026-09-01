package com.fitloop.campus;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.campus.CampusDtos.ScheduleCourseRow;
import java.time.LocalTime;
import java.util.List;
import org.junit.jupiter.api.Test;

class CampusSchedulePlannerTest {
    @Test
    void suggestsWorkoutWindowBetweenClasses() {
        var service = new CampusScheduleService(null, null, null, null, null);
        var todayCourses = List.of(
                new ScheduleCourseRow("高等数学", "张老师", "A101", 1, 1, 2, "1-16",
                        "08:00", "09:35"),
                new ScheduleCourseRow("大学英语", "李老师", "B202", 1, 5, 2, "1-16",
                        "14:00", "15:35"));
        var windows = invokeSuggest(service, todayCourses, LocalTime.of(9, 40));
        assertThat(windows).isNotEmpty();
        assertThat(windows.getFirst().startTime()).isEqualTo("09:40");
    }

    @SuppressWarnings("unchecked")
    private List<com.fitloop.campus.CampusDtos.WorkoutWindowRow> invokeSuggest(
            CampusScheduleService service,
            List<ScheduleCourseRow> courses,
            LocalTime now) {
        try {
            var method = CampusScheduleService.class.getDeclaredMethod(
                    "suggestWorkoutWindows", List.class, LocalTime.class);
            method.setAccessible(true);
            return (List<com.fitloop.campus.CampusDtos.WorkoutWindowRow>) method.invoke(service, courses, now);
        } catch (ReflectiveOperationException ex) {
            throw new AssertionError(ex);
        }
    }
}

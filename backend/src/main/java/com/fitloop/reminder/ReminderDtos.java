package com.fitloop.reminder;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;

public final class ReminderDtos {
    private ReminderDtos() {
    }

    public record ReminderRequest(String type, LocalTime time, String cycle, Boolean enabled) {
    }

    public record ReminderResponse(Long id, String type, LocalTime time, String cycle, boolean enabled) {
        public static ReminderResponse from(ReminderConfig config) {
            return new ReminderResponse(config.getRemindId(), config.getType(), config.getRemindTime(),
                    config.getCycle(), config.isEnabled());
        }
    }

    public record TargetReminderResponse(
            Long targetId,
            String periodType,
            String metric,
            double targetValue,
            double completedValue,
            double progress,
            LocalDate startDate,
            LocalDate endDate,
            String status,
            boolean due,
            LocalTime remindTime,
            String message
    ) {
    }

    public record TargetReminderListResponse(List<TargetReminderResponse> targets) {
    }
}

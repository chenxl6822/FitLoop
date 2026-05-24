package com.fitloop.reminder;

import java.time.LocalTime;

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
}

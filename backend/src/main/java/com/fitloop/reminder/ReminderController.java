package com.fitloop.reminder;

import com.fitloop.common.ApiResponse;
import com.fitloop.reminder.ReminderDtos.ReminderRequest;
import com.fitloop.reminder.ReminderDtos.ReminderResponse;
import com.fitloop.reminder.ReminderDtos.ReminderListResponse;
import com.fitloop.reminder.ReminderDtos.TargetReminderListResponse;
import com.fitloop.security.AuthSupport;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ReminderController {
    private final ReminderService reminders;

    public ReminderController(ReminderService reminders) {
        this.reminders = reminders;
    }

    @GetMapping("/api/reminders")
    public ApiResponse<ReminderListResponse> list() {
        return ApiResponse.ok(reminders.list(AuthSupport.currentUserId()));
    }

    @PutMapping("/api/reminders/{id}")
    public ApiResponse<ReminderResponse> upsert(@PathVariable Long id, @RequestBody ReminderRequest request) {
        return ApiResponse.ok(reminders.upsert(AuthSupport.currentUserId(), id, request));
    }

    @GetMapping("/api/reminders/targets")
    public ApiResponse<TargetReminderListResponse> targetReminders() {
        return ApiResponse.ok(reminders.getTargetReminders(AuthSupport.currentUserId()));
    }

    @PutMapping("/api/reminders/targets/{targetId}/read")
    public ApiResponse<Map<String, Boolean>> acknowledgeTarget(@PathVariable Long targetId) {
        reminders.acknowledgeTargetReminder(AuthSupport.currentUserId(), targetId);
        return ApiResponse.ok(Map.of("acknowledged", true));
    }
}

package com.fitloop.reminder;

import com.fitloop.common.ApiResponse;
import com.fitloop.reminder.ReminderDtos.ReminderRequest;
import com.fitloop.reminder.ReminderDtos.ReminderResponse;
import com.fitloop.security.AuthSupport;
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

    @PutMapping("/api/reminders/{id}")
    public ApiResponse<ReminderResponse> upsert(@PathVariable Long id, @RequestBody ReminderRequest request) {
        return ApiResponse.ok(reminders.upsert(AuthSupport.currentUserId(), id, request));
    }
}

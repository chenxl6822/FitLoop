package com.fitloop.reminder;

import com.fitloop.reminder.ReminderDtos.ReminderRequest;
import com.fitloop.reminder.ReminderDtos.ReminderResponse;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ReminderService {
    private final ReminderConfigRepository reminders;

    public ReminderService(ReminderConfigRepository reminders) {
        this.reminders = reminders;
    }

    @Transactional
    public ReminderResponse upsert(Long userId, Long id, ReminderRequest request) {
        ReminderConfig config = reminders.findByRemindIdAndUserId(id, userId).orElseGet(ReminderConfig::new);
        config.setUserId(userId);
        if (request.type() != null) config.setType(request.type());
        if (request.time() != null) config.setRemindTime(request.time());
        if (request.cycle() != null) config.setCycle(request.cycle());
        if (request.enabled() != null) config.setEnabled(request.enabled());
        return ReminderResponse.from(reminders.save(config));
    }
}

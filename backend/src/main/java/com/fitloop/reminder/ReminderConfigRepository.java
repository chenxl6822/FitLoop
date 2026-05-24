package com.fitloop.reminder;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReminderConfigRepository extends JpaRepository<ReminderConfig, Long> {
    Optional<ReminderConfig> findByRemindIdAndUserId(Long remindId, Long userId);
}

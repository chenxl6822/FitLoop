package com.fitloop.reminder;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReminderConfigRepository extends JpaRepository<ReminderConfig, Long> {
    Optional<ReminderConfig> findByRemindIdAndUserId(Long remindId, Long userId);

    List<ReminderConfig> findByUserIdAndTypeAndEnabled(Long userId, String type, boolean enabled);

    List<ReminderConfig> findByUserIdOrderByType(Long userId);
}

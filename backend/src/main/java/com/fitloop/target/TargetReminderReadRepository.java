package com.fitloop.target;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TargetReminderReadRepository extends JpaRepository<TargetReminderRead, Long> {
    List<TargetReminderRead> findByUserId(Long userId);

    Optional<TargetReminderRead> findByUserIdAndTargetId(Long userId, Long targetId);
}

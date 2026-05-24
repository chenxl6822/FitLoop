package com.fitloop.sport;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SportRecordRepository extends JpaRepository<SportRecord, Long> {
    Optional<SportRecord> findBySessionIdAndUserId(String sessionId, Long userId);

    List<SportRecord> findTop50ByUserIdOrderByStartedAtDesc(Long userId);

    List<SportRecord> findByStatus(int status);
}

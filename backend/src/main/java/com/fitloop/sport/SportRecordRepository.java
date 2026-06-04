package com.fitloop.sport;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SportRecordRepository extends JpaRepository<SportRecord, Long> {
    Optional<SportRecord> findBySessionIdAndUserId(String sessionId, Long userId);

    List<SportRecord> findTop50ByUserIdOrderByStartedAtDesc(Long userId);

    List<SportRecord> findByStatus(int status);

    List<SportRecord> findByUserIdAndStatusAndStartedAtBetweenOrderByStartedAtAsc(
            Long userId, int status, Instant start, Instant end);

    @Query("SELECT r FROM SportRecord r WHERE r.userId = :userId AND r.status = :status "
            + "AND r.startedAt >= :start AND r.startedAt < :end ORDER BY r.startedAt ASC")
    List<SportRecord> findValidInRange(@Param("userId") Long userId,
                                       @Param("status") int status,
                                       @Param("start") Instant start,
                                       @Param("end") Instant end);

    long countByUserId(Long userId);

    long countByStartedAtAfter(Instant after);
}

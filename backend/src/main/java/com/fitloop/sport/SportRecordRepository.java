package com.fitloop.sport;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Lock;
import jakarta.persistence.LockModeType;
import org.springframework.data.repository.query.Param;

public interface SportRecordRepository extends JpaRepository<SportRecord, Long> {
    Optional<SportRecord> findBySessionIdAndUserId(String sessionId, Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from SportRecord r where r.sessionId = :sessionId and r.userId = :userId")
    Optional<SportRecord> findForUpdate(@Param("sessionId") String sessionId, @Param("userId") Long userId);

    List<SportRecord> findTop50ByUserIdOrderByStartedAtDesc(Long userId);

    List<SportRecord> findByStatus(int status);

    List<SportRecord> findByStatusAndStartedAtBetween(int status, Instant start, Instant end);

    List<SportRecord> findByUserIdInAndStatusAndStartedAtBetween(
            Collection<Long> userIds, int status, Instant start, Instant end);

    List<SportRecord> findByUserIdInAndStatus(Collection<Long> userIds, int status);

    @Query("select r from SportRecord r where r.userId = :userId and "
            + "(:cursor is null or r.recordId < :cursor) order by r.recordId desc")
    List<SportRecord> findPageBefore(@Param("userId") Long userId, @Param("cursor") Long cursor,
                                     org.springframework.data.domain.Pageable pageable);

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

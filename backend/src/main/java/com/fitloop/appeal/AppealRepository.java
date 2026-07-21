package com.fitloop.appeal;

import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface AppealRepository extends JpaRepository<Appeal, Long> {
    List<Appeal> findByUserIdOrderByCreatedAtDesc(Long userId);

    Optional<Appeal> findByRecordIdAndUserId(Long recordId, Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from Appeal a where a.appealId = :appealId")
    Optional<Appeal> findForReview(@Param("appealId") Long appealId);

    Page<Appeal> findAllByOrderByCreatedAtDesc(Pageable pageable);

    Page<Appeal> findByStatusIgnoreCaseOrderByCreatedAtDesc(String status, Pageable pageable);
}

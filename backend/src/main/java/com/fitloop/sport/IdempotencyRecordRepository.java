package com.fitloop.sport;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface IdempotencyRecordRepository extends JpaRepository<IdempotencyRecord, Long> {
    Optional<IdempotencyRecord> findByUserIdAndOperationAndIdempotencyKey(
            Long userId, String operation, String idempotencyKey);
}

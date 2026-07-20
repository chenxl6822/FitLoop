package com.fitloop.common;

import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OutboxEventRepository extends JpaRepository<OutboxEvent, Long> {
    List<OutboxEvent> findTop100ByProcessedAtIsNullAndAvailableAtBeforeOrderByIdAsc(Instant now);
    long countByProcessedAtIsNull();
}

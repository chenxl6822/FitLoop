package com.fitloop.agent;

import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AgentRunRepository extends JpaRepository<AgentRun, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from AgentRun r where r.runId = :runId")
    Optional<AgentRun> findForUpdate(@Param("runId") String runId);

    List<AgentRun> findTop100ByStatusAndUpdatedAtBeforeOrderByCreatedAtAsc(AgentRunStatus status, Instant before);
}

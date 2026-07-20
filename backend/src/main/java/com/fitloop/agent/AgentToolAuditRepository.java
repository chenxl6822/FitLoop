package com.fitloop.agent;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AgentToolAuditRepository extends JpaRepository<AgentToolAudit, Long> {
    List<AgentToolAudit> findByRunIdOrderByAuditIdAsc(String runId);
    long countByRunId(String runId);
}

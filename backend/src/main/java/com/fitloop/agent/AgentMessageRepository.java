package com.fitloop.agent;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AgentMessageRepository extends JpaRepository<AgentMessage, Long> {
    List<AgentMessage> findByRunIdOrderByMessageIdAsc(String runId);
}

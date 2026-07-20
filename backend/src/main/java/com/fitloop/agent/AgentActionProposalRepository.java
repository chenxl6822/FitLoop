package com.fitloop.agent;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AgentActionProposalRepository extends JpaRepository<AgentActionProposal, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from AgentActionProposal p where p.proposalId = :proposalId")
    Optional<AgentActionProposal> findForUpdate(@Param("proposalId") Long proposalId);
    List<AgentActionProposal> findByRunIdOrderByProposalIdAsc(String runId);
}

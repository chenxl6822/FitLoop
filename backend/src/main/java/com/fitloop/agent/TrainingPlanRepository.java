package com.fitloop.agent;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TrainingPlanRepository extends JpaRepository<TrainingPlan, Long> {
    boolean existsBySourceProposalId(Long sourceProposalId);
    List<TrainingPlan> findByUserIdOrderByCreatedAtDesc(Long userId);
}

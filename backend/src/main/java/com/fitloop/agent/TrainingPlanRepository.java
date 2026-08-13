package com.fitloop.agent;

import java.util.List;
import java.util.Optional;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.repository.query.Param;

public interface TrainingPlanRepository extends JpaRepository<TrainingPlan, Long> {
    boolean existsBySourceProposalId(Long sourceProposalId);
    List<TrainingPlan> findByUserIdOrderByCreatedAtDesc(Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from TrainingPlan p where p.planId = :planId and p.userId = :userId")
    Optional<TrainingPlan> findForUpdate(@Param("planId") Long planId, @Param("userId") Long userId);
}

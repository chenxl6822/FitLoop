package com.fitloop.target;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SportTargetRepository extends JpaRepository<SportTarget, Long> {
    List<SportTarget> findByUserIdAndStatusAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
            Long userId, String status, LocalDate from, LocalDate to);

    Optional<SportTarget> findByTargetIdAndUserId(Long targetId, Long userId);
}

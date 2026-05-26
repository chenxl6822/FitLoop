package com.fitloop.stats;

import java.time.LocalDate;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface HealthDataRepository extends JpaRepository<HealthData, Long> {
    List<HealthData> findByUserIdAndDataDateBetweenOrderByDataDateAsc(Long userId, LocalDate start, LocalDate end);
}

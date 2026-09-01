package com.fitloop.campus;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CampusScheduleMetaRepository extends JpaRepository<CampusScheduleMeta, Long> {
    Optional<CampusScheduleMeta> findByUserId(Long userId);
}

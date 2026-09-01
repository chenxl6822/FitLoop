package com.fitloop.campus;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CampusScheduleExamRepository extends JpaRepository<CampusScheduleExam, Long> {
    List<CampusScheduleExam> findByUserIdOrderByStartTimeAsc(Long userId);

    void deleteByUserId(Long userId);
}

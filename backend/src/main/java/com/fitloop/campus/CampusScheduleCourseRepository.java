package com.fitloop.campus;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CampusScheduleCourseRepository extends JpaRepository<CampusScheduleCourse, Long> {
    List<CampusScheduleCourse> findByUserIdOrderByDayOfWeekAscStartSectionAsc(Long userId);

    void deleteByUserId(Long userId);
}

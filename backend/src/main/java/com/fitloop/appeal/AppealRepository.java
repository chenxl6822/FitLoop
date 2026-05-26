package com.fitloop.appeal;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AppealRepository extends JpaRepository<Appeal, Long> {
    List<Appeal> findByUserIdOrderByCreatedAtDesc(Long userId);

    Optional<Appeal> findByRecordIdAndUserId(Long recordId, Long userId);
}

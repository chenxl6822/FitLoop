package com.fitloop.campus;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CampusVerificationRepository extends JpaRepository<CampusVerification, Long> {
    Optional<CampusVerification> findByUserId(Long userId);

    Optional<CampusVerification> findByStudentIdHash(String studentIdHash);

    void deleteByUserId(Long userId);
}

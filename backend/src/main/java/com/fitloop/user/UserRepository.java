package com.fitloop.user;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<UserInfo, Long> {
    Optional<UserInfo> findByPhoneOrEmail(String phone, String email);

    boolean existsByPhone(String phone);

    boolean existsByEmail(String email);

    boolean existsByRole(UserRole role);

    List<UserInfo> findByNicknameContainingOrPhoneContaining(String nickname, String phone);

    long countByCreatedAtAfter(Instant after);

    Page<UserInfo> findAllByOrderByCreatedAtDesc(Pageable pageable);
}

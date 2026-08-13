package com.fitloop.user;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface UserRepository extends JpaRepository<UserInfo, Long> {
    Optional<UserInfo> findByPhoneOrEmail(String phone, String email);

    boolean existsByPhone(String phone);

    boolean existsByEmail(String email);

    boolean existsByRole(UserRole role);

    @Query("select u from UserInfo u where u.deletedAt is null and "
            + "(u.nickname like concat(concat('%', :query), '%') "
            + "or u.phone like concat(concat('%', :query), '%'))")
    List<UserInfo> findActiveMatches(@Param("query") String query);

    long countByCreatedAtAfter(Instant after);

    Page<UserInfo> findAllByOrderByCreatedAtDesc(Pageable pageable);

    boolean existsByUserIdAndDeletedAtIsNull(Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from UserInfo u where u.userId = :userId")
    Optional<UserInfo> findForUpdate(@Param("userId") Long userId);
}

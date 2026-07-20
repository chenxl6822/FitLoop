package com.fitloop.security;

import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<RefreshToken> findByTokenHash(String tokenHash);

    @Modifying
    @Query("update RefreshToken t set t.revokedAt = :now, t.revocationReason = :reason "
            + "where t.familyId = :familyId and t.revokedAt is null")
    int revokeFamily(@Param("familyId") String familyId, @Param("now") Instant now,
                     @Param("reason") String reason);

    @Modifying
    @Query("update RefreshToken t set t.revokedAt = :now, t.revocationReason = :reason "
            + "where t.userId = :userId and t.revokedAt is null")
    int revokeUser(@Param("userId") Long userId, @Param("now") Instant now,
                   @Param("reason") String reason);
}

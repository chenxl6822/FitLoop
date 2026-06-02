package com.fitloop.user;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface VerificationCodeRepository extends JpaRepository<VerificationCode, Long> {
    Optional<VerificationCode> findTopByTargetAndChannelAndPurposeAndUsedFalseOrderByCreatedAtDesc(
            String target, String channel, String purpose);

    List<VerificationCode> findByTargetAndChannelAndPurposeAndUsedFalse(
            String target, String channel, String purpose);

    long countByTargetAndChannelAndPurposeAndCreatedAtAfter(
            String target, String channel, String purpose, Instant createdAt);

    long countByRequestIpHashAndCreatedAtAfter(String requestIpHash, Instant createdAt);
}

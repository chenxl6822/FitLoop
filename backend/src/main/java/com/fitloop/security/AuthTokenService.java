package com.fitloop.security;

import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthTokenService {
    private final JwtService jwtService;
    private final RefreshTokenRepository refreshTokens;
    private final UserRepository users;
    private final SecureRandom secureRandom = new SecureRandom();
    private final long refreshTtlSeconds;

    public AuthTokenService(JwtService jwtService, RefreshTokenRepository refreshTokens, UserRepository users,
                            @Value("${fitloop.jwt.refresh-ttl-seconds}") long refreshTtlSeconds) {
        this.jwtService = jwtService;
        this.refreshTokens = refreshTokens;
        this.users = users;
        this.refreshTtlSeconds = refreshTtlSeconds;
    }

    @Transactional
    public TokenPair issue(UserInfo user) {
        return create(user, UUID.randomUUID().toString());
    }

    @Transactional(noRollbackFor = IllegalArgumentException.class)
    public RotatedToken rotate(String rawToken) {
        String tokenHash = hash(rawToken);
        RefreshToken current = refreshTokens.findByTokenHash(tokenHash)
                .orElseThrow(() -> new IllegalArgumentException("刷新令牌无效"));
        Instant now = Instant.now();
        if (current.getRevokedAt() != null) {
            refreshTokens.revokeFamily(current.getFamilyId(), now, "REPLAY_DETECTED");
            throw new IllegalArgumentException("检测到刷新令牌重放，请重新登录");
        }
        if (!current.getExpiresAt().isAfter(now)) {
            current.setRevokedAt(now);
            current.setRevocationReason("EXPIRED");
            throw new IllegalArgumentException("刷新令牌已过期");
        }
        UserInfo user = users.findById(current.getUserId())
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        TokenPair replacement = create(user, current.getFamilyId());
        current.setRevokedAt(now);
        current.setRevocationReason("ROTATED");
        current.setReplacedByHash(hash(replacement.refreshToken()));
        return new RotatedToken(replacement, user);
    }

    @Transactional
    public void revoke(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) {
            return;
        }
        refreshTokens.findByTokenHash(hash(rawToken)).ifPresent(token -> {
            if (token.getRevokedAt() == null) {
                token.setRevokedAt(Instant.now());
                token.setRevocationReason("LOGOUT");
            }
        });
    }

    @Transactional
    public void revokeAll(Long userId, String reason) {
        refreshTokens.revokeUser(userId, Instant.now(), reason);
    }

    private TokenPair create(UserInfo user, String familyId) {
        byte[] bytes = new byte[32];
        secureRandom.nextBytes(bytes);
        String raw = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant now = Instant.now();
        RefreshToken refresh = new RefreshToken();
        refresh.setUserId(user.getUserId());
        refresh.setTokenHash(hash(raw));
        refresh.setFamilyId(familyId);
        refresh.setIssuedAt(now);
        refresh.setExpiresAt(now.plusSeconds(refreshTtlSeconds));
        refreshTokens.save(refresh);
        return new TokenPair(jwtService.issue(user.getUserId(), user.getRole()), raw,
                jwtService.ttlSeconds());
    }

    private String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to hash refresh token", ex);
        }
    }

    public record TokenPair(String accessToken, String refreshToken, long expiresIn) { }
    public record RotatedToken(TokenPair tokenPair, UserInfo user) { }
}

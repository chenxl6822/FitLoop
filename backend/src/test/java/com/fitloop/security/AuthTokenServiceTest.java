package com.fitloop.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import com.fitloop.user.UserRole;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class AuthTokenServiceTest {
    @Mock RefreshTokenRepository refreshTokens;
    @Mock UserRepository users;

    private JwtService jwt;
    private AuthTokenService service;

    @BeforeEach
    void setUp() {
        jwt = new JwtService("0123456789abcdef0123456789abcdef", 900);
        service = new AuthTokenService(jwt, refreshTokens, users, 3600);
    }

    @Test
    void issuePersistsHashedRefreshTokenAndReturnsAccessToken() {
        UserInfo user = user(7L);

        var pair = service.issue(user);

        assertThat(jwt.verify(pair.accessToken())).isEqualTo(7L);
        assertThat(pair.refreshToken()).doesNotContain("=");
        assertThat(pair.expiresIn()).isEqualTo(900);
        ArgumentCaptor<RefreshToken> saved = ArgumentCaptor.forClass(RefreshToken.class);
        verify(refreshTokens).save(saved.capture());
        assertThat(saved.getValue().getTokenHash()).hasSize(64).doesNotContain(pair.refreshToken());
        assertThat(saved.getValue().getExpiresAt()).isAfter(saved.getValue().getIssuedAt());
    }

    @Test
    void rotateRevokesCurrentTokenAndKeepsFamily() {
        RefreshToken current = token(7L, Instant.now().plusSeconds(60));
        when(refreshTokens.findByTokenHash(anyString())).thenReturn(Optional.of(current));
        when(users.findById(7L)).thenReturn(Optional.of(user(7L)));

        var rotated = service.rotate("raw-refresh-token");

        assertThat(rotated.user().getUserId()).isEqualTo(7L);
        assertThat(current.getRevocationReason()).isEqualTo("ROTATED");
        assertThat(current.getRevokedAt()).isNotNull();
        assertThat(current.getReplacedByHash()).hasSize(64);
        ArgumentCaptor<RefreshToken> saved = ArgumentCaptor.forClass(RefreshToken.class);
        verify(refreshTokens).save(saved.capture());
        assertThat(saved.getValue().getFamilyId()).isEqualTo("family-1");
    }

    @Test
    void replayRevokesWholeFamily() {
        RefreshToken current = token(7L, Instant.now().plusSeconds(60));
        current.setRevokedAt(Instant.now());
        when(refreshTokens.findByTokenHash(anyString())).thenReturn(Optional.of(current));

        assertThatThrownBy(() -> service.rotate("replayed"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("重放");
        verify(refreshTokens).revokeFamily(anyString(), any(Instant.class), anyString());
        verify(users, never()).findById(any());
    }

    @Test
    void expiredTokenIsMarkedAndRejected() {
        RefreshToken current = token(7L, Instant.now().minusSeconds(1));
        when(refreshTokens.findByTokenHash(anyString())).thenReturn(Optional.of(current));

        assertThatThrownBy(() -> service.rotate("expired"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("过期");
        assertThat(current.getRevocationReason()).isEqualTo("EXPIRED");
    }

    @Test
    void rotateRejectsUnknownTokenAndDeletedUser() {
        when(refreshTokens.findByTokenHash(anyString()))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(token(7L, Instant.now().plusSeconds(60))));
        when(users.findById(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.rotate("unknown")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.rotate("deleted-user")).isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void revokeIsNullSafeIdempotentAndSupportsAllSessions() {
        service.revoke(null);
        service.revoke(" ");
        verify(refreshTokens, never()).findByTokenHash(anyString());

        RefreshToken active = token(7L, Instant.now().plusSeconds(60));
        when(refreshTokens.findByTokenHash(anyString())).thenReturn(Optional.of(active));
        service.revoke("active");
        assertThat(active.getRevocationReason()).isEqualTo("LOGOUT");

        RefreshToken revoked = token(7L, Instant.now().plusSeconds(60));
        revoked.setRevokedAt(Instant.now());
        when(refreshTokens.findByTokenHash(anyString())).thenReturn(Optional.of(revoked));
        service.revoke("already-revoked");
        assertThat(revoked.getRevocationReason()).isNull();

        service.revokeAll(7L, "PASSWORD_CHANGED");
        verify(refreshTokens).revokeUser(any(), any(Instant.class), anyString());
    }

    private UserInfo user(Long id) {
        UserInfo user = new UserInfo();
        user.setPasswordHash("hash");
        user.setRole(UserRole.USER);
        try {
            var field = UserInfo.class.getDeclaredField("userId");
            field.setAccessible(true);
            field.set(user, id);
            return user;
        } catch (ReflectiveOperationException ex) {
            throw new AssertionError(ex);
        }
    }

    private RefreshToken token(Long userId, Instant expiresAt) {
        RefreshToken token = new RefreshToken();
        token.setUserId(userId);
        token.setFamilyId("family-1");
        token.setIssuedAt(Instant.now().minusSeconds(10));
        token.setExpiresAt(expiresAt);
        token.setTokenHash("a".repeat(64));
        return token;
    }
}

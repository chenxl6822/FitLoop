package com.fitloop.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.user.UserRole;
import org.junit.jupiter.api.Test;

class JwtServiceTest {
    private final JwtService jwt = new JwtService("0123456789abcdef0123456789abcdef", 3600);

    @Test
    void issuesStandardThreePartJwtWithRole() {
        String token = jwt.issue(42L, UserRole.ADMIN);

        assertThat(token.split("\\.")).hasSize(3);
        JwtService.VerifiedToken verified = jwt.verifyClaims(token);
        assertThat(verified.userId()).isEqualTo(42L);
        assertThat(verified.role()).isEqualTo(UserRole.ADMIN);
        assertThat(verified.jti()).isNotBlank();
    }

    @Test
    void rejectsTamperedJwt() {
        String token = jwt.issue(42L, UserRole.USER);

        assertThatThrownBy(() -> jwt.verify(token + "x"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}

package com.fitloop.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class ProductionSecretsTest {

    @Test
    void rejectsMissingPlaceholderAndShortSecrets() {
        assertThatThrownBy(() -> ProductionSecrets.requireSecret("fitloop.jwt.secret", null, 32))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("must be configured");
        assertThatThrownBy(() -> ProductionSecrets.requireSecret(
                        "fitloop.jwt.secret",
                        "change-me-to-a-long-random-secret-for-production",
                        32))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("placeholder");
        assertThatThrownBy(() -> ProductionSecrets.requireSecret(
                        "fitloop.agent.service-key",
                        "replace-with-a-random-agent-service-key",
                        32))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("placeholder");
        assertThatThrownBy(() -> ProductionSecrets.requireSecret("fitloop.jwt.secret", "too-short", 32))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("at least 32 bytes");
    }

    @Test
    void acceptsConfiguredSecrets() {
        byte[] secret = ProductionSecrets.requireSecret(
                "fitloop.jwt.secret",
                "configured-production-secret-value-32b",
                32);
        assertThat(secret).hasSizeGreaterThanOrEqualTo(32);
    }
}

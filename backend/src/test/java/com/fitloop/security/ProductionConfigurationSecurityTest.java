package com.fitloop.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.assertj.core.api.SoftAssertions;
import org.junit.jupiter.api.Test;

class ProductionConfigurationSecurityTest {

    @Test
    void authenticationAndAgentSecretsMustNotHaveKnownUsableFallbacks() throws IOException {
        String application = Files.readString(Path.of("src/main/resources/application.yml"));
        String compose = Files.readString(Path.of("../deploy/docker-compose.yml"));

        SoftAssertions.assertSoftly(softly -> {
            softly.assertThat(application)
                    .as("application.yml must fail closed when the JWT secret is absent")
                    .doesNotContain("${FITLOOP_JWT_SECRET:change-me-to-a-long-random-secret-for-production}")
                    .contains("secret: ${FITLOOP_JWT_SECRET}");
            softly.assertThat(application)
                    .as("application.yml must fail closed when the Agent service key is absent")
                    .doesNotContain("${FITLOOP_AGENT_SERVICE_KEY:change-me-agent-service-key-32-bytes}")
                    .contains("service-key: ${FITLOOP_AGENT_SERVICE_KEY}");
            softly.assertThat(compose)
                    .as("the production Compose path must require an externally supplied JWT secret")
                    .doesNotContain("${FITLOOP_JWT_SECRET:-replace-with-a-long-random-production-secret}")
                    .contains("${FITLOOP_JWT_SECRET:?");
            softly.assertThat(compose)
                    .as("the production Compose path must require independent Agent credentials")
                    .doesNotContain("${FITLOOP_AGENT_SERVICE_KEY:-replace-with-a-random-agent-service-key}")
                    .doesNotContain("${FITLOOP_AGENT_DELEGATION_SECRET:-replace-with-a-random-agent-delegation-secret}")
                    .contains("${FITLOOP_AGENT_SERVICE_KEY:?")
                    .contains("${FITLOOP_AGENT_DELEGATION_SECRET:?");
            softly.assertThat(compose)
                    .as("OTP hash secret must also be required without a usable default")
                    .doesNotContain("${FITLOOP_OTP_HASH_SECRET:-replace-with-a-long-random-otp-hash-secret}")
                    .contains("${FITLOOP_OTP_HASH_SECRET:?");
        });
    }

    @Test
    void httpsOnlyDeploymentMustNotPublishTheRawBackendOnAllInterfaces() throws IOException {
        String compose = Files.readString(Path.of("../deploy/docker-compose.yml"));

        assertThat(compose)
                .as("the raw Spring API must remain on the private Compose network")
                .doesNotContain("- \"${SERVER_PORT:-8080}:8080\"")
                .contains("- \"127.0.0.1:${SERVER_PORT:-8080}:8080\"");
    }
}

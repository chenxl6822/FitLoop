package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.user.UserDtos.LoginRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mysql.MySQLContainer;
import org.testcontainers.utility.DockerImageName;

@Testcontainers(disabledWithoutDocker = true)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@ActiveProfiles("test")
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {
                "spring.flyway.enabled=true",
                "spring.jpa.hibernate.ddl-auto=validate",
                "spring.jpa.open-in-view=false",
                "spring.mail.host=localhost",
                "management.health.mail.enabled=false",
                "fitloop.admin.bootstrap-account=",
                "fitloop.verification.debug-return=true",
                "fitloop.agent.service-key=test-agent-service-key-32-bytes-ok",
                "fitloop.agent.delegation-secret=test-agent-delegation-secret-32-bytes"
        })
class VerificationCodeRollbackIT {

    @Container
    private static final MySQLContainer MYSQL = new MySQLContainer("mysql:8.0.43")
            .withDatabaseName("fitloop")
            .withUsername("fitloop")
            .withPassword("fitloop-test");

    @Container
    private static final GenericContainer<?> REDIS = new GenericContainer<>(
            DockerImageName.parse("redis:6.2.19-alpine"))
            .withExposedPorts(6379);

    @DynamicPropertySource
    static void infrastructureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "com.mysql.cj.jdbc.Driver");
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @Test
    void wrongLoginCodesMustDurablyConsumeTheAttemptBudget(
            @Autowired UserService usersService,
            @Autowired UserRepository users,
            @Autowired VerificationCodeService verificationCodes,
            @Autowired VerificationCodeRepository codeRepository) {
        String phone = "13900009001";
        UserInfo user = new UserInfo();
        user.setPhone(phone);
        user.setPasswordHash("synthetic-unused-password-hash");
        user.setNickname("Synthetic OTP user");
        user.setRole(UserRole.USER);
        users.saveAndFlush(user);

        String validCode = verificationCodes.sendCode("phone", phone, "login", null).debugCode();
        assertThat(validCode).isNotBlank();

        for (int attempt = 0; attempt < 5; attempt += 1) {
            assertThatThrownBy(() -> usersService.login(
                    new LoginRequest(phone, null, "999999", "code")))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("验证码错误或已过期");
        }

        VerificationCode stored = codeRepository
                .findTopByTargetAndChannelAndPurposeOrderByCreatedAtDesc(
                        phone, VerificationCodeService.CHANNEL_PHONE, VerificationCodeService.PURPOSE_LOGIN)
                .orElseThrow();
        assertThat(stored.getAttemptCount())
                .as("failed guesses must survive the outer login transaction rollback")
                .isEqualTo(5);
        assertThat(stored.isUsed()).isTrue();
        assertThatThrownBy(() -> usersService.login(
                new LoginRequest(phone, null, validCode, "code")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("验证码错误或已过期");
    }
}

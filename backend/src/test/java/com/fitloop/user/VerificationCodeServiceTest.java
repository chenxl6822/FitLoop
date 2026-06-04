package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.security.SecureRandom;
import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

@DataJpaTest
@ActiveProfiles("test")
@TestPropertySource(properties = "fitloop.verification.debug-return=true")
@Import({
        VerificationCodeService.class,
        PhoneVerificationCodeSender.class,
        VerificationCodeServiceTest.EmailSenderConfig.class
})
class VerificationCodeServiceTest {
    @Autowired
    private VerificationCodeService verificationCodes;

    @Autowired
    private VerificationCodeRepository repository;

    @Autowired
    private RecordingEmailSender emailSender;

    @Test
    void sendsEmailCodeAndStoresOnlyHash() {
        VerificationCodeSendResult result = verificationCodes.sendCode(
                "email", "USER@example.com", "register", "127.0.0.1");

        assertThat(result.debugCode()).hasSize(6);
        assertThat(emailSender.sent).hasSize(1);
        assertThat(emailSender.sent.get(0).target()).isEqualTo("user@example.com");
        assertThat(repository.findAll()).hasSize(1);
        VerificationCode stored = repository.findAll().get(0);
        assertThat(stored.getCodeHash()).isNotEqualTo(result.debugCode());
        assertThat(stored.getRequestIpHash()).isNotBlank();
    }

    @Test
    void verifiesCodeOnceOnly() {
        String code = verificationCodes.sendCode("phone", "13800000001", "login", null).debugCode();

        assertThat(verificationCodes.verifyCode("phone", "13800000001", "login", code)).isTrue();
        assertThat(verificationCodes.verifyCode("phone", "13800000001", "login", code)).isFalse();
    }

    @Test
    void rejectsAfterFiveWrongAttempts() {
        String code = verificationCodes.sendCode("phone", "13800000002", "login", null).debugCode();

        for (int i = 0; i < 5; i += 1) {
            assertThat(verificationCodes.verifyCode("phone", "13800000002", "login", "000000")).isFalse();
        }

        assertThat(verificationCodes.verifyCode("phone", "13800000002", "login", code)).isFalse();
    }

    @Test
    void rateLimitsRapidResend() {
        verificationCodes.sendCode("phone", "13800000003", "login", null);

        assertThatThrownBy(() -> verificationCodes.sendCode("phone", "13800000003", "login", null))
                .hasMessageContaining("过于频繁");
    }

    @Test
    void rejectsInvalidChannelAndTarget() {
        assertThatThrownBy(() -> verificationCodes.sendCode("fax", "13800000003", "login", null))
                .hasMessageContaining("渠道");
        assertThatThrownBy(() -> verificationCodes.sendCode("email", "bad-email", "login", null))
                .hasMessageContaining("邮箱");
    }

    @Test
    void rejectsPhoneWhenSmsDisabledAndNotDebug() {
        // 构造一个 smsEnabled=false 且 debugReturnEnabled=false 的 service
        var env = new MockEnvironment();
        env.setActiveProfiles("production");
        var service = new VerificationCodeService(
                repository,
                List.of(new PhoneVerificationCodeSender()),
                env,
                new SecureRandom(),
                Clock.systemUTC(),
                "test-hash-secret",
                false,  // debugReturnEnabled = false
                false   // smsEnabled = false
        );
        assertThatThrownBy(() -> service.sendCode("phone", "13800000004", "login", null))
                .hasMessageContaining("手机短信通道暂未开放");
    }

    @Test
    void phoneWorksWhenSmsEnabledAndNotDebug() {
        var env = new MockEnvironment();
        env.setActiveProfiles("production");
        var service = new VerificationCodeService(
                repository,
                List.of(new PhoneVerificationCodeSender()),
                env,
                new SecureRandom(),
                Clock.systemUTC(),
                "test-hash-secret",
                false,  // debugReturnEnabled = false
                true    // smsEnabled = true
        );
        // smsEnabled=true 时不抛异常（sender 是 stub，但不会抛异常）
        var result = service.sendCode("phone", "13800000005", "login", null);
        assertThat(result.debugCode()).isNull();  // 非 debug 模式不返回 code
        assertThat(result.message()).contains("已发送");
    }

    @TestConfiguration
    static class EmailSenderConfig {
        @Bean
        RecordingEmailSender recordingEmailSender() {
            return new RecordingEmailSender();
        }
    }

    static class RecordingEmailSender implements VerificationCodeSender {
        final List<SentCode> sent = new ArrayList<>();

        @Override
        public String channel() {
            return VerificationCodeService.CHANNEL_EMAIL;
        }

        @Override
        public void send(String target, String code, String purpose) {
            sent.add(new SentCode(target, code, purpose));
        }
    }

    record SentCode(String target, String code, String purpose) {
    }
}

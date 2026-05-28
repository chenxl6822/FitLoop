package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import(SmsService.class)
class SmsServiceTest {

    @Autowired
    private SmsService smsService;

    @Test
    void sendCodeGenerates6Digits() {
        String code = smsService.sendCode("13800000001");

        assertThat(code).hasSize(6);
        assertThat(code).containsPattern("^[0-9]{6}$");
    }

    @Test
    void sendCodeRejectsInvalidPhone() {
        assertThatThrownBy(() -> smsService.sendCode("12345"))
                .hasMessageContaining("手机号格式不正确");
    }

    @Test
    void verifyValidCode() {
        String code = smsService.sendCode("13800000002");

        boolean result = smsService.verifyCode("13800000002", code);

        assertThat(result).isTrue();
    }

    @Test
    void verifyRejectsWrongCode() {
        smsService.sendCode("13800000003");

        boolean result = smsService.verifyCode("13800000003", "000000");

        assertThat(result).isFalse();
    }

    @Test
    void verifyRejectsUsedCode() {
        String code = smsService.sendCode("13800000004");
        smsService.verifyCode("13800000004", code);

        boolean result = smsService.verifyCode("13800000004", code);

        assertThat(result).isFalse();
    }

    @Test
    void verifyRejectsWrongPhone() {
        String code = smsService.sendCode("13800000005");

        boolean result = smsService.verifyCode("13800000006", code);

        assertThat(result).isFalse();
    }
}

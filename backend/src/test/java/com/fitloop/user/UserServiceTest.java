package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.security.JwtService;
import com.fitloop.security.AuthTokenService;
import com.fitloop.user.UserDtos.LoginRequest;
import com.fitloop.user.UserDtos.RegisterRequest;
import com.fitloop.user.UserDtos.UpdateProfileRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

@DataJpaTest
@ActiveProfiles("test")
@TestPropertySource(properties = "fitloop.verification.debug-return=true")
@Import({
        UserService.class,
        SmsService.class,
        VerificationCodeService.class,
        PhoneVerificationCodeSender.class,
        UserServiceTest.EmailSenderConfig.class,
        UserServiceTest.PasswordEncoderConfig.class,
        JwtService.class,
        AuthTokenService.class
})
class UserServiceTest {

    @TestConfiguration
    static class PasswordEncoderConfig {
        @Bean
        PasswordEncoder passwordEncoder() {
            return new BCryptPasswordEncoder();
        }
    }

    @TestConfiguration
    static class EmailSenderConfig {
        @Bean
        VerificationCodeSender emailVerificationCodeSender() {
            return new VerificationCodeSender() {
                @Override
                public String channel() {
                    return VerificationCodeService.CHANNEL_EMAIL;
                }

                @Override
                public void send(String target, String code, String purpose) {
                }
            };
        }
    }

    @Autowired
    private UserService userService;

    @Autowired
    private UserRepository users;

    @Autowired
    private SmsService smsService;

    @Autowired
    private VerificationCodeService verificationCodes;

    private UserDtos.UserProfile registerWithCode(String phone, String password, String nickname) {
        String code = smsService.sendCode(phone);
        return userService.register(new RegisterRequest(phone, null, password, code, nickname));
    }

    @Test
    void registerCreatesUser() {
        var profile = registerWithCode("13800000001", "pass1234", "TestUser");

        assertThat(profile.userId()).isNotNull();
        assertThat(profile.phone()).isEqualTo("13800000001");
        assertThat(profile.nickname()).isEqualTo("TestUser");
        assertThat(profile.points()).isZero();
        assertThat(profile.level()).isEqualTo(1);
    }

    @Test
    void registerDefaultsNicknameWhenNotProvided() {
        var profile = registerWithCode("13800000002", "pass1234", null);

        assertThat(profile.nickname()).isEqualTo("FitLoop 用户");
    }

    @Test
    void registerRejectsDuplicatePhone() {
        registerWithCode("13800000003", "pass1234", "A");

        assertThatThrownBy(() -> userService.register(
                new RegisterRequest("13800000003", null, "pass1234", null, "B")))
                .hasMessageContaining("已注册");
    }

    @Test
    void registerRejectsEmptyPhoneAndEmail() {
        assertThatThrownBy(() -> userService.register(
                new RegisterRequest(null, null, "pass1234", null, "C")))
                .hasMessageContaining("至少填写一项");
    }

    @Test
    void registerRejectsMissingPhoneCode() {
        assertThatThrownBy(() -> userService.register(
                new RegisterRequest("13800000008", null, "pass1234", null, "NoCode")))
                .hasMessageContaining("验证码");
    }

    @Test
    void loginWithCorrectPasswordReturnsToken() {
        registerWithCode("13800000004", "correct", "User4");

        var result = userService.login(
                new LoginRequest("13800000004", "correct", null, "password"));

        assertThat(result.token()).isNotNull().isNotEmpty();
        assertThat(result.refreshToken()).isNotBlank();
        assertThat(result.tokenType()).isEqualTo("Bearer");
        assertThat(result.userProfile().nickname()).isEqualTo("User4");
        assertThat(result.role()).isEqualTo(UserRole.USER);
    }

    @Test
    void refreshTokenRotatesAndOldTokenCannotBeReused() {
        registerWithCode("13800000014", "correct", "RotateUser");
        var login = userService.login(
                new LoginRequest("13800000014", "correct", null, "password"));

        var refreshed = userService.refresh(login.refreshToken());

        assertThat(refreshed.token()).isNotBlank().isNotEqualTo(login.token());
        assertThat(refreshed.refreshToken()).isNotBlank().isNotEqualTo(login.refreshToken());
        assertThatThrownBy(() -> userService.refresh(login.refreshToken()))
                .hasMessageContaining("重放");
    }

    @Test
    void loginRejectsWrongPassword() {
        registerWithCode("13800000005", "correct", "User5");

        assertThatThrownBy(() -> userService.login(
                new LoginRequest("13800000005", "wrong", null, "password")))
                .hasMessageContaining("账号或密码错误");
    }

    @Test
    void loginRejectsUnknownAccount() {
        assertThatThrownBy(() -> userService.login(
                new LoginRequest("13899999999", "p", null, "password")))
                .hasMessageContaining("账号或密码错误");
    }

    @Test
    void updateProfileChangesNickname() {
        var created = registerWithCode("13800000006", "pass1234", "OldName");

        var updated = userService.updateProfile(created.userId(),
                new UpdateProfileRequest("NewName", null, null, null, null));

        assertThat(updated.nickname()).isEqualTo("NewName");
    }

    @Test
    void updateProfileDoesNotChangeUnspecifiedFields() {
        var created = registerWithCode("13800000007", "pass1234", "KeepName");

        var updated = userService.updateProfile(created.userId(),
                new UpdateProfileRequest(null, "https://example.com/avatar.png", "男", "2023级", "计算机学院"));

        assertThat(updated.nickname()).isEqualTo("KeepName");
        assertThat(updated.avatarUrl()).isEqualTo("https://example.com/avatar.png");
        assertThat(updated.gender()).isEqualTo("男");
        assertThat(updated.grade()).isEqualTo("2023级");
        assertThat(updated.college()).isEqualTo("计算机学院");
    }

    @Test
    void updateProfileRejectsUnknownUser() {
        assertThatThrownBy(() -> userService.updateProfile(9999L,
                new UpdateProfileRequest("X", null, null, null, null)))
                .hasMessageContaining("不存在");
    }

    @Test
    void loginWithValidCodeSucceeds() {
        registerWithCode("13800000010", "pass1234", "CodeUser");
        String code = verificationCodes.sendCode("phone", "13800000010", "login", null).debugCode();

        var result = userService.login(
                new LoginRequest("13800000010", null, code, "code"));

        assertThat(result.token()).isNotNull().isNotEmpty();
        assertThat(result.userProfile().nickname()).isEqualTo("CodeUser");
    }

    @Test
    void loginWithWrongCodeRejected() {
        registerWithCode("13800000011", "pass1234", "CodeUser2");
        verificationCodes.sendCode("phone", "13800000011", "login", null);

        assertThatThrownBy(() -> userService.login(
                new LoginRequest("13800000011", null, "000000", "code")))
                .hasMessageContaining("验证码错误或已过期");
    }

    @Test
    void loginWithExpiredCodeRejected() {
        registerWithCode("13800000012", "pass1234", "CodeUser3");
        String code = verificationCodes.sendCode("phone", "13800000012", "login", null).debugCode();
        verificationCodes.verifyCode("phone", "13800000012", "login", code);

        assertThatThrownBy(() -> userService.login(
                new LoginRequest("13800000012", null, code, "code")))
                .hasMessageContaining("验证码错误或已过期");
    }

    @Test
    void resetPasswordWithValidCodeChangesPassword() {
        registerWithCode("13800000013", "oldpass", "ResetUser");
        String code = verificationCodes.sendCode("phone", "13800000013", "reset_password", null).debugCode();

        userService.resetPassword(new UserDtos.PasswordResetRequest("13800000013", code, "newpass"));

        var result = userService.login(new LoginRequest("13800000013", "newpass", null, "password"));
        assertThat(result.token()).isNotBlank();
    }

    @Test
    void emailRegisterAndCodeLoginSucceed() {
        String email = "Student@Example.com";
        String registerCode = verificationCodes.sendCode("email", email, "register", null).debugCode();
        var profile = userService.register(new RegisterRequest(null, email, "pass1234", registerCode, "EmailUser"));

        assertThat(profile.email()).isEqualTo("student@example.com");

        String loginCode = verificationCodes.sendCode("email", "student@example.com", "login", null).debugCode();
        var result = userService.login(new LoginRequest("student@example.com", null, loginCode, "code"));

        assertThat(result.userProfile().nickname()).isEqualTo("EmailUser");
    }

    @Test
    void administratorMustUsePasswordAndReceivesAdminRole() {
        var created = registerWithCode("13800000015", "admin-pass", "AdminUser");
        UserInfo admin = users.findById(created.userId()).orElseThrow();
        admin.setRole(UserRole.ADMIN);
        users.saveAndFlush(admin);
        String code = verificationCodes.sendCode("phone", "13800000015", "login", null).debugCode();

        assertThatThrownBy(() -> userService.login(
                new LoginRequest("13800000015", null, code, "code")))
                .hasMessageContaining("密码登录");

        var result = userService.login(
                new LoginRequest("13800000015", "admin-pass", null, "password"));
        assertThat(result.role()).isEqualTo(UserRole.ADMIN);
    }
}

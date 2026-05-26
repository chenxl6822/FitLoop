package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.security.JwtService;
import com.fitloop.user.UserDtos.LoginRequest;
import com.fitloop.user.UserDtos.RegisterRequest;
import com.fitloop.user.UserDtos.UpdateProfileRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@DataJpaTest
@Import({UserService.class, JwtService.class, UserServiceTest.PasswordEncoderConfig.class})
class UserServiceTest {

    @TestConfiguration
    static class PasswordEncoderConfig {
        @Bean
        PasswordEncoder passwordEncoder() {
            return new BCryptPasswordEncoder();
        }
    }

    @Autowired
    private UserService userService;

    @Test
    void registerCreatesUser() {
        var profile = userService.register(
                new RegisterRequest("13800000001", null, "pass1234", null, "TestUser"));

        assertThat(profile.userId()).isNotNull();
        assertThat(profile.phone()).isEqualTo("13800000001");
        assertThat(profile.nickname()).isEqualTo("TestUser");
        assertThat(profile.points()).isZero();
        assertThat(profile.level()).isEqualTo(1);
    }

    @Test
    void registerDefaultsNicknameWhenNotProvided() {
        var profile = userService.register(
                new RegisterRequest("13800000002", null, "pass1234", null, null));

        assertThat(profile.nickname()).isEqualTo("FitLoop 用户");
    }

    @Test
    void registerRejectsDuplicatePhone() {
        userService.register(new RegisterRequest("13800000003", null, "pass1234", null, "A"));

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
    void loginWithCorrectPasswordReturnsToken() {
        userService.register(
                new RegisterRequest("13800000004", null, "correct", null, "User4"));

        var result = userService.login(
                new LoginRequest("13800000004", "correct", null, "password"));

        assertThat(result.token()).isNotNull().isNotEmpty();
        assertThat(result.userProfile().nickname()).isEqualTo("User4");
    }

    @Test
    void loginRejectsWrongPassword() {
        userService.register(
                new RegisterRequest("13800000005", null, "correct", null, "User5"));

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
        var created = userService.register(
                new RegisterRequest("13800000006", null, "pass1234", null, "OldName"));

        var updated = userService.updateProfile(created.userId(),
                new UpdateProfileRequest("NewName", null, null, null, null));

        assertThat(updated.nickname()).isEqualTo("NewName");
    }

    @Test
    void updateProfileDoesNotChangeUnspecifiedFields() {
        var created = userService.register(
                new RegisterRequest("13800000007", null, "pass1234", null, "KeepName"));

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
}

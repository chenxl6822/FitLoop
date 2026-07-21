package com.fitloop.user;

import com.fitloop.security.AuthTokenService;
import com.fitloop.user.UserDtos.LoginRequest;
import com.fitloop.user.UserDtos.LoginResponse;
import com.fitloop.user.UserDtos.PasswordResetRequest;
import com.fitloop.user.UserDtos.RegisterRequest;
import com.fitloop.user.UserDtos.UpdateProfileRequest;
import com.fitloop.user.UserDtos.UserProfile;
import java.util.Locale;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class UserService {
    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final AuthTokenService authTokens;
    private final VerificationCodeService verificationCodes;

    public UserService(UserRepository users, PasswordEncoder passwordEncoder, AuthTokenService authTokens,
                       VerificationCodeService verificationCodes) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.authTokens = authTokens;
        this.verificationCodes = verificationCodes;
    }

    @Transactional
    public UserProfile register(RegisterRequest request) {
        String phone = normalizePhone(request.phone());
        String email = normalizeEmail(request.email());
        if (!StringUtils.hasText(phone) && !StringUtils.hasText(email)) {
            throw new IllegalArgumentException("手机号和邮箱至少填写一项");
        }
        if (StringUtils.hasText(phone) && StringUtils.hasText(email)) {
            throw new IllegalArgumentException("手机号和邮箱只能填写一项");
        }
        if (StringUtils.hasText(phone) && users.existsByPhone(phone)) {
            throw new IllegalArgumentException("手机号已注册");
        }
        if (StringUtils.hasText(email) && users.existsByEmail(email)) {
            throw new IllegalArgumentException("邮箱已注册");
        }
        if (StringUtils.hasText(phone) && !verificationCodes.verifyCode(
                VerificationCodeService.CHANNEL_PHONE, phone,
                VerificationCodeService.PURPOSE_REGISTER, request.code())) {
            throw new IllegalArgumentException("验证码错误或已过期");
        }
        if (StringUtils.hasText(email) && !verificationCodes.verifyCode(
                VerificationCodeService.CHANNEL_EMAIL, email,
                VerificationCodeService.PURPOSE_REGISTER, request.code())) {
            throw new IllegalArgumentException("验证码错误或已过期");
        }
        UserInfo user = new UserInfo();
        user.setPhone(phone);
        user.setEmail(email);
        user.setNickname(StringUtils.hasText(request.nickname()) ? request.nickname() : "FitLoop 用户");
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        return UserProfile.from(users.save(user));
    }

    @Transactional
    public LoginResponse login(LoginRequest request) {
        String account = normalizeAccount(request.account());
        UserInfo user = users.findByPhoneOrEmail(account, account)
                .orElseThrow(() -> new IllegalArgumentException("账号或密码错误"));
        boolean codeLogin = "code".equalsIgnoreCase(request.loginType());
        if (user.getRole() == UserRole.ADMIN && codeLogin) {
            throw new IllegalArgumentException("管理员账号必须使用密码登录");
        }
        if (codeLogin) {
            String channel = verificationCodes.inferChannel(account);
            if (!verificationCodes.verifyCode(channel, account,
                    VerificationCodeService.PURPOSE_LOGIN, request.code())) {
                throw new IllegalArgumentException("验证码错误或已过期");
            }
        } else if (!StringUtils.hasText(request.password())
                || !passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new IllegalArgumentException("账号或密码错误");
        }
        return response(authTokens.issue(user), user);
    }

    @Transactional
    public LoginResponse refresh(String refreshToken) {
        AuthTokenService.RotatedToken rotated = authTokens.rotate(refreshToken);
        return response(rotated.tokenPair(), rotated.user());
    }

    @Transactional
    public void logout(String refreshToken) {
        authTokens.revoke(refreshToken);
    }

    @Transactional
    public void resetPassword(PasswordResetRequest request) {
        String account = normalizeAccount(request.account());
        String channel = verificationCodes.inferChannel(account);
        UserInfo user = users.findByPhoneOrEmail(account, account)
                .orElseThrow(() -> new IllegalArgumentException("账号不存在"));
        if (!verificationCodes.verifyCode(channel, account,
                VerificationCodeService.PURPOSE_RESET_PASSWORD, request.code())) {
            throw new IllegalArgumentException("验证码错误或已过期");
        }
        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        authTokens.revokeAll(user.getUserId(), "PASSWORD_CHANGED");
    }

    private String normalizeAccount(String value) {
        return value != null && value.contains("@") ? normalizeEmail(value) : normalizePhone(value);
    }

    private String normalizeEmail(String value) {
        return StringUtils.hasText(value) ? value.trim().toLowerCase(Locale.ROOT) : value;
    }

    private String normalizePhone(String value) {
        return StringUtils.hasText(value) ? value.trim() : value;
    }

    @Transactional
    public UserProfile updateProfile(Long userId, UpdateProfileRequest request) {
        UserInfo user = users.findById(userId).orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        if (StringUtils.hasText(request.nickname())) user.setNickname(request.nickname());
        if (StringUtils.hasText(request.avatarUrl())) user.setAvatarUrl(request.avatarUrl());
        if (StringUtils.hasText(request.gender())) user.setGender(request.gender());
        if (StringUtils.hasText(request.grade())) user.setGrade(request.grade());
        if (StringUtils.hasText(request.college())) user.setCollege(request.college());
        return UserProfile.from(user);
    }

    @Transactional
    public void updateAvatar(Long userId, String avatarUrl) {
        UserInfo user = users.findById(userId).orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        user.setAvatarUrl(avatarUrl);
    }

    @Transactional(readOnly = true)
    public UserProfile getProfile(Long userId) {
        UserInfo user = users.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        return UserProfile.from(user);
    }

    private LoginResponse response(AuthTokenService.TokenPair pair, UserInfo user) {
        return new LoginResponse(pair.accessToken(), pair.refreshToken(), "Bearer", pair.expiresIn(),
                UserProfile.from(user), user.getRole());
    }
}

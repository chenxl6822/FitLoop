package com.fitloop.user;

import com.fitloop.security.JwtService;
import com.fitloop.user.UserDtos.LoginRequest;
import com.fitloop.user.UserDtos.LoginResponse;
import com.fitloop.user.UserDtos.RegisterRequest;
import com.fitloop.user.UserDtos.UpdateProfileRequest;
import com.fitloop.user.UserDtos.UserProfile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class UserService {
    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final SmsService smsService;

    public UserService(UserRepository users, PasswordEncoder passwordEncoder, JwtService jwtService,
                       SmsService smsService) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.smsService = smsService;
    }

    @Transactional
    public UserProfile register(RegisterRequest request) {
        if (!StringUtils.hasText(request.phone()) && !StringUtils.hasText(request.email())) {
            throw new IllegalArgumentException("手机号和邮箱至少填写一项");
        }
        if (StringUtils.hasText(request.phone()) && users.existsByPhone(request.phone())) {
            throw new IllegalArgumentException("手机号已注册");
        }
        if (StringUtils.hasText(request.email()) && users.existsByEmail(request.email())) {
            throw new IllegalArgumentException("邮箱已注册");
        }
        UserInfo user = new UserInfo();
        user.setPhone(request.phone());
        user.setEmail(request.email());
        user.setNickname(StringUtils.hasText(request.nickname()) ? request.nickname() : "FitLoop 用户");
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        return UserProfile.from(users.save(user));
    }

    @Transactional(readOnly = true)
    public LoginResponse login(LoginRequest request) {
        UserInfo user = users.findByPhoneOrEmail(request.account(), request.account())
                .orElseThrow(() -> new IllegalArgumentException("账号或密码错误"));
        boolean codeLogin = "code".equalsIgnoreCase(request.loginType());
        if (codeLogin) {
            if (!smsService.verifyCode(request.account(), request.code())) {
                throw new IllegalArgumentException("验证码错误或已过期");
            }
        } else if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new IllegalArgumentException("账号或密码错误");
        }
        return new LoginResponse(jwtService.issue(user.getUserId()), UserProfile.from(user));
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
}

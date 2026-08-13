package com.fitloop.user;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import com.fitloop.user.UserDtos.LoginRequest;
import com.fitloop.user.UserDtos.LoginResponse;
import com.fitloop.user.UserDtos.PasswordResetRequest;
import com.fitloop.user.UserDtos.RegisterRequest;
import com.fitloop.user.UserDtos.UpdateProfileRequest;
import com.fitloop.user.UserDtos.UserProfile;
import com.fitloop.user.UserDtos.DeleteAccountRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class UserController {
    private final UserService users;
    private final AccountDataService accountData;

    public UserController(UserService users, AccountDataService accountData) {
        this.users = users;
        this.accountData = accountData;
    }

    @PostMapping("/api/user/register")
    public ApiResponse<UserProfile> register(@Valid @RequestBody RegisterRequest request) {
        return ApiResponse.ok(users.register(request));
    }

    @PostMapping("/api/auth/login")
    public ApiResponse<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        return ApiResponse.ok(users.login(request));
    }

    @PostMapping("/api/auth/password/reset")
    public ApiResponse<Void> resetPassword(@Valid @RequestBody PasswordResetRequest request) {
        users.resetPassword(request);
        return ApiResponse.ok(null);
    }

    @PutMapping("/api/user/update")
    public ApiResponse<UserProfile> update(@RequestBody UpdateProfileRequest request) {
        return ApiResponse.ok(users.updateProfile(AuthSupport.currentUserId(), request));
    }

    @GetMapping("/api/user/profile")
    public ApiResponse<UserProfile> profile() {
        return ApiResponse.ok(users.getProfile(AuthSupport.currentUserId()));
    }

    @GetMapping("/api/user/data-export")
    public ApiResponse<java.util.Map<String, Object>> exportData() {
        return ApiResponse.ok(accountData.export(AuthSupport.currentUserId()));
    }

    @DeleteMapping("/api/user/account")
    public ApiResponse<Void> deleteAccount(@Valid @RequestBody DeleteAccountRequest request) {
        accountData.delete(AuthSupport.currentUserId(), request.password());
        return ApiResponse.ok(null);
    }
}

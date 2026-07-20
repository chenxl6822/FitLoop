package com.fitloop.user;

import jakarta.validation.constraints.NotBlank;

public final class UserDtos {
    private UserDtos() {
    }

    public record RegisterRequest(String phone, String email, @NotBlank String password, String code, String nickname) {
    }

    public record LoginRequest(@NotBlank String account, String password, String code, String loginType) {
    }

    public record PasswordResetRequest(@NotBlank String account, @NotBlank String code,
                                       @NotBlank String newPassword) {
    }

    public record UpdateProfileRequest(String nickname, String avatarUrl, String gender, String grade, String college) {
    }

    public record UserProfile(Long userId, String phone, String email, String nickname, String avatarUrl,
                              String gender, String grade, String college, int points, int level) {
        public static UserProfile from(UserInfo user) {
            return new UserProfile(user.getUserId(), user.getPhone(), user.getEmail(), user.getNickname(),
                    user.getAvatarUrl(), user.getGender(), user.getGrade(), user.getCollege(),
                    user.getPoints(), user.getLevel());
        }
    }

    public record LoginResponse(String token, String refreshToken, String tokenType, long expiresIn,
                                UserProfile userProfile) {
    }

    public record RefreshRequest(@NotBlank String refreshToken) { }
}

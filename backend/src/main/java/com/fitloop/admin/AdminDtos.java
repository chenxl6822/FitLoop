package com.fitloop.admin;

import java.util.List;

public final class AdminDtos {
    private AdminDtos() {}

    public record UserListItem(
            Long userId,
            String nickname,
            String phone,
            String email,
            Integer points,
            Integer level,
            String createdAt) {}

    public record PaginatedUserListResponse(
            List<UserListItem> users,
            int page,
            int size,
            long total) {}

    public record UserDetailResponse(
            Long userId,
            String nickname,
            String phone,
            String email,
            String avatarUrl,
            String createdAt,
            long sportRecordCount,
            long targetCount,
            long totalDurationSeconds,
            double totalDistanceKm) {}

    public record SystemStatsResponse(
            long totalUsers,
            long todayNewUsers,
            long totalSportRecords,
            long todayCheckins,
            long pendingFeedbackCount) {}
}

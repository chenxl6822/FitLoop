package com.fitloop.admin;

import com.fitloop.admin.AdminDtos.PaginatedUserListResponse;
import com.fitloop.admin.AdminDtos.SystemStatsResponse;
import com.fitloop.admin.AdminDtos.UserDetailResponse;
import com.fitloop.admin.AdminDtos.UserListItem;
import com.fitloop.feedback.FeedbackRepository;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.target.SportTargetRepository;
import com.fitloop.user.UserRepository;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AdminService {
    private final UserRepository users;
    private final SportRecordRepository sportRecords;
    private final SportTargetRepository targets;
    private final FeedbackRepository feedbacks;

    public AdminService(UserRepository users, SportRecordRepository sportRecords,
                        SportTargetRepository targets, FeedbackRepository feedbacks) {
        this.users = users;
        this.sportRecords = sportRecords;
        this.targets = targets;
        this.feedbacks = feedbacks;
    }

    @Transactional(readOnly = true)
    public SystemStatsResponse getStats() {
        ZoneId zone = ZoneId.of("Asia/Shanghai");
        Instant todayStart = LocalDate.now().atStartOfDay(zone).toInstant();

        long totalUsers = users.count();
        long todayNewUsers = users.countByCreatedAtAfter(todayStart);
        long totalSportRecords = sportRecords.count();
        long todayCheckins = sportRecords.countByStartedAtAfter(todayStart);
        long pendingFeedbackCount = feedbacks.findAll().stream()
                .filter(f -> "pending".equals(f.getStatus())).count();

        return new SystemStatsResponse(totalUsers, todayNewUsers,
                totalSportRecords, todayCheckins, pendingFeedbackCount);
    }

    @Transactional(readOnly = true)
    public PaginatedUserListResponse listUsers(int page, int size) {
        var pageResult = users.findAllByOrderByCreatedAtDesc(PageRequest.of(page, size));
        List<UserListItem> items = pageResult.stream()
                .map(u -> new UserListItem(
                        u.getUserId(), u.getNickname(), u.getPhone(), u.getEmail(),
                        u.getPoints(), u.getLevel(),
                        null))
                .toList();
        return new PaginatedUserListResponse(items, page, size, pageResult.getTotalElements());
    }

    @Transactional(readOnly = true)
    public UserDetailResponse getUserDetail(Long userId) {
        var user = users.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        long sportRecordCount = sportRecords.countByUserId(userId);
        long targetCount = targets.countByUserId(userId);

        return new UserDetailResponse(
                user.getUserId(), user.getNickname(), user.getPhone(), user.getEmail(),
                user.getAvatarUrl(),
                null,
                sportRecordCount, targetCount, 0L, 0.0);
    }
}

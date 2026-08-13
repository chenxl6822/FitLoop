package com.fitloop.user;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.WeekFields;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@Service
public class AccountDataService {
    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final JdbcTemplate jdbc;
    private final StringRedisTemplate redis;
    private final Path avatarDir;
    private final Path photoDir;

    public AccountDataService(UserRepository users, PasswordEncoder passwordEncoder, JdbcTemplate jdbc,
                              StringRedisTemplate redis,
                              @Value("${fitloop.upload.avatar-dir:uploads/avatars}") String avatarDir,
                              @Value("${fitloop.upload.photo-dir:uploads/photos}") String photoDir) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.jdbc = jdbc;
        this.redis = redis;
        this.avatarDir = Paths.get(avatarDir).toAbsolutePath().normalize();
        this.photoDir = Paths.get(photoDir).toAbsolutePath().normalize();
    }

    @Transactional(readOnly = true)
    public Map<String, Object> export(Long userId) {
        requireActive(userId);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("exportedAt", Instant.now());
        data.put("profile", single("select user_id, phone, email, nickname, avatar_url, gender, grade, college, "
                + "points, level, created_at, updated_at from user_info where user_id = ?", userId));
        data.put("workouts", list("select record_id, session_id, sport_type, checkin_mode, duration_seconds, "
                + "distance_km, calorie, note, photo_url, status, abnormal_reason, started_at, ended_at "
                + "from sport_record where user_id = ? order by record_id", userId));
        data.put("trackPoints", list("select p.record_id, p.sequence_no, p.latitude, p.longitude, p.accuracy, "
                + "p.recorded_at from sport_track_point p join sport_record r on r.record_id = p.record_id "
                + "where r.user_id = ? order by p.record_id, p.sequence_no", userId));
        data.put("targets", list("select target_id, period_type, metric, target_value, completed_value, "
                + "start_date, end_date, status from sport_target where user_id = ? order by target_id", userId));
        data.put("healthData", list("select health_id, weight_kg, sleep_hours, diet_note, data_date "
                + "from health_data where user_id = ? order by data_date", userId));
        data.put("reminders", list("select remind_id, type, remind_time, cycle, enabled "
                + "from reminder_config where user_id = ? order by remind_id", userId));
        data.put("friends", list("select friend_id, friend_user_id, status, created_at "
                + "from user_friend where user_id = ? order by friend_id", userId));
        data.put("appeals", list("select appeal_id, record_id, reason, evidence_url, status, review_note, created_at "
                + "from appeal where user_id = ? order by appeal_id", userId));
        data.put("feedback", list("select feedback_id, type, content, contact, status, admin_note, created_at "
                + "from feedback where user_id = ? order by feedback_id", userId));
        data.put("trainingPlans", list("select plan_id, title, plan_json, completed_days_json, status, created_at "
                + "from training_plan where user_id = ? order by plan_id", userId));
        return data;
    }

    @Transactional
    public void delete(Long userId, String password) {
        UserInfo user = users.findForUpdate(userId)
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        if (user.getDeletedAt() != null) throw new IllegalStateException("账号已注销");
        if (user.getRole() == UserRole.ADMIN) throw new IllegalStateException("管理员账号不能在应用内注销");
        if (password == null || !passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new IllegalArgumentException("当前密码不正确");
        }

        List<String> mediaUrls = new ArrayList<>();
        if (user.getAvatarUrl() != null) mediaUrls.add(user.getAvatarUrl());
        mediaUrls.addAll(jdbc.queryForList(
                "select photo_url from sport_record where user_id = ? and photo_url is not null", String.class, userId));
        List<Long> recordIds = jdbc.queryForList(
                "select record_id from sport_record where user_id = ?", Long.class, userId);
        List<String> runIds = jdbc.queryForList(
                "select run_id from agent_run where requested_by_user_id = ? or subject_user_id = ?",
                String.class, userId, userId);

        jdbc.update("delete from admin_audit_log where actor_user_id = ? or "
                + "(resource_type = 'USER' and resource_id = ?)", userId, userId.toString());
        for (String runId : runIds) {
            jdbc.update("delete from training_plan where source_proposal_id in "
                    + "(select proposal_id from agent_action_proposal where run_id = ?)", runId);
            jdbc.update("delete from agent_tool_audit where run_id = ?", runId);
            jdbc.update("delete from agent_message where run_id = ?", runId);
            jdbc.update("delete from agent_action_proposal where run_id = ?", runId);
            jdbc.update("delete from agent_run where run_id = ?", runId);
        }
        jdbc.update("delete from training_plan where user_id = ?", userId);
        jdbc.update("delete from appeal where user_id = ?", userId);
        jdbc.update("delete from feedback where user_id = ?", userId);
        jdbc.update("delete from health_data where user_id = ?", userId);
        jdbc.update("delete from reminder_config where user_id = ?", userId);
        jdbc.update("delete from target_reminder_read where user_id = ?", userId);
        jdbc.update("delete from sport_target where user_id = ?", userId);
        jdbc.update("delete from user_friend where user_id = ? or friend_user_id = ?", userId, userId);
        for (Long recordId : recordIds) {
            jdbc.update("delete from sport_track_point where record_id = ?", recordId);
            jdbc.update("delete from outbox_event where event_type = 'WORKOUT_COMPLETED' and aggregate_id = ?",
                    recordId.toString());
        }
        jdbc.update("delete from idempotency_record where user_id = ?", userId);
        jdbc.update("delete from sport_record where user_id = ?", userId);
        jdbc.update("delete from refresh_token where user_id = ?", userId);
        if (user.getPhone() != null) {
            jdbc.update("delete from sms_code where phone = ?", user.getPhone());
            jdbc.update("delete from verification_code where target = ?", user.getPhone());
        }
        if (user.getEmail() != null) {
            jdbc.update("delete from verification_code where target = ?", user.getEmail());
        }

        user.setPhone(null);
        user.setEmail(null);
        user.setNickname("已注销用户");
        user.setAvatarUrl(null);
        user.setGender(null);
        user.setGrade(null);
        user.setCollege(null);
        user.setPoints(0);
        user.setLevel(1);
        user.setPasswordHash(passwordEncoder.encode(UUID.randomUUID().toString()));
        user.setDeletedAt(Instant.now());
        cleanupAfterCommit(userId, mediaUrls);
    }

    private void requireActive(Long userId) {
        if (!users.existsByUserIdAndDeletedAtIsNull(userId)) {
            throw new IllegalArgumentException("用户不存在或账号已注销");
        }
    }

    private Map<String, Object> single(String sql, Object... arguments) {
        List<Map<String, Object>> values = list(sql, arguments);
        if (values.isEmpty()) throw new IllegalArgumentException("用户不存在");
        return values.getFirst();
    }

    private List<Map<String, Object>> list(String sql, Object... arguments) {
        return jdbc.queryForList(sql, arguments);
    }

    private void cleanupAfterCommit(Long userId, List<String> urls) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) return;
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                for (String url : urls) deleteMedia(url);
                removeLeaderboardProjection(userId);
            }
        });
    }

    private void removeLeaderboardProjection(Long userId) {
        try {
            LocalDate date = LocalDate.now(ZoneId.of("Asia/Shanghai"));
            WeekFields fields = WeekFields.ISO;
            String period = date.get(fields.weekBasedYear()) + "-"
                    + String.format("%02d", date.get(fields.weekOfWeekBasedYear()));
            String member = userId.toString();
            redis.opsForZSet().remove("ranking:week:distance:" + period, member);
            redis.opsForHash().delete("ranking:week:calorie:" + period, member);
            redis.delete("ranking:personal:week");
        } catch (RuntimeException ignored) {
            // Ranking is a short-lived projection and can be rebuilt from the now-erased database records.
        }
    }

    private void deleteMedia(String url) {
        try {
            Path root = url.startsWith("/uploads/avatars/") ? avatarDir
                    : url.startsWith("/uploads/photos/") ? photoDir : null;
            if (root == null) return;
            Path name = Paths.get(url).getFileName();
            if (name == null) return;
            Path target = root.resolve(name).normalize();
            if (target.startsWith(root)) Files.deleteIfExists(target);
        } catch (Exception ignored) {
            // Database erasure already succeeded. Orphan-media cleanup can be retried operationally.
        }
    }
}

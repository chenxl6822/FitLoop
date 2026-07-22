package com.fitloop.demo;

import com.fitloop.appeal.Appeal;
import com.fitloop.appeal.AppealRepository;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.HealthData;
import com.fitloop.stats.HealthDataRepository;
import com.fitloop.target.SportTarget;
import com.fitloop.target.SportTargetRepository;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import com.fitloop.user.UserRole;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@Profile("agent-e2e")
public class AgentE2eDataBootstrap implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(AgentE2eDataBootstrap.class);
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    private final UserRepository users;
    private final SportTargetRepository targets;
    private final HealthDataRepository health;
    private final SportRecordRepository workouts;
    private final AppealRepository appeals;
    private final PasswordEncoder passwordEncoder;
    private final String userAccount;
    private final String userPassword;
    private final String adminAccount;
    private final String adminPassword;

    public AgentE2eDataBootstrap(
            UserRepository users,
            SportTargetRepository targets,
            HealthDataRepository health,
            SportRecordRepository workouts,
            AppealRepository appeals,
            PasswordEncoder passwordEncoder,
            @Value("${fitloop.demo-e2e.user-account}") String userAccount,
            @Value("${fitloop.demo-e2e.user-password}") String userPassword,
            @Value("${fitloop.demo-e2e.admin-account}") String adminAccount,
            @Value("${fitloop.demo-e2e.admin-password}") String adminPassword) {
        this.users = users;
        this.targets = targets;
        this.health = health;
        this.workouts = workouts;
        this.appeals = appeals;
        this.passwordEncoder = passwordEncoder;
        this.userAccount = userAccount;
        this.userPassword = userPassword;
        this.adminAccount = adminAccount;
        this.adminPassword = adminPassword;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        UserInfo demoUser = ensureUser(userAccount, userPassword, "Agent E2E User", UserRole.USER);
        ensureUser(adminAccount, adminPassword, "Agent E2E Admin", UserRole.ADMIN);
        ensureTarget(demoUser.getUserId());
        ensureHealthData(demoUser.getUserId());
        ensureWorkout(demoUser.getUserId(), "agent-e2e-valid-1", 5, 1_800, 4.2,
                SportRecord.STATUS_VALID, null);
        ensureWorkout(demoUser.getUserId(), "agent-e2e-valid-2", 2, 2_100, 5.1,
                SportRecord.STATUS_VALID, null);
        SportRecord abnormal = ensureWorkout(demoUser.getUserId(), "agent-e2e-abnormal", 1, 1_860, 5.0,
                SportRecord.STATUS_APPEALING, "isolated GPS speed spike");
        ensureAppeal(demoUser.getUserId(), abnormal);
        log.info("Agent E2E fixture is ready: userId={}, appealRecordId={}",
                demoUser.getUserId(), abnormal.getRecordId());
    }

    private UserInfo ensureUser(String account, String password, String nickname, UserRole role) {
        UserInfo user = users.findByPhoneOrEmail(account, account).orElseGet(() -> {
            UserInfo created = new UserInfo();
            created.setEmail(account);
            created.setPasswordHash(passwordEncoder.encode(password));
            created.setNickname(nickname);
            return created;
        });
        user.setRole(role);
        return users.save(user);
    }

    private void ensureTarget(Long userId) {
        if (targets.countByUserId(userId) > 0) return;
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        SportTarget target = new SportTarget();
        target.setUserId(userId);
        target.setPeriodType("week");
        target.setMetric("distance");
        target.setTargetValue(15.0);
        target.setCompletedValue(9.3);
        target.setStartDate(today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)));
        target.setEndDate(today.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY)));
        target.setStatus("active");
        targets.save(target);
    }

    private void ensureHealthData(Long userId) {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        if (!health.findByUserIdAndDataDateBetweenOrderByDataDateAsc(
                userId, today.minusDays(29), today).isEmpty()) {
            return;
        }
        health.saveAll(List.of(
                healthPoint(userId, today.minusDays(6), 65.2, 7.2),
                healthPoint(userId, today.minusDays(3), 65.0, 7.5),
                healthPoint(userId, today, 64.9, 7.1)));
    }

    private HealthData healthPoint(Long userId, LocalDate date, double weight, double sleep) {
        HealthData point = new HealthData();
        point.setUserId(userId);
        point.setDataDate(date);
        point.setWeightKg(weight);
        point.setSleepHours(sleep);
        point.setDietNote("agent-e2e fixture");
        return point;
    }

    private SportRecord ensureWorkout(Long userId, String sessionId, int daysAgo, long durationSeconds,
                                      double distanceKm, int status, String abnormalReason) {
        return workouts.findBySessionIdAndUserId(sessionId, userId).orElseGet(() -> {
            Instant started = Instant.now().minusSeconds(daysAgo * 24L * 60 * 60);
            SportRecord workout = new SportRecord();
            workout.setUserId(userId);
            workout.setSessionId(sessionId);
            workout.setSportType("running");
            workout.setCheckinMode("gps");
            workout.setDurationSeconds(durationSeconds);
            workout.setDistanceKm(distanceKm);
            workout.setCalorie(Math.round(distanceKm * 62.0 * 100.0) / 100.0);
            workout.setStatus(status);
            workout.setAbnormalReason(abnormalReason);
            workout.setStartedAt(started);
            workout.setEndedAt(started.plusSeconds(durationSeconds));
            workout.setNote("isolated agent-e2e fixture");
            return workouts.save(workout);
        });
    }

    private void ensureAppeal(Long userId, SportRecord abnormal) {
        if (appeals.findByRecordIdAndUserId(abnormal.getRecordId(), userId).isPresent()) return;
        Appeal appeal = new Appeal();
        appeal.setUserId(userId);
        appeal.setRecordId(abnormal.getRecordId());
        appeal.setReason("A short tunnel section caused one isolated GPS speed spike.");
        appeal.setEvidenceUrl("https://example.invalid/agent-e2e-evidence");
        appeal.setStatus("pending");
        appeals.save(appeal);
    }
}

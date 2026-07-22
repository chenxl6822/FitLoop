package com.fitloop.demo;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.appeal.AppealRepository;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.HealthDataRepository;
import com.fitloop.target.SportTargetRepository;
import com.fitloop.user.UserDtos.LoginRequest;
import com.fitloop.user.UserRepository;
import com.fitloop.user.UserRole;
import com.fitloop.user.UserService;
import java.time.LocalDate;
import java.time.ZoneId;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

@SpringBootTest(properties =
        "spring.datasource.url=jdbc:h2:mem:agent-e2e;MODE=MySQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
@ActiveProfiles({"test", "agent-e2e"})
class AgentE2eDataBootstrapTest {
    @Autowired UserRepository users;
    @Autowired UserService userService;
    @Autowired SportTargetRepository targets;
    @Autowired HealthDataRepository health;
    @Autowired SportRecordRepository workouts;
    @Autowired AppealRepository appeals;
    @MockitoBean StringRedisTemplate redis;
    @MockitoBean JavaMailSender mailSender;

    @Test
    void profileSeedsLoginReadyUsersAndAgentEvidence() {
        var user = users.findByPhoneOrEmail("agent.user@fitloop.local", "agent.user@fitloop.local")
                .orElseThrow();
        var admin = users.findByPhoneOrEmail("agent.admin@fitloop.local", "agent.admin@fitloop.local")
                .orElseThrow();

        assertThat(user.getRole()).isEqualTo(UserRole.USER);
        assertThat(admin.getRole()).isEqualTo(UserRole.ADMIN);
        assertThat(userService.login(new LoginRequest(
                "agent.user@fitloop.local", "AgentUserDemo!2026", null, "password")).role())
                .isEqualTo(UserRole.USER);
        assertThat(userService.login(new LoginRequest(
                "agent.admin@fitloop.local", "AgentAdminDemo!2026", null, "password")).role())
                .isEqualTo(UserRole.ADMIN);
        assertThat(targets.countByUserId(user.getUserId())).isEqualTo(1);
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Shanghai"));
        assertThat(health.findByUserIdAndDataDateBetweenOrderByDataDateAsc(
                user.getUserId(), today.minusDays(29), today))
                .hasSize(3);
        assertThat(workouts.findTop50ByUserIdOrderByStartedAtDesc(user.getUserId())).hasSize(3);

        var appeal = appeals.findByUserIdOrderByCreatedAtDesc(user.getUserId()).getFirst();
        assertThat(appeal.getStatus()).isEqualTo("pending");
        assertThat(workouts.findById(appeal.getRecordId()).orElseThrow().getStatus())
                .isEqualTo(SportRecord.STATUS_APPEALING);
    }
}

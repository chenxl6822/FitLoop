package com.fitloop.agent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.agent.AgentDtos.ProposalRequest;
import com.fitloop.agent.AgentDtos.RunResultRequest;
import com.fitloop.audit.AdminAuditLogRepository;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

@SpringBootTest
@ActiveProfiles("test")
class AgentGatewayIntegrationTest {
    @Autowired AgentGatewayService gateway;
    @Autowired AgentRunRepository runs;
    @Autowired TrainingPlanRepository plans;
    @Autowired UserRepository users;
    @Autowired AgentDelegationTokenService delegationTokens;
    @Autowired AdminAuditLogRepository auditLogs;
    @MockitoBean StringRedisTemplate redis;
    @MockitoBean JavaMailSender mailSender;

    @Test
    void coachProposalRequiresOwnerConfirmationAndBackendPerformsWrite() {
        Long owner = user("13910000001", "AgentOwner");
        Long stranger = user("13910000002", "AgentStranger");
        AgentRun run = gateway.createCoachRun(owner, "prepare for a 5 km run");
        gateway.claim(run.getRunId());
        var proposal = gateway.propose(run.getRunId(), new ProposalRequest(
                "CREATE_TRAINING_PLAN",
                "{\"title\":\"Safe 5K starter\",\"goal\":\"Complete 5K safely\","
                        + "\"days\":[{\"day\":1,\"session_type\":\"easy run\","
                        + "\"duration_minutes\":20,\"intensity\":\"LOW\"}]}", false));
        gateway.complete(run.getRunId(), new RunResultRequest(AgentRunStatus.WAITING_APPROVAL,
                "{\"summary\":\"plan ready\"}", "deepseek-v4-flash", "coach-v1",
                120, 80, 20, 950, null, false));

        assertThatThrownBy(() -> gateway.confirm(proposal.proposalId(), stranger, false))
                .isInstanceOf(AccessDeniedException.class);
        assertThat(plans.count()).isZero();

        var confirmed = gateway.confirm(proposal.proposalId(), owner, false);

        assertThat(confirmed.status()).isEqualTo("CONFIRMED");
        assertThat(plans.findById(confirmed.affectedResourceId())).isPresent();
        assertThat(gateway.listTrainingPlans(owner))
                .singleElement()
                .satisfies(plan -> {
                    assertThat(plan.planId()).isEqualTo(confirmed.affectedResourceId());
                    assertThat(plan.title()).isEqualTo("Safe 5K starter");
                    assertThat(plan.planJson()).contains("Complete 5K safely");
                    assertThat(plan.status()).isEqualTo("ACTIVE");
                });
        assertThat(gateway.listTrainingPlans(stranger)).isEmpty();
        assertThat(runs.findById(run.getRunId()).orElseThrow().getStatus()).isEqualTo(AgentRunStatus.SUCCEEDED);

        var next = gateway.nextTrainingSession(owner);
        assertThat(next.planId()).isEqualTo(confirmed.affectedResourceId());
        assertThat(next.day()).isEqualTo(1);
        assertThat(next.sessionType()).isEqualTo("easy run");
        assertThat(next.completedSessions()).isZero();
        assertThat(next.totalSessions()).isEqualTo(1);
        assertThat(gateway.nextTrainingSession(stranger)).isNull();

        var progressed = gateway.completeTrainingDay(owner, confirmed.affectedResourceId(), 1);
        assertThat(progressed.completedDays()).containsExactly(1);
        assertThat(gateway.completeTrainingDay(owner, confirmed.affectedResourceId(), 1).completedDays())
                .containsExactly(1);
        assertThat(gateway.nextTrainingSession(owner)).isNull();
        assertThatThrownBy(() -> gateway.completeTrainingDay(stranger, confirmed.affectedResourceId(), 1))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void delegationTokenIsScopedAndToolCallsAreLimitedToEight() {
        Long owner = user("13910000003", "ToolOwner");
        AgentRun run = gateway.createCoachRun(owner, "weekly summary");
        AgentDtos.ToolContext context = delegationTokens.verify(delegationTokens.issue(run));
        assertThat(context.runId()).isEqualTo(run.getRunId());
        assertThat(context.subjectUserId()).isEqualTo(owner);
        assertThat(context.type()).isEqualTo(AgentRunType.COACH);
        gateway.claim(run.getRunId());

        for (int i = 0; i < 8; i++) {
            int value = i;
            assertThat((Integer) gateway.executeTool(context, "test_tool", Map.of("index", i), () -> value))
                    .isEqualTo(i);
        }
        assertThatThrownBy(() -> gateway.executeTool(context, "ninth_tool", Map.of(), () -> "blocked"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("limit");
        assertThat(gateway.adminRuns(AgentRunType.COACH, AgentRunStatus.RUNNING, 0, 20).items())
                .extracting(AgentDtos.AdminRunSummary::runId)
                .contains(run.getRunId());
        assertThat(gateway.runAudit(run.getRunId()).toolCalls()).hasSize(8);
    }

    @Test
    void ownerCanRejectProposalWithoutExecutingBusinessWrite() {
        Long owner = user("13910000005", "RejectOwner");
        AgentRun run = gateway.createCoachRun(owner, "plan later");
        gateway.claim(run.getRunId());
        var proposal = gateway.propose(run.getRunId(), new ProposalRequest(
                "CREATE_TRAINING_PLAN", "{\"title\":\"Deferred plan\"}", false));
        gateway.complete(run.getRunId(), new RunResultRequest(AgentRunStatus.WAITING_APPROVAL,
                "{\"summary\":\"plan ready\"}", "deepseek-v4-flash", "coach-v1",
                10, 5, 2, 100, null, false));

        var rejected = gateway.reject(proposal.proposalId(), owner, false, "Not this week");

        assertThat(rejected.status()).isEqualTo("REJECTED");
        assertThat(plans.existsBySourceProposalId(proposal.proposalId())).isFalse();
        assertThat(runs.findById(run.getRunId()).orElseThrow().getStatus())
                .isEqualTo(AgentRunStatus.SUCCEEDED);
        assertThat(auditLogs.findAll()).anySatisfy(log -> {
            assertThat(log.getAction()).isEqualTo("AGENT_PROPOSAL_REJECTED");
            assertThat(log.getActorUserId()).isEqualTo(owner);
        });
    }

    @Test
    void delegationTokenRejectsTampering() {
        Long owner = user("13910000004", "TokenOwner");
        AgentRun run = gateway.createCoachRun(owner, "token test");
        String token = delegationTokens.issue(run);
        int middle = token.indexOf('.') + 3;
        char replacement = token.charAt(middle) == 'A' ? 'B' : 'A';
        String tampered = token.substring(0, middle) + replacement + token.substring(middle + 1);

        assertThatThrownBy(() -> delegationTokens.verify(tampered))
                .isInstanceOf(IllegalArgumentException.class);
    }

    private Long user(String phone, String nickname) {
        UserInfo user = new UserInfo();
        user.setPhone(phone);
        user.setPasswordHash("hash");
        user.setNickname(nickname);
        return users.save(user).getUserId();
    }
}

package com.fitloop.agent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.lang.reflect.Field;
import java.time.Instant;
import org.junit.jupiter.api.Test;

class AgentStateMachineTest {
    @Test
    void runCapturesLifecycleAndResultMetrics() {
        AgentRun run = queued();
        run.prePersist();
        run.preUpdate();
        assertThat(run.getCreatedAt()).isNotNull();
        assertThat(run.getUpdatedAt()).isNotNull();

        run.claim();
        run.waitingApproval("{}", "deepseek-v4-flash", "coach-v1", 10, 20, 30, 40);

        assertThat(run.getStatus()).isEqualTo(AgentRunStatus.WAITING_APPROVAL);
        assertThat(run.getModel()).isEqualTo("deepseek-v4-flash");
        assertThat(run.getPromptVersion()).isEqualTo("coach-v1");
        assertThat(run.getInputTokens()).isEqualTo(10);
        assertThat(run.getOutputTokens()).isEqualTo(20);
        assertThat(run.getCostMicros()).isEqualTo(30);
        assertThat(run.getLatencyMs()).isEqualTo(40);
        run.approve();
        assertThat(run.getStatus()).isEqualTo(AgentRunStatus.SUCCEEDED);
        assertThat(run.getCompletedAt()).isNotNull();
    }

    @Test
    void runRejectsIllegalTransitions() {
        AgentRun run = queued();
        assertThatThrownBy(() -> run.succeed("{}", "model", "v1", 0, 0, 0, 0))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(run::approve).isInstanceOf(IllegalStateException.class);
        run.claim();
        assertThatThrownBy(run::claim).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void retryableFailuresStopAfterThreeAttemptsAndBoundErrorLength() {
        AgentRun run = queued();
        run.claim();
        run.fail(null, true);
        assertThat(run.getStatus()).isEqualTo(AgentRunStatus.FAILED_RETRYABLE);
        assertThat(run.getErrorMessage()).isEqualTo("Agent execution failed");

        run.claim();
        run.fail("second", true);
        assertThat(run.getStatus()).isEqualTo(AgentRunStatus.FAILED_RETRYABLE);

        run.claim();
        run.fail("x".repeat(600), true);
        assertThat(run.getStatus()).isEqualTo(AgentRunStatus.FAILED_FINAL);
        assertThat(run.getErrorMessage()).hasSize(500);
        assertThat(run.getCompletedAt()).isNotNull();
    }

    @Test
    void nonRetryableFailureIsImmediatelyFinal() {
        AgentRun run = queued();
        run.claim();
        run.fail("fatal", false);
        assertThat(run.getStatus()).isEqualTo(AgentRunStatus.FAILED_FINAL);
    }

    @Test
    void proposalCanOnlyBeConfirmedOnceAndBeforeExpiry() throws Exception {
        AgentActionProposal proposal = proposal();
        proposal.prePersist();
        assertThat(proposal.getCreatedAt()).isNotNull();
        assertThat(proposal.getExpiresAt()).isAfter(proposal.getCreatedAt());
        proposal.confirm(9L);
        assertThat(proposal.getStatus()).isEqualTo("CONFIRMED");
        assertThat(proposal.getConfirmedByUserId()).isEqualTo(9L);
        assertThatThrownBy(() -> proposal.confirm(9L)).isInstanceOf(IllegalStateException.class);

        AgentActionProposal expired = proposal();
        set(expired, "expiresAt", Instant.now().minusSeconds(1));
        expired.prePersist();
        assertThatThrownBy(() -> expired.confirm(9L)).hasMessageContaining("expired");
    }

    private AgentRun queued() {
        return AgentRun.queued(AgentRunType.COACH, 1L, 1L, null, "{}");
    }

    private AgentActionProposal proposal() {
        AgentActionProposal proposal = new AgentActionProposal();
        proposal.setRunId("run-1");
        proposal.setSubjectUserId(1L);
        proposal.setActionType("CREATE_TRAINING_PLAN");
        proposal.setPayloadJson("{}");
        return proposal;
    }

    private void set(Object target, String name, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }
}

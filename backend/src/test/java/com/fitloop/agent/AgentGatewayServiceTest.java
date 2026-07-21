package com.fitloop.agent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fitloop.agent.AgentDtos.AgentMessageRequest;
import com.fitloop.agent.AgentDtos.ProposalRequest;
import com.fitloop.agent.AgentDtos.RunResultRequest;
import com.fitloop.agent.AgentDtos.ToolAuditRequest;
import com.fitloop.appeal.Appeal;
import com.fitloop.appeal.AppealRepository;
import com.fitloop.appeal.AppealService;
import com.fitloop.audit.AdminAuditService;
import com.fitloop.user.UserRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.security.access.AccessDeniedException;
import tools.jackson.databind.ObjectMapper;

@ExtendWith(MockitoExtension.class)
class AgentGatewayServiceTest {
    @Mock AgentRunRepository runs;
    @Mock AgentMessageRepository messages;
    @Mock AgentToolAuditRepository toolAudits;
    @Mock AgentActionProposalRepository proposals;
    @Mock TrainingPlanRepository trainingPlans;
    @Mock AppealRepository appeals;
    @Mock AppealService appealService;
    @Mock UserRepository users;
    @Mock AdminAuditService audits;
    @Mock ApplicationEventPublisher events;

    private AgentGatewayService gateway;

    @BeforeEach
    void setUp() {
        gateway = new AgentGatewayService(runs, messages, toolAudits, proposals, trainingPlans,
                appeals, appealService, users, audits, events, new ObjectMapper());
    }

    @Test
    void creationValidatesUserAndPendingAppeal() {
        when(users.existsById(1L)).thenReturn(false, true);
        assertThatThrownBy(() -> gateway.createCoachRun(1L, "goal"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(gateway.createCoachRun(1L, null).getInputJson()).contains("objective");
        verify(events).publishEvent(any(AgentRunQueuedEvent.class));

        when(appeals.findById(10L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> gateway.createAppealReview(99L, 10L))
                .isInstanceOf(IllegalArgumentException.class);
        when(appeals.findById(10L)).thenReturn(Optional.of(appeal("approved")));
        assertThatThrownBy(() -> gateway.createAppealReview(99L, 10L))
                .isInstanceOf(IllegalArgumentException.class);
        when(appeals.findById(10L)).thenReturn(Optional.of(appeal("pending")));
        assertThat(gateway.createAppealReview(99L, 10L).getRunType())
                .isEqualTo(AgentRunType.APPEAL_REVIEW);
    }

    @Test
    void visibilitySeparatesOwnersAdminsAndAppealReviewers() {
        AgentRun coach = AgentRun.queued(AgentRunType.COACH, 1L, 1L, null, "{}");
        when(runs.findById(coach.getRunId())).thenReturn(Optional.of(coach));
        when(proposals.findByRunIdOrderByProposalIdAsc(coach.getRunId())).thenReturn(List.of());
        when(messages.findByRunIdOrderByMessageIdAsc(coach.getRunId())).thenReturn(List.of());

        assertThat(gateway.getVisibleRun(coach.getRunId(), 1L, false).runId()).isEqualTo(coach.getRunId());
        assertThat(gateway.getVisibleRun(coach.getRunId(), 2L, true).runId()).isEqualTo(coach.getRunId());
        assertThat(gateway.messages(coach.getRunId(), 1L, false)).isEmpty();
        assertThatThrownBy(() -> gateway.getVisibleRun(coach.getRunId(), 2L, false))
                .isInstanceOf(AccessDeniedException.class);

        AgentRun appeal = AgentRun.queued(AgentRunType.APPEAL_REVIEW, 9L, 1L, 10L, "{}");
        when(runs.findById(appeal.getRunId())).thenReturn(Optional.of(appeal));
        assertThatThrownBy(() -> gateway.getVisibleRun(appeal.getRunId(), 1L, false))
                .isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> gateway.getVisibleRun("missing", 1L, true))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void executionRequiresRunningStateMatchingScopeAndEightToolLimit() {
        AgentRun run = running(AgentRunType.COACH, null);
        when(runs.findById(run.getRunId())).thenReturn(Optional.of(run));
        when(toolAudits.countByRunId(run.getRunId())).thenReturn(0L);

        gateway.appendMessage(run.getRunId(), new AgentMessageRequest("user", "hello"));
        gateway.auditTool(run.getRunId(), new ToolAuditRequest("goal", "{}", "{}", true, 1L, null));
        assertThat(gateway.executeTool(context(run), "goal", Map.of(), () -> "ok")).isEqualTo("ok");
        assertThatThrownBy(() -> gateway.executeTool(context(run), "failure", Map.of(), () -> {
            throw new IllegalStateException("tool failed");
        })).hasMessageContaining("tool failed");

        var wrong = new AgentDtos.ToolContext(run.getRunId(), 2L, null, AgentRunType.COACH);
        assertThatThrownBy(() -> gateway.executeTool(wrong, "goal", Map.of(), () -> "blocked"))
                .isInstanceOf(AccessDeniedException.class);
        when(toolAudits.countByRunId(run.getRunId())).thenReturn(8L);
        assertThatThrownBy(() -> gateway.auditTool(run.getRunId(),
                new ToolAuditRequest("ninth", "{}", null, false, 1L, "blocked")))
                .isInstanceOf(IllegalStateException.class);

        AgentRun queued = AgentRun.queued(AgentRunType.COACH, 1L, 1L, null, "{}");
        when(runs.findById(queued.getRunId())).thenReturn(Optional.of(queued));
        assertThatThrownBy(() -> gateway.appendMessage(queued.getRunId(),
                new AgentMessageRequest("user", "early"))).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void executableRunStatesAreStrictlyBounded() {
        AgentRun queued = AgentRun.queued(AgentRunType.COACH, 1L, 1L, null, "{}");
        when(runs.findById(queued.getRunId())).thenReturn(Optional.of(queued));
        assertThat(gateway.runForDelegation(queued.getRunId())).isSameAs(queued);

        AgentRun retryable = running(AgentRunType.COACH, null);
        retryable.fail("retry", true);
        when(runs.findById(retryable.getRunId())).thenReturn(Optional.of(retryable));
        assertThat(gateway.runForDelegation(retryable.getRunId())).isSameAs(retryable);

        AgentRun succeeded = running(AgentRunType.COACH, null);
        succeeded.succeed("{}", "model", "v1", 0, 0, 0, 1);
        when(runs.findById(succeeded.getRunId())).thenReturn(Optional.of(succeeded));
        assertThatThrownBy(() -> gateway.runForDelegation(succeeded.getRunId()))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> gateway.runForDelegation("missing"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void proposalValidationEnforcesAgentSpecificWriteBoundaries() {
        AgentRun coach = running(AgentRunType.COACH, null);
        when(runs.findById(coach.getRunId())).thenReturn(Optional.of(coach));
        when(proposals.findByRunIdOrderByProposalIdAsc(coach.getRunId())).thenReturn(List.of());

        assertThatThrownBy(() -> gateway.propose(coach.getRunId(),
                new ProposalRequest("CREATE_TRAINING_PLAN", "not-json", false)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> gateway.propose(coach.getRunId(),
                new ProposalRequest("REVIEW_APPEAL", "{}", false)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> gateway.propose(coach.getRunId(),
                new ProposalRequest("CREATE_TRAINING_PLAN", "{}", true)))
                .isInstanceOf(IllegalArgumentException.class);

        AgentRun appeal = running(AgentRunType.APPEAL_REVIEW, 10L);
        when(runs.findById(appeal.getRunId())).thenReturn(Optional.of(appeal));
        when(proposals.findByRunIdOrderByProposalIdAsc(appeal.getRunId())).thenReturn(List.of());
        assertThatThrownBy(() -> gateway.propose(appeal.getRunId(),
                new ProposalRequest("CREATE_TRAINING_PLAN", "{}", true)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> gateway.propose(appeal.getRunId(),
                new ProposalRequest("REVIEW_APPEAL", "{}", false)))
                .isInstanceOf(IllegalArgumentException.class);

        when(proposals.findByRunIdOrderByProposalIdAsc(coach.getRunId()))
                .thenReturn(List.of(proposal(coach, "CREATE_TRAINING_PLAN", "{}", false)));
        assertThatThrownBy(() -> gateway.propose(coach.getRunId(),
                new ProposalRequest("CREATE_TRAINING_PLAN", "{}", false)))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void completionHandlesSuccessApprovalRetryAndTerminalFailure() {
        AgentRun waiting = running(AgentRunType.COACH, null);
        when(runs.findForUpdate(waiting.getRunId())).thenReturn(Optional.of(waiting));
        when(proposals.findByRunIdOrderByProposalIdAsc(waiting.getRunId()))
                .thenReturn(List.of(), List.of(proposal(waiting, "CREATE_TRAINING_PLAN", "{}", false)));
        assertThatThrownBy(() -> gateway.complete(waiting.getRunId(), result(AgentRunStatus.WAITING_APPROVAL, false)))
                .isInstanceOf(IllegalStateException.class);
        gateway.complete(waiting.getRunId(), result(AgentRunStatus.WAITING_APPROVAL, false));
        assertThat(waiting.getStatus()).isEqualTo(AgentRunStatus.WAITING_APPROVAL);

        AgentRun success = running(AgentRunType.COACH, null);
        when(runs.findForUpdate(success.getRunId())).thenReturn(Optional.of(success));
        gateway.complete(success.getRunId(), result(AgentRunStatus.SUCCEEDED, false));
        assertThat(success.getStatus()).isEqualTo(AgentRunStatus.SUCCEEDED);

        AgentRun retry = running(AgentRunType.COACH, null);
        when(runs.findForUpdate(retry.getRunId())).thenReturn(Optional.of(retry));
        gateway.complete(retry.getRunId(), result(AgentRunStatus.FAILED_RETRYABLE, true));
        assertThat(retry.getStatus()).isEqualTo(AgentRunStatus.FAILED_RETRYABLE);
        verify(events).publishEvent(any(AgentRunQueuedEvent.class));

        AgentRun fatal = running(AgentRunType.COACH, null);
        when(runs.findForUpdate(fatal.getRunId())).thenReturn(Optional.of(fatal));
        gateway.complete(fatal.getRunId(), result(AgentRunStatus.FAILED_FINAL, false));
        assertThat(fatal.getStatus()).isEqualTo(AgentRunStatus.FAILED_FINAL);
        assertThatThrownBy(() -> gateway.complete(fatal.getRunId(), result(AgentRunStatus.QUEUED, false)))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void confirmationRechecksActorPayloadAndFinalWrite() {
        AgentRun run = waiting(AgentRunType.COACH, null);
        AgentActionProposal training = proposal(run, "CREATE_TRAINING_PLAN", "{\"title\":\"5K\"}", false);
        when(proposals.findForUpdate(1L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> gateway.confirm(1L, 1L, false)).isInstanceOf(IllegalArgumentException.class);

        when(proposals.findForUpdate(1L)).thenReturn(Optional.of(training));
        assertThatThrownBy(() -> gateway.confirm(1L, 2L, false)).isInstanceOf(AccessDeniedException.class);
        when(trainingPlans.existsBySourceProposalId(any())).thenReturn(false);
        when(trainingPlans.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(runs.findForUpdate(run.getRunId())).thenReturn(Optional.of(run));
        assertThat(gateway.confirm(1L, 1L, false).status()).isEqualTo("CONFIRMED");

        AgentActionProposal adminOnly = proposal(run, "REVIEW_APPEAL", "{\"decision\":\"APPROVE\"}", true);
        when(proposals.findForUpdate(2L)).thenReturn(Optional.of(adminOnly));
        assertThatThrownBy(() -> gateway.confirm(2L, 1L, false)).isInstanceOf(AccessDeniedException.class);
    }

    @Test
    void invalidTrainingAndAppealPayloadsNeverReachBusinessWrites() {
        AgentRun coach = waiting(AgentRunType.COACH, null);
        when(trainingPlans.existsBySourceProposalId(any())).thenReturn(false);
        for (String payload : List.of("{\"title\":\"\"}", "{\"title\":\"" + "x".repeat(121) + "\"}")) {
            when(proposals.findForUpdate(3L))
                    .thenReturn(Optional.of(proposal(coach, "CREATE_TRAINING_PLAN", payload, false)));
            assertThatThrownBy(() -> gateway.confirm(3L, 1L, false)).isInstanceOf(IllegalArgumentException.class);
        }

        AgentRun appealWithoutId = waiting(AgentRunType.APPEAL_REVIEW, null);
        AgentActionProposal review = proposal(
                appealWithoutId, "REVIEW_APPEAL", "{\"decision\":\"APPROVE\"}", true);
        when(proposals.findForUpdate(4L)).thenReturn(Optional.of(review));
        when(runs.findById(appealWithoutId.getRunId())).thenReturn(Optional.of(appealWithoutId));
        assertThatThrownBy(() -> gateway.confirm(4L, 9L, true)).isInstanceOf(IllegalArgumentException.class);
        verify(appealService, never()).review(any(), any());

        AgentRun appeal = waiting(AgentRunType.APPEAL_REVIEW, 10L);
        AgentActionProposal undecided = proposal(
                appeal, "REVIEW_APPEAL", "{\"decision\":\"NEED_MORE_INFO\"}", true);
        when(proposals.findForUpdate(5L)).thenReturn(Optional.of(undecided));
        when(runs.findById(appeal.getRunId())).thenReturn(Optional.of(appeal));
        assertThatThrownBy(() -> gateway.confirm(5L, 9L, true)).isInstanceOf(IllegalArgumentException.class);
    }

    private AgentRun running(AgentRunType type, Long resourceId) {
        AgentRun run = AgentRun.queued(type, type == AgentRunType.COACH ? 1L : 9L, 1L, resourceId, "{}");
        run.claim();
        return run;
    }

    private AgentRun waiting(AgentRunType type, Long resourceId) {
        AgentRun run = running(type, resourceId);
        run.waitingApproval("{}", "model", "v1", 0, 0, 0, 1);
        return run;
    }

    private AgentDtos.ToolContext context(AgentRun run) {
        return new AgentDtos.ToolContext(run.getRunId(), run.getSubjectUserId(),
                run.getSubjectResourceId(), run.getRunType());
    }

    private RunResultRequest result(AgentRunStatus status, boolean retryable) {
        return new RunResultRequest(status, "{}", "model", "v1", 1, 1, 1, 1,
                retryable ? "temporary" : "fatal", retryable);
    }

    private AgentActionProposal proposal(AgentRun run, String action, String payload, boolean admin) {
        AgentActionProposal proposal = new AgentActionProposal();
        proposal.setRunId(run.getRunId());
        proposal.setSubjectUserId(run.getSubjectUserId());
        proposal.setActionType(action);
        proposal.setPayloadJson(payload);
        proposal.setRequiresAdmin(admin);
        proposal.prePersist();
        return proposal;
    }

    private Appeal appeal(String status) {
        Appeal appeal = new Appeal();
        appeal.setUserId(1L);
        appeal.setRecordId(20L);
        appeal.setReason("reason");
        appeal.setStatus(status);
        return appeal;
    }
}

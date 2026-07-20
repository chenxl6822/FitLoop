package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.AgentMessageRequest;
import com.fitloop.agent.AgentDtos.ClaimResponse;
import com.fitloop.agent.AgentDtos.ConfirmResponse;
import com.fitloop.agent.AgentDtos.ProposalRequest;
import com.fitloop.agent.AgentDtos.ProposalResponse;
import com.fitloop.agent.AgentDtos.RunResponse;
import com.fitloop.agent.AgentDtos.RunResultRequest;
import com.fitloop.agent.AgentDtos.ToolAuditRequest;
import com.fitloop.appeal.Appeal;
import com.fitloop.appeal.AppealDtos.ReviewAppealRequest;
import com.fitloop.appeal.AppealRepository;
import com.fitloop.appeal.AppealService;
import com.fitloop.user.UserRepository;
import java.util.List;
import java.util.Map;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

@Service
public class AgentGatewayService {
    private final AgentRunRepository runs;
    private final AgentMessageRepository messages;
    private final AgentToolAuditRepository toolAudits;
    private final AgentActionProposalRepository proposals;
    private final TrainingPlanRepository trainingPlans;
    private final AppealRepository appeals;
    private final AppealService appealService;
    private final UserRepository users;
    private final ApplicationEventPublisher events;
    private final ObjectMapper objectMapper;

    public AgentGatewayService(AgentRunRepository runs, AgentMessageRepository messages,
                               AgentToolAuditRepository toolAudits, AgentActionProposalRepository proposals,
                               TrainingPlanRepository trainingPlans, AppealRepository appeals,
                               AppealService appealService, UserRepository users,
                               ApplicationEventPublisher events, ObjectMapper objectMapper) {
        this.runs = runs;
        this.messages = messages;
        this.toolAudits = toolAudits;
        this.proposals = proposals;
        this.trainingPlans = trainingPlans;
        this.appeals = appeals;
        this.appealService = appealService;
        this.users = users;
        this.events = events;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public AgentRun createCoachRun(Long userId, String objective) {
        requireUser(userId);
        String input = write(Map.of("objective", objective == null ? "" : objective));
        return queue(AgentRun.queued(AgentRunType.COACH, userId, userId, null, input));
    }

    @Transactional
    public AgentRun createAppealReview(Long adminId, Long appealId) {
        Appeal appeal = appeals.findById(appealId)
                .orElseThrow(() -> new IllegalArgumentException("Appeal does not exist"));
        if (!"pending".equalsIgnoreCase(appeal.getStatus())) {
            throw new IllegalArgumentException("Only pending appeals can be reviewed");
        }
        String input = write(Map.of("appealId", appealId));
        return queue(AgentRun.queued(AgentRunType.APPEAL_REVIEW, adminId, appeal.getUserId(), appealId, input));
    }

    private AgentRun queue(AgentRun run) {
        runs.save(run);
        events.publishEvent(new AgentRunQueuedEvent(run.getRunId(), run.getRunType(), run.getTraceId()));
        return run;
    }

    @Transactional(readOnly = true)
    public RunResponse getVisibleRun(String runId, Long actorId, boolean admin) {
        AgentRun run = requireVisible(runId, actorId, admin);
        return response(run);
    }

    @Transactional(readOnly = true)
    public List<AgentMessage> messages(String runId, Long actorId, boolean admin) {
        requireVisible(runId, actorId, admin);
        return messages.findByRunIdOrderByMessageIdAsc(runId);
    }

    @Transactional
    public ClaimResponse claim(String runId) {
        AgentRun run = lockedRun(runId);
        run.claim();
        return new ClaimResponse(run.getRunId(), run.getRunType(), run.getInputJson(),
                run.getSubjectUserId(), run.getSubjectResourceId(), run.getTraceId());
    }

    @Transactional
    public void appendMessage(String runId, AgentMessageRequest request) {
        requireRunning(runId);
        messages.save(new AgentMessage(runId, request.role(), request.content()));
    }

    @Transactional
    public void auditTool(String runId, ToolAuditRequest request) {
        requireRunning(runId);
        if (toolAudits.countByRunId(runId) >= 8) {
            throw new IllegalStateException("Agent run tool-call limit exceeded");
        }
        toolAudits.save(new AgentToolAudit(runId, request.toolName(), request.argumentsJson(),
                request.resultJson(), request.succeeded(), request.durationMs(), request.errorMessage()));
    }

    Object executeTool(AgentDtos.ToolContext context, String toolName,
                       Map<String, Object> arguments, AgentToolInvocation invocation) {
        AgentRun run = requireRunning(context.runId());
        if (!run.getSubjectUserId().equals(context.subjectUserId())
                || run.getRunType() != context.type()
                || !java.util.Objects.equals(run.getSubjectResourceId(), context.subjectResourceId())) {
            throw new org.springframework.security.access.AccessDeniedException("Delegation scope does not match run");
        }
        if (toolAudits.countByRunId(context.runId()) >= 8) {
            throw new IllegalStateException("Agent run tool-call limit exceeded");
        }
        long started = System.nanoTime();
        String argumentsJson = write(arguments);
        try {
            Object result = invocation.invoke();
            long duration = (System.nanoTime() - started) / 1_000_000;
            toolAudits.save(new AgentToolAudit(context.runId(), toolName, argumentsJson,
                    write(result), true, duration, null));
            return result;
        } catch (RuntimeException ex) {
            long duration = (System.nanoTime() - started) / 1_000_000;
            toolAudits.save(new AgentToolAudit(context.runId(), toolName, argumentsJson,
                    null, false, duration, ex.getMessage()));
            throw ex;
        }
    }

    @Transactional(readOnly = true)
    public AgentRun runForDelegation(String runId) {
        AgentRun run = runs.findById(runId).orElseThrow(() -> new IllegalArgumentException("Agent run does not exist"));
        if (run.getStatus() != AgentRunStatus.QUEUED && run.getStatus() != AgentRunStatus.FAILED_RETRYABLE
                && run.getStatus() != AgentRunStatus.RUNNING) {
            throw new IllegalStateException("Agent run is not executable");
        }
        return run;
    }

    @Transactional
    public ProposalResponse propose(String runId, ProposalRequest request) {
        AgentRun run = requireRunning(runId);
        if (!proposals.findByRunIdOrderByProposalIdAsc(runId).isEmpty()) {
            throw new IllegalStateException("Agent run already has an action proposal");
        }
        validateProposal(run, request);
        AgentActionProposal proposal = new AgentActionProposal();
        proposal.setRunId(runId);
        proposal.setSubjectUserId(run.getSubjectUserId());
        proposal.setActionType(request.actionType());
        proposal.setPayloadJson(request.payloadJson());
        proposal.setRequiresAdmin(request.requiresAdmin());
        return proposalResponse(proposals.save(proposal));
    }

    @Transactional
    public void complete(String runId, RunResultRequest request) {
        AgentRun run = lockedRun(runId);
        if (request.status() == AgentRunStatus.WAITING_APPROVAL) {
            if (proposals.findByRunIdOrderByProposalIdAsc(runId).isEmpty()) {
                throw new IllegalStateException("WAITING_APPROVAL requires an action proposal");
            }
            run.waitingApproval(request.resultJson(), request.model(), request.promptVersion(),
                    request.inputTokens(), request.outputTokens(), request.costMicros(), request.latencyMs());
        } else if (request.status() == AgentRunStatus.SUCCEEDED) {
            run.succeed(request.resultJson(), request.model(), request.promptVersion(),
                    request.inputTokens(), request.outputTokens(), request.costMicros(), request.latencyMs());
        } else if (request.status() == AgentRunStatus.FAILED_RETRYABLE
                || request.status() == AgentRunStatus.FAILED_FINAL) {
            run.fail(request.errorMessage(), request.retryable());
            if (run.getStatus() == AgentRunStatus.FAILED_RETRYABLE) {
                events.publishEvent(new AgentRunQueuedEvent(run.getRunId(), run.getRunType(), run.getTraceId()));
            }
        } else {
            throw new IllegalArgumentException("Unsupported completion status");
        }
    }

    @Transactional
    public ConfirmResponse confirm(Long proposalId, Long actorId, boolean admin) {
        AgentActionProposal proposal = proposals.findForUpdate(proposalId)
                .orElseThrow(() -> new IllegalArgumentException("Proposal does not exist"));
        if (proposal.isRequiresAdmin()) {
            if (!admin) throw new org.springframework.security.access.AccessDeniedException("Admin approval required");
        } else if (!proposal.getSubjectUserId().equals(actorId)) {
            throw new org.springframework.security.access.AccessDeniedException("Proposal does not belong to user");
        }

        Long resourceId;
        if ("CREATE_TRAINING_PLAN".equals(proposal.getActionType())) {
            resourceId = createTrainingPlan(proposal);
        } else if ("REVIEW_APPEAL".equals(proposal.getActionType())) {
            resourceId = reviewAppeal(proposal);
        } else {
            throw new IllegalArgumentException("Unsupported proposal action");
        }
        proposal.confirm(actorId);
        AgentRun run = lockedRun(proposal.getRunId());
        run.approve();
        return new ConfirmResponse(proposalId, proposal.getStatus(), resourceId);
    }

    private Long createTrainingPlan(AgentActionProposal proposal) {
        if (trainingPlans.existsBySourceProposalId(proposal.getProposalId())) {
            throw new IllegalStateException("Training plan has already been created");
        }
        Map<String, Object> payload = readMap(proposal.getPayloadJson());
        String title = String.valueOf(payload.getOrDefault("title", "FitLoop training plan"));
        if (title.isBlank() || title.length() > 120) throw new IllegalArgumentException("Invalid training plan title");
        TrainingPlan plan = new TrainingPlan();
        plan.setUserId(proposal.getSubjectUserId());
        plan.setSourceProposalId(proposal.getProposalId());
        plan.setTitle(title);
        plan.setPlanJson(proposal.getPayloadJson());
        return trainingPlans.save(plan).getPlanId();
    }

    private Long reviewAppeal(AgentActionProposal proposal) {
        AgentRun run = runs.findById(proposal.getRunId()).orElseThrow();
        if (run.getSubjectResourceId() == null) throw new IllegalArgumentException("Appeal run has no appeal id");
        Map<String, Object> payload = readMap(proposal.getPayloadJson());
        String decision = String.valueOf(payload.get("decision"));
        String status = switch (decision) {
            case "APPROVE" -> "approved";
            case "REJECT" -> "rejected";
            default -> throw new IllegalArgumentException("Only APPROVE or REJECT can be confirmed");
        };
        appealService.review(run.getSubjectResourceId(),
                new ReviewAppealRequest(status, String.valueOf(payload.getOrDefault("reason", "Agent-assisted review"))));
        return run.getSubjectResourceId();
    }

    private void validateProposal(AgentRun run, ProposalRequest request) {
        readMap(request.payloadJson());
        if (run.getRunType() == AgentRunType.COACH
                && (!"CREATE_TRAINING_PLAN".equals(request.actionType()) || request.requiresAdmin())) {
            throw new IllegalArgumentException("Coach may only propose a user-approved training plan");
        }
        if (run.getRunType() == AgentRunType.APPEAL_REVIEW
                && (!"REVIEW_APPEAL".equals(request.actionType()) || !request.requiresAdmin())) {
            throw new IllegalArgumentException("Appeal agent may only propose an admin-approved review");
        }
    }

    private AgentRun requireRunning(String runId) {
        AgentRun run = runs.findById(runId).orElseThrow(() -> new IllegalArgumentException("Agent run does not exist"));
        if (run.getStatus() != AgentRunStatus.RUNNING) throw new IllegalStateException("Agent run is not RUNNING");
        return run;
    }

    private AgentRun lockedRun(String runId) {
        return runs.findForUpdate(runId).orElseThrow(() -> new IllegalArgumentException("Agent run does not exist"));
    }

    private AgentRun requireVisible(String runId, Long actorId, boolean admin) {
        AgentRun run = runs.findById(runId).orElseThrow(() -> new IllegalArgumentException("Agent run does not exist"));
        if (run.getRunType() == AgentRunType.APPEAL_REVIEW && !admin) {
            throw new org.springframework.security.access.AccessDeniedException("Appeal review runs are admin-only");
        }
        if (!admin && !run.getRequestedByUserId().equals(actorId) && !run.getSubjectUserId().equals(actorId)) {
            throw new org.springframework.security.access.AccessDeniedException("Agent run is not visible to user");
        }
        return run;
    }

    private void requireUser(Long userId) {
        if (!users.existsById(userId)) throw new IllegalArgumentException("User does not exist");
    }

    private RunResponse response(AgentRun run) {
        return new RunResponse(run.getRunId(), run.getRunType(), run.getStatus(), run.getTraceId(),
                run.getResultJson(), run.getModel(), run.getPromptVersion(), run.getInputTokens(),
                run.getOutputTokens(), run.getCostMicros(), run.getLatencyMs(), run.getRetryCount(),
                run.getErrorMessage(), run.getCreatedAt(), run.getStartedAt(), run.getCompletedAt(),
                proposals.findByRunIdOrderByProposalIdAsc(run.getRunId()).stream().map(this::proposalResponse).toList());
    }

    private ProposalResponse proposalResponse(AgentActionProposal proposal) {
        return new ProposalResponse(proposal.getProposalId(), proposal.getActionType(), proposal.getPayloadJson(),
                proposal.getStatus(), proposal.isRequiresAdmin(), proposal.getExpiresAt(), proposal.getConfirmedAt());
    }

    private String write(Object value) {
        try { return objectMapper.writeValueAsString(value); }
        catch (Exception ex) { throw new IllegalStateException("Could not serialize agent input", ex); }
    }

    private Map<String, Object> readMap(String json) {
        try { return objectMapper.readValue(json, new TypeReference<>() { }); }
        catch (Exception ex) { throw new IllegalArgumentException("Proposal payload must be valid JSON", ex); }
    }
}

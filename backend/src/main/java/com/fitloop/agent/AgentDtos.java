package com.fitloop.agent;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;

public final class AgentDtos {
    private AgentDtos() { }

    public record CoachRunRequest(@Size(max = 500) String objective) { }
    public record RunCreatedResponse(String runId, AgentRunType type, AgentRunStatus status, String traceId) { }
    public record RunResponse(String runId, AgentRunType type, AgentRunStatus status, String traceId,
                              String resultJson, String model, String promptVersion, Integer inputTokens,
                              Integer outputTokens, Long costMicros, Long latencyMs, Integer retryCount,
                              String errorMessage, Instant createdAt, Instant startedAt, Instant completedAt,
                              List<ProposalResponse> proposals) { }
    public record MessageResponse(Long messageId, String role, String content, Instant createdAt) { }
    public record ProposalResponse(Long proposalId, String actionType, String payloadJson, String status,
                                   boolean requiresAdmin, Instant expiresAt, Long decidedByUserId,
                                   Instant decidedAt, String decisionNote) { }
    public record ConfirmResponse(Long proposalId, String status, Long affectedResourceId) { }
    public record RejectProposalRequest(@Size(max = 500) String reason) { }
    public record DelegationTokenResponse(String accessToken, long expiresIn) { }
    public record ClaimResponse(String runId, AgentRunType type, String inputJson, Long subjectUserId,
                                Long subjectResourceId, String traceId) { }
    public record AgentMessageRequest(@NotBlank String role, @NotBlank @Size(max = 20000) String content) { }
    public record ToolAuditRequest(@NotBlank String toolName, @NotBlank String argumentsJson,
                                   String resultJson, boolean succeeded, Long durationMs, String errorMessage) { }
    public record ProposalRequest(@NotBlank String actionType, @NotBlank String payloadJson,
                                  boolean requiresAdmin) { }
    public record RunResultRequest(@NotNull AgentRunStatus status, String resultJson,
                                   @NotBlank String model, @NotBlank String promptVersion,
                                   @Min(0) int inputTokens, @Min(0) int outputTokens,
                                   @Min(0) long costMicros, @Min(0) long latencyMs,
                                   String errorMessage, boolean retryable) { }
    public record ToolContext(String runId, Long subjectUserId, Long subjectResourceId, AgentRunType type) { }
    public record TrainingLoadResponse(int workoutCount, double distanceKm, double durationHours,
                                       double acuteLoad, String assessment) { }
    public record CompletionResponse(String metric, double target, double completed, double rate) { }

    public record AdminRunSummary(String runId, AgentRunType type, AgentRunStatus status,
                                  Long requestedByUserId, Long subjectUserId, Long subjectResourceId,
                                  String traceId, String model, String promptVersion,
                                  Long latencyMs, String errorMessage, Instant createdAt,
                                  Instant completedAt) {
        static AdminRunSummary from(AgentRun run) {
            return new AdminRunSummary(run.getRunId(), run.getRunType(), run.getStatus(),
                    run.getRequestedByUserId(), run.getSubjectUserId(), run.getSubjectResourceId(),
                    run.getTraceId(), run.getModel(), run.getPromptVersion(), run.getLatencyMs(),
                    run.getErrorMessage(), run.getCreatedAt(), run.getCompletedAt());
        }
    }

    public record AdminRunPageResponse(List<AdminRunSummary> items, int page, int size,
                                       long totalElements, int totalPages) { }

    public record ToolAuditResponse(Long auditId, String toolName, String argumentsJson,
                                    String resultJson, boolean succeeded, Long durationMs,
                                    String errorMessage, Instant createdAt) {
        static ToolAuditResponse from(AgentToolAudit audit) {
            return new ToolAuditResponse(audit.getAuditId(), audit.getToolName(), audit.getArgumentsJson(),
                    audit.getResultJson(), audit.isSucceeded(), audit.getDurationMs(),
                    audit.getErrorMessage(), audit.getCreatedAt());
        }
    }

    public record RunAuditResponse(RunResponse run, List<MessageResponse> messages,
                                   List<ToolAuditResponse> toolCalls) { }
}

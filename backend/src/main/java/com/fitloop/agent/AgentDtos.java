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
                                   boolean requiresAdmin, Instant expiresAt, Instant confirmedAt) { }
    public record ConfirmResponse(Long proposalId, String status, Long affectedResourceId) { }
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
}

package com.fitloop.agent;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;

@Entity
public class AgentRun {
    @Id
    @Column(length = 36)
    private String runId;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private AgentRunType runType;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    private AgentRunStatus status = AgentRunStatus.QUEUED;
    @Column(nullable = false)
    private Long requestedByUserId;
    @Column(nullable = false)
    private Long subjectUserId;
    private Long subjectResourceId;
    @Column(nullable = false, unique = true, length = 36)
    private String traceId;
    @Lob
    @Column(nullable = false)
    private String inputJson;
    @Lob
    private String resultJson;
    @Column(length = 64)
    private String model;
    @Column(length = 64)
    private String promptVersion;
    private Integer inputTokens;
    private Integer outputTokens;
    private Long costMicros;
    private Long latencyMs;
    private Integer retryCount = 0;
    @Column(length = 500)
    private String errorMessage;
    private Instant createdAt;
    private Instant updatedAt;
    private Instant startedAt;
    private Instant completedAt;
    @Version
    private long version;

    public AgentRun() { }

    public static AgentRun queued(AgentRunType type, Long requestedBy, Long subjectUser,
                                  Long subjectResourceId, String inputJson) {
        AgentRun run = new AgentRun();
        run.runId = UUID.randomUUID().toString();
        run.traceId = UUID.randomUUID().toString();
        run.runType = type;
        run.requestedByUserId = requestedBy;
        run.subjectUserId = subjectUser;
        run.subjectResourceId = subjectResourceId;
        run.inputJson = inputJson;
        return run;
    }

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void preUpdate() { updatedAt = Instant.now(); }

    public void claim() {
        if (status != AgentRunStatus.QUEUED && status != AgentRunStatus.FAILED_RETRYABLE) {
            throw new IllegalStateException("Agent run cannot be claimed from " + status);
        }
        status = AgentRunStatus.RUNNING;
        startedAt = Instant.now();
        errorMessage = null;
    }

    public void waitingApproval(String resultJson, String model, String promptVersion,
                                int inputTokens, int outputTokens, long costMicros, long latencyMs) {
        requireRunning();
        status = AgentRunStatus.WAITING_APPROVAL;
        recordResult(resultJson, model, promptVersion, inputTokens, outputTokens, costMicros, latencyMs);
    }

    public void succeed(String resultJson, String model, String promptVersion,
                        int inputTokens, int outputTokens, long costMicros, long latencyMs) {
        requireRunning();
        status = AgentRunStatus.SUCCEEDED;
        completedAt = Instant.now();
        recordResult(resultJson, model, promptVersion, inputTokens, outputTokens, costMicros, latencyMs);
    }

    public void fail(String error, boolean retryable) {
        requireRunning();
        retryCount++;
        status = retryable && retryCount < 3 ? AgentRunStatus.FAILED_RETRYABLE : AgentRunStatus.FAILED_FINAL;
        errorMessage = error == null ? "Agent execution failed" : error.substring(0, Math.min(error.length(), 500));
        if (status == AgentRunStatus.FAILED_FINAL) completedAt = Instant.now();
    }

    public void approve() {
        if (status != AgentRunStatus.WAITING_APPROVAL) {
            throw new IllegalStateException("Agent run is not waiting for approval");
        }
        status = AgentRunStatus.SUCCEEDED;
        completedAt = Instant.now();
    }

    public void rejectApproval() {
        if (status != AgentRunStatus.WAITING_APPROVAL) {
            throw new IllegalStateException("Agent run is not waiting for approval");
        }
        status = AgentRunStatus.SUCCEEDED;
        completedAt = Instant.now();
    }

    private void requireRunning() {
        if (status != AgentRunStatus.RUNNING) throw new IllegalStateException("Agent run is not RUNNING");
    }

    private void recordResult(String resultJson, String model, String promptVersion,
                              int inputTokens, int outputTokens, long costMicros, long latencyMs) {
        this.resultJson = resultJson;
        this.model = model;
        this.promptVersion = promptVersion;
        this.inputTokens = inputTokens;
        this.outputTokens = outputTokens;
        this.costMicros = costMicros;
        this.latencyMs = latencyMs;
    }

    public String getRunId() { return runId; }
    public AgentRunType getRunType() { return runType; }
    public AgentRunStatus getStatus() { return status; }
    public Long getRequestedByUserId() { return requestedByUserId; }
    public Long getSubjectUserId() { return subjectUserId; }
    public Long getSubjectResourceId() { return subjectResourceId; }
    public String getTraceId() { return traceId; }
    public String getInputJson() { return inputJson; }
    public String getResultJson() { return resultJson; }
    public String getModel() { return model; }
    public String getPromptVersion() { return promptVersion; }
    public Integer getInputTokens() { return inputTokens; }
    public Integer getOutputTokens() { return outputTokens; }
    public Long getCostMicros() { return costMicros; }
    public Long getLatencyMs() { return latencyMs; }
    public Integer getRetryCount() { return retryCount; }
    public String getErrorMessage() { return errorMessage; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getStartedAt() { return startedAt; }
    public Instant getCompletedAt() { return completedAt; }
}

package com.fitloop.agent;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import java.time.Instant;

@Entity
public class AgentToolAudit {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long auditId;
    @Column(nullable = false, length = 36)
    private String runId;
    @Column(nullable = false, length = 64)
    private String toolName;
    @Lob @Column(nullable = false)
    private String argumentsJson;
    @Lob
    private String resultJson;
    @Column(nullable = false)
    private boolean succeeded;
    private Long durationMs;
    @Column(length = 500)
    private String errorMessage;
    private Instant createdAt;

    @PrePersist void prePersist() { createdAt = Instant.now(); }
    public AgentToolAudit() { }
    public AgentToolAudit(String runId, String toolName, String argumentsJson, String resultJson,
                          boolean succeeded, Long durationMs, String errorMessage) {
        this.runId = runId;
        this.toolName = toolName;
        this.argumentsJson = argumentsJson;
        this.resultJson = resultJson;
        this.succeeded = succeeded;
        this.durationMs = durationMs;
        this.errorMessage = errorMessage;
    }
    public Long getAuditId() { return auditId; }
    public String getRunId() { return runId; }
    public String getToolName() { return toolName; }
    public String getArgumentsJson() { return argumentsJson; }
    public String getResultJson() { return resultJson; }
    public boolean isSucceeded() { return succeeded; }
    public Long getDurationMs() { return durationMs; }
    public String getErrorMessage() { return errorMessage; }
    public Instant getCreatedAt() { return createdAt; }
}

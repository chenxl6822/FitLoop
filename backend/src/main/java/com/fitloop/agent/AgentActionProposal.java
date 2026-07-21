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
public class AgentActionProposal {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long proposalId;
    @Column(nullable = false, length = 36)
    private String runId;
    @Column(nullable = false)
    private Long subjectUserId;
    @Column(nullable = false, length = 64)
    private String actionType;
    @Lob @Column(nullable = false)
    private String payloadJson;
    @Column(nullable = false, length = 24)
    private String status = "PENDING";
    @Column(nullable = false)
    private boolean requiresAdmin;
    private Instant expiresAt;
    private Long confirmedByUserId;
    private Instant confirmedAt;
    @Column(length = 500)
    private String decisionNote;
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
        if (expiresAt == null) expiresAt = createdAt.plusSeconds(24 * 60 * 60);
    }

    public void confirm(Long actorUserId) {
        assertActionable();
        status = "CONFIRMED";
        confirmedByUserId = actorUserId;
        confirmedAt = Instant.now();
    }

    public void reject(Long actorUserId, String note) {
        assertActionable();
        status = "REJECTED";
        confirmedByUserId = actorUserId;
        confirmedAt = Instant.now();
        decisionNote = note == null ? null : note.trim();
    }

    public void assertActionable() {
        if (!"PENDING".equals(status)) throw new IllegalStateException("Proposal has already been handled");
        if (Instant.now().isAfter(expiresAt)) throw new IllegalStateException("Proposal has expired");
    }

    public Long getProposalId() { return proposalId; }
    public String getRunId() { return runId; }
    public Long getSubjectUserId() { return subjectUserId; }
    public String getActionType() { return actionType; }
    public String getPayloadJson() { return payloadJson; }
    public String getStatus() { return status; }
    public boolean isRequiresAdmin() { return requiresAdmin; }
    public Instant getExpiresAt() { return expiresAt; }
    public Long getConfirmedByUserId() { return confirmedByUserId; }
    public Instant getConfirmedAt() { return confirmedAt; }
    public String getDecisionNote() { return decisionNote; }
    public Instant getCreatedAt() { return createdAt; }
    public void setRunId(String runId) { this.runId = runId; }
    public void setSubjectUserId(Long subjectUserId) { this.subjectUserId = subjectUserId; }
    public void setActionType(String actionType) { this.actionType = actionType; }
    public void setPayloadJson(String payloadJson) { this.payloadJson = payloadJson; }
    public void setRequiresAdmin(boolean requiresAdmin) { this.requiresAdmin = requiresAdmin; }
}

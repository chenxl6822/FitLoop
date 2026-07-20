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
public class TrainingPlan {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long planId;
    @Column(nullable = false)
    private Long userId;
    @Column(nullable = false)
    private Long sourceProposalId;
    @Column(nullable = false, length = 120)
    private String title;
    @Lob @Column(nullable = false)
    private String planJson;
    @Column(nullable = false, length = 24)
    private String status = "ACTIVE";
    private Instant createdAt;

    @PrePersist void prePersist() { createdAt = Instant.now(); }
    public Long getPlanId() { return planId; }
    public Long getUserId() { return userId; }
    public Long getSourceProposalId() { return sourceProposalId; }
    public String getTitle() { return title; }
    public String getPlanJson() { return planJson; }
    public String getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
    public void setUserId(Long userId) { this.userId = userId; }
    public void setSourceProposalId(Long sourceProposalId) { this.sourceProposalId = sourceProposalId; }
    public void setTitle(String title) { this.title = title; }
    public void setPlanJson(String planJson) { this.planJson = planJson; }
}

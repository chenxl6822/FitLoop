package com.fitloop.audit;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "admin_audit_log")
public class AdminAuditLog {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long auditId;
    @Column(nullable = false)
    private Long actorUserId;
    @Column(nullable = false, length = 64)
    private String action;
    @Column(nullable = false, length = 64)
    private String resourceType;
    @Column(nullable = false, length = 64)
    private String resourceId;
    @Lob
    private String detailsJson;
    @Column(nullable = false)
    private Instant createdAt;

    protected AdminAuditLog() { }

    public AdminAuditLog(Long actorUserId, String action, String resourceType,
                         String resourceId, String detailsJson) {
        this.actorUserId = actorUserId;
        this.action = action;
        this.resourceType = resourceType;
        this.resourceId = resourceId;
        this.detailsJson = detailsJson;
    }

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
    }

    public Long getAuditId() { return auditId; }
    public Long getActorUserId() { return actorUserId; }
    public String getAction() { return action; }
    public String getResourceType() { return resourceType; }
    public String getResourceId() { return resourceId; }
    public String getDetailsJson() { return detailsJson; }
    public Instant getCreatedAt() { return createdAt; }
}

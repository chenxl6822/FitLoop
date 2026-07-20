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
public class AgentMessage {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long messageId;
    @Column(nullable = false, length = 36)
    private String runId;
    @Column(nullable = false, length = 16)
    private String role;
    @Lob @Column(nullable = false)
    private String content;
    private Instant createdAt;

    @PrePersist void prePersist() { createdAt = Instant.now(); }
    public AgentMessage() { }
    public AgentMessage(String runId, String role, String content) {
        this.runId = runId;
        this.role = role;
        this.content = content;
    }
    public Long getMessageId() { return messageId; }
    public String getRunId() { return runId; }
    public String getRole() { return role; }
    public String getContent() { return content; }
    public Instant getCreatedAt() { return createdAt; }
}

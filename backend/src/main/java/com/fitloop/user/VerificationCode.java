package com.fitloop.user;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(indexes = {
        @Index(name = "idx_verification_target_channel_purpose", columnList = "target,channel,purpose,createdAt"),
        @Index(name = "idx_verification_request_ip", columnList = "requestIpHash,createdAt")
})
public class VerificationCode {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 128)
    private String target;

    @Column(nullable = false, length = 16)
    private String channel;

    @Column(nullable = false, length = 32)
    private String purpose;

    @Column(nullable = false, length = 128)
    private String codeHash;

    @Column(nullable = false)
    private Instant expiresAt;

    private boolean used;

    private int attemptCount;

    @Column(length = 128)
    private String requestIpHash;

    private Instant createdAt;

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getTarget() { return target; }
    public void setTarget(String target) { this.target = target; }
    public String getChannel() { return channel; }
    public void setChannel(String channel) { this.channel = channel; }
    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }
    public String getCodeHash() { return codeHash; }
    public void setCodeHash(String codeHash) { this.codeHash = codeHash; }
    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }
    public boolean isUsed() { return used; }
    public void setUsed(boolean used) { this.used = used; }
    public int getAttemptCount() { return attemptCount; }
    public void setAttemptCount(int attemptCount) { this.attemptCount = attemptCount; }
    public String getRequestIpHash() { return requestIpHash; }
    public void setRequestIpHash(String requestIpHash) { this.requestIpHash = requestIpHash; }
    public Instant getCreatedAt() { return createdAt; }
}

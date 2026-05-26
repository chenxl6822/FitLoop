package com.fitloop.social;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import java.time.Instant;

@Entity
public class UserFriend {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long friendId;
    private Long userId;
    private Long friendUserId;
    private String status = "active";
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
    }

    public Long getFriendId() { return friendId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public Long getFriendUserId() { return friendUserId; }
    public void setFriendUserId(Long friendUserId) { this.friendUserId = friendUserId; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
}

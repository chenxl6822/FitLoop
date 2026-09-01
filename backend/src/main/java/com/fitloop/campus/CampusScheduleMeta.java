package com.fitloop.campus;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "campus_schedule_meta")
public class CampusScheduleMeta {
    @Id
    private Long userId;

    @Column(nullable = false, length = 16)
    private String termYear;

    @Column(nullable = false, length = 16)
    private String termCode;

    @Column(nullable = false)
    private Instant lastSyncedAt;

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getTermYear() { return termYear; }
    public void setTermYear(String termYear) { this.termYear = termYear; }
    public String getTermCode() { return termCode; }
    public void setTermCode(String termCode) { this.termCode = termCode; }
    public Instant getLastSyncedAt() { return lastSyncedAt; }
    public void setLastSyncedAt(Instant lastSyncedAt) { this.lastSyncedAt = lastSyncedAt; }
}

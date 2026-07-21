package com.fitloop.sport;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Version;
import java.time.Instant;
import org.hibernate.Length;

@Entity
public class SportRecord {
    public static final int STATUS_DRAFT = 0;
    public static final int STATUS_VALID = 1;
    public static final int STATUS_ABNORMAL = 2;
    public static final int STATUS_APPEALING = 3;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long recordId;

    @Column(nullable = false)
    private Long userId;

    @Column(nullable = false, unique = true, length = 64)
    private String sessionId;

    @Column(nullable = false, length = 32)
    private String sportType;

    @Column(nullable = false, length = 32)
    private String checkinMode;

    private long durationSeconds;
    private double distanceKm;
    private double calorie;

    @Column(length = Length.LONG32)
    private String trackJson = "[]";

    @Column(length = 500)
    private String note;

    private String photoUrl;
    private int status = STATUS_DRAFT;
    private String abnormalReason;
    private Instant startedAt;
    private Instant endedAt;
    private Instant createdAt;
    private Instant updatedAt;

    @Version
    private long version;

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }

    public Long getRecordId() { return recordId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getSessionId() { return sessionId; }
    public void setSessionId(String sessionId) { this.sessionId = sessionId; }
    public String getSportType() { return sportType; }
    public void setSportType(String sportType) { this.sportType = sportType; }
    public String getCheckinMode() { return checkinMode; }
    public void setCheckinMode(String checkinMode) { this.checkinMode = checkinMode; }
    public long getDurationSeconds() { return durationSeconds; }
    public void setDurationSeconds(long durationSeconds) { this.durationSeconds = durationSeconds; }
    public double getDistanceKm() { return distanceKm; }
    public void setDistanceKm(double distanceKm) { this.distanceKm = distanceKm; }
    public double getCalorie() { return calorie; }
    public void setCalorie(double calorie) { this.calorie = calorie; }
    public String getTrackJson() { return trackJson; }
    public void setTrackJson(String trackJson) { this.trackJson = trackJson; }
    public String getPhotoUrl() { return photoUrl; }
    public void setPhotoUrl(String photoUrl) { this.photoUrl = photoUrl; }
    public String getNote() { return note; }
    public void setNote(String note) { this.note = note; }
    public int getStatus() { return status; }
    public void setStatus(int status) { this.status = status; }
    public WorkoutStatus workoutStatus() { return WorkoutStatus.fromCode(status); }
    public void finishAs(WorkoutStatus target) {
        if (workoutStatus() != WorkoutStatus.DRAFT) {
            throw new IllegalStateException("Only a draft workout can be finished");
        }
        if (target != WorkoutStatus.VALID && target != WorkoutStatus.ABNORMAL) {
            throw new IllegalArgumentException("Invalid finish state: " + target);
        }
        status = target.code();
    }
    public String getAbnormalReason() { return abnormalReason; }
    public void setAbnormalReason(String abnormalReason) { this.abnormalReason = abnormalReason; }
    public Instant getStartedAt() { return startedAt; }
    public void setStartedAt(Instant startedAt) { this.startedAt = startedAt; }
    public Instant getEndedAt() { return endedAt; }
    public void setEndedAt(Instant endedAt) { this.endedAt = endedAt; }
    public long getVersion() { return version; }
}

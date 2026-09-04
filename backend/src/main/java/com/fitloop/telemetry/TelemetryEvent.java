package com.fitloop.telemetry;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "telemetry_event")
public class TelemetryEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long eventId;
    @Column(nullable = false)
    private Long userId;
    @Column(nullable = false, length = 64)
    private String eventName;
    private Instant clientTimestamp;
    @Column(nullable = false, length = 2000)
    private String propsJson;
    @Column(nullable = false)
    private Instant createdAt;

    protected TelemetryEvent() { }

    public TelemetryEvent(Long userId, String eventName, Instant clientTimestamp, String propsJson) {
        this.userId = userId;
        this.eventName = eventName;
        this.clientTimestamp = clientTimestamp;
        this.propsJson = propsJson;
    }

    @PrePersist
    void prePersist() {
        createdAt = Instant.now();
    }

    public Long getEventId() { return eventId; }
    public Long getUserId() { return userId; }
    public String getEventName() { return eventName; }
    public Instant getClientTimestamp() { return clientTimestamp; }
    public String getPropsJson() { return propsJson; }
    public Instant getCreatedAt() { return createdAt; }
}

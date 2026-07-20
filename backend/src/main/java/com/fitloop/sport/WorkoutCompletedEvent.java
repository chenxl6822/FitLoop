package com.fitloop.sport;

import java.time.Instant;

public record WorkoutCompletedEvent(Long recordId, Long userId, long durationSeconds,
                                    double distanceKm, double calorie, Instant occurredAt) { }

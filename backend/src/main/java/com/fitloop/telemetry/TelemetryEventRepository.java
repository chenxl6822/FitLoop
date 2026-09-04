package com.fitloop.telemetry;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TelemetryEventRepository extends JpaRepository<TelemetryEvent, Long> {
}

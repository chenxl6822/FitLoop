CREATE TABLE telemetry_event (
    event_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_name VARCHAR(64) NOT NULL,
    client_timestamp TIMESTAMP(6) NULL,
    props_json VARCHAR(2000) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    INDEX idx_telemetry_user_created (user_id, created_at),
    INDEX idx_telemetry_name_created (event_name, created_at)
);

ALTER TABLE sport_record
    ADD COLUMN version BIGINT NOT NULL DEFAULT 0;

CREATE TABLE sport_track_point (
    id BIGINT NOT NULL AUTO_INCREMENT,
    record_id BIGINT NOT NULL,
    sequence_no INT NOT NULL,
    latitude DOUBLE NOT NULL,
    longitude DOUBLE NOT NULL,
    accuracy DOUBLE NOT NULL,
    recorded_at DATETIME(6) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_track_record_sequence (record_id, sequence_no),
    KEY idx_track_record_time (record_id, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE idempotency_record (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    operation VARCHAR(32) NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    resource_id BIGINT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_idempotency_user_operation_key (user_id, operation, idempotency_key),
    KEY idx_idempotency_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE outbox_event (
    id BIGINT NOT NULL AUTO_INCREMENT,
    event_type VARCHAR(64) NOT NULL,
    aggregate_id VARCHAR(64) NOT NULL,
    payload LONGTEXT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    available_at DATETIME(6) NOT NULL,
    processed_at DATETIME(6) NULL,
    attempts INT NOT NULL DEFAULT 0,
    last_error VARCHAR(500) NULL,
    PRIMARY KEY (id),
    KEY idx_outbox_pending (processed_at, available_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

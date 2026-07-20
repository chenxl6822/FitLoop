CREATE TABLE IF NOT EXISTS user_info (
    user_id BIGINT NOT NULL AUTO_INCREMENT,
    phone VARCHAR(64) NULL,
    email VARCHAR(64) NULL,
    password_hash VARCHAR(255) NOT NULL,
    nickname VARCHAR(255) NULL,
    avatar_url VARCHAR(255) NULL,
    gender VARCHAR(255) NULL,
    grade VARCHAR(255) NULL,
    college VARCHAR(255) NULL,
    points INT NOT NULL DEFAULT 0,
    level INT NOT NULL DEFAULT 1,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uk_user_info_phone (phone),
    UNIQUE KEY uk_user_info_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sport_record (
    record_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    sport_type VARCHAR(32) NOT NULL,
    checkin_mode VARCHAR(32) NOT NULL,
    duration_seconds BIGINT NOT NULL DEFAULT 0,
    distance_km DOUBLE NOT NULL DEFAULT 0,
    calorie DOUBLE NOT NULL DEFAULT 0,
    track_json LONGTEXT NULL,
    note VARCHAR(500) NULL,
    photo_url VARCHAR(255) NULL,
    status INT NOT NULL DEFAULT 0,
    abnormal_reason VARCHAR(255) NULL,
    started_at DATETIME(6) NULL,
    ended_at DATETIME(6) NULL,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (record_id),
    UNIQUE KEY uk_sport_record_session (session_id),
    KEY idx_sport_user_started (user_id, started_at),
    KEY idx_sport_status_started (status, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sport_target (
    target_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    period_type VARCHAR(255) NULL,
    metric VARCHAR(255) NULL,
    target_value DOUBLE NOT NULL DEFAULT 0,
    completed_value DOUBLE NOT NULL DEFAULT 0,
    start_date DATE NULL,
    end_date DATE NULL,
    status VARCHAR(255) NULL,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (target_id),
    KEY idx_target_user_status (user_id, status, start_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS user_friend (
    friend_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    friend_user_id BIGINT NULL,
    status VARCHAR(255) NULL,
    created_at DATETIME(6) NULL,
    PRIMARY KEY (friend_id),
    UNIQUE KEY uk_friend_pair (user_id, friend_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS health_data (
    health_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    weight_kg DOUBLE NULL,
    sleep_hours DOUBLE NULL,
    diet_note VARCHAR(255) NULL,
    data_date DATE NULL,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (health_id),
    KEY idx_health_user_date (user_id, data_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS reminder_config (
    remind_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    type VARCHAR(255) NULL,
    remind_time TIME(6) NULL,
    cycle VARCHAR(255) NULL,
    enabled BIT NOT NULL DEFAULT 1,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (remind_id),
    KEY idx_reminder_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS appeal (
    appeal_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    record_id BIGINT NOT NULL,
    reason LONGTEXT NOT NULL,
    evidence_url VARCHAR(255) NULL,
    status VARCHAR(255) NULL,
    review_note VARCHAR(255) NULL,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (appeal_id),
    KEY idx_appeal_user_status (user_id, status),
    KEY idx_appeal_record (record_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS feedback (
    feedback_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    type VARCHAR(50) NOT NULL,
    content VARCHAR(2000) NOT NULL,
    contact VARCHAR(200) NULL,
    status VARCHAR(20) NOT NULL,
    admin_note VARCHAR(1000) NULL,
    created_at DATETIME(6) NULL,
    updated_at DATETIME(6) NULL,
    PRIMARY KEY (feedback_id),
    KEY idx_feedback_user_created (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS target_reminder_read (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NULL,
    target_id BIGINT NULL,
    acknowledged_at DATETIME(6) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_target_reminder_read (user_id, target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sms_code (
    id BIGINT NOT NULL AUTO_INCREMENT,
    phone VARCHAR(20) NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    used BIT NOT NULL DEFAULT 0,
    created_at DATETIME(6) NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS verification_code (
    id BIGINT NOT NULL AUTO_INCREMENT,
    target VARCHAR(128) NOT NULL,
    channel VARCHAR(16) NOT NULL,
    purpose VARCHAR(32) NOT NULL,
    code_hash VARCHAR(128) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    used BIT NOT NULL DEFAULT 0,
    attempt_count INT NOT NULL DEFAULT 0,
    request_ip_hash VARCHAR(128) NULL,
    created_at DATETIME(6) NULL,
    PRIMARY KEY (id),
    KEY idx_verification_target_channel_purpose (target, channel, purpose, created_at),
    KEY idx_verification_request_ip (request_ip_hash, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

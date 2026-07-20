ALTER TABLE user_info
    ADD COLUMN role VARCHAR(16) NOT NULL DEFAULT 'USER';

CREATE TABLE refresh_token (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    family_id VARCHAR(36) NOT NULL,
    issued_at DATETIME(6) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6) NULL,
    replaced_by_hash VARCHAR(64) NULL,
    revocation_reason VARCHAR(64) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_refresh_token_hash (token_hash),
    KEY idx_refresh_user_active (user_id, revoked_at, expires_at),
    KEY idx_refresh_family (family_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

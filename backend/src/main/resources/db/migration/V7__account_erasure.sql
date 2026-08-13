ALTER TABLE user_info
    ADD COLUMN deleted_at DATETIME(6) NULL AFTER updated_at;

CREATE INDEX idx_user_info_deleted_at ON user_info (deleted_at);

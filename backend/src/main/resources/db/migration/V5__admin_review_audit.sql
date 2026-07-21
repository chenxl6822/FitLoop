ALTER TABLE agent_action_proposal
    ADD COLUMN decision_note VARCHAR(500) NULL AFTER confirmed_at;

CREATE TABLE admin_audit_log (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    actor_user_id BIGINT NOT NULL,
    action VARCHAR(64) NOT NULL,
    resource_type VARCHAR(64) NOT NULL,
    resource_id VARCHAR(64) NOT NULL,
    details_json LONGTEXT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    INDEX idx_admin_audit_actor (actor_user_id, created_at),
    INDEX idx_admin_audit_resource (resource_type, resource_id, created_at)
);

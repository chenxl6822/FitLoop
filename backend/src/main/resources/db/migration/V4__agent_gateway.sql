CREATE TABLE agent_run (
    run_id VARCHAR(36) PRIMARY KEY,
    run_type VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL,
    requested_by_user_id BIGINT NOT NULL,
    subject_user_id BIGINT NOT NULL,
    subject_resource_id BIGINT NULL,
    trace_id VARCHAR(36) NOT NULL UNIQUE,
    input_json LONGTEXT NOT NULL,
    result_json LONGTEXT NULL,
    model VARCHAR(64) NULL,
    prompt_version VARCHAR(64) NULL,
    input_tokens INT NULL,
    output_tokens INT NULL,
    cost_micros BIGINT NULL,
    latency_ms BIGINT NULL,
    retry_count INT NOT NULL DEFAULT 0,
    error_message VARCHAR(500) NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    started_at TIMESTAMP(6) NULL,
    completed_at TIMESTAMP(6) NULL,
    version BIGINT NOT NULL DEFAULT 0,
    INDEX idx_agent_run_requester (requested_by_user_id, created_at),
    INDEX idx_agent_run_recovery (status, updated_at)
);

CREATE TABLE agent_message (
    message_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id VARCHAR(36) NOT NULL,
    role VARCHAR(16) NOT NULL,
    content LONGTEXT NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    INDEX idx_agent_message_run (run_id, message_id),
    CONSTRAINT fk_agent_message_run FOREIGN KEY (run_id) REFERENCES agent_run(run_id)
);

CREATE TABLE agent_tool_audit (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id VARCHAR(36) NOT NULL,
    tool_name VARCHAR(64) NOT NULL,
    arguments_json LONGTEXT NOT NULL,
    result_json LONGTEXT NULL,
    succeeded BOOLEAN NOT NULL,
    duration_ms BIGINT NULL,
    error_message VARCHAR(500) NULL,
    created_at TIMESTAMP(6) NOT NULL,
    INDEX idx_agent_tool_run (run_id, audit_id),
    CONSTRAINT fk_agent_tool_run FOREIGN KEY (run_id) REFERENCES agent_run(run_id)
);

CREATE TABLE agent_action_proposal (
    proposal_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id VARCHAR(36) NOT NULL,
    subject_user_id BIGINT NOT NULL,
    action_type VARCHAR(64) NOT NULL,
    payload_json LONGTEXT NOT NULL,
    status VARCHAR(24) NOT NULL,
    requires_admin BOOLEAN NOT NULL,
    expires_at TIMESTAMP(6) NOT NULL,
    confirmed_by_user_id BIGINT NULL,
    confirmed_at TIMESTAMP(6) NULL,
    created_at TIMESTAMP(6) NOT NULL,
    INDEX idx_agent_proposal_run (run_id, proposal_id),
    CONSTRAINT fk_agent_proposal_run FOREIGN KEY (run_id) REFERENCES agent_run(run_id)
);

CREATE TABLE training_plan (
    plan_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    source_proposal_id BIGINT NOT NULL UNIQUE,
    title VARCHAR(120) NOT NULL,
    plan_json LONGTEXT NOT NULL,
    status VARCHAR(24) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    INDEX idx_training_plan_user (user_id, created_at),
    CONSTRAINT fk_training_plan_proposal FOREIGN KEY (source_proposal_id)
        REFERENCES agent_action_proposal(proposal_id)
);

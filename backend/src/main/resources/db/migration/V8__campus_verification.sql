CREATE TABLE campus_verification (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    student_id_hash VARCHAR(64) NOT NULL,
    college VARCHAR(128) NOT NULL,
    class_name VARCHAR(128) NOT NULL,
    major VARCHAR(128) NULL,
    grade VARCHAR(64) NULL,
    verified_at DATETIME(6) NOT NULL,
    provider VARCHAR(32) NOT NULL DEFAULT 'xtu_ems',
    CONSTRAINT uk_campus_verification_user UNIQUE (user_id),
    CONSTRAINT uk_campus_verification_student_hash UNIQUE (student_id_hash),
    CONSTRAINT fk_campus_verification_user FOREIGN KEY (user_id) REFERENCES user_info (user_id)
);

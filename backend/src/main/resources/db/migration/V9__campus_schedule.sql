CREATE TABLE campus_schedule_meta (
    user_id BIGINT NOT NULL,
    term_year VARCHAR(16) NOT NULL,
    term_code VARCHAR(16) NOT NULL,
    last_synced_at DATETIME(6) NOT NULL,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_campus_schedule_meta_user FOREIGN KEY (user_id) REFERENCES user_info (user_id)
);

CREATE TABLE campus_schedule_course (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    course_name VARCHAR(128) NOT NULL,
    teacher VARCHAR(64) NULL,
    classroom VARCHAR(128) NULL,
    day_of_week TINYINT NOT NULL,
    start_section TINYINT NOT NULL,
    section_count TINYINT NOT NULL,
    weeks VARCHAR(256) NULL,
    term_year VARCHAR(16) NOT NULL,
    term_code VARCHAR(16) NOT NULL,
    synced_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_campus_schedule_course_user FOREIGN KEY (user_id) REFERENCES user_info (user_id),
    INDEX idx_campus_schedule_course_user_day (user_id, day_of_week)
);

CREATE TABLE campus_schedule_exam (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    exam_name VARCHAR(128) NOT NULL,
    start_time DATETIME(6) NOT NULL,
    end_time DATETIME(6) NULL,
    location VARCHAR(128) NULL,
    exam_type VARCHAR(32) NULL,
    term_year VARCHAR(16) NOT NULL,
    term_code VARCHAR(16) NOT NULL,
    synced_at DATETIME(6) NOT NULL,
    CONSTRAINT fk_campus_schedule_exam_user FOREIGN KEY (user_id) REFERENCES user_info (user_id),
    INDEX idx_campus_schedule_exam_user_start (user_id, start_time)
);

package com.fitloop.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.LocalDate;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class AccountDataServiceIntegrationTest {
    @MockitoBean JavaMailSender mailSender;
    @Autowired AccountDataService accountData;
    @Autowired UserRepository users;
    @Autowired PasswordEncoder passwordEncoder;
    @Autowired JdbcTemplate jdbc;

    @Test
    void exportIncludesOwnedBusinessDataButNeverSecrets() {
        UserInfo user = user("13972000001", "export-pass", "Export Owner");
        Long userId = users.saveAndFlush(user).getUserId();
        jdbc.update("insert into health_data(user_id, weight_kg, sleep_hours, diet_note, data_date) "
                + "values (?, ?, ?, ?, ?)", userId, 62.5, 7.5, "synthetic note", LocalDate.of(2026, 8, 13));

        Map<String, Object> exported = accountData.export(userId);

        assertThat(exported).containsKeys("exportedAt", "profile", "workouts", "trackPoints",
                "targets", "healthData", "reminders", "friends", "appeals", "feedback", "trainingPlans");
        assertThat(exported.toString()).contains("Export Owner", "synthetic note");
        assertThat(exported.toString()).doesNotContain(user.getPasswordHash(), "refresh_token", "password_hash");
    }

    @Test
    void wrongPasswordPreservesDataAndCorrectPasswordErasesIt() {
        UserInfo user = user("13972000002", "delete-pass", "Delete Owner");
        Long userId = users.saveAndFlush(user).getUserId();
        jdbc.update("insert into sport_record(user_id, session_id, sport_type, checkin_mode, "
                + "duration_seconds, distance_km, calorie, status, version) "
                + "values (?, ?, 'running', 'gps', 60, 0.2, 12, 1, 0)",
                userId, "synthetic-delete-session");
        Long recordId = jdbc.queryForObject(
                "select record_id from sport_record where session_id = 'synthetic-delete-session'", Long.class);
        jdbc.update("insert into sport_track_point(record_id, sequence_no, latitude, longitude, accuracy, "
                + "recorded_at, created_at) values (?, 0, 30.0, 114.0, 5.0, current_timestamp, current_timestamp)",
                recordId);
        jdbc.update("insert into health_data(user_id, weight_kg, data_date) values (?, 60.0, current_date)", userId);
        jdbc.update("insert into reminder_config(user_id, type, cycle, enabled) values (?, 'sport', 'daily', true)",
                userId);
        jdbc.update("insert into feedback(user_id, type, content, status) values (?, 'feature', 'synthetic', 'pending')",
                userId);
        jdbc.update("insert into telemetry_event(user_id, event_name, props_json, created_at) "
                + "values (?, 'workout_finish', '{\"result\":\"saved\"}', current_timestamp)", userId);

        assertThatThrownBy(() -> accountData.delete(userId, "wrong-pass"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("密码");
        assertThat(count("sport_record", userId)).isEqualTo(1);
        assertThat(count("telemetry_event", userId)).isEqualTo(1);

        accountData.delete(userId, "delete-pass");
        users.flush();

        UserInfo tombstone = users.findById(userId).orElseThrow();
        assertThat(tombstone.getDeletedAt()).isNotNull();
        assertThat(tombstone.getPhone()).isNull();
        assertThat(tombstone.getEmail()).isNull();
        assertThat(tombstone.getNickname()).isEqualTo("已注销用户");
        assertThat(users.existsByUserIdAndDeletedAtIsNull(userId)).isFalse();
        assertThat(count("sport_record", userId)).isZero();
        assertThat(count("health_data", userId)).isZero();
        assertThat(count("reminder_config", userId)).isZero();
        assertThat(count("feedback", userId)).isZero();
        assertThat(count("telemetry_event", userId)).isZero();
        assertThat(jdbc.queryForObject("select count(*) from sport_track_point where record_id = ?",
                Long.class, recordId)).isZero();
        assertThatThrownBy(() -> accountData.export(userId)).isInstanceOf(IllegalArgumentException.class);
    }

    private UserInfo user(String phone, String password, String nickname) {
        UserInfo user = new UserInfo();
        user.setPhone(phone);
        user.setPasswordHash(passwordEncoder.encode(password));
        user.setNickname(nickname);
        return user;
    }

    private long count(String table, Long userId) {
        return jdbc.queryForObject("select count(*) from " + table + " where user_id = ?", Long.class, userId);
    }
}

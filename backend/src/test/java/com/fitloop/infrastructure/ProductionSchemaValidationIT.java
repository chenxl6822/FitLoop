package com.fitloop.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.user.AccountDataService;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.WeekFields;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mysql.MySQLContainer;
import org.testcontainers.utility.DockerImageName;

@Testcontainers(disabledWithoutDocker = true)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {
                "spring.flyway.enabled=true",
                "spring.jpa.hibernate.ddl-auto=validate",
                "spring.jpa.open-in-view=false",
                "spring.mail.host=localhost",
                "management.health.mail.enabled=false",
                "fitloop.admin.bootstrap-account=",
                "fitloop.agent.service-key=test-agent-service-key-32-bytes-ok",
                "fitloop.agent.delegation-secret=test-agent-delegation-secret-32-bytes"
        })
class ProductionSchemaValidationIT {
    @Container
    private static final MySQLContainer MYSQL = new MySQLContainer("mysql:8.0.43")
            .withDatabaseName("fitloop")
            .withUsername("fitloop")
            .withPassword("fitloop-test");

    @Container
    private static final GenericContainer<?> REDIS = new GenericContainer<>(
            DockerImageName.parse("redis:6.2.19-alpine"))
            .withExposedPorts(6379);

    @DynamicPropertySource
    static void infrastructureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "com.mysql.cj.jdbc.Driver");
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @Test
    void flywaySchemaPassesProductionJpaValidationAndAccountErasureRunsOnMySql(
            @Autowired DataSource dataSource,
            @Autowired UserRepository users,
            @Autowired PasswordEncoder passwordEncoder,
            @Autowired AccountDataService accountData,
            @Autowired StringRedisTemplate redis) {
        var jdbc = new JdbcTemplate(dataSource);

        assertThat(jdbc.queryForObject(
                "select version from flyway_schema_history "
                        + "where success = 1 order by installed_rank desc limit 1",
                String.class))
                .isEqualTo("7");

        UserInfo user = new UserInfo();
        user.setPhone("13973000001");
        user.setNickname("MySQL erasure owner");
        user.setPasswordHash(passwordEncoder.encode("mysql-delete-pass"));
        Long userId = users.saveAndFlush(user).getUserId();
        jdbc.update("insert into health_data(user_id, weight_kg, data_date) values (?, 61.0, current_date)",
                userId);
        LocalDate date = LocalDate.now(ZoneId.of("Asia/Shanghai"));
        WeekFields fields = WeekFields.ISO;
        String period = date.get(fields.weekBasedYear()) + "-"
                + String.format("%02d", date.get(fields.weekOfWeekBasedYear()));
        String distanceKey = "ranking:week:distance:" + period;
        String calorieKey = "ranking:week:calorie:" + period;
        redis.opsForZSet().add(distanceKey, userId.toString(), 5.0);
        redis.opsForHash().put(calorieKey, userId.toString(), "300");

        assertThat(accountData.export(userId).toString()).contains("MySQL erasure owner");
        accountData.delete(userId, "mysql-delete-pass");
        users.flush();

        assertThat(users.existsByUserIdAndDeletedAtIsNull(userId)).isFalse();
        assertThat(jdbc.queryForObject(
                "select count(*) from health_data where user_id = ?", Long.class, userId)).isZero();
        assertThat(redis.opsForZSet().score(distanceKey, userId.toString())).isNull();
        assertThat(redis.opsForHash().get(calorieKey, userId.toString())).isNull();
    }
}

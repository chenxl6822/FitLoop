package com.fitloop.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
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
    void flywaySchemaPassesProductionJpaValidation(@Autowired DataSource dataSource) {
        var jdbc = new JdbcTemplate(dataSource);

        assertThat(jdbc.queryForObject(
                "select version from flyway_schema_history "
                        + "where success = 1 order by installed_rank desc limit 1",
                String.class))
                .isEqualTo("5");
    }
}

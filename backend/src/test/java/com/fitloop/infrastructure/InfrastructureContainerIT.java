package com.fitloop.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.DriverManager;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mysql.MySQLContainer;
import org.testcontainers.utility.DockerImageName;

@Testcontainers(disabledWithoutDocker = true)
class InfrastructureContainerIT {
    @Container
    private static final MySQLContainer MYSQL = new MySQLContainer("mysql:8.0.43")
            .withDatabaseName("fitloop")
            .withUsername("fitloop")
            .withPassword("fitloop-test");

    @Container
    private static final GenericContainer<?> REDIS = new GenericContainer<>(
            DockerImageName.parse("redis:6.2.19-alpine"))
            .withExposedPorts(6379);

    @Test
    void productionMigrationsRunOnMySqlAndRedisAcceptsCommands() throws Exception {
        var migration = Flyway.configure()
                .dataSource(MYSQL.getJdbcUrl(), MYSQL.getUsername(), MYSQL.getPassword())
                .locations("classpath:db/migration")
                .load()
                .migrate();

        assertThat(migration.success).isTrue();
        assertThat(migration.migrationsExecuted).isGreaterThanOrEqualTo(4);
        try (var connection = DriverManager.getConnection(
                MYSQL.getJdbcUrl(), MYSQL.getUsername(), MYSQL.getPassword());
             var statement = connection.createStatement();
             var rows = statement.executeQuery(
                     "select version from flyway_schema_history where success = 1 order by installed_rank desc limit 1")) {
            assertThat(rows.next()).isTrue();
            assertThat(rows.getString(1)).isEqualTo("4");
        }

        var ping = REDIS.execInContainer("redis-cli", "PING");
        assertThat(ping.getExitCode()).isZero();
        assertThat(ping.getStdout()).contains("PONG");
    }
}

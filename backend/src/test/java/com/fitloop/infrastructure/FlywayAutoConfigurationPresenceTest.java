package com.fitloop.infrastructure;

import static org.assertj.core.api.Assertions.assertThatCode;

import org.junit.jupiter.api.Test;

class FlywayAutoConfigurationPresenceTest {

    @Test
    void springBootFlywayAutoConfigurationModuleIsOnTheClasspath() {
        assertThatCode(() -> Class.forName(
                "org.springframework.boot.flyway.autoconfigure.FlywayAutoConfiguration"))
                .doesNotThrowAnyException();
    }
}

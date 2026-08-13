package com.fitloop.agent;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.mysql.MySQLContainer;
import org.testcontainers.utility.DockerImageName;

@Testcontainers(disabledWithoutDocker = true)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
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
class AgentToolBudgetConcurrencyIT {
    private static final int CALLERS = 16;

    @Container
    private static final MySQLContainer MYSQL = new MySQLContainer("mysql:8.0.43")
            .withDatabaseName("fitloop")
            .withUsername("fitloop")
            .withPassword("fitloop-test");

    @Container
    private static final GenericContainer<?> REDIS = new GenericContainer<>(
            DockerImageName.parse("redis:6.2.19-alpine"))
            .withExposedPorts(6379);

    @Autowired AgentGatewayService gateway;
    @Autowired AgentToolAuditRepository toolAudits;
    @Autowired UserRepository users;

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
    void concurrentCallsReserveAtMostEightToolSlots() throws Exception {
        UserInfo user = new UserInfo();
        user.setPhone("13971000001");
        user.setPasswordHash("synthetic-password-hash");
        user.setNickname("SyntheticToolBudgetOwner");
        Long owner = users.saveAndFlush(user).getUserId();
        AgentRun run = gateway.createCoachRun(owner, "synthetic concurrent tool budget");
        gateway.claim(run.getRunId());
        AgentDtos.ToolContext context = new AgentDtos.ToolContext(
                run.getRunId(), owner, null, AgentRunType.COACH);

        CountDownLatch ready = new CountDownLatch(CALLERS);
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch releaseInvocations = new CountDownLatch(1);
        AtomicInteger invoked = new AtomicInteger();
        List<Future<Object>> futures = new ArrayList<>();

        try (var executor = Executors.newFixedThreadPool(CALLERS);
             var releaseTimer = Executors.newSingleThreadScheduledExecutor()) {
            for (int index = 0; index < CALLERS; index++) {
                int callIndex = index;
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    if (!start.await(10, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("Synthetic race start timed out");
                    }
                    return gateway.executeTool(
                            context,
                            "synthetic_tool_" + callIndex,
                            Map.of("index", callIndex),
                            () -> {
                                invoked.incrementAndGet();
                                try {
                                    if (!releaseInvocations.await(5, TimeUnit.SECONDS)) {
                                        throw new IllegalStateException("Synthetic invocation release timed out");
                                    }
                                } catch (InterruptedException interrupted) {
                                    Thread.currentThread().interrupt();
                                    throw new IllegalStateException("Synthetic invocation interrupted", interrupted);
                                }
                                return callIndex;
                            });
                }));
            }
            assertThat(ready.await(10, TimeUnit.SECONDS)).isTrue();
            releaseTimer.schedule(releaseInvocations::countDown, 1, TimeUnit.SECONDS);
            start.countDown();
            executor.shutdown();
            assertThat(executor.awaitTermination(30, TimeUnit.SECONDS)).isTrue();
            releaseInvocations.countDown();
        }

        int succeeded = 0;
        List<Throwable> failures = new ArrayList<>();
        for (Future<Object> future : futures) {
            try {
                future.get(5, TimeUnit.SECONDS);
                succeeded++;
            } catch (ExecutionException failure) {
                failures.add(failure.getCause());
            }
        }

        assertThat(succeeded).isEqualTo(8);
        assertThat(invoked.get()).isEqualTo(8);
        assertThat(failures).hasSize(8).allSatisfy(failure ->
                assertThat(failure)
                        .isInstanceOf(IllegalStateException.class)
                        .hasMessageContaining("limit"));
        assertThat(toolAudits.findByRunIdOrderByAuditIdAsc(run.getRunId())).hasSize(8);
    }
}

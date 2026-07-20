package com.fitloop.sport;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.common.OutboxEventRepository;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.SportRecordResponse;
import com.fitloop.sport.SportDtos.StartSessionRequest;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

@SpringBootTest
@ActiveProfiles("test")
class WorkoutConcurrencyIntegrationTest {
    @Autowired SportService workouts;
    @Autowired SportRecordRepository records;
    @Autowired UserRepository users;
    @Autowired OutboxEventRepository outbox;
    @MockitoBean StringRedisTemplate redis;
    @MockitoBean JavaMailSender mailSender;

    @Test
    void twentyConcurrentFinishRequestsSettleExactlyOnce() throws Exception {
        UserInfo user = new UserInfo();
        user.setPhone("13900000020");
        user.setPasswordHash("hash");
        user.setNickname("ConcurrentUser");
        Long userId = users.save(user).getUserId();
        var session = workouts.start(userId, new StartSessionRequest("running", "manual"));
        FinishSessionRequest request = new FinishSessionRequest(
                session.sessionId(), 1800L, 3.0, 240.0, 60.0, null, null);

        CountDownLatch ready = new CountDownLatch(20);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<SportRecordResponse>> futures = new ArrayList<>();
        try (var executor = Executors.newFixedThreadPool(20)) {
            for (int i = 0; i < 20; i++) {
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    start.await(5, TimeUnit.SECONDS);
                    return workouts.finish(userId, request, "concurrent-finish-001");
                }));
            }
            assertThat(ready.await(5, TimeUnit.SECONDS)).isTrue();
            start.countDown();
            List<Long> ids = new ArrayList<>();
            for (Future<SportRecordResponse> future : futures) {
                ids.add(future.get(15, TimeUnit.SECONDS).recordId());
            }
            assertThat(new HashSet<>(ids)).hasSize(1);
        }

        SportRecord saved = records.findBySessionIdAndUserId(session.sessionId(), userId).orElseThrow();
        assertThat(saved.workoutStatus()).isEqualTo(WorkoutStatus.VALID);
        assertThat(outbox.count()).isEqualTo(1);
        assertThat(users.findById(userId).orElseThrow().getPoints()).isEqualTo(24);
    }
}

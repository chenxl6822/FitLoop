package com.fitloop.sport;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.common.DomainEventOutbox;
import com.fitloop.social.SocialService;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.StartSessionRequest;
import com.fitloop.sport.SportDtos.TrackBatchRequest;
import com.fitloop.sport.SportDtos.TrackPointInput;
import com.fitloop.target.TargetService;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.TestPropertySource;
import tools.jackson.databind.ObjectMapper;

@DataJpaTest
@Import({SportService.class, CalorieCalculator.class, TargetService.class, DomainEventOutbox.class,
        SportServiceTest.TestConfig.class})
@TestPropertySource(properties = "fitloop.upload.photo-dir=${java.io.tmpdir}/fitloop-sport-test-photos")
class SportServiceTest {
    private static final long USER_ID = 1L;

    @TestConfiguration
    static class TestConfig {
        @Bean ObjectMapper objectMapper() { return new ObjectMapper(); }
    }

    @Autowired SportService sportService;
    @MockitoBean SocialService socialService;

    @Test
    void startAndFinishRunningGps() {
        var start = sportService.start(USER_ID, new StartSessionRequest("running", "gps"));
        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 1800L, null, null, 60.0, null, null));
        assertThat(record.sportType()).isEqualTo("running");
        assertThat(record.checkinMode()).isEqualTo("gps");
        assertThat(record.status()).isEqualTo(SportRecord.STATUS_VALID);
        assertThat(record.durationSeconds()).isEqualTo(1800);
    }

    @Test
    void startAndFinishManualMode() {
        var start = sportService.start(USER_ID, new StartSessionRequest("custom", "manual"));
        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 1800L, 3.0, 200.0, 60.0, null, "晨跑打卡"));
        assertThat(record.distanceKm()).isEqualTo(3.0);
        assertThat(record.calorie()).isEqualTo(200.0);
    }

    @Test
    void finishWithoutTrackPointsIsValid() {
        var start = sportService.start(USER_ID, new StartSessionRequest("rope_skipping", "sensor"));
        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 600L, null, null, 55.0, null, null));
        assertThat(record.status()).isEqualTo(SportRecord.STATUS_VALID);
        assertThat(record.distanceKm()).isZero();
        assertThat(record.calorie()).isGreaterThan(0);
    }

    @Test
    void rejectsGpsForIndoorSport() {
        assertThatThrownBy(() -> sportService.start(USER_ID,
                new StartSessionRequest("rope_skipping", "gps")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("不支持");
    }

    @Test
    void batchTrackDeduplicatesSequencesAndFinishIsIdempotent() {
        var start = sportService.start(USER_ID, new StartSessionRequest("running", "gps"));
        Instant now = Instant.now();
        var first = sportService.appendTrackBatch(USER_ID, start.sessionId(), new TrackBatchRequest(List.of(
                new TrackPointInput(0, 31.2304, 121.4737, 5.0, now),
                new TrackPointInput(1, 31.2305, 121.4738, 5.0, now.plusSeconds(30)),
                new TrackPointInput(1, 31.2306, 121.4739, 5.0, now.plusSeconds(31)))));
        var retry = sportService.appendTrackBatch(USER_ID, start.sessionId(), new TrackBatchRequest(List.of(
                new TrackPointInput(0, 31.2304, 121.4737, 5.0, now),
                new TrackPointInput(1, 31.2305, 121.4738, 5.0, now.plusSeconds(30)))));
        assertThat(first.accepted()).isEqualTo(2);
        assertThat(first.duplicates()).isEqualTo(1);
        assertThat(retry.accepted()).isZero();
        assertThat(retry.duplicates()).isEqualTo(2);

        var request = new FinishSessionRequest(start.sessionId(), 1800L, null, null, 60.0, null, null);
        var completed = sportService.finish(USER_ID, request, "finish-key-001");
        var replay = sportService.finish(USER_ID, request, "finish-key-001");
        assertThat(replay.recordId()).isEqualTo(completed.recordId());
        assertThatThrownBy(() -> sportService.finish(USER_ID,
                new FinishSessionRequest(start.sessionId(), 1900L, null, null, 60.0, null, null),
                "finish-key-001")).hasMessageContaining("不同请求");
    }
    @Test
    void photoUploadValidatesInputAndMapsSupportedExtensions() {
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "empty.png", "image/png", new byte[0])))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "unknown", null, new byte[]{1})))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "note.txt", "text/plain", new byte[]{1})))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "huge.png", "image/png", new byte[10 * 1024 * 1024 + 1])))
                .isInstanceOf(IllegalArgumentException.class);

        assertThat(upload("image/jpeg")).endsWith(".jpg");
        assertThat(upload("image/jpg")).endsWith(".jpg");
        assertThat(upload("image/png")).endsWith(".png");
        assertThat(upload("image/gif")).endsWith(".gif");
        assertThat(upload("image/webp")).endsWith(".webp");
        assertThat(upload("image/bmp")).endsWith(".img");
    }

    @Test
    void cursorPaginationClampsSizeAndReturnsStableCursor() {
        for (int i = 0; i < 3; i++) {
            sportService.start(USER_ID, new StartSessionRequest("running", "timer"));
        }

        var first = sportService.list(USER_ID, null, 1);
        assertThat(first.records()).hasSize(1);
        assertThat(first.hasMore()).isTrue();
        assertThat(first.nextCursor()).isNotNull();

        var remainder = sportService.list(USER_ID, first.nextCursor(), 1000);
        assertThat(remainder.records()).hasSizeGreaterThanOrEqualTo(1);
        assertThat(sportService.list(USER_ID, null, 0).records()).hasSize(1);
        assertThat(sportService.list(USER_ID)).hasSizeGreaterThanOrEqualTo(3);
    }

    private String upload(String contentType) {
        return sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "photo", contentType, new byte[]{1, 2, 3}));
    }
}

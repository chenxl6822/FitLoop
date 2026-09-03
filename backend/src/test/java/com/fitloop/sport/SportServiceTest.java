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
        Instant now = Instant.now();
        sportService.appendTrackBatch(USER_ID, start.sessionId(), new TrackBatchRequest(List.of(
                new TrackPointInput(0, 31.2304, 121.4737, 5.0, now),
                new TrackPointInput(1, 31.2305, 121.4738, 5.0, now.plusSeconds(60)))));
        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 1800L, null, null, 60.0, null, null));
        assertThat(record.sportType()).isEqualTo("running");
        assertThat(record.checkinMode()).isEqualTo("gps");
        assertThat(record.status()).isEqualTo(SportRecord.STATUS_VALID);
        assertThat(record.durationSeconds()).isEqualTo(1800);
    }

    @Test
    void finishGpsWithoutTrackPointsIsAbnormal() {
        var start = sportService.start(USER_ID, new StartSessionRequest("running", "gps"));
        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 120L, null, null, 60.0, null, null));
        assertThat(record.status()).isEqualTo(SportRecord.STATUS_ABNORMAL);
        assertThat(record.abnormalReason()).contains("无有效轨迹");
        assertThat(record.distanceKm()).isZero();
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
    void cancelAbandonsDraftWithoutCountingAsWorkout() {
        var start = sportService.start(USER_ID, new StartSessionRequest("running", "gps"));
        var cancelled = sportService.cancel(USER_ID, start.sessionId());
        assertThat(cancelled.status()).isEqualTo(SportRecord.STATUS_CANCELLED);
        assertThat(cancelled.endedAt()).isNotNull();
        assertThat(cancelled.distanceKm()).isZero();

        var again = sportService.cancel(USER_ID, start.sessionId());
        assertThat(again.recordId()).isEqualTo(cancelled.recordId());
        assertThat(again.status()).isEqualTo(SportRecord.STATUS_CANCELLED);

        assertThatThrownBy(() -> sportService.appendTrackBatch(USER_ID, start.sessionId(),
                new TrackBatchRequest(List.of(new TrackPointInput(
                        0, 31.23, 121.47, 5.0, Instant.now())))))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("已结束");

        var finished = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 60L, null, null, 60.0, null, null));
        assertThat(finished.status()).isEqualTo(SportRecord.STATUS_CANCELLED);
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
    void returnsTrackOnlyToRecordOwnerInWgs84Order() {
        var start = sportService.start(USER_ID, new StartSessionRequest("running", "gps"));
        Instant now = Instant.now();
        sportService.appendTrackBatch(USER_ID, start.sessionId(), new TrackBatchRequest(List.of(
                new TrackPointInput(1, 31.2305, 121.4738, 6.0, now.plusSeconds(30)),
                new TrackPointInput(0, 31.2304, 121.4737, 5.0, now))));
        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 1800L, null, null, 60.0, null, null));

        var track = sportService.track(USER_ID, record.recordId());

        assertThat(track.coordinateSystem()).isEqualTo("WGS84");
        assertThat(track.points()).extracting(point -> point.sequenceNo())
                .containsExactly(0, 1);
        assertThat(track.points()).extracting(point -> point.lat())
                .containsExactly(31.2304, 31.2305);
        assertThatThrownBy(() -> sportService.track(999L, record.recordId()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("不存在");
    }

    @Test
    void photoUploadValidatesInputAndMapsSupportedExtensions() throws Exception {
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
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "fake.bmp", "image/bmp", samplePng())))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "broken.jpg", "image/jpeg",
                        new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x00})))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");

        assertThat(upload("image/jpeg", sampleJpeg())).endsWith(".jpg");
        assertThat(upload("image/jpg", sampleJpeg())).endsWith(".jpg");
        assertThat(upload("image/png", samplePng())).endsWith(".png");
        assertThat(upload("image/gif", sampleGif())).endsWith(".gif");
        assertThat(upload("image/webp", sampleWebp())).endsWith(".webp");
        assertThat(upload(null, samplePng())).endsWith(".png");
        assertThat(upload("   ", samplePng())).endsWith(".png");
        assertThat(upload("application/octet-stream", sampleJpeg())).endsWith(".jpg");
    }

    @Test
    void photoUploadRejectsContentTypeThatConflictsWithDetectedBytes() throws Exception {
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "proof.png", "image/gif", samplePng())))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");
        assertThatThrownBy(() -> sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "proof.webp", "image/png", sampleWebp())))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("图片");
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

    private String upload(String contentType, byte[] bytes) {
        return sportService.savePhoto(USER_ID,
                new MockMultipartFile("file", "photo", contentType, bytes));
    }

    private static byte[] samplePng() throws Exception {
        var image = new java.awt.image.BufferedImage(1, 1, java.awt.image.BufferedImage.TYPE_INT_RGB);
        var out = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(image, "png", out);
        return out.toByteArray();
    }

    private static byte[] sampleJpeg() throws Exception {
        var image = new java.awt.image.BufferedImage(1, 1, java.awt.image.BufferedImage.TYPE_INT_RGB);
        var out = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(image, "jpg", out);
        return out.toByteArray();
    }

    private static byte[] sampleGif() throws Exception {
        var image = new java.awt.image.BufferedImage(1, 1, java.awt.image.BufferedImage.TYPE_INT_RGB);
        var out = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(image, "gif", out);
        return out.toByteArray();
    }

    private static byte[] sampleWebp() {
        // Minimal RIFF/WEBP container header; WebP is accepted by magic only.
        return new byte[] {
                'R', 'I', 'F', 'F', 0x1A, 0x00, 0x00, 0x00,
                'W', 'E', 'B', 'P',
                'V', 'P', '8', ' ', 0x0E, 0x00, 0x00, 0x00,
                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E
        };
    }
}

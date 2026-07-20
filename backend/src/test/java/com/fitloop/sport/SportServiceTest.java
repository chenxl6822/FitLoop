package com.fitloop.sport;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;

import tools.jackson.databind.ObjectMapper;
import com.fitloop.social.SocialService;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.StartSessionRequest;
import com.fitloop.target.TargetService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import({SportService.class, CalorieCalculator.class, TargetService.class, SportServiceTest.TestConfig.class})
class SportServiceTest {

    @TestConfiguration
    static class TestConfig {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Autowired
    private SportService sportService;

    @MockitoBean
    private SocialService socialService;

    private static final long USER_ID = 1L;

    @Test
    void startAndFinishRunningGps() {
        doNothing().when(socialService).reward(any());
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
        doNothing().when(socialService).reward(any());
        var start = sportService.start(USER_ID, new StartSessionRequest("custom", "manual"));

        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 1800L, 3.0, 200.0, 60.0, null, "晨跑打卡"));

        assertThat(record.sportType()).isEqualTo("custom");
        assertThat(record.checkinMode()).isEqualTo("manual");
        assertThat(record.distanceKm()).isEqualTo(3.0);
        assertThat(record.calorie()).isEqualTo(200.0);
    }

    @Test
    void finishWithoutTrackPointsIsValid() {
        doNothing().when(socialService).reward(any());
        var start = sportService.start(USER_ID, new StartSessionRequest("rope_skipping", "sensor"));

        var record = sportService.finish(USER_ID, new FinishSessionRequest(
                start.sessionId(), 600L, null, null, 55.0, null, null));

        assertThat(record.status()).isEqualTo(SportRecord.STATUS_VALID);
        assertThat(record.distanceKm()).isZero();
        assertThat(record.calorie()).isGreaterThan(0);
    }

    @Test
    void rejectsGpsForIndoorSport() {
        assertThatThrownBy(() ->
                sportService.start(USER_ID, new StartSessionRequest("rope_skipping", "gps")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("不支持");
    }
}

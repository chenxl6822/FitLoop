package com.fitloop.stats;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.StatsDtos.HealthRequest;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import({StatsService.class, CalorieCalculator.class})
class StatsServiceTest {

    @Autowired
    private StatsService statsService;

    @Autowired
    private SportRecordRepository sportRecordRepository;

    @Test
    void addHealthSavesAndReturnsData() {
        var result = statsService.addHealth(1L,
                new HealthRequest(65.0, 7.5, "健康饮食", LocalDate.of(2026, 5, 26)));

        assertThat(result.healthId()).isNotNull();
        assertThat(result.weightKg()).isEqualTo(65.0);
        assertThat(result.sleepHours()).isEqualTo(7.5);
        assertThat(result.dietNote()).isEqualTo("健康饮食");
        assertThat(result.dataDate()).isEqualTo(LocalDate.of(2026, 5, 26));
    }

    @Test
    void addHealthDefaultsToTodayWhenDateNotProvided() {
        var result = statsService.addHealth(2L, new HealthRequest(70.0, null, null, null));

        assertThat(result.dataDate()).isEqualTo(LocalDate.now());
        assertThat(result.weightKg()).isEqualTo(70.0);
        assertThat(result.sleepHours()).isNull();
    }

    @Test
    void sportStatsReturnsEmptyForNewUser() {
        var result = statsService.sport(99L, null);

        assertThat(result.checkinCount()).isZero();
        assertThat(result.durationSeconds()).isZero();
        assertThat(result.distanceKm()).isZero();
        assertThat(result.calorie()).isZero();
    }

    @Test
    void sportStatsCountsOnlyValidRecords() {
        var valid = createRecord(1L, SportRecord.STATUS_VALID, 1800, 5.0, 300);
        var abnormal = createRecord(1L, SportRecord.STATUS_ABNORMAL, 900, 2.0, 150);
        createRecord(1L, SportRecord.STATUS_DRAFT, 600, 1.0, 80);

        var result = statsService.sport(1L, null);

        assertThat(result.checkinCount()).isEqualTo(1);
        assertThat(result.durationSeconds()).isEqualTo(1800);
    }

    @Test
    void sportStatsSumsMultipleValidRecords() {
        createRecord(1L, SportRecord.STATUS_VALID, 1800, 5.0, 300);
        createRecord(1L, SportRecord.STATUS_VALID, 3600, 10.0, 600);

        var result = statsService.sport(1L, null);

        assertThat(result.checkinCount()).isEqualTo(2);
        assertThat(result.durationSeconds()).isEqualTo(5400);
        assertThat(result.distanceKm()).isEqualTo(15.0);
        assertThat(result.calorie()).isEqualTo(900.0);
    }

    @Test
    void sportStatsPeriodReflectedInResponse() {
        var result = statsService.sport(1L, "week");
        assertThat(result.period()).isEqualTo("week");
    }

    private SportRecord createRecord(Long userId, int status, long seconds,
                                     double distanceKm, double calorie) {
        SportRecord r = new SportRecord();
        r.setUserId(userId);
        r.setSessionId("s-" + System.nanoTime());
        r.setSportType("running");
        r.setCheckinMode("gps");
        r.setDurationSeconds(seconds);
        r.setDistanceKm(distanceKm);
        r.setCalorie(calorie);
        r.setStatus(status);
        r.setStartedAt(java.time.Instant.now());
        return sportRecordRepository.save(r);
    }
}

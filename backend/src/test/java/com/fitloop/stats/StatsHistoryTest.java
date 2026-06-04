package com.fitloop.stats;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.StatsDtos.SportHistoryPoint;
import com.fitloop.stats.StatsDtos.SportHistoryResponse;
import com.fitloop.stats.StatsDtos.WeightHistoryResponse;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.annotation.Transactional;

@DataJpaTest
@Import({StatsService.class, CalorieCalculator.class})
@Transactional
class StatsHistoryTest {

    @Autowired
    private StatsService statsService;

    @Autowired
    private SportRecordRepository sportRecords;

    @Autowired
    private HealthDataRepository healthData;

    private static final Long USER_ID = 1L;
    private final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private LocalDate today;

    @BeforeEach
    void setUp() {
        today = LocalDate.now();
    }

    @Test
    void sportHistoryShouldReturnDailyAggregation() {
        LocalDate monday = today.with(TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY));

        SportRecord r1 = record(USER_ID, monday.atStartOfDay(ZONE).toInstant(), 600, 3.0, 300.0);
        SportRecord r2 = record(USER_ID, monday.atStartOfDay(ZONE).plusHours(2).toInstant(), 300, 1.5, 150.0);
        sportRecords.save(r1);
        sportRecords.save(r2);

        SportHistoryResponse result = statsService.sportHistory(USER_ID, "week", "all");

        assertThat(result.points()).isNotEmpty();
        // 周一应该聚合两条记录
        SportHistoryPoint mondayPoint = result.points().get(0);
        assertThat(mondayPoint.date()).isEqualTo(monday);
        assertThat(mondayPoint.count()).isEqualTo(2);
        assertThat(mondayPoint.durationSeconds()).isEqualTo(900);  // 600 + 300
        assertThat(mondayPoint.distanceKm()).isEqualTo(4.5);
        assertThat(mondayPoint.calorie()).isEqualTo(450.0);
    }

    @Test
    void sportHistoryShouldReturnEmptyForNoRecords() {
        SportHistoryResponse result = statsService.sportHistory(USER_ID, "week", "all");
        assertThat(result.points()).isEmpty(); // 无记录时不补零
    }

    @Test
    void weightHistoryShouldReturnOnlyDaysWithData() {
        healthData.save(healthEntry(USER_ID, today.minusDays(5), 70.0));
        healthData.save(healthEntry(USER_ID, today.minusDays(2), 69.0));
        healthData.save(healthEntry(USER_ID, today, 68.5));

        WeightHistoryResponse result = statsService.weightHistory(USER_ID, 30);

        assertThat(result.points()).hasSize(3);
        assertThat(result.points().get(0).weightKg()).isEqualTo(70.0);
        assertThat(result.points().get(2).weightKg()).isEqualTo(68.5);
    }

    @Test
    void weightHistoryShouldReturnEmptyWhenNoData() {
        WeightHistoryResponse result = statsService.weightHistory(USER_ID, 7);
        assertThat(result.points()).isEmpty();
    }

    private SportRecord record(Long userId, Instant startedAt, long duration, double distance, double calorie) {
        SportRecord r = new SportRecord();
        r.setUserId(userId);
        r.setSessionId(java.util.UUID.randomUUID().toString());
        r.setSportType("running");
        r.setCheckinMode("gps");
        r.setStartedAt(startedAt);
        r.setEndedAt(startedAt.plusSeconds(duration));
        r.setDurationSeconds(duration);
        r.setDistanceKm(distance);
        r.setCalorie(calorie);
        r.setStatus(SportRecord.STATUS_VALID);
        return r;
    }

    private HealthData healthEntry(Long userId, LocalDate date, double weight) {
        HealthData d = new HealthData();
        d.setUserId(userId);
        d.setDataDate(date);
        d.setWeightKg(weight);
        return d;
    }
}

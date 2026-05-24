package com.fitloop.stats;

import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.StatsDtos.HealthRequest;
import com.fitloop.stats.StatsDtos.HealthResponse;
import com.fitloop.stats.StatsDtos.SportStatsResponse;
import java.time.LocalDate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class StatsService {
    private final HealthDataRepository healthData;
    private final SportRecordRepository sportRecords;
    private final CalorieCalculator calculator;

    public StatsService(HealthDataRepository healthData, SportRecordRepository sportRecords, CalorieCalculator calculator) {
        this.healthData = healthData;
        this.sportRecords = sportRecords;
        this.calculator = calculator;
    }

    @Transactional
    public HealthResponse addHealth(Long userId, HealthRequest request) {
        HealthData data = new HealthData();
        data.setUserId(userId);
        data.setWeightKg(request.weightKg());
        data.setSleepHours(request.sleepHours());
        data.setDietNote(request.dietNote());
        data.setDataDate(request.dataDate() == null ? LocalDate.now() : request.dataDate());
        return HealthResponse.from(healthData.save(data));
    }

    @Transactional(readOnly = true)
    public SportStatsResponse sport(Long userId, String period) {
        var records = sportRecords.findTop50ByUserIdOrderByStartedAtDesc(userId).stream()
                .filter(record -> record.getStatus() == SportRecord.STATUS_VALID)
                .toList();
        long duration = records.stream().mapToLong(SportRecord::getDurationSeconds).sum();
        double distance = records.stream().mapToDouble(SportRecord::getDistanceKm).sum();
        double calorie = records.stream().mapToDouble(SportRecord::getCalorie).sum();
        return new SportStatsResponse(period == null ? "all" : period, records.size(), duration,
                calculator.round(distance), calculator.round(calorie));
    }
}

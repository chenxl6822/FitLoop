package com.fitloop.stats;

import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.stats.StatsDtos.HealthRequest;
import com.fitloop.stats.StatsDtos.HealthResponse;
import com.fitloop.stats.StatsDtos.SportHistoryPoint;
import com.fitloop.stats.StatsDtos.SportHistoryResponse;
import com.fitloop.stats.StatsDtos.SportStatsResponse;
import com.fitloop.stats.StatsDtos.WeightHistoryPoint;
import com.fitloop.stats.StatsDtos.WeightHistoryResponse;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
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

    @Transactional(readOnly = true)
    public SportHistoryResponse sportHistory(Long userId, String period, String metric) {
        LocalDate today = LocalDate.now();
        LocalDate start;

        if ("month".equalsIgnoreCase(period) || "月".equals(period)) {
            start = today.withDayOfMonth(1);
        } else {
            // 默认 week
            start = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        }
        LocalDate endExclusive = today.plusDays(1);

        ZoneId zone = ZoneId.of("Asia/Shanghai");
        Instant startInstant = start.atStartOfDay(zone).toInstant();
        Instant endInstant = endExclusive.atStartOfDay(zone).toInstant();

        List<SportRecord> records = sportRecords.findValidInRange(
                userId, SportRecord.STATUS_VALID, startInstant, endInstant);

        // 按日期分组聚合
        Map<LocalDate, List<SportRecord>> byDate = records.stream()
                .collect(Collectors.groupingBy(
                        r -> r.getStartedAt().atZone(zone).toLocalDate(),
                        LinkedHashMap::new,
                        Collectors.toList()));

        // 填充缺失日期
        List<SportHistoryPoint> points = new ArrayList<>();
        for (LocalDate d = start; !d.isAfter(today); d = d.plusDays(1)) {
            List<SportRecord> dayRecords = byDate.getOrDefault(d, List.of());
            points.add(aggregateDay(d, dayRecords));
        }

        return new SportHistoryResponse(
                period == null ? "week" : period,
                metric == null ? "all" : metric,
                points);
    }

    private SportHistoryPoint aggregateDay(LocalDate date, List<SportRecord> dayRecords) {
        long count = dayRecords.size();
        long duration = dayRecords.stream().mapToLong(SportRecord::getDurationSeconds).sum();
        double distance = calculator.round(
                dayRecords.stream().mapToDouble(SportRecord::getDistanceKm).sum());
        double calorie = calculator.round(
                dayRecords.stream().mapToDouble(SportRecord::getCalorie).sum());
        return new SportHistoryPoint(date, count, duration, distance, calorie);
    }

    @Transactional(readOnly = true)
    public WeightHistoryResponse weightHistory(Long userId, int days) {
        LocalDate today = LocalDate.now();
        LocalDate start = today.minusDays(Math.max(days, 1) - 1);

        List<HealthData> dataList = healthData
                .findByUserIdAndDataDateBetweenOrderByDataDateAsc(userId, start, today);

        // 每天取最新一条
        Map<LocalDate, HealthData> latestPerDay = new LinkedHashMap<>();
        for (HealthData d : dataList) {
            latestPerDay.put(d.getDataDate(), d);
        }

        List<WeightHistoryPoint> points = new ArrayList<>();
        for (LocalDate d = start; !d.isAfter(today); d = d.plusDays(1)) {
            HealthData entry = latestPerDay.get(d);
            if (entry != null && entry.getWeightKg() != null) {
                points.add(WeightHistoryPoint.from(entry));
            }
        }

        return new WeightHistoryResponse(points);
    }
}

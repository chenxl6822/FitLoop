package com.fitloop.social;

import com.fitloop.social.SocialDtos.RankingResponse;
import com.fitloop.social.SocialDtos.RankingRow;
import com.fitloop.sport.CalorieCalculator;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.sport.WorkoutCompletedEvent;
import com.fitloop.user.UserInfo;
import com.fitloop.user.UserRepository;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.WeekFields;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LeaderboardService {
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");
    private static final DefaultRedisScript<Long> APPLY_EVENT = new DefaultRedisScript<>("""
            if redis.call('SADD', KEYS[3], ARGV[1]) == 0 then return 0 end
            redis.call('ZINCRBY', KEYS[1], ARGV[2], ARGV[3])
            redis.call('HINCRBYFLOAT', KEYS[2], ARGV[4], ARGV[3])
            redis.call('EXPIRE', KEYS[1], ARGV[5])
            redis.call('EXPIRE', KEYS[2], ARGV[5])
            redis.call('EXPIRE', KEYS[3], ARGV[5])
            return 1
            """, Long.class);

    private final SportRecordRepository records;
    private final UserRepository users;
    private final CalorieCalculator calculator;
    private final StringRedisTemplate redis;

    public LeaderboardService(SportRecordRepository records, UserRepository users,
                              CalorieCalculator calculator, StringRedisTemplate redis) {
        this.records = records;
        this.users = users;
        this.calculator = calculator;
        this.redis = redis;
    }

    public void project(long outboxId, WorkoutCompletedEvent event) {
        String period = periodKey(event.occurredAt());
        List<String> keys = List.of(distanceKey(period), calorieKey(period), processedKey(period));
        redis.execute(APPLY_EVENT, keys, Long.toString(outboxId), Double.toString(event.distanceKm()),
                event.userId().toString(), Double.toString(event.calorie()), Long.toString(TimeUnit.DAYS.toSeconds(15)));
    }

    @Transactional(readOnly = true)
    public RankingResponse ranking(String scope, String period, int page, int size) {
        int safePage = Math.max(page, 1);
        int safeSize = Math.max(1, Math.min(size, 100));
        if ("week".equalsIgnoreCase(period)) {
            List<RankingRow> cached = fromRedis(safePage, safeSize);
            if (!cached.isEmpty()) return new RankingResponse(scope, period, cached);
            List<SportRecord> week = currentWeekRecords();
            List<RankingRow> fallback = aggregate(week, safePage, safeSize);
            rebuild(week);
            return new RankingResponse(scope, period, fallback);
        }
        return new RankingResponse(scope, period,
                aggregate(records.findByStatus(SportRecord.STATUS_VALID), safePage, safeSize));
    }

    private List<RankingRow> fromRedis(int page, int size) {
        try {
            String period = periodKey(Instant.now());
            long offset = (long) (page - 1) * size;
            Set<org.springframework.data.redis.core.ZSetOperations.TypedTuple<String>> values =
                    redis.opsForZSet().reverseRangeWithScores(distanceKey(period), offset, offset + size - 1);
            if (values == null || values.isEmpty()) return List.of();
            List<RankingRow> rows = new ArrayList<>();
            int rank = (int) offset + 1;
            for (var value : values) {
                Long userId = Long.valueOf(value.getValue());
                Object calories = redis.opsForHash().get(calorieKey(period), value.getValue());
                double calorie = calories == null ? 0 : Double.parseDouble(calories.toString());
                rows.add(row(rank++, userId, value.getScore() == null ? 0 : value.getScore(), calorie));
            }
            return rows;
        } catch (RuntimeException ex) {
            return List.of();
        }
    }

    private List<SportRecord> currentWeekRecords() {
        LocalDate monday = LocalDate.now(BUSINESS_ZONE).with(DayOfWeek.MONDAY);
        Instant start = monday.atStartOfDay(BUSINESS_ZONE).toInstant();
        Instant end = monday.plusDays(7).atStartOfDay(BUSINESS_ZONE).toInstant();
        List<SportRecord> result = records.findByStatusAndStartedAtBetween(SportRecord.STATUS_VALID, start, end);
        return result == null ? List.of() : result;
    }

    private List<RankingRow> aggregate(List<SportRecord> source, int page, int size) {
        Map<Long, double[]> totals = new HashMap<>();
        source.forEach(record -> {
            double[] total = totals.computeIfAbsent(record.getUserId(), ignored -> new double[2]);
            total[0] += record.getDistanceKm();
            total[1] += record.getCalorie();
        });
        List<Map.Entry<Long, double[]>> ordered = totals.entrySet().stream()
                .sorted(Map.Entry.<Long, double[]>comparingByValue(
                        Comparator.comparingDouble((double[] value) -> -value[0])))
                .toList();
        long offset = (long) (page - 1) * size;
        return java.util.stream.IntStream.range(0, ordered.size())
                .skip(offset).limit(size)
                .mapToObj(index -> {
                    var entry = ordered.get(index);
                    return row(index + 1, entry.getKey(), entry.getValue()[0], entry.getValue()[1]);
                }).toList();
    }

    private RankingRow row(int rank, Long userId, double distance, double calorie) {
        UserInfo user = users.findById(userId).orElse(null);
        return new RankingRow(rank, userId, user == null ? "FitLoop 用户" : user.getNickname(),
                calculator.round(distance), calculator.round(calorie));
    }

    private void rebuild(List<SportRecord> source) {
        try {
            String period = periodKey(Instant.now());
            redis.delete(List.of(distanceKey(period), calorieKey(period)));
            Map<Long, double[]> totals = new HashMap<>();
            source.forEach(record -> {
                double[] total = totals.computeIfAbsent(record.getUserId(), ignored -> new double[2]);
                total[0] += record.getDistanceKm();
                total[1] += record.getCalorie();
            });
            totals.forEach((userId, value) -> {
                redis.opsForZSet().add(distanceKey(period), userId.toString(), value[0]);
                redis.opsForHash().put(calorieKey(period), userId.toString(), Double.toString(value[1]));
            });
            redis.expire(distanceKey(period), 15, TimeUnit.DAYS);
            redis.expire(calorieKey(period), 15, TimeUnit.DAYS);
        } catch (RuntimeException ignored) {
            // MySQL result has already been returned; Redis is an optional projection.
        }
    }

    private String periodKey(Instant instant) {
        LocalDate date = instant.atZone(BUSINESS_ZONE).toLocalDate();
        WeekFields fields = WeekFields.ISO;
        return date.get(fields.weekBasedYear()) + "-" + String.format("%02d", date.get(fields.weekOfWeekBasedYear()));
    }

    private String distanceKey(String period) { return "ranking:week:distance:" + period; }
    private String calorieKey(String period) { return "ranking:week:calorie:" + period; }
    private String processedKey(String period) { return "ranking:week:processed:" + period; }
}

package com.fitloop.target;

import com.fitloop.sport.SportRecord;
import com.fitloop.target.TargetDtos.CreateTargetRequest;
import com.fitloop.target.TargetDtos.TargetResponse;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TargetService {
    private final SportTargetRepository targets;

    public TargetService(SportTargetRepository targets) {
        this.targets = targets;
    }

    @Transactional
    public TargetResponse create(Long userId, CreateTargetRequest request) {
        LocalDate now = LocalDate.now();
        SportTarget target = new SportTarget();
        target.setUserId(userId);
        target.setPeriodType(request.periodType());
        target.setMetric(request.metric());
        target.setTargetValue(request.targetValue());
        if ("month".equalsIgnoreCase(request.periodType()) || "月".equals(request.periodType())) {
            target.setStartDate(now.withDayOfMonth(1));
            target.setEndDate(now.with(TemporalAdjusters.lastDayOfMonth()));
        } else {
            target.setStartDate(now.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)));
            target.setEndDate(now.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY)));
        }
        return TargetResponse.from(targets.save(target));
    }

    @Transactional(readOnly = true)
    public List<TargetResponse> current(Long userId) {
        LocalDate now = LocalDate.now();
        return targets.findByUserIdAndStatusAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
                        userId, "active", now, now)
                .stream()
                .map(TargetResponse::from)
                .toList();
    }

    @Transactional
    public void applySportRecord(SportRecord record) {
        LocalDate now = LocalDate.now();
        List<SportTarget> active = targets.findByUserIdAndStatusAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
                record.getUserId(), "active", now, now);
        for (SportTarget target : active) {
            double increment = switch (target.getMetric().toLowerCase()) {
                case "count", "次数" -> 1.0;
                case "duration", "时长" -> record.getDurationSeconds() / 60.0;
                case "distance", "里程" -> record.getDistanceKm();
                case "calorie", "卡路里" -> record.getCalorie();
                default -> 0.0;
            };
            target.setCompletedValue(target.getCompletedValue() + increment);
            if (target.getCompletedValue() >= target.getTargetValue()) {
                target.setStatus("completed");
            }
        }
    }
}

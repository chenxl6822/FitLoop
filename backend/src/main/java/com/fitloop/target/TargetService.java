package com.fitloop.target;

import com.fitloop.sport.SportRecord;
import com.fitloop.sport.WorkoutCompletedEvent;
import com.fitloop.target.TargetDtos.CreateTargetRequest;
import com.fitloop.target.TargetDtos.UpdateTargetRequest;
import com.fitloop.target.TargetDtos.TargetResponse;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

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
    public void delete(Long userId, Long targetId) {
        SportTarget target = targets.findByTargetIdAndUserId(targetId, userId)
                .orElseThrow(() -> new IllegalArgumentException("目标不存在"));
        if ("deleted".equals(target.getStatus())) {
            throw new IllegalArgumentException("目标已被删除");
        }
        target.setStatus("deleted");
    }

    @Transactional
    public TargetResponse update(Long userId, Long targetId, UpdateTargetRequest request) {
        SportTarget target = targets.findByTargetIdAndUserId(targetId, userId)
                .orElseThrow(() -> new IllegalArgumentException("目标不存在"));
        if ("deleted".equals(target.getStatus())) {
            throw new IllegalArgumentException("目标已被删除");
        }

        boolean metricChanged = false;
        boolean periodChanged = false;

        if (request.periodType() != null && !request.periodType().isBlank()
                && !request.periodType().equals(target.getPeriodType())) {
            target.setPeriodType(request.periodType().trim());
            periodChanged = true;
        }
        if (request.metric() != null && !request.metric().isBlank()
                && !request.metric().equals(target.getMetric())) {
            target.setMetric(request.metric().trim());
            metricChanged = true;
        }
        if (request.targetValue() > 0 && request.targetValue() != target.getTargetValue()) {
            target.setTargetValue(request.targetValue());
            metricChanged = true;
        }

        // 周期变了就重算时间范围
        if (periodChanged) {
            LocalDate now = LocalDate.now();
            if ("month".equalsIgnoreCase(target.getPeriodType()) || "月".equals(target.getPeriodType())) {
                target.setStartDate(now.withDayOfMonth(1));
                target.setEndDate(now.with(TemporalAdjusters.lastDayOfMonth()));
            } else {
                target.setStartDate(now.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)));
                target.setEndDate(now.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY)));
            }
        }

        // 指标或目标值变了就重置进度
        if (metricChanged) {
            target.setCompletedValue(0);
            target.setStatus("active");
        }

        return TargetResponse.from(targets.save(target));
    }

    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
    public void onWorkoutCompleted(WorkoutCompletedEvent event) {
        SportRecord record = new SportRecord();
        record.setUserId(event.userId());
        record.setDurationSeconds(event.durationSeconds());
        record.setDistanceKm(event.distanceKm());
        record.setCalorie(event.calorie());
        applySportRecord(record);
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

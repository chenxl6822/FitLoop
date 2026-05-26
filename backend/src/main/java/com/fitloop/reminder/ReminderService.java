package com.fitloop.reminder;

import com.fitloop.reminder.ReminderDtos.ReminderRequest;
import com.fitloop.reminder.ReminderDtos.ReminderResponse;
import com.fitloop.reminder.ReminderDtos.TargetReminderListResponse;
import com.fitloop.reminder.ReminderDtos.TargetReminderResponse;
import com.fitloop.target.SportTarget;
import com.fitloop.target.SportTargetRepository;
import com.fitloop.target.TargetReminderRead;
import com.fitloop.target.TargetReminderReadRepository;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ReminderService {
    private final ReminderConfigRepository reminders;
    private final SportTargetRepository targets;
    private final TargetReminderReadRepository reminderReads;

    public ReminderService(ReminderConfigRepository reminders, SportTargetRepository targets,
                           TargetReminderReadRepository reminderReads) {
        this.reminders = reminders;
        this.targets = targets;
        this.reminderReads = reminderReads;
    }

    @Transactional
    public ReminderResponse upsert(Long userId, Long id, ReminderRequest request) {
        ReminderConfig config = reminders.findByRemindIdAndUserId(id, userId).orElseGet(ReminderConfig::new);
        config.setUserId(userId);
        if (request.type() != null) config.setType(request.type());
        if (request.time() != null) config.setRemindTime(request.time());
        if (request.cycle() != null) config.setCycle(request.cycle());
        if (request.enabled() != null) config.setEnabled(request.enabled());
        return ReminderResponse.from(reminders.save(config));
    }

    @Transactional(readOnly = true)
    public TargetReminderListResponse getTargetReminders(Long userId) {
        LocalDate today = LocalDate.now();

        // 查找当前周期内 active 的目标
        List<SportTarget> activeTargets = targets
                .findByUserIdAndStatusAndStartDateLessThanEqualAndEndDateGreaterThanEqual(
                        userId, "active", today, today);

        // 查找用户已启用的目标类型提醒配置
        List<ReminderConfig> configs = reminders.findByUserIdAndTypeAndEnabled(userId, "target", true);

        // 判断是否有已到提醒时间的配置
        LocalTime now = LocalTime.now();
        boolean hasDueConfig = configs.stream()
                .anyMatch(c -> c.getRemindTime() != null && !now.isBefore(c.getRemindTime()));

        // 取第一个配置的 remindTime 作为参考
        LocalTime configRemindTime = configs.stream()
                .map(ReminderConfig::getRemindTime)
                .filter(t -> t != null)
                .findFirst()
                .orElse(null);

        // 查找用户已确认过的提醒
        Set<Long> acknowledgedTargetIds = reminderReads.findByUserId(userId)
                .stream()
                .map(TargetReminderRead::getTargetId)
                .collect(Collectors.toSet());

        List<TargetReminderResponse> items = activeTargets.stream()
                .map(t -> {
                    boolean completed = t.getCompletedValue() >= t.getTargetValue();
                    double progress = t.getTargetValue() <= 0 ? 0
                            : Math.min(100.0, t.getCompletedValue() / t.getTargetValue() * 100.0);
                    boolean acknowledged = acknowledgedTargetIds.contains(t.getTargetId());
                    boolean due = !completed && !acknowledged && hasDueConfig;

                    String message = buildReminderMessage(t, completed, progress, due);

                    return new TargetReminderResponse(
                            t.getTargetId(),
                            t.getPeriodType(),
                            t.getMetric(),
                            t.getTargetValue(),
                            t.getCompletedValue(),
                            Math.round(progress * 10.0) / 10.0,
                            t.getStartDate(),
                            t.getEndDate(),
                            t.getStatus(),
                            due,
                            acknowledged,
                            configRemindTime,
                            message
                    );
                })
                .toList();

        return new TargetReminderListResponse(items);
    }

    private String buildReminderMessage(SportTarget target, boolean completed, double progress, boolean due) {
        String metricLabel = switch (target.getMetric().toLowerCase()) {
            case "count", "次数" -> "次";
            case "duration", "时长" -> "分钟";
            case "distance", "里程" -> "公里";
            case "calorie", "卡路里" -> "千卡";
            default -> "";
        };
        String periodLabel = "周".equals(target.getPeriodType()) || "week".equalsIgnoreCase(target.getPeriodType())
                ? "本周" : "本月";

        if (completed) {
            return periodLabel + "目标已完成! ✅ (" + target.getCompletedValue() + "/" + target.getTargetValue() + metricLabel + ")";
        }
        if (due) {
            return "⏰ " + periodLabel + "运动目标待完成 (" + target.getCompletedValue() + "/" + target.getTargetValue()
                    + metricLabel + ", " + progress + "%)";
        }
        return periodLabel + "目标进度: " + target.getCompletedValue() + "/" + target.getTargetValue()
                + metricLabel + " (" + progress + "%)";
    }

    @Transactional
    public void acknowledgeTargetReminder(Long userId, Long targetId) {
        if (reminderReads.findByUserIdAndTargetId(userId, targetId).isEmpty()) {
            TargetReminderRead read = new TargetReminderRead();
            read.setUserId(userId);
            read.setTargetId(targetId);
            reminderReads.save(read);
        }
    }
}

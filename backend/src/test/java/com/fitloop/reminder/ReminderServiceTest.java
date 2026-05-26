package com.fitloop.reminder;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.reminder.ReminderDtos.ReminderRequest;
import com.fitloop.reminder.ReminderDtos.TargetReminderListResponse;
import com.fitloop.target.SportTarget;
import com.fitloop.target.SportTargetRepository;
import com.fitloop.target.TargetDtos.CreateTargetRequest;
import com.fitloop.target.TargetService;
import java.time.LocalDate;
import java.time.LocalTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import({ReminderService.class, TargetService.class})
class ReminderServiceTest {

    @Autowired
    private ReminderService reminderService;

    @Autowired
    private TargetService targetService;

    @Autowired
    private SportTargetRepository targetRepository;

    @Test
    void returnsActiveTargetsWhenNoReminderConfigExists() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 5));

        TargetReminderListResponse result = reminderService.getTargetReminders(1L);

        assertThat(result.targets()).hasSize(1);
        assertThat(result.targets().get(0).due()).isFalse();
        assertThat(result.targets().get(0).remindTime()).isNull();
        assertThat(result.targets().get(0).message()).contains("目标进度");
    }

    @Test
    void marksAsDueWhenConfigExistsAndTimePassed() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 5));
        reminderService.upsert(1L, 0L,
                new ReminderRequest("target", LocalTime.of(0, 0), "daily", true));

        TargetReminderListResponse result = reminderService.getTargetReminders(1L);

        assertThat(result.targets()).hasSize(1);
        assertThat(result.targets().get(0).due()).isTrue();
        assertThat(result.targets().get(0).remindTime()).isEqualTo(LocalTime.of(0, 0));
    }

    @Test
    void showsCompletedTargetMessageWhenProgressReached() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 5));

        // 直接修改目标完成度
        SportTarget target = targetRepository.findAll().get(0);
        target.setCompletedValue(5);
        targetRepository.save(target);

        reminderService.upsert(1L, 0L,
                new ReminderRequest("target", LocalTime.of(0, 0), "daily", true));

        TargetReminderListResponse result = reminderService.getTargetReminders(1L);

        assertThat(result.targets()).hasSize(1);
        assertThat(result.targets().get(0).due()).isFalse();
        assertThat(result.targets().get(0).message()).contains("已完成");
    }

    @Test
    void ignoresTargetsFromOtherUsers() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 5));
        targetService.create(2L, new CreateTargetRequest("week", "count", 3));

        TargetReminderListResponse result = reminderService.getTargetReminders(2L);

        assertThat(result.targets()).hasSize(1);
        assertThat(result.targets().get(0).targetValue()).isEqualTo(3.0);
    }

    @Test
    void returnsEmptyWhenNoActiveTargets() {
        TargetReminderListResponse result = reminderService.getTargetReminders(99L);
        assertThat(result.targets()).isEmpty();
    }

    @Test
    void doesNotReturnCompletedTargets() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 5));
        SportTarget target = targetRepository.findAll().get(0);
        target.setCompletedValue(5);
        target.setStatus("completed");
        targetRepository.save(target);

        TargetReminderListResponse result = reminderService.getTargetReminders(1L);
        assertThat(result.targets()).isEmpty();
    }

    @Test
    void existingUpsertBehaviourNotBroken() {
        var response = reminderService.upsert(1L, 0L,
                new ReminderRequest("sport", LocalTime.of(7, 0), "daily", true));

        assertThat(response.id()).isNotNull();
        assertThat(response.type()).isEqualTo("sport");
        assertThat(response.time()).isEqualTo(LocalTime.of(7, 0));

        // 更新已有配置
        var updated = reminderService.upsert(1L, response.id(),
                new ReminderRequest("target", LocalTime.of(8, 0), "daily", null));

        assertThat(updated.id()).isEqualTo(response.id());
        assertThat(updated.type()).isEqualTo("target");
        assertThat(updated.enabled()).isTrue(); // 未传递的值保持不变
    }
}

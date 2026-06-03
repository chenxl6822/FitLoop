package com.fitloop.target;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fitloop.sport.SportRecord;
import com.fitloop.target.TargetDtos.CreateTargetRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import(TargetService.class)
class TargetServiceTest {
    @Autowired
    private TargetService targetService;

    @Autowired
    private SportTargetRepository targets;

    @Test
    void updatesCurrentTargetAfterValidSportRecord() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 1));
        SportRecord record = new SportRecord();
        record.setUserId(1L);
        record.setStatus(SportRecord.STATUS_VALID);
        record.setDurationSeconds(1800);
        record.setDistanceKm(3.0);
        record.setCalorie(180);

        targetService.applySportRecord(record);

        assertThat(targetService.current(1L)).isEmpty();
    }

    @Test
    void createsAndListsCurrentTarget() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 5));
        var current = targetService.current(1L);
        assertThat(current).hasSize(1);
        assertThat(current.get(0).metric()).isEqualTo("count");
        assertThat(current.get(0).targetValue()).isEqualTo(5.0);
        assertThat(current.get(0).status()).isEqualTo("active");
    }

    @Test
    void deletesOwnTarget() {
        var created = targetService.create(1L, new CreateTargetRequest("week", "count", 3));
        targetService.delete(1L, created.targetId());

        var current = targetService.current(1L);
        assertThat(current).isEmpty();
    }

    @Test
    void cannotDeleteOtherUsersTarget() {
        var created = targetService.create(1L, new CreateTargetRequest("week", "count", 3));

        assertThatThrownBy(() -> targetService.delete(2L, created.targetId()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("目标不存在");
    }

    @Test
    void cannotDeleteAlreadyDeletedTarget() {
        var created = targetService.create(1L, new CreateTargetRequest("week", "count", 3));
        targetService.delete(1L, created.targetId());

        assertThatThrownBy(() -> targetService.delete(1L, created.targetId()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("已被删除");
    }

    @Test
    void deletedTargetNotInCurrentList() {
        targetService.create(1L, new CreateTargetRequest("week", "count", 3));
        var created2 = targetService.create(1L, new CreateTargetRequest("month", "distance", 10));

        // Delete first target
        var all = targets.findAll();
        targetService.delete(1L, all.get(0).getTargetId());

        var current = targetService.current(1L);
        // Only the month target should remain (the week target was first in DB)
        assertThat(current).hasSize(1);
    }

    @Test
    void deleteNonExistentTargetThrows() {
        assertThatThrownBy(() -> targetService.delete(1L, 9999L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("目标不存在");
    }
}

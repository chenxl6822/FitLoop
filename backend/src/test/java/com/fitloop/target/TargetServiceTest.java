package com.fitloop.target;

import static org.assertj.core.api.Assertions.assertThat;

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
}

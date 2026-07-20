package com.fitloop.appeal;

import static org.assertj.core.api.Assertions.assertThat;

import com.fitloop.appeal.AppealDtos.CreateAppealRequest;
import com.fitloop.appeal.AppealDtos.ReviewAppealRequest;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;

@DataJpaTest
@Import(AppealService.class)
class AppealServiceTest {
    @Autowired
    private AppealService appealService;

    @Autowired
    private SportRecordRepository records;

    @Test
    void createsAppealForAbnormalSportRecord() {
        SportRecord record = new SportRecord();
        record.setUserId(1L);
        record.setSessionId("session-appeal-1");
        record.setSportType("running");
        record.setCheckinMode("gps");
        record.setStartedAt(Instant.now());
        record.setStatus(SportRecord.STATUS_ABNORMAL);
        records.save(record);

        var response = appealService.create(1L, new CreateAppealRequest(record.getRecordId(), "GPS 漂移导致异常", null));

        assertThat(response.status()).isEqualTo("pending");
        assertThat(appealService.list(1L)).hasSize(1);
        assertThat(records.findById(record.getRecordId()).orElseThrow().getStatus())
                .isEqualTo(SportRecord.STATUS_APPEALING);
    }

    @Test
    void approvesPendingAppealAndRestoresRecordAsValid() {
        SportRecord record = new SportRecord();
        record.setUserId(1L);
        record.setSessionId("session-appeal-2");
        record.setSportType("running");
        record.setCheckinMode("gps");
        record.setStartedAt(Instant.now());
        record.setStatus(SportRecord.STATUS_ABNORMAL);
        records.save(record);
        var appeal = appealService.create(1L, new CreateAppealRequest(record.getRecordId(), "操场定位漂移", null));

        var reviewed = appealService.review(appeal.appealId(), new ReviewAppealRequest("approved", "轨迹异常属实但可接受"));

        assertThat(reviewed.status()).isEqualTo("approved");
        assertThat(records.findById(record.getRecordId()).orElseThrow().getStatus())
                .isEqualTo(SportRecord.STATUS_VALID);
    }
}

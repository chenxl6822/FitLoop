package com.fitloop.appeal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;

import com.fitloop.audit.AdminAuditService;
import com.fitloop.audit.AdminAuditLogRepository;
import com.fitloop.common.DomainEventOutbox;
import com.fitloop.appeal.AppealDtos.CreateAppealRequest;
import com.fitloop.appeal.AppealDtos.ReviewAppealRequest;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.sport.WorkoutCompletedEvent;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.event.ApplicationEvents;
import org.springframework.test.context.event.RecordApplicationEvents;

@DataJpaTest
@Import({AppealService.class, AdminAuditService.class})
@RecordApplicationEvents
class AppealServiceTest {
    @Autowired
    private AppealService appealService;

    @Autowired
    private SportRecordRepository records;

    @Autowired
    private AdminAuditLogRepository auditLogs;

    @MockitoBean
    private DomainEventOutbox outbox;

    @Autowired
    private ApplicationEvents applicationEvents;

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
        assertThat(applicationEvents.stream(WorkoutCompletedEvent.class)).singleElement()
                .satisfies(event -> assertThat(event.recordId()).isEqualTo(record.getRecordId()));
        verify(outbox).append(eq("WORKOUT_COMPLETED"), eq(record.getRecordId().toString()),
                any(WorkoutCompletedEvent.class));
    }

    @Test
    void adminListSupportsStatusFilterAndHumanDecisionIsAudited() {
        SportRecord record = new SportRecord();
        record.setUserId(5L);
        record.setSessionId("session-appeal-admin");
        record.setSportType("running");
        record.setCheckinMode("gps");
        record.setStartedAt(Instant.now());
        record.setStatus(SportRecord.STATUS_ABNORMAL);
        records.save(record);
        var appeal = appealService.create(5L,
                new CreateAppealRequest(record.getRecordId(), "GPS drift", null));

        appealService.review(appeal.appealId(),
                new ReviewAppealRequest("rejected", "Evidence is insufficient"), 99L, "HUMAN");

        assertThatThrownBy(() -> appealService.review(appeal.appealId(),
                new ReviewAppealRequest("approved", "Second decision"), 100L, "HUMAN"))
                .isInstanceOf(IllegalArgumentException.class);

        var page = appealService.adminList("rejected", 0, 20);
        assertThat(page.items()).singleElement()
                .satisfies(item -> assertThat(item.userId()).isEqualTo(5L));
        assertThat(auditLogs.findAll()).singleElement()
                .satisfies(log -> {
                    assertThat(log.getActorUserId()).isEqualTo(99L);
                    assertThat(log.getAction()).isEqualTo("APPEAL_REVIEWED");
                });
        assertThat(applicationEvents.stream(WorkoutCompletedEvent.class)).isEmpty();
    }
}

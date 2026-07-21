package com.fitloop.appeal;

import com.fitloop.appeal.AppealDtos.AppealResponse;
import com.fitloop.appeal.AppealDtos.AdminAppealPageResponse;
import com.fitloop.appeal.AppealDtos.AdminAppealResponse;
import com.fitloop.appeal.AppealDtos.CreateAppealRequest;
import com.fitloop.appeal.AppealDtos.ReviewAppealRequest;
import com.fitloop.audit.AdminAuditService;
import com.fitloop.common.DomainEventOutbox;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import com.fitloop.sport.WorkoutCompletedEvent;
import java.time.Instant;
import java.util.List;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class AppealService {
    private final AppealRepository appeals;
    private final SportRecordRepository records;
    private final AdminAuditService audits;
    private final DomainEventOutbox outbox;
    private final ApplicationEventPublisher eventPublisher;

    public AppealService(AppealRepository appeals, SportRecordRepository records,
                         AdminAuditService audits, DomainEventOutbox outbox,
                         ApplicationEventPublisher eventPublisher) {
        this.appeals = appeals;
        this.records = records;
        this.audits = audits;
        this.outbox = outbox;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public AppealResponse create(Long userId, CreateAppealRequest request) {
        SportRecord record = records.findById(request.recordId())
                .orElseThrow(() -> new IllegalArgumentException("运动记录不存在"));
        if (!record.getUserId().equals(userId)) {
            throw new IllegalArgumentException("不能申诉他人的运动记录");
        }
        if (record.getStatus() != SportRecord.STATUS_ABNORMAL) {
            throw new IllegalArgumentException("只有异常记录可以发起申诉");
        }
        appeals.findByRecordIdAndUserId(record.getRecordId(), userId).ifPresent(existing -> {
            throw new IllegalArgumentException("该记录已提交申诉");
        });

        Appeal appeal = new Appeal();
        appeal.setUserId(userId);
        appeal.setRecordId(record.getRecordId());
        appeal.setReason(request.reason());
        appeal.setEvidenceUrl(request.evidenceUrl());
        record.setStatus(SportRecord.STATUS_APPEALING);
        return AppealResponse.from(appeals.save(appeal));
    }

    @Transactional(readOnly = true)
    public List<AppealResponse> list(Long userId) {
        return appeals.findByUserIdOrderByCreatedAtDesc(userId)
                .stream()
                .map(AppealResponse::from)
                .toList();
    }

    @Transactional
    public AppealResponse review(Long appealId, ReviewAppealRequest request) {
        return review(appealId, request, null, "SYSTEM");
    }

    @Transactional
    public AppealResponse review(Long appealId, ReviewAppealRequest request,
                                 Long actorUserId, String source) {
        Appeal appeal = appeals.findForReview(appealId)
                .orElseThrow(() -> new IllegalArgumentException("申诉不存在"));
        if (!"pending".equals(appeal.getStatus())) {
            throw new IllegalArgumentException("申诉已审核，不能重复处理");
        }
        SportRecord record = records.findById(appeal.getRecordId())
                .orElseThrow(() -> new IllegalArgumentException("运动记录不存在"));
        if ("approved".equalsIgnoreCase(request.status())) {
            appeal.setStatus("approved");
            record.setStatus(SportRecord.STATUS_VALID);
            publishWorkoutCompleted(record);
        } else if ("rejected".equalsIgnoreCase(request.status())) {
            appeal.setStatus("rejected");
            record.setStatus(SportRecord.STATUS_ABNORMAL);
        } else {
            throw new IllegalArgumentException("审核状态只能为 approved 或 rejected");
        }
        appeal.setReviewNote(request.reviewNote());
        if (actorUserId != null) {
            audits.record(actorUserId, "APPEAL_REVIEWED", "APPEAL", appealId,
                    "{\"status\":\"" + appeal.getStatus() + "\",\"source\":\"" + source + "\"}");
        }
        return AppealResponse.from(appeal);
    }

    private void publishWorkoutCompleted(SportRecord record) {
        Instant occurredAt = record.getStartedAt() == null ? Instant.now() : record.getStartedAt();
        WorkoutCompletedEvent event = new WorkoutCompletedEvent(
                record.getRecordId(), record.getUserId(), record.getDurationSeconds(),
                record.getDistanceKm(), record.getCalorie(), occurredAt);
        eventPublisher.publishEvent(event);
        outbox.append("WORKOUT_COMPLETED", record.getRecordId().toString(), event);
    }

    @Transactional(readOnly = true)
    public AdminAppealPageResponse adminList(String status, int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.clamp(size, 1, 100);
        PageRequest pageable = PageRequest.of(safePage, safeSize);
        Page<Appeal> result = StringUtils.hasText(status)
                ? appeals.findByStatusIgnoreCaseOrderByCreatedAtDesc(status.trim(), pageable)
                : appeals.findAllByOrderByCreatedAtDesc(pageable);
        return new AdminAppealPageResponse(result.stream().map(AdminAppealResponse::from).toList(),
                safePage, safeSize, result.getTotalElements(), result.getTotalPages());
    }
}

package com.fitloop.appeal;

import com.fitloop.appeal.AppealDtos.AppealResponse;
import com.fitloop.appeal.AppealDtos.CreateAppealRequest;
import com.fitloop.sport.SportRecord;
import com.fitloop.sport.SportRecordRepository;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AppealService {
    private final AppealRepository appeals;
    private final SportRecordRepository records;

    public AppealService(AppealRepository appeals, SportRecordRepository records) {
        this.appeals = appeals;
        this.records = records;
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
}

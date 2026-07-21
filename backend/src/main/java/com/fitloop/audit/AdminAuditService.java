package com.fitloop.audit;

import com.fitloop.audit.AdminAuditDtos.AuditPageResponse;
import java.util.Objects;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
public class AdminAuditService {
    private final AdminAuditLogRepository logs;

    public AdminAuditService(AdminAuditLogRepository logs) {
        this.logs = logs;
    }

    @Transactional
    public void record(Long actorUserId, String action, String resourceType,
                       Object resourceId, String detailsJson) {
        logs.save(new AdminAuditLog(Objects.requireNonNull(actorUserId), action, resourceType,
                String.valueOf(resourceId), detailsJson));
    }

    @Transactional(readOnly = true)
    public AuditPageResponse list(String resourceType, String resourceId, int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.clamp(size, 1, 100);
        PageRequest pageable = PageRequest.of(safePage, safeSize);
        Page<AdminAuditLog> result;
        if (StringUtils.hasText(resourceType) && StringUtils.hasText(resourceId)) {
            result = logs.findByResourceTypeAndResourceIdOrderByCreatedAtDesc(
                    resourceType.trim(), resourceId.trim(), pageable);
        } else {
            result = logs.findAllByOrderByCreatedAtDesc(pageable);
        }
        return new AuditPageResponse(result.stream().map(AdminAuditDtos.AuditLogResponse::from).toList(),
                safePage, safeSize, result.getTotalElements(), result.getTotalPages());
    }
}

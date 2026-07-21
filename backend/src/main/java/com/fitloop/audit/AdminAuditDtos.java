package com.fitloop.audit;

import java.time.Instant;
import java.util.List;

public final class AdminAuditDtos {
    private AdminAuditDtos() { }

    public record AuditLogResponse(Long auditId, Long actorUserId, String action,
                                   String resourceType, String resourceId,
                                   String detailsJson, Instant createdAt) {
        static AuditLogResponse from(AdminAuditLog log) {
            return new AuditLogResponse(log.getAuditId(), log.getActorUserId(), log.getAction(),
                    log.getResourceType(), log.getResourceId(), log.getDetailsJson(), log.getCreatedAt());
        }
    }

    public record AuditPageResponse(List<AuditLogResponse> items, int page, int size,
                                    long totalElements, int totalPages) { }
}

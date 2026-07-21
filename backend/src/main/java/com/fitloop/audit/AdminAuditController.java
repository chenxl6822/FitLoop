package com.fitloop.audit;

import com.fitloop.audit.AdminAuditDtos.AuditPageResponse;
import com.fitloop.common.ApiResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/audit-logs")
public class AdminAuditController {
    private final AdminAuditService audits;

    public AdminAuditController(AdminAuditService audits) {
        this.audits = audits;
    }

    @GetMapping
    public ApiResponse<AuditPageResponse> list(
            @RequestParam(required = false) String resourceType,
            @RequestParam(required = false) String resourceId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(audits.list(resourceType, resourceId, page, size));
    }
}

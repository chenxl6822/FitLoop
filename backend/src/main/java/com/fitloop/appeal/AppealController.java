package com.fitloop.appeal;

import com.fitloop.appeal.AppealDtos.AppealListResponse;
import com.fitloop.appeal.AppealDtos.AppealResponse;
import com.fitloop.appeal.AppealDtos.CreateAppealRequest;
import com.fitloop.appeal.AppealDtos.ReviewAppealRequest;
import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AppealController {
    private final AppealService appeals;
    private final String adminKey;

    public AppealController(AppealService appeals, @Value("${fitloop.admin.key}") String adminKey) {
        this.appeals = appeals;
        this.adminKey = adminKey;
    }

    @PostMapping("/api/appeals")
    public ApiResponse<AppealResponse> create(@Valid @RequestBody CreateAppealRequest request) {
        return ApiResponse.ok(appeals.create(AuthSupport.currentUserId(), request));
    }

    @GetMapping("/api/appeals")
    public ApiResponse<AppealListResponse> list() {
        return ApiResponse.ok(new AppealListResponse(appeals.list(AuthSupport.currentUserId())));
    }

    @PutMapping("/api/admin/appeals/{id}")
    public ApiResponse<AppealResponse> review(@PathVariable Long id,
                                              @RequestHeader("X-Admin-Key") String key,
                                              @Valid @RequestBody ReviewAppealRequest request) {
        if (!adminKey.equals(key)) {
            throw new IllegalArgumentException("管理员密钥不正确");
        }
        return ApiResponse.ok(appeals.review(id, request));
    }
}

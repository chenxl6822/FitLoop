package com.fitloop.appeal;

import com.fitloop.appeal.AppealDtos.AdminAppealPageResponse;
import com.fitloop.appeal.AppealDtos.AppealResponse;
import com.fitloop.appeal.AppealDtos.ReviewAppealRequest;
import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/appeals")
public class AdminAppealController {
    private final AppealService appeals;

    public AdminAppealController(AppealService appeals) {
        this.appeals = appeals;
    }

    @GetMapping
    public ApiResponse<AdminAppealPageResponse> list(
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(appeals.adminList(status, page, size));
    }

    @PutMapping("/{appealId}")
    public ApiResponse<AppealResponse> review(@PathVariable Long appealId,
                                              @Valid @RequestBody ReviewAppealRequest request) {
        return ApiResponse.ok(appeals.review(appealId, request, AuthSupport.currentUserId(), "HUMAN"));
    }
}

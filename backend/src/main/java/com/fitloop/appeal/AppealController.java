package com.fitloop.appeal;

import com.fitloop.appeal.AppealDtos.AppealListResponse;
import com.fitloop.appeal.AppealDtos.AppealResponse;
import com.fitloop.appeal.AppealDtos.CreateAppealRequest;
import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AppealController {
    private final AppealService appeals;

    public AppealController(AppealService appeals) {
        this.appeals = appeals;
    }

    @PostMapping("/api/appeals")
    public ApiResponse<AppealResponse> create(@Valid @RequestBody CreateAppealRequest request) {
        return ApiResponse.ok(appeals.create(AuthSupport.currentUserId(), request));
    }

    @GetMapping("/api/appeals")
    public ApiResponse<AppealListResponse> list() {
        return ApiResponse.ok(new AppealListResponse(appeals.list(AuthSupport.currentUserId())));
    }
}

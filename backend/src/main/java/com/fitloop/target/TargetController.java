package com.fitloop.target;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import com.fitloop.target.TargetDtos.CreateTargetRequest;
import com.fitloop.target.TargetDtos.TargetListResponse;
import com.fitloop.target.TargetDtos.TargetResponse;
import com.fitloop.target.TargetDtos.UpdateTargetRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class TargetController {
    private final TargetService targets;

    public TargetController(TargetService targets) {
        this.targets = targets;
    }

    @PostMapping({"/api/target/add", "/api/targets"})
    public ApiResponse<TargetResponse> create(@Valid @RequestBody CreateTargetRequest request) {
        return ApiResponse.ok(targets.create(AuthSupport.currentUserId(), request));
    }

    @GetMapping({"/api/target/info", "/api/targets/current"})
    public ApiResponse<TargetListResponse> current() {
        return ApiResponse.ok(new TargetListResponse(targets.current(AuthSupport.currentUserId())));
    }

    @DeleteMapping("/api/targets/{targetId}")
    public ApiResponse<String> delete(@PathVariable Long targetId) {
        targets.delete(AuthSupport.currentUserId(), targetId);
        return ApiResponse.ok("目标已删除");
    }

    @PutMapping("/api/targets/{targetId}")
    public ApiResponse<TargetResponse> update(@PathVariable Long targetId,
                                              @Valid @RequestBody UpdateTargetRequest request) {
        return ApiResponse.ok(targets.update(AuthSupport.currentUserId(), targetId, request));
    }
}

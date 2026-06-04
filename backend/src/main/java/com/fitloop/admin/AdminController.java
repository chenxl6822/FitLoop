package com.fitloop.admin;

import com.fitloop.common.ApiResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private final AdminService adminService;

    public AdminController(AdminService adminService) {
        this.adminService = adminService;
    }

    @GetMapping("/stats")
    public ApiResponse<AdminDtos.SystemStatsResponse> stats() {
        return ApiResponse.ok(adminService.getStats());
    }

    @GetMapping("/users")
    public ApiResponse<AdminDtos.PaginatedUserListResponse> users(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(adminService.listUsers(page, size));
    }

    @GetMapping("/users/{userId}")
    public ApiResponse<AdminDtos.UserDetailResponse> userDetail(@PathVariable Long userId) {
        return ApiResponse.ok(adminService.getUserDetail(userId));
    }
}

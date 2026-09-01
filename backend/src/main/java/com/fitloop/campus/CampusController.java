package com.fitloop.campus;

import com.fitloop.common.ApiResponse;
import com.fitloop.campus.CampusDtos.CampusScheduleResponse;
import com.fitloop.campus.CampusDtos.CampusScheduleSyncRequest;
import com.fitloop.campus.CampusDtos.CampusStatusResponse;
import com.fitloop.campus.CampusDtos.CampusVerifyRequest;
import com.fitloop.security.AuthSupport;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.HttpStatus;

@RestController
@RequestMapping("/api/v1/campus")
public class CampusController {
    private final CampusService campusService;
    private final CampusScheduleService campusScheduleService;

    public CampusController(CampusService campusService, CampusScheduleService campusScheduleService) {
        this.campusService = campusService;
        this.campusScheduleService = campusScheduleService;
    }

    @GetMapping("/status")
    public ApiResponse<CampusStatusResponse> status() {
        return ApiResponse.ok(campusService.status(AuthSupport.currentUserId()));
    }

    @PostMapping("/verify")
    public ApiResponse<CampusStatusResponse> verify(@Valid @RequestBody CampusVerifyRequest request) {
        return ApiResponse.ok(campusService.verify(AuthSupport.currentUserId(), request));
    }

    @DeleteMapping("/link")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void unlink() {
        campusService.unlink(AuthSupport.currentUserId());
    }

    @GetMapping("/schedule")
    public ApiResponse<CampusScheduleResponse> schedule() {
        return ApiResponse.ok(campusScheduleService.getSchedule(AuthSupport.currentUserId()));
    }

    @PostMapping("/sync-schedule")
    public ApiResponse<CampusScheduleResponse> syncSchedule(
            @Valid @RequestBody CampusScheduleSyncRequest request) {
        return ApiResponse.ok(campusScheduleService.syncSchedule(AuthSupport.currentUserId(), request));
    }
}

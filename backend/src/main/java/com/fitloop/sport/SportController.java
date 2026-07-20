package com.fitloop.sport;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import com.fitloop.sport.SportDtos.FinishSessionRequest;
import com.fitloop.sport.SportDtos.SportListResponse;
import com.fitloop.sport.SportDtos.SportRecordResponse;
import com.fitloop.sport.SportDtos.StartSessionRequest;
import com.fitloop.sport.SportDtos.StartSessionResponse;
import com.fitloop.sport.SportDtos.TrackPointRequest;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/sport")
public class SportController {
    private final SportService sportService;

    public SportController(SportService sportService) {
        this.sportService = sportService;
    }

    @PostMapping("/session/start")
    public ApiResponse<StartSessionResponse> start(@Valid @RequestBody StartSessionRequest request) {
        return ApiResponse.ok(sportService.start(AuthSupport.currentUserId(), request));
    }

    @PostMapping("/session/track")
    public ApiResponse<Map<String, Boolean>> track(@Valid @RequestBody TrackPointRequest request) {
        sportService.appendTrack(AuthSupport.currentUserId(), request);
        return ApiResponse.ok(Map.of("accepted", true));
    }

    @PostMapping("/session/finish")
    public ApiResponse<SportRecordResponse> finish(
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody FinishSessionRequest request) {
        return ApiResponse.ok(sportService.finish(AuthSupport.currentUserId(), request, idempotencyKey));
    }

    @PostMapping("/photo")
    public ApiResponse<String> uploadPhoto(@RequestParam("file") MultipartFile file) {
        return ApiResponse.ok(sportService.savePhoto(AuthSupport.currentUserId(), file));
    }

    @GetMapping("/list")
    public ApiResponse<SportListResponse> list() {
        return ApiResponse.ok(new SportListResponse(sportService.list(AuthSupport.currentUserId())));
    }

}

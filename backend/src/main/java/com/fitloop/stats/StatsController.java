package com.fitloop.stats;

import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import com.fitloop.stats.StatsDtos.HealthRequest;
import com.fitloop.stats.StatsDtos.HealthResponse;
import com.fitloop.stats.StatsDtos.SportHistoryResponse;
import com.fitloop.stats.StatsDtos.SportStatsResponse;
import com.fitloop.stats.StatsDtos.WeightHistoryResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class StatsController {
    private final StatsService stats;

    public StatsController(StatsService stats) {
        this.stats = stats;
    }

    @GetMapping("/api/stat/sport")
    public ApiResponse<SportStatsResponse> sport(@RequestParam(required = false) String period) {
        return ApiResponse.ok(stats.sport(AuthSupport.currentUserId(), period));
    }

    @PostMapping("/api/stat/health")
    public ApiResponse<HealthResponse> health(@RequestBody HealthRequest request) {
        return ApiResponse.ok(stats.addHealth(AuthSupport.currentUserId(), request));
    }

    @GetMapping("/api/stat/sport/history")
    public ApiResponse<SportHistoryResponse> sportHistory(
            @RequestParam(defaultValue = "week") String period,
            @RequestParam(defaultValue = "all") String metric) {
        return ApiResponse.ok(stats.sportHistory(AuthSupport.currentUserId(), period, metric));
    }

    @GetMapping("/api/stat/health/history")
    public ApiResponse<WeightHistoryResponse> weightHistory(
            @RequestParam(defaultValue = "30") int days) {
        return ApiResponse.ok(stats.weightHistory(AuthSupport.currentUserId(), days));
    }
}

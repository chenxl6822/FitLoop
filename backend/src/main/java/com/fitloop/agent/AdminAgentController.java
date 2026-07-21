package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.RunCreatedResponse;
import com.fitloop.agent.AgentDtos.AdminRunPageResponse;
import com.fitloop.agent.AgentDtos.RunAuditResponse;
import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin")
public class AdminAgentController {
    private final AgentGatewayService gateway;

    public AdminAgentController(AgentGatewayService gateway) { this.gateway = gateway; }

    @PostMapping("/appeals/{appealId}/agent-review")
    public ApiResponse<RunCreatedResponse> review(@PathVariable Long appealId) {
        AgentRun run = gateway.createAppealReview(AuthSupport.currentUserId(), appealId);
        return ApiResponse.ok(new RunCreatedResponse(run.getRunId(), run.getRunType(), run.getStatus(), run.getTraceId()));
    }

    @GetMapping("/agent/runs")
    public ApiResponse<AdminRunPageResponse> runs(
            @RequestParam(required = false) AgentRunType type,
            @RequestParam(required = false) AgentRunStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(gateway.adminRuns(type, status, page, size));
    }

    @GetMapping("/agent/runs/{runId}/audit")
    public ApiResponse<RunAuditResponse> audit(@PathVariable String runId) {
        return ApiResponse.ok(gateway.runAudit(runId));
    }
}

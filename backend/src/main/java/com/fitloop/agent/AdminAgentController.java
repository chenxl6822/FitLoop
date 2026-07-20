package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.RunCreatedResponse;
import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/admin/appeals")
public class AdminAgentController {
    private final AgentGatewayService gateway;

    public AdminAgentController(AgentGatewayService gateway) { this.gateway = gateway; }

    @PostMapping("/{appealId}/agent-review")
    public ApiResponse<RunCreatedResponse> review(@PathVariable Long appealId) {
        AgentRun run = gateway.createAppealReview(AuthSupport.currentUserId(), appealId);
        return ApiResponse.ok(new RunCreatedResponse(run.getRunId(), run.getRunType(), run.getStatus(), run.getTraceId()));
    }
}

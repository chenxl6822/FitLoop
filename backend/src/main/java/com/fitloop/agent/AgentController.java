package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.CoachRunRequest;
import com.fitloop.agent.AgentDtos.ConfirmResponse;
import com.fitloop.agent.AgentDtos.MessageResponse;
import com.fitloop.agent.AgentDtos.RunCreatedResponse;
import com.fitloop.agent.AgentDtos.RunResponse;
import com.fitloop.common.ApiResponse;
import com.fitloop.security.AuthSupport;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/agent")
public class AgentController {
    private final AgentGatewayService gateway;

    public AgentController(AgentGatewayService gateway) { this.gateway = gateway; }

    @PostMapping("/coach/runs")
    public ApiResponse<RunCreatedResponse> coach(@Valid @RequestBody CoachRunRequest request) {
        AgentRun run = gateway.createCoachRun(AuthSupport.currentUserId(), request.objective());
        return ApiResponse.ok(new RunCreatedResponse(run.getRunId(), run.getRunType(), run.getStatus(), run.getTraceId()));
    }

    @GetMapping("/runs/{runId}")
    public ApiResponse<RunResponse> run(@PathVariable String runId) {
        return ApiResponse.ok(gateway.getVisibleRun(runId, AuthSupport.currentUserId(), isAdmin()));
    }

    @GetMapping("/runs/{runId}/events")
    public ApiResponse<List<MessageResponse>> events(@PathVariable String runId) {
        return ApiResponse.ok(gateway.messages(runId, AuthSupport.currentUserId(), isAdmin()).stream()
                .map(message -> new MessageResponse(message.getMessageId(), message.getRole(),
                        message.getContent(), message.getCreatedAt()))
                .toList());
    }

    @PostMapping("/actions/{proposalId}/confirm")
    public ApiResponse<ConfirmResponse> confirm(@PathVariable Long proposalId) {
        return ApiResponse.ok(gateway.confirm(proposalId, AuthSupport.currentUserId(), isAdmin()));
    }

    private boolean isAdmin() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return authentication != null && authentication.getAuthorities().stream()
                .anyMatch(authority -> "ROLE_ADMIN".equals(authority.getAuthority()));
    }
}

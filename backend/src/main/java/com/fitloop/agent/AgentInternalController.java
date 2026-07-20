package com.fitloop.agent;

import com.fitloop.agent.AgentDtos.AgentMessageRequest;
import com.fitloop.agent.AgentDtos.ClaimResponse;
import com.fitloop.agent.AgentDtos.DelegationTokenResponse;
import com.fitloop.agent.AgentDtos.ProposalRequest;
import com.fitloop.agent.AgentDtos.ProposalResponse;
import com.fitloop.agent.AgentDtos.RunResultRequest;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/internal/v1/agent/runs")
public class AgentInternalController {
    private final AgentGatewayService gateway;
    private final AgentDelegationTokenService tokens;
    private final byte[] serviceKey;

    public AgentInternalController(AgentGatewayService gateway, AgentDelegationTokenService tokens,
                                   @Value("${fitloop.agent.service-key}") String serviceKey) {
        this.gateway = gateway;
        this.tokens = tokens;
        if (serviceKey.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("fitloop.agent.service-key must contain at least 32 bytes");
        }
        this.serviceKey = serviceKey.getBytes(StandardCharsets.UTF_8);
    }

    @PostMapping("/{runId}/delegation-token")
    public DelegationTokenResponse token(@PathVariable String runId,
                                         @RequestHeader("X-Agent-Service-Key") String suppliedKey) {
        if (!MessageDigest.isEqual(serviceKey, suppliedKey.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid agent service credential");
        }
        AgentRun run = gateway.runForDelegation(runId);
        return new DelegationTokenResponse(tokens.issue(run), tokens.ttlSeconds());
    }

    @PostMapping("/{runId}/claim")
    public ClaimResponse claim(@PathVariable String runId, Authentication authentication) {
        requireRun(authentication, runId);
        return gateway.claim(runId);
    }

    @PostMapping("/{runId}/messages")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void message(@PathVariable String runId, Authentication authentication,
                        @Valid @RequestBody AgentMessageRequest request) {
        requireRun(authentication, runId);
        gateway.appendMessage(runId, request);
    }

    @PostMapping("/{runId}/proposals")
    public ProposalResponse proposal(@PathVariable String runId, Authentication authentication,
                                     @Valid @RequestBody ProposalRequest request) {
        requireRun(authentication, runId);
        return gateway.propose(runId, request);
    }

    @PostMapping("/{runId}/result")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void result(@PathVariable String runId, Authentication authentication,
                       @Valid @RequestBody RunResultRequest request) {
        requireRun(authentication, runId);
        gateway.complete(runId, request);
    }

    private void requireRun(Authentication authentication, String runId) {
        if (!(authentication.getDetails() instanceof AgentDtos.ToolContext context)
                || !runId.equals(context.runId())) {
            throw new org.springframework.security.access.AccessDeniedException("Delegation is scoped to another run");
        }
    }
}

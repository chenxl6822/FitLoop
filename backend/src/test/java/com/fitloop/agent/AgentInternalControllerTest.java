package com.fitloop.agent;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import com.fitloop.common.GlobalExceptionHandler;
import java.time.Instant;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
class AgentInternalControllerTest {
    @Mock AgentGatewayService gateway;
    @Mock AgentDelegationTokenService tokens;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(
                        new AgentInternalController(gateway, tokens, "s".repeat(48)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    @Test
    void duplicateProposalUsesTheRecoverableConflictContract() throws Exception {
        String runId = "00000000-0000-0000-0000-000000000001";
        var authentication = new UsernamePasswordAuthenticationToken("agent", null, List.of());
        authentication.setDetails(new AgentDtos.ToolContext(
                runId, 7L, null, AgentRunType.COACH));
        when(gateway.propose(eq(runId), any()))
                .thenThrow(new ExistingAgentProposalException(new AgentDtos.ProposalResponse(
                        9L, "CREATE_TRAINING_PLAN", "{}", "PENDING", false,
                        Instant.parse("2026-01-01T00:00:00Z"), null, null, null)));

        mockMvc.perform(post("/internal/v1/agent/runs/{runId}/proposals", runId)
                        .principal(authentication)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "actionType": "CREATE_TRAINING_PLAN",
                                  "payloadJson": "{}",
                                  "requiresAdmin": false
                                }
                                """))
                .andExpect(status().isConflict());
    }
}

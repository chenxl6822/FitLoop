package com.fitloop.agent;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.agent.AgentDtos.TrainingPlanResponse;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
class AgentControllerTest {
    @Mock AgentGatewayService gateway;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new AgentController(gateway)).build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("41", null, List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void listsOnlyPlansForTheAuthenticatedUser() throws Exception {
        String planJson = "{\"title\":\"5K starter\",\"goal\":\"Finish safely\",\"days\":[]}";
        when(gateway.listTrainingPlans(41L)).thenReturn(List.of(
                new TrainingPlanResponse(9L, "5K starter", planJson,
                        "ACTIVE", Instant.parse("2026-08-01T00:00:00Z"))));

        mockMvc.perform(get("/api/v1/agent/training-plans"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].planId").value(9))
                .andExpect(jsonPath("$.data[0].title").value("5K starter"))
                .andExpect(jsonPath("$.data[0].planJson").value(planJson))
                .andExpect(jsonPath("$.data[0].status").value("ACTIVE"));

        verify(gateway).listTrainingPlans(41L);
    }
}

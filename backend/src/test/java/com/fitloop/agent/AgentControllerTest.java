package com.fitloop.agent;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fitloop.agent.AgentDtos.TrainingPlanResponse;
import com.fitloop.agent.AgentDtos.NextTrainingSessionResponse;
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
                        "ACTIVE", Instant.parse("2026-08-01T00:00:00Z"), List.of())));

        mockMvc.perform(get("/api/v1/agent/training-plans"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].planId").value(9))
                .andExpect(jsonPath("$.data[0].title").value("5K starter"))
                .andExpect(jsonPath("$.data[0].planJson").value(planJson))
                .andExpect(jsonPath("$.data[0].status").value("ACTIVE"))
                .andExpect(jsonPath("$.data[0].completedDays").isEmpty());

        verify(gateway).listTrainingPlans(41L);
    }

    @Test
    void exposesAndCompletesOnlyTheAuthenticatedUsersNextTraining() throws Exception {
        when(gateway.nextTrainingSession(41L)).thenReturn(
                new NextTrainingSessionResponse(9L, "5K starter", 1, "easy run",
                        20, "LOW", "conversational pace", 0, 3));
        when(gateway.completeTrainingDay(41L, 9L, 1)).thenReturn(
                new TrainingPlanResponse(9L, "5K starter", "{}", "ACTIVE",
                        Instant.parse("2026-08-01T00:00:00Z"), List.of(1)));

        mockMvc.perform(get("/api/v1/agent/training-plans/next"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.planId").value(9))
                .andExpect(jsonPath("$.data.sessionType").value("easy run"))
                .andExpect(jsonPath("$.data.completedSessions").value(0));
        mockMvc.perform(post("/api/v1/agent/training-plans/9/days/1/complete"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.completedDays[0]").value(1));

        verify(gateway).nextTrainingSession(41L);
        verify(gateway).completeTrainingDay(41L, 9L, 1);
    }
}

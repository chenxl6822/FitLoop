package com.fitloop;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class FitLoopApiIntegrationTest {
    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void registersLogsInAndFinishesSportSession() throws Exception {
        mockMvc.perform(post("/api/user/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("phone", "13800000000", "password", "pass1234", "nickname", "测试用户"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.userId").exists());

        String loginBody = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("account", "13800000000", "password", "pass1234", "loginType", "password"))))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String token = objectMapper.readTree(loginBody).at("/data/token").asText();
        assertThat(token).isNotBlank();

        String startBody = mockMvc.perform(post("/api/sport/session/start")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sportType", "running", "checkinMode", "gps"))))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
        JsonNode start = objectMapper.readTree(startBody);
        String sessionId = start.at("/data/sessionId").asText();

        mockMvc.perform(post("/api/sport/session/track")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sessionId", sessionId,
                                "lat", 31.2304,
                                "lng", 121.4737,
                                "accuracy", 20,
                                "timestamp", Instant.now().toString()))))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/sport/session/finish")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sessionId", sessionId, "durationSeconds", 1800, "weightKg", 60))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.recordId").exists())
                .andExpect(jsonPath("$.data.calorie").value(240.0));

        mockMvc.perform(get("/api/stat/sport")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.checkinCount").value(1));
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }
}
